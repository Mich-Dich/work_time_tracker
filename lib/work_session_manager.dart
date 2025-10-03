import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class WorkSession {
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;
  final Duration breakDuration;
  final List<BreakPeriod> breaks; // Track individual breaks

  WorkSession({
    required this.startTime,
    this.endTime,
    this.duration,
    this.breakDuration = Duration.zero,
    this.breaks = const [],
  });

  WorkSession copyWith({
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    Duration? breakDuration,
    List<BreakPeriod>? breaks,
  }) {
    return WorkSession(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      breakDuration: breakDuration ?? this.breakDuration,
      breaks: breaks ?? this.breaks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration?.inSeconds,
      'breakDuration': breakDuration.inSeconds,
      'breaks': breaks.map((breakPeriod) => breakPeriod.toJson()).toList(),
    };
  }

  factory WorkSession.fromJson(Map<String, dynamic> json) {
    return WorkSession(
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      duration: json['duration'] != null 
          ? Duration(seconds: json['duration'])
          : null,
      breakDuration: json['breakDuration'] != null
          ? Duration(seconds: json['breakDuration'])
          : Duration.zero,
      breaks: json['breaks'] != null
          ? (json['breaks'] as List).map((breakJson) => BreakPeriod.fromJson(breakJson)).toList()
          : [],
    );
  }
}

class BreakPeriod {
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;

  BreakPeriod({
    required this.startTime,
    this.endTime,
    this.duration,
  });

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration?.inSeconds,
    };
  }

  factory BreakPeriod.fromJson(Map<String, dynamic> json) {
    return BreakPeriod(
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      duration: json['duration'] != null ? Duration(seconds: json['duration']) : null,
    );
  }

  BreakPeriod copyWith({
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
  }) {
    return BreakPeriod(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
    );
  }
}

class WorkSessionManager {
  static const String _sessionsKey = 'work_sessions';
  static const String _ongoingSessionKey = 'ongoing_session';
  static const String _ongoingBreakKey = 'ongoing_break';
  
  final List<WorkSession> _sessions = [];

