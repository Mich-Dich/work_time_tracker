import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'work_session_manager.dart';
import 'today_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

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
  Duration _currentBreakDuration = Duration.zero;
  Timer? _breakTimer;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _breakTimer?.cancel();
    super.dispose();
  }

  void _startBreakTimer() {
    _breakTimer?.cancel();
    _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isBreakOngoing) {
        setState(() {
          _currentBreakDuration += const Duration(seconds: 1);
        });
      } else {
        timer.cancel();
      }
    });
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
        if (_isBreakOngoing) {
          _startBreakTimer();
        }
      } else {
        _isRunning = false;
        _isBreakOngoing = false;
        _currentBreakDuration = Duration.zero;
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
      _currentBreakDuration = Duration.zero;
    });
    
    _breakTimer?.cancel();
    
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
      _currentBreakDuration = Duration.zero;
    });
    _sessionManager.startBreak();
    _startBreakTimer();
  }

  void _stopBreak() {
    setState(() {
      _isBreakOngoing = false;
      _currentBreakDuration = Duration.zero;
    });
    _breakTimer?.cancel();
    _sessionManager.stopBreak();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Time Tracker'),
        actions: [
          if (_currentPageIndex == 1) ...[
            IconButton(
              icon: Icon(Icons.content_copy, color: Theme.of(context).colorScheme.primary),
              onPressed: () => _exportSessions(context),
              tooltip: 'Export all sessions to clipboard',
            ),
            IconButton(
              icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.primary),
              onPressed: _showDeleteConfirmation,
              tooltip: 'Delete all sessions',
            ),
          ],
        ],
      ),
      body: IndexedStack(
        index: _currentPageIndex,
        children: [
          TodayPage(
            isRunning: _isRunning,
            isBreakOngoing: _isBreakOngoing,
            currentStartTime: _currentStartTime,
            todaySessions: _todaySessions,
            currentBreakDuration: _currentBreakDuration,
            sessionManager: _sessionManager,
            onStartTimer: _startTimer,
            onStopTimer: _stopTimer,
            onStartBreak: _startBreak,
            onStopBreak: _stopBreak,
          ),
          HistoryPage(
            allSessions: _allSessions,
            sessionManager: _sessionManager,
            onSessionsUpdated: _loadSessions,
          ),
          SettingsPage(),
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
        selectedItemColor: Theme.of(context).colorScheme.primary,
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
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _exportSessions(BuildContext context) async {
    if (_allSessions.isEmpty) {
      _showErrorDialog('No sessions to export');
      return;
    }

    final yamlContent = _convertSessionsToYaml(_allSessions);
    
    try {
      await Clipboard.setData(ClipboardData(text: yamlContent));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
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
    // ... (keep the existing implementation, it's too long to duplicate here)
    return ''; // Placeholder - keep your existing implementation
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Delete All Data?',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
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
                    _currentBreakDuration = Duration.zero;
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
}
