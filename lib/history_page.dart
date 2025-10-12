import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'work_session_manager.dart';
import 'package:flutter/services.dart'; // Add this import for Clipboard

class HistoryPage extends StatefulWidget {
  final List<WorkSession> allSessions;
  final WorkSessionManager sessionManager;
  final VoidCallback onSessionsUpdated;

  const HistoryPage({
    super.key,
    required this.allSessions,
    required this.sessionManager,
    required this.onSessionsUpdated,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes";
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatTime(DateTime time) {
    return DateFormat('HH:mm').format(time);
  }

  String _formatMonth(DateTime date) {
    return DateFormat('MMMM yyyy').format(date);
  }

  String _formatWeek(DateTime date) {
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    
    if (startOfWeek.month == endOfWeek.month) {
      return '${DateFormat('MMM dd').format(startOfWeek)} - ${DateFormat('dd, yyyy').format(endOfWeek)}';
    } else if (startOfWeek.year == endOfWeek.year) {
      return '${DateFormat('MMM dd').format(startOfWeek)} - ${DateFormat('MMM dd, yyyy').format(endOfWeek)}';
    } else {
      return '${DateFormat('MMM dd, yyyy').format(startOfWeek)} - ${DateFormat('MMM dd, yyyy').format(endOfWeek)}';
    }
  }

  Map<String, Map<String, List<WorkSession>>> _groupSessionsByWeekAndMonth(List<WorkSession> sessions) {
    final grouped = <String, Map<String, List<WorkSession>>>{};
    
    for (final session in sessions) {
      final monthKey = DateFormat('yyyy-MM').format(session.startTime);
      final year = session.startTime.year;
      final weekNumber = _getWeekNumber(session.startTime);
      final weekKey = '$year-W${weekNumber.toString().padLeft(2, '0')}';
      
      if (!grouped.containsKey(monthKey)) {
        grouped[monthKey] = {};
      }
      
      if (!grouped[monthKey]!.containsKey(weekKey)) {
        grouped[monthKey]![weekKey] = [];
      }
      
      grouped[monthKey]![weekKey]!.add(session);
    }
    
    return grouped;
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceStart = date.difference(firstDayOfYear).inDays;
    final weekNumber = ((daysSinceStart + firstDayOfYear.weekday - 1) / 7).floor() + 1;
    return weekNumber;
  }

  void _showDeleteSessionConfirmation(WorkSession session) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Delete Session?',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          content: Text(
            'Delete ${_formatTime(session.startTime)} - ${_formatTime(session.endTime!)}?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () {
                widget.sessionManager.deleteSession(session).then((_) {
                  widget.onSessionsUpdated();
                });
                Navigator.of(context).pop();
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showEditSessionDialog(WorkSession session) {
    DateTime selectedDate = session.startTime;
    TimeOfDay selectedStartTime = TimeOfDay.fromDateTime(session.startTime);
    TimeOfDay selectedEndTime = TimeOfDay.fromDateTime(session.endTime!);
    Duration selectedBreakDuration = session.breakDuration;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Calculate current total duration and net duration
            final currentTotalDuration = _calculateDuration(selectedStartTime, selectedEndTime);
            final currentNetDuration = currentTotalDuration - selectedBreakDuration;
            
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Edit Session',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildEditField(
                      context: context,
                      icon: Icons.calendar_today,
                      label: 'Date',
                      value: _formatDate(selectedDate),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: ColorScheme.dark(
                                  primary: Theme.of(context).colorScheme.primary,
                                  onPrimary: Colors.black,
                                  surface: const Color(0xFF1A1A1A),
                                  onSurface: Colors.white,
                                ), 
                                dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1A1A1A)),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null && picked != selectedDate) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      context: context,
                      icon: Icons.access_time,
                      label: 'Start Time',
                      value: selectedStartTime.format(context),
                      onTap: () async {
                        TimeOfDay? picked = await showDialog<TimeOfDay>(
                          context: context,
                          builder: (BuildContext context) {
                            return _TimePickerDialog(
                              initialTime: selectedStartTime,
                              onTimeChanged: (time) {
                                setState(() {
                                  selectedStartTime = time;
                                  
                                  // Validate that start time is before end time
                                  final newTotalDuration = _calculateDuration(time, selectedEndTime);
                                  if (newTotalDuration <= Duration.zero) {
                                    _showErrorDialog('Start time must be before end time');
                                    return;
                                  }
                                  
                                  // Validate that break duration doesn't exceed total duration
                                  if (selectedBreakDuration > newTotalDuration) {
                                    _showErrorDialog('Break duration cannot exceed total work time');
                                    // Auto-adjust break duration to maximum allowed
                                    selectedBreakDuration = newTotalDuration;
                                  }
                                });
                              },
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            selectedStartTime = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      context: context,
                      icon: Icons.access_time,
                      label: 'End Time',
                      value: selectedEndTime.format(context),
                      onTap: () async {
                        TimeOfDay? picked = await showDialog<TimeOfDay>(
                          context: context,
                          builder: (BuildContext context) {
                            return _TimePickerDialog(
                              initialTime: selectedEndTime,
                              onTimeChanged: (time) {
                                setState(() {
                                  selectedEndTime = time;
                                  
                                  // Validate that end time is after start time
                                  final newTotalDuration = _calculateDuration(selectedStartTime, time);
                                  if (newTotalDuration <= Duration.zero) {
                                    _showErrorDialog('End time must be after start time');
                                    return;
                                  }
                                  
                                  // Validate that break duration doesn't exceed total duration
                                  if (selectedBreakDuration > newTotalDuration) {
                                    _showErrorDialog('Break duration cannot exceed total work time');
                                    // Auto-adjust break duration to maximum allowed
                                    selectedBreakDuration = newTotalDuration;
                                  }
                                });
                              },
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            selectedEndTime = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      context: context,
                      icon: Icons.free_breakfast,
                      label: 'Break Duration',
                      value: _formatDuration(selectedBreakDuration),
                      onTap: () {
                        final maxBreakDuration = _calculateDuration(selectedStartTime, selectedEndTime);
                        _showBreakDurationPicker(
                          context,
                          setState, 
                          selectedBreakDuration, 
                          maxBreakDuration,
                          (newDuration) {
                            setState(() {
                              selectedBreakDuration = newDuration;
                            });
                          }
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${selectedStartTime.format(context)} - ${selectedEndTime.format(context)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _formatDuration(currentTotalDuration),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (selectedBreakDuration.inMinutes > 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Break:',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _formatDuration(selectedBreakDuration),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          const Divider(color: Color(0xFF333333), height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Net Duration:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatDuration(currentNetDuration),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          // Show validation warning if break is too long
                          if (selectedBreakDuration > currentTotalDuration)
                            const SizedBox(height: 8),
                          if (selectedBreakDuration > currentTotalDuration)
                            Text(
                              'Warning: Break exceeds work time!',
                              style: TextStyle(
                                color: Colors.orange[300],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final newStartDateTime = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedStartTime.hour,
                      selectedStartTime.minute,
                    );
                    
                    final newEndDateTime = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedEndTime.hour,
                      selectedEndTime.minute,
                    );
                    
                    if (newEndDateTime.isBefore(newStartDateTime)) {
                      _showErrorDialog('End time must be after start time');
                      return;
                    }
                    
                    final totalDuration = newEndDateTime.difference(newStartDateTime);
                    if (selectedBreakDuration > totalDuration) {
                      _showErrorDialog('Break duration cannot exceed total work time');
                      return;
                    }
                    
                    final updatedSession = session.copyWith(
                      startTime: newStartDateTime,
                      endTime: newEndDateTime,
                      breakDuration: selectedBreakDuration,
                    );
                    
                    widget.sessionManager.updateSession(session, updatedSession).then((_) {
                      widget.onSessionsUpdated();
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Save',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEditField({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  void _showBreakDurationPicker(BuildContext context, StateSetter setState, Duration currentDuration, Duration maxBreakDuration, Function(Duration) onDurationChanged) {
    int hours = currentDuration.inHours;
    int minutes = currentDuration.inMinutes.remainder(60);

    // Calculate maximum allowed values
    final maxHours = maxBreakDuration.inHours;
    final maxMinutes = maxBreakDuration.inMinutes.remainder(60);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Select Break Duration',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Max allowed: ${_formatDuration(maxBreakDuration)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDurationWheel(
                        context: context,
                        items: List.generate(maxHours + 1, (index) => index),
                        selectedIndex: hours,
                        label: 'HOURS',
                        onChanged: (index) {
                          setDialogState(() {
                            hours = index;
                            // If we're at max hours, limit minutes
                            if (hours == maxHours) {
                              final availableMinutes = [0, 15, 30, 45].where((m) => m <= maxMinutes).toList();
                              if (availableMinutes.isNotEmpty && !availableMinutes.contains(minutes)) {
                                minutes = availableMinutes.last;
                              }
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 20),
                      _buildDurationWheel(
                        context: context,
                        items: _getAvailableMinutes(hours, maxHours, maxMinutes),
                        selectedIndex: _getMinuteIndex(minutes, hours, maxHours, maxMinutes),
                        label: 'MINUTES',
                        onChanged: (index) {
                          setDialogState(() {
                            final availableMinutes = _getAvailableMinutes(hours, maxHours, maxMinutes);
                            if (index < availableMinutes.length) {
                              minutes = availableMinutes[index];
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Selected: ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Max: ${_formatDuration(maxBreakDuration)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final newDuration = Duration(hours: hours, minutes: minutes);
                    if (newDuration > maxBreakDuration) {
                      _showErrorDialog('Break duration cannot exceed work time');
                      return;
                    }
                    onDurationChanged(newDuration);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'OK',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  List<int> _getAvailableMinutes(int currentHours, int maxHours, int maxMinutes) {
    List<int> allMinutes = [0, 15, 30, 45];
    
    if (currentHours == maxHours) {
      // If at max hours, only show minutes up to maxMinutes
      return allMinutes.where((minute) => minute <= maxMinutes).toList();
    } else {
      return allMinutes;
    }
  }

  int _getMinuteIndex(int currentMinutes, int currentHours, int maxHours, int maxMinutes) {
    final availableMinutes = _getAvailableMinutes(currentHours, maxHours, maxMinutes);
    final index = availableMinutes.indexOf(currentMinutes);
    return index >= 0 ? index : 0;
  }

  Widget _buildDurationWheel({
    required BuildContext context,
    required List<int> items,
    required int selectedIndex,
    required String label,
    required Function(int) onChanged,
  }) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListWheelScrollView(
              itemExtent: 40,
              diameterRatio: 1.5,
              onSelectedItemChanged: onChanged,
              children: items.map((value) {
                return Center(
                  child: Text(
                    value.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: items.indexOf(value) == selectedIndex 
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.white70,
                      fontSize: 18,
                      fontWeight: items.indexOf(value) == selectedIndex 
                          ? FontWeight.w600 
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Duration _calculateDuration(TimeOfDay start, TimeOfDay end) {
    final now = DateTime.now();
    final startDateTime = DateTime(now.year, now.month, now.day, start.hour, start.minute);
    final endDateTime = DateTime(now.year, now.month, now.day, end.hour, end.minute);
    
    if (endDateTime.isAfter(startDateTime)) {
      return endDateTime.difference(startDateTime);
    } else {
      return endDateTime.add(const Duration(days: 1)).difference(startDateTime);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Error',
            style: TextStyle(color: Colors.red),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSessionsList(List<WorkSession> sessions) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'No sessions recorded',
          style: TextStyle(color: Colors.grey[700]),
        ),
      );
    }

    final groupedSessions = _groupSessionsByWeekAndMonth(sessions);
    final sortedMonthKeys = groupedSessions.keys.toList()..sort((a, b) => b.compareTo(a));
    
    return ListView.builder(
      itemCount: _calculateGroupedItemCount(groupedSessions, sortedMonthKeys),
      itemBuilder: (context, index) {
        return _buildGroupedSessionItem(index, groupedSessions, sortedMonthKeys);
      },
    );
  }

  int _calculateGroupedItemCount(
    Map<String, Map<String, List<WorkSession>>> groupedSessions,
    List<String> sortedMonthKeys,
  ) {
    int count = 0;
    for (final monthKey in sortedMonthKeys) {
      count++;
      final weeks = groupedSessions[monthKey]!;
      final sortedWeekKeys = weeks.keys.toList()..sort((a, b) => b.compareTo(a));
      
      for (final weekKey in sortedWeekKeys) {
        count++;
        count += weeks[weekKey]!.length;
      }
    }
    return count;
  }

  Widget _buildGroupedSessionItem(
    int index,
    Map<String, Map<String, List<WorkSession>>> groupedSessions,
    List<String> sortedMonthKeys,
  ) {
    int currentIndex = 0;
    
    for (final monthKey in sortedMonthKeys) {
      if (index == currentIndex) {
        final monthDate = DateTime.parse('$monthKey-01');
        return _buildMonthHeader(monthDate);
      }
      currentIndex++;
      
      final weeks = groupedSessions[monthKey]!;
      final sortedWeekKeys = weeks.keys.toList()..sort((a, b) => b.compareTo(a));
      
      for (final weekKey in sortedWeekKeys) {
        if (index == currentIndex) {
          final firstSession = weeks[weekKey]!.first;
          return _buildWeekHeader(firstSession.startTime);
        }
        currentIndex++;
        
        final weekSessions = weeks[weekKey]!;
        for (final session in weekSessions) {
          if (index == currentIndex) {
            return _buildSessionCard(session);
          }
          currentIndex++;
        }
      }
    }
    
    return Container();
  }

  Widget _buildMonthHeader(DateTime month) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4),
        ),
      ),
      child: Text(
        _formatMonth(month),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildWeekHeader(DateTime weekStart) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      margin: const EdgeInsets.only(top: 8),
      child: Text(
        _formatWeek(weekStart),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildSessionCard(WorkSession session) {
    final netDuration = session.duration! - session.breakDuration;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(session.startTime),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_formatTime(session.startTime)} - ${_formatTime(session.endTime!)}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatDuration(netDuration),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (session.breakDuration.inMinutes > 0)
                            Text(
                              'Break: ${_formatDuration(session.breakDuration)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          if (session.breaks.length > 1)
                            Text(
                              '${session.breaks.length} breaks',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary, size: 18),
                  onPressed: () => _showEditSessionDialog(session),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _showDeleteSessionConfirmation(session),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildSessionsList(widget.allSessions);
  }
}

// New TimePickerDialog with improved scroll behavior
class _TimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final Function(TimeOfDay) onTimeChanged;

  const _TimePickerDialog({
    required this.initialTime,
    required this.onTimeChanged,
  });

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  
  final List<int> _hours = List.generate(24, (index) => index);
  final List<int> _minutes = [0, 15, 30, 45];
  
  int _selectedHour = 0;
  int _selectedMinute = 0;

  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialTime.hour;
    _selectedMinute = _getNearestQuarterHour(widget.initialTime.minute);
    
    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController = FixedExtentScrollController(
      initialItem: _minutes.indexOf(_selectedMinute)
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  int _getNearestQuarterHour(int minute) {
    if (minute < 8) return 0;
    if (minute < 23) return 15;
    if (minute < 38) return 30;
    if (minute < 53) return 45;
    return 0; // 60 minutes wraps to next hour
  }

  void _onHourChanged(int index) {
    setState(() {
      _selectedHour = _hours[index];
      _updateTime();
    });
  }

  void _onMinuteChanged(int index) {
    setState(() {
      _selectedMinute = _minutes[index];
      _updateTime();
    });
  }

  void _updateTime() {
    widget.onTimeChanged(TimeOfDay(hour: _selectedHour, minute: _selectedMinute));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Select Time', 
        style: TextStyle(color: Theme.of(context).colorScheme.primary)
      ),
      content: SizedBox(
        height: 200,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Hours wheel
            _buildTimeWheel(
              controller: _hourController,
              items: _hours,
              selectedIndex: _selectedHour,
              label: 'HOURS',
              onChanged: _onHourChanged,
            ),
            const SizedBox(width: 20),
            // Minutes wheel (only quarter hours)
            _buildTimeWheel(
              controller: _minuteController,
              items: _minutes,
              selectedIndex: _minutes.indexOf(_selectedMinute),
              label: 'MINUTES',
              onChanged: _onMinuteChanged,
            ),
            const SizedBox(width: 10),
            // AM/PM indicator (for 12-hour format)
            if (!MediaQuery.of(context).alwaysUse24HourFormat) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _selectedHour < 12 ? 'AM' : 'PM',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel', 
            style: TextStyle(color: Colors.white70)
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(TimeOfDay(hour: _selectedHour, minute: _selectedMinute));
          },
          child: Text(
            'OK', 
            style: TextStyle(color: Theme.of(context).colorScheme.primary)
          ),
        ),
      ],
    );
  }

  Widget _buildTimeWheel({
    required FixedExtentScrollController controller,
    required List<int> items,
    required int selectedIndex,
    required String label,
    required Function(int) onChanged,
  }) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: 40,
              diameterRatio: 1.5,
              onSelectedItemChanged: onChanged,
              physics: const FixedExtentScrollPhysics(),
              childDelegate: ListWheelChildLoopingListDelegate(
                children: items.map((value) {
                  return Center(
                    child: Text(
                      value.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: value == (label == 'HOURS' ? _selectedHour : _selectedMinute)
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.white70,
                        fontSize: 18,
                        fontWeight: value == (label == 'HOURS' ? _selectedHour : _selectedMinute)
                            ? FontWeight.w600 
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