  // Round to nearest quarter hour (15 minutes)
  DateTime roundToNearestQuarterHour(DateTime dateTime) {
    int minutes = dateTime.minute;
    int remainder = minutes % 15;
    
    if (remainder < 8) {
      // Round down
      minutes = minutes - remainder;
    } else {
      // Round up
      minutes = minutes + (15 - remainder);
    }
    
    if (minutes == 60) {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour + 1,
        0,
      );
    } else {
      return DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        minutes,
      );
    }
  }

  Future<void> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = prefs.getStringList(_sessionsKey);
    
    if (sessionsJson != null) {
      _sessions.clear();
      for (final jsonString in sessionsJson) {
        try {
          final sessionMap = json.decode(jsonString);
          _sessions.add(WorkSession.fromJson(sessionMap));
        } catch (e) {
          print('Error parsing session: $e');
        }
      }
      // Sort sessions by start time (newest first)
      _sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = _sessions.map((session) => json.encode(session.toJson())).toList();
    await prefs.setStringList(_sessionsKey, sessionsJson);
  }

  Future<void> startSession() async {
    final prefs = await SharedPreferences.getInstance();
    final roundedStartTime = roundToNearestQuarterHour(DateTime.now());
    final newSession = WorkSession(startTime: roundedStartTime, breaks: []);
    
    // Save ongoing session
    await prefs.setString(_ongoingSessionKey, json.encode(newSession.toJson()));
  }

  Future<void> stopSession() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    
    // Get ongoing session
    final ongoingSessionJson = prefs.getString(_ongoingSessionKey);
    if (ongoingSessionJson != null) {
      final sessionMap = json.decode(ongoingSessionJson);
      final startTime = DateTime.parse(sessionMap['startTime']);
      
      // Calculate total break duration from all breaks
      final List<BreakPeriod> breaks = sessionMap['breaks'] != null
          ? (sessionMap['breaks'] as List).map<BreakPeriod>((breakJson) => BreakPeriod.fromJson(breakJson)).toList()
          : <BreakPeriod>[];
      
      Duration totalBreakDuration = Duration.zero;
      for (final breakPeriod in breaks) {
        if (breakPeriod.duration != null) {
          totalBreakDuration += breakPeriod.duration!;
        }
      }
      
      // Round stop time
      final roundedStopTime = roundToNearestQuarterHour(now);
      
      // Calculate actual duration without forced minimum
      Duration duration;
      if (roundedStopTime.isAfter(startTime)) {
        duration = roundedStopTime.difference(startTime);
      } else {
        // If rounding makes end time before start time, use actual time difference
        // but ensure it's at least 1 minute
        final actualDuration = now.difference(startTime);
        duration = actualDuration.inMinutes > 0 ? actualDuration : Duration(minutes: 1);
      }
      
      // Subtract total break duration from total duration
      final netDuration = duration - totalBreakDuration;
      
      final completedSession = WorkSession(
        startTime: startTime,
        endTime: roundedStopTime,
        duration: netDuration,
        breakDuration: totalBreakDuration,
        breaks: breaks,
      );
      
      _sessions.add(completedSession);
      // Sort sessions by start time (newest first)
      _sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      
      await _saveSessions();
      await prefs.remove(_ongoingSessionKey);
      await prefs.remove(_ongoingBreakKey);
    }
  }

  Future<void> startBreak() async {
    final prefs = await SharedPreferences.getInstance();
    final breakStartTime = DateTime.now();
    
    // Get ongoing session
    final ongoingSessionJson = prefs.getString(_ongoingSessionKey);
    if (ongoingSessionJson != null) {
      final sessionMap = json.decode(ongoingSessionJson);
      final breaks = sessionMap['breaks'] != null
          ? (sessionMap['breaks'] as List).map((breakJson) => BreakPeriod.fromJson(breakJson)).toList()
          : [];
      
      // Add new break period
      breaks.add(BreakPeriod(startTime: breakStartTime));
      
      // Update session with new breaks list
      sessionMap['breaks'] = breaks.map((breakPeriod) => breakPeriod.toJson()).toList();
      await prefs.setString(_ongoingSessionKey, json.encode(sessionMap));
    }
    
    await prefs.setString(_ongoingBreakKey, breakStartTime.toIso8601String());
  }

  Future<void> stopBreak() async {
    final prefs = await SharedPreferences.getInstance();
    final breakEndTime = DateTime.now();
    
    // Get break start time
    final breakStartTimeString = prefs.getString(_ongoingBreakKey);
    if (breakStartTimeString != null) {
      final breakStartTime = DateTime.parse(breakStartTimeString);
      
      // Calculate break duration
      final breakDuration = breakEndTime.difference(breakStartTime);
      
      // Get ongoing session and update the most recent break
      final ongoingSessionJson = prefs.getString(_ongoingSessionKey);
      if (ongoingSessionJson != null) {
        final sessionMap = json.decode(ongoingSessionJson);
        final breaks = sessionMap['breaks'] != null
            ? (sessionMap['breaks'] as List).map((breakJson) => BreakPeriod.fromJson(breakJson)).toList()
            : [];
        
        if (breaks.isNotEmpty) {
          // Update the most recent break (the one we just ended)
          final lastBreak = breaks.last;
          final updatedBreak = lastBreak.copyWith(
            endTime: breakEndTime,
            duration: breakDuration,
          );
          breaks[breaks.length - 1] = updatedBreak;
          
          // Update session with updated breaks list
          sessionMap['breaks'] = breaks.map((breakPeriod) => breakPeriod.toJson()).toList();
          await prefs.setString(_ongoingSessionKey, json.encode(sessionMap));
        }
      }
      
      await prefs.remove(_ongoingBreakKey);
    }
  }

  Future<bool> isBreakOngoing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ongoingBreakKey) != null;
  }

  Future<WorkSession?> getOngoingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final ongoingSessionJson = prefs.getString(_ongoingSessionKey);
    
    if (ongoingSessionJson != null) {
      try {
        final sessionMap = json.decode(ongoingSessionJson);
        return WorkSession.fromJson(sessionMap);
      } catch (e) {
        print('Error parsing ongoing session: $e');
        return null;
      }
    }
    return null;
  }

  List<WorkSession> getTodaySessions() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    return _sessions.where((session) {
      final sessionDay = DateTime(
        session.startTime.year, 
        session.startTime.month, 
        session.startTime.day
      );
      return sessionDay == today && session.endTime != null;
    }).toList();
  }

  List<WorkSession> getAllSessions() {
    return _sessions.where((session) => session.endTime != null).toList();
  }

  Future<void> clearAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    _sessions.clear();
    await prefs.remove(_sessionsKey);
    await prefs.remove(_ongoingSessionKey);
    await prefs.remove(_ongoingBreakKey);
  }

  Future<void> deleteSession(WorkSession sessionToDelete) async {
    _sessions.removeWhere((session) => 
      session.startTime == sessionToDelete.startTime &&
      session.endTime == sessionToDelete.endTime
    );
    await _saveSessions();
  }

  Future<void> updateSession(WorkSession oldSession, WorkSession newSession) async {
    final index = _sessions.indexWhere((session) => 
      session.startTime == oldSession.startTime &&
      session.endTime == oldSession.endTime
    );
    
    if (index != -1) {
      // Calculate duration for the updated session
      final duration = newSession.endTime!.difference(newSession.startTime);
      final updatedSession = newSession.copyWith(duration: duration);
      
      _sessions[index] = updatedSession;
      // Re-sort sessions
      _sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      await _saveSessions();
    }
  }
}