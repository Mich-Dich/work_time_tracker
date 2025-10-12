import 'package:flutter/material.dart';
import 'work_session_manager.dart';

class TodayPage extends StatelessWidget {
  final bool isRunning;
  final bool isBreakOngoing;
  final DateTime? currentStartTime;
  final List<WorkSession> todaySessions;
  final Duration currentBreakDuration;
  final WorkSessionManager sessionManager;
  final VoidCallback onStartTimer;
  final VoidCallback onStopTimer;
  final VoidCallback onStartBreak;
  final VoidCallback onStopBreak;

  const TodayPage({
    super.key,
    required this.isRunning,
    required this.isBreakOngoing,
    required this.currentStartTime,
    required this.todaySessions,
    required this.currentBreakDuration,
    required this.sessionManager,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onStartBreak,
    required this.onStopBreak,
  });

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes";
  }

  Widget _buildSessionsList(BuildContext context, List<WorkSession> sessions) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'No sessions recorded',
          style: TextStyle(color: Colors.grey[700]),
        ),
      );
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        return _buildSessionCard(context, sessions[index]);
      },
    );
  }

  Widget _buildSessionCard(BuildContext context, WorkSession session) {
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        color: isRunning 
                            ? Theme.of(context).colorScheme.primary 
                            : const Color(0xFF333333),
                        width: 3,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: isRunning ? onStopTimer : onStartTimer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning 
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.transparent,
                        foregroundColor: Colors.black,
                        shape: const CircleBorder(),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        isRunning ? 'STOP' : 'START',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isRunning ? Colors.black : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Break button - only show when timer is running
                  if (isRunning)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isBreakOngoing ? const Color(0xFFFFB74D) : const Color(0xFF333333),
                          width: 2,
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: isBreakOngoing ? onStopBreak : onStartBreak,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isBreakOngoing ? const Color(0xFFFFB74D) : Colors.transparent,
                          foregroundColor: Colors.black,
                          shape: const CircleBorder(),
                          elevation: 0,
                          padding: EdgeInsets.zero,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isBreakOngoing ? Icons.coffee : Icons.free_breakfast,
                              size: 24,
                              color: isBreakOngoing ? Colors.black : const Color(0xFFFFB74D),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isBreakOngoing ? 'END' : 'BREAK',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isBreakOngoing ? Colors.black : const Color(0xFFFFB74D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Started at time display
              if (isRunning && currentStartTime != null)
                Text(
                  'started at: ${_formatTime(currentStartTime!)}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 8),
              // Break info when session is running
              if (isRunning)
                FutureBuilder<WorkSession?>(
                  future: sessionManager.getOngoingSession(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final session = snapshot.data!;
                      final breakCount = session.breaks.length;
                      final totalBreakDuration = session.breakDuration + (isBreakOngoing ? currentBreakDuration : Duration.zero);
                      
                      return Column(
                        children: [
                          if (breakCount > 0 || isBreakOngoing)
                            Text(
                              'Breaks: $breakCount • Total: ${_formatDuration(totalBreakDuration)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          if (isBreakOngoing)
                            Text(
                              'Current break: ${_formatDuration(currentBreakDuration)}',
                              style: const TextStyle(
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
          child: _buildSessionsList(context, todaySessions),
        ),
      ],
    );
  }
}
