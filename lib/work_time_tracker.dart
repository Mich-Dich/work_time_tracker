import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'work_session_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_time_picker_spinner/flutter_time_picker_spinner.dart';


class WorkTimeTracker extends StatefulWidget {
  const WorkTimeTracker({super.key});

  @override
  State<WorkTimeTracker> createState() => _WorkTimeTrackerState();
}

class _WorkTimeTrackerState extends State<WorkTimeTracker> {
  final WorkSessionManager _sessionManager = WorkSessionManager();
  bool _isRunning = false;
  bool _isBreakOngoing = false;
  DateTime? _currentStartTime;
  List<WorkSession> _todaySessions = [];
  List<WorkSession> _allSessions = [];
  int _currentPageIndex = 0;




  // Add this function to the _WorkTimeTrackerState class
  void _exportSessions() async {
    if (_allSessions.isEmpty) {
      _showErrorDialog('No sessions to export');
      return;
    }

    final yamlContent = _convertSessionsToYaml(_allSessions);
    
    try {
      await Clipboard.setData(ClipboardData(text: yamlContent));
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00F5FF),
            content: Text(
              'Copied ${_allSessions.length} sessions to clipboard',
              style: const TextStyle(color: Colors.black),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Failed to copy to clipboard: $e');
      }
    }
  }

  String _convertSessionsToYaml(List<WorkSession> sessions) {
    final buffer = StringBuffer();
    
    buffer.writeln('# Work Time Tracker Export');
    buffer.writeln('# Generated on ${DateTime.now().toIso8601String()}');
    buffer.writeln('# Total sessions: ${sessions.length}');
    buffer.writeln('');
    
    // Group sessions by month for better organization
    final sessionsByMonth = <String, List<WorkSession>>{};
    
    for (final session in sessions) {
      final monthKey = '${session.startTime.year}-${session.startTime.month.toString().padLeft(2, '0')}';
      if (!sessionsByMonth.containsKey(monthKey)) {
        sessionsByMonth[monthKey] = [];
      }
      sessionsByMonth[monthKey]!.add(session);
    }
    
    // Sort months in descending order (newest first)
    final sortedMonths = sessionsByMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    
    for (final monthKey in sortedMonths) {
      final monthSessions = sessionsByMonth[monthKey]!;
      final monthDate = DateTime.parse('$monthKey-01');
      final monthName = DateFormat('MMMM yyyy').format(monthDate);
      
      buffer.writeln('# $monthName');
      buffer.writeln('${_formatMonthForYaml(monthDate)}:');
      
      // Group sessions by week within the month
      final sessionsByWeek = <String, List<WorkSession>>{};
      
      for (final session in monthSessions) {
        final weekNumber = _getWeekNumber(session.startTime);
        final weekKey = 'Week $weekNumber';
        if (!sessionsByWeek.containsKey(weekKey)) {
          sessionsByWeek[weekKey] = [];
        }
        sessionsByWeek[weekKey]!.add(session);
      }
      
      // Sort weeks in descending order
      final sortedWeeks = sessionsByWeek.keys.toList()
        ..sort((a, b) => int.parse(b.split(' ')[1]).compareTo(int.parse(a.split(' ')[1])));
      
      for (final weekKey in sortedWeeks) {
        final weekSessions = sessionsByWeek[weekKey]!;
        buffer.writeln('  $weekKey:');
        
        for (final session in weekSessions) {
          final netDuration = session.duration! - session.breakDuration;
          
          buffer.writeln('    - date: ${_formatDateForYaml(session.startTime)}');
          buffer.writeln('      start_time: "${_formatTime(session.startTime)}"');
          buffer.writeln('      end_time: "${_formatTime(session.endTime!)}"');
          buffer.writeln('      total_duration: "${_formatDuration(session.duration!)}"');
          buffer.writeln('      break_duration: "${_formatDuration(session.breakDuration)}"');
          buffer.writeln('      net_duration: "${_formatDuration(netDuration)}"');
          buffer.writeln('      break_count: ${session.breaks.length}');
          
          if (session.breaks.isNotEmpty) {
            buffer.writeln('      breaks:');
            for (final breakPeriod in session.breaks) {
              if (breakPeriod.endTime != null) {
                buffer.writeln('        - start: "${_formatTime(breakPeriod.startTime)}"');
                buffer.writeln('          end: "${_formatTime(breakPeriod.endTime!)}"');
                buffer.writeln('          duration: "${_formatDuration(breakPeriod.duration!)}"');
              }
            }
          }
          buffer.writeln('');
        }
      }
      buffer.writeln('');
    }
    
    // Add summary at the end
    buffer.writeln('# Summary');
    buffer.writeln('summary:');
    buffer.writeln('  total_sessions: ${sessions.length}');
    
    final totalDuration = sessions.fold<Duration>(Duration.zero, (prev, session) => prev + session.duration!);
    final totalBreakDuration = sessions.fold<Duration>(Duration.zero, (prev, session) => prev + session.breakDuration);
    final totalNetDuration = totalDuration - totalBreakDuration;
    
    buffer.writeln('  total_work_time: "${_formatDuration(totalDuration)}"');
    buffer.writeln('  total_break_time: "${_formatDuration(totalBreakDuration)}"');
    buffer.writeln('  total_net_time: "${_formatDuration(totalNetDuration)}"');
    buffer.writeln('  average_session_length: "${_formatDuration(Duration(seconds: totalDuration.inSeconds ~/ sessions.length))}"');
    
    return buffer.toString();
  }

  String _formatMonthForYaml(DateTime date) {
    return DateFormat('yyyy_MM').format(date).toLowerCase();
  }

  String _formatDateForYaml(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  TimeOfDay _roundToNearestQuarterHourTime(TimeOfDay time) {
    int minutes = time.minute;
    int remainder = minutes % 15;
    
    if (remainder < 8) {
      minutes = minutes - remainder;
    } else {
      minutes = minutes + (15 - remainder);
    }
    
    if (minutes == 60) {
      return TimeOfDay(hour: time.hour + 1, minute: 0);
    } else {
      return TimeOfDay(hour: time.hour, minute: minutes);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    await _sessionManager.loadSessions();
    final ongoingSession = await _sessionManager.getOngoingSession();
    final isBreakOngoing = await _sessionManager.isBreakOngoing();
    
    setState(() {
      _todaySessions = _sessionManager.getTodaySessions();
      _allSessions = _sessionManager.getAllSessions();
      
      if (ongoingSession != null) {
        _isRunning = true;
        _currentStartTime = ongoingSession.startTime;
        _isBreakOngoing = isBreakOngoing;
      } else {
        _isRunning = false;
        _isBreakOngoing = false;
      }
    });
  }

  void _startTimer() {
    setState(() {
      _isRunning = true;
      _currentStartTime = DateTime.now();
    });
    _sessionManager.startSession();
  }

  void _stopTimer() {
    if (_currentStartTime == null) return;

    setState(() {
      _isRunning = false;
      _isBreakOngoing = false;
    });
    
    if (_isBreakOngoing) {
      _sessionManager.stopBreak().then((_) {
        _sessionManager.stopSession().then((_) {
          _loadSessions();
        });
      });
    } else {
      _sessionManager.stopSession().then((_) {
        _loadSessions();
      });
    }
  }

  void _startBreak() {
    setState(() {
      _isBreakOngoing = true;
    });
    _sessionManager.startBreak();
  }

  void _stopBreak() {
    setState(() {
      _isBreakOngoing = false;
    });
    _sessionManager.stopBreak();
  }

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

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Delete All Data?',
            style: TextStyle(color: Color(0xFF00F5FF)),
          ),
          content: const Text(
            'This will permanently delete all your work sessions.',
            style: TextStyle(color: Colors.white70),
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
                _sessionManager.clearAllSessions().then((_) {
                  setState(() {
                    _todaySessions = [];
                    _allSessions = [];
                    _isRunning = false;
                    _isBreakOngoing = false;
                  });
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

  void _showDeleteSessionConfirmation(WorkSession session) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Delete Session?',
            style: TextStyle(color: Color(0xFF00F5FF)),
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
                _sessionManager.deleteSession(session).then((_) {
                  _loadSessions();
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

  int _getMinuteIndex(int currentMinutes, int currentHours, int maxHours, int maxMinutes) {
    final availableMinutes = _getAvailableMinutes(currentHours, maxHours, maxMinutes);
    final index = availableMinutes.indexOf(currentMinutes);
    return index >= 0 ? index : 0;
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
              title: const Text(
                'Edit Session',
                style: TextStyle(color: Color(0xFF00F5FF)),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildEditField(
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
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF00F5FF),
                                  onPrimary: Colors.black,
                                  surface: Color(0xFF1A1A1A),
                                  onSurface: Colors.white,
                                ),
                                dialogBackgroundColor: const Color(0xFF1A1A1A),
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
                      icon: Icons.access_time,
                      label: 'Start Time',
                      value: selectedStartTime.format(context),
                      onTap: () async {
                        TimeOfDay? picked = await showDialog<TimeOfDay>(
                          context: context,
                          builder: (BuildContext context) {
                            TimeOfDay tempPickedTime = selectedStartTime;
                            
                            return AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              surfaceTintColor: Colors.transparent,
                              title: const Text(
                                'Select Start Time', 
                                style: TextStyle(color: Color(0xFF00F5FF))
                              ),
                              content: Container(
                                height: 200,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Hours picker
                                    _buildQuarterHourTimePicker(
                                      initialTime: selectedStartTime,
                                      onTimeChanged: (time) {
                                        tempPickedTime = time;
                                      },
                                    ),
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
                                    Navigator.of(context).pop(tempPickedTime);
                                  },
                                  child: const Text(
                                    'OK', 
                                    style: TextStyle(color: Color(0xFF00F5FF))
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            selectedStartTime = picked;
                            
                            // Validate that start time is before end time
                            final newTotalDuration = _calculateDuration(picked, selectedEndTime);
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
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      icon: Icons.access_time,
                      label: 'End Time',
                      value: selectedEndTime.format(context),
                      onTap: () async {
                        TimeOfDay? picked = await showDialog<TimeOfDay>(
                          context: context,
                          builder: (BuildContext context) {
                            TimeOfDay tempPickedTime = selectedEndTime;
                            
                            return AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              surfaceTintColor: Colors.transparent,
                              title: const Text(
                                'Select End Time', 
                                style: TextStyle(color: Color(0xFF00F5FF))
                              ),
                              content: Container(
                                height: 200,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Hours picker
                                    _buildQuarterHourTimePicker(
                                      initialTime: selectedEndTime,
                                      onTimeChanged: (time) {
                                        tempPickedTime = time;
                                      },
                                    ),
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
                                    Navigator.of(context).pop(tempPickedTime);
                                  },
                                  child: const Text(
                                    'OK', 
                                    style: TextStyle(color: Color(0xFF00F5FF))
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            selectedEndTime = picked;
                            
                            // Validate that end time is after start time
                            final newTotalDuration = _calculateDuration(selectedStartTime, picked);
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
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditField(
                      icon: Icons.free_breakfast,
                      label: 'Break Duration',
                      value: _formatDuration(selectedBreakDuration),
                      onTap: () {
                        final maxBreakDuration = _calculateDuration(selectedStartTime, selectedEndTime);
                        _showBreakDurationPicker(
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
                                style: const TextStyle(
                                  color: Color(0xFF00F5FF),
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
                                style: const TextStyle(
                                  color: Color(0xFF00F5FF),
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
                    
                    _sessionManager.updateSession(session, updatedSession).then((_) {
                      _loadSessions();
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(color: Color(0xFF00F5FF)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Add this new function to create the quarter-hour time picker
  Widget _buildQuarterHourTimePicker({
    required TimeOfDay initialTime,
    required Function(TimeOfDay) onTimeChanged,
  }) {
    int selectedHour = initialTime.hour;
    int selectedMinute = initialTime.minute;
    
    // Convert minute to nearest quarter hour
    final quarterHours = [0, 15, 30, 45];
    int initialMinuteIndex = 0;
    for (int i = 0; i < quarterHours.length; i++) {
      if (selectedMinute <= quarterHours[i] || i == quarterHours.length - 1) {
        initialMinuteIndex = i;
        break;
      }
    }
    selectedMinute = quarterHours[initialMinuteIndex];

    return StatefulBuilder(
      builder: (context, setState) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Hours wheel
            _buildTimeWheel(
              items: List.generate(24, (index) => index),
              selectedIndex: selectedHour,
              label: 'HOURS',
              onChanged: (index) {
                setState(() {
                  selectedHour = index;
                  onTimeChanged(TimeOfDay(hour: selectedHour, minute: selectedMinute));
                });
              },
            ),
            const SizedBox(width: 20),
            // Minutes wheel (only quarter hours)
            _buildTimeWheel(
              items: quarterHours,
              selectedIndex: quarterHours.indexOf(selectedMinute),
              label: 'MINUTES',
              onChanged: (index) {
                setState(() {
                  selectedMinute = quarterHours[index];
                  onTimeChanged(TimeOfDay(hour: selectedHour, minute: selectedMinute));
                });
              },
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
                  selectedHour < 12 ? 'AM' : 'PM',
                  style: const TextStyle(
                    color: Color(0xFF00F5FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // Update the existing _buildDurationWheel to work for time as well
  Widget _buildTimeWheel({
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
            style: const TextStyle(
              color: Color(0xFF00F5FF),
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
                          ? const Color(0xFF00F5FF) 
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

  Widget _buildEditField({
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
            Icon(icon, color: const Color(0xFF00F5FF), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF00F5FF),
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

  void _showBreakDurationPicker(StateSetter setState, Duration currentDuration, Duration maxBreakDuration, Function(Duration) onDurationChanged) {
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
              title: const Text(
                'Select Break Duration',
                style: TextStyle(color: Color(0xFF00F5FF)),
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
                  child: const Text(
                    'OK',
                    style: TextStyle(color: Color(0xFF00F5FF)),
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

  Widget _buildDurationWheel({
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
            style: const TextStyle(
              color: Color(0xFF00F5FF),
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
                          ? const Color(0xFF00F5FF) 
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
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFF00F5FF)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSessionsList(List<WorkSession> sessions, {bool showDate = false}) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'No sessions recorded',
          style: TextStyle(color: Colors.grey[700]),
        ),
      );
    }

    if (!showDate) {
      return ListView.builder(
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          return _buildSessionCard(sessions[index], showDate);
        },
      );
    } else {
      final groupedSessions = _groupSessionsByWeekAndMonth(sessions);
      final sortedMonthKeys = groupedSessions.keys.toList()..sort((a, b) => b.compareTo(a));
      
      return ListView.builder(
        itemCount: _calculateGroupedItemCount(groupedSessions, sortedMonthKeys),
        itemBuilder: (context, index) {
          return _buildGroupedSessionItem(index, groupedSessions, sortedMonthKeys);
        },
      );
    }
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
            return _buildSessionCard(session, true);
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
          left: BorderSide(color: const Color(0xFF00F5FF), width: 4),
        ),
      ),
      child: Text(
        _formatMonth(month),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF00F5FF),
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

  Widget _buildSessionCard(WorkSession session, bool showDate) {
    // Calculate net duration (total - breaks)
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
                  if (showDate)
                    Text(
                      _formatDate(session.startTime),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF00F5FF),
                      ),
                    ),
                  if (showDate) const SizedBox(height: 8),
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
                          // Show net duration instead of total duration
                          Text(
                            _formatDuration(netDuration),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF00F5FF),
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
                  icon: const Icon(Icons.edit, color: Color(0xFF00F5FF), size: 18),
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

  Widget _buildTimerPage() {
    return Column(
      children: [
        // Timer section
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Main timer button
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isRunning ? const Color(0xFF00F5FF) : const Color(0xFF333333),
                        width: 3,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: _isRunning ? _stopTimer : _startTimer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRunning ? const Color(0xFF00F5FF) : Colors.transparent,
                        foregroundColor: Colors.black,
                        shape: const CircleBorder(),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        _isRunning ? 'STOP' : 'START',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _isRunning ? Colors.black : const Color(0xFF00F5FF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Break button - only show when timer is running
                  if (_isRunning)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isBreakOngoing ? const Color(0xFFFFB74D) : const Color(0xFF333333),
                          width: 2,
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _isBreakOngoing ? _stopBreak : _startBreak,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isBreakOngoing ? const Color(0xFFFFB74D) : Colors.transparent,
                          foregroundColor: Colors.black,
                          shape: const CircleBorder(),
                          elevation: 0,
                          padding: EdgeInsets.zero,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isBreakOngoing ? Icons.coffee : Icons.free_breakfast,
                              size: 24,
                              color: _isBreakOngoing ? Colors.black : const Color(0xFFFFB74D),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isBreakOngoing ? 'END' : 'BREAK',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isBreakOngoing ? Colors.black : const Color(0xFFFFB74D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Break info when session is running
              if (_isRunning)
                FutureBuilder<WorkSession?>(
                  future: _sessionManager.getOngoingSession(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final session = snapshot.data!;
                      final breakCount = session.breaks.length;
                      final totalBreakDuration = session.breakDuration;
                      
                      return Column(
                        children: [
                          if (breakCount > 0)
                            Text(
                              'Breaks: $breakCount • Total: ${_formatDuration(totalBreakDuration)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          if (_isBreakOngoing)
                            const Text(
                              'Break in progress...',
                              style: TextStyle(
                                color: Color(0xFFFFB74D),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      );
                    }
                    return Container();
                  },
                ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF333333), height: 1),
        // Today's sessions list
        Expanded(
          child: _buildSessionsList(_todaySessions, showDate: false),
        ),
      ],
    );
  }

  Widget _buildHistoryPage() {
    return _buildSessionsList(_allSessions, showDate: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Time Tracker'),
        actions: [
          // Only show export and delete buttons on history page
          if (_currentPageIndex == 1) ...[
            IconButton(
              icon: const Icon(Icons.content_copy, color: Color(0xFF00F5FF)),
              onPressed: _exportSessions,
              tooltip: 'Export all sessions to clipboard',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Color(0xFF00F5FF)),
              onPressed: _showDeleteConfirmation,
              tooltip: 'Delete all sessions',
            ),
          ],
        ],
      ),
      body: IndexedStack(
        index: _currentPageIndex,
        children: [
          _buildTimerPage(),
          _buildHistoryPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentPageIndex,
        onTap: (index) {
          setState(() {
            _currentPageIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: const Color(0xFF00F5FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.timer),
            label: 'Timer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}