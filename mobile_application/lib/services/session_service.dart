import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../models/sensor_data.dart';

/// Service for managing monitoring sessions and data persistence
class SessionService extends ChangeNotifier {
  List<SensorData> _currentSessionData = [];
  DateTime? _sessionStartTime;
  bool _saveCurrentSession = true;
  bool _isNotificationScheduled = false;
  
  List<SensorData> get currentSessionData => List.unmodifiable(_currentSessionData);
  DateTime? get sessionStartTime => _sessionStartTime;
  bool get saveCurrentSession => _saveCurrentSession;
  int get currentSessionDataCount => _currentSessionData.length;
  
  /// Safely notify listeners after the current frame
  void _safeNotifyListeners() {
    if (_isNotificationScheduled) return;
    
    _isNotificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _isNotificationScheduled = false;
      if (hasListeners) {
        notifyListeners();
      }
    });
  }
  
  /// Start a new monitoring session
  void startSession() {
    _currentSessionData.clear();
    _sessionStartTime = DateTime.now();
    _safeNotifyListeners();
    print('Session started at $_sessionStartTime');
  }
  
  /// Add sensor data to the current session
  void addSensorData(SensorData data) {
    _currentSessionData.add(data);
    _safeNotifyListeners();
  }
  
  /// Set whether to save the current session
  void setSaveSession(bool save) {
    _saveCurrentSession = save;
    _safeNotifyListeners();
  }
  
  /// End the current session and save if enabled
  Future<bool> endSession() async {
    if (_currentSessionData.isEmpty || _sessionStartTime == null) {
      print('No session data to save');
      clearSession();
      return false;
    }
    
    if (_saveCurrentSession) {
      final success = await _saveSession();
      if (success) {
        print('Session saved successfully');
      } else {
        print('Failed to save session');
      }
      clearSession();
      return success;
    } else {
      print('Session not saved (user choice)');
      clearSession();
      return true;
    }
  }
  
  /// Clear the current session data
  void clearSession() {
    _currentSessionData.clear();
    _sessionStartTime = null;
    _safeNotifyListeners();
  }
  
  /// Save the current session to disk
  Future<bool> _saveSession() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionsDir = Directory('${directory.path}/sessions');
      
      // Create sessions directory if it doesn't exist
      if (!await sessionsDir.exists()) {
        await sessionsDir.create(recursive: true);
      }
      
      // Generate filename with timestamp
      final endTime = DateTime.now();
      final filename = 'session_${DateFormat('yyyy-MM-dd_HH-mm-ss').format(endTime)}.json';
      final file = File('${sessionsDir.path}/$filename');
      
      // Create session metadata
      final sessionData = {
        'startTime': _sessionStartTime!.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': endTime.difference(_sessionStartTime!).inSeconds,
        'dataPoints': _currentSessionData.length,
        'data': _currentSessionData.map((d) => d.toJson()).toList(),
      };
      
      // Write to file
      await file.writeAsString(jsonEncode(sessionData));
      print('Session saved to: ${file.path}');
      
      return true;
    } catch (e) {
      print('Error saving session: $e');
      return false;
    }
  }
  
  /// Get list of all saved sessions
  Future<List<SessionMetadata>> getSavedSessions() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionsDir = Directory('${directory.path}/sessions');
      
      if (!await sessionsDir.exists()) {
        return [];
      }
      
      final files = await sessionsDir.list().toList();
      final sessions = <SessionMetadata>[];
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            
            sessions.add(SessionMetadata(
              filePath: file.path,
              startTime: DateTime.parse(json['startTime']),
              endTime: DateTime.parse(json['endTime']),
              duration: Duration(seconds: json['duration']),
              dataPoints: json['dataPoints'],
            ));
          } catch (e) {
            print('Error reading session file ${file.path}: $e');
          }
        }
      }
      
      // Sort by end time, most recent first
      sessions.sort((a, b) => b.endTime.compareTo(a.endTime));
      
      return sessions;
    } catch (e) {
      print('Error getting saved sessions: $e');
      return [];
    }
  }
  
  /// Load session data from file
  Future<List<SensorData>?> loadSession(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final dataList = json['data'] as List;
      
      return dataList
          .map((d) => SensorData.fromJson(d as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading session: $e');
      return null;
    }
  }
  
  /// Delete a saved session
  Future<bool> deleteSession(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        _safeNotifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting session: $e');
      return false;
    }
  }
  
  /// Export session to CSV format
  Future<String?> exportSessionToCsv(String filePath) async {
    try {
      final data = await loadSession(filePath);
      if (data == null) return null;
      
      final csv = StringBuffer();
      csv.writeln('Timestamp,CO2 (ppm),Humidity (%),Temperature (°C),Alert Level');
      
      for (final point in data) {
        csv.writeln(
          '${point.timestamp.toIso8601String()},'
          '${point.co2},'
          '${point.humidity},'
          '${point.temperature},'
          '${point.alert}'
        );
      }
      
      // Save CSV file
      final file = File(filePath.replaceAll('.json', '.csv'));
      await file.writeAsString(csv.toString());
      
      return file.path;
    } catch (e) {
      print('Error exporting session to CSV: $e');
      return null;
    }
  }
  
  /// Delete old sessions (keep only last N days)
  Future<int> cleanupOldSessions({int daysToKeep = 30}) async {
    try {
      final sessions = await getSavedSessions();
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      int deletedCount = 0;
      
      for (final session in sessions) {
        if (session.endTime.isBefore(cutoffDate)) {
          final success = await deleteSession(session.filePath);
          if (success) deletedCount++;
        }
      }
      
      print('Cleaned up $deletedCount old sessions');
      return deletedCount;
    } catch (e) {
      print('Error cleaning up old sessions: $e');
      return 0;
    }
  }
  
  /// Get session statistics
  SessionStatistics? getSessionStatistics() {
    if (_currentSessionData.isEmpty) return null;
    
    final co2Values = _currentSessionData.map((d) => d.co2).toList();
    final humidityValues = _currentSessionData.map((d) => d.humidity).toList();
    final temperatureValues = _currentSessionData.map((d) => d.temperature).toList();
    
    return SessionStatistics(
      co2Min: co2Values.reduce((a, b) => a < b ? a : b),
      co2Max: co2Values.reduce((a, b) => a > b ? a : b),
      co2Avg: co2Values.reduce((a, b) => a + b) / co2Values.length,
      humidityMin: humidityValues.reduce((a, b) => a < b ? a : b),
      humidityMax: humidityValues.reduce((a, b) => a > b ? a : b),
      humidityAvg: humidityValues.reduce((a, b) => a + b) / humidityValues.length,
      temperatureMin: temperatureValues.reduce((a, b) => a < b ? a : b),
      temperatureMax: temperatureValues.reduce((a, b) => a > b ? a : b),
      temperatureAvg: temperatureValues.reduce((a, b) => a + b) / temperatureValues.length,
      maxAlertLevel: _currentSessionData.map((d) => d.alert).reduce((a, b) => a > b ? a : b),
    );
  }
}

/// Metadata for a saved session
class SessionMetadata {
  final String filePath;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final int dataPoints;
  
  SessionMetadata({
    required this.filePath,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.dataPoints,
  });
  
  String get displayName {
    return DateFormat('MMM d, yyyy - HH:mm').format(endTime);
  }
  
  String get durationString {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}

/// Statistics for a session
class SessionStatistics {
  final double co2Min;
  final double co2Max;
  final double co2Avg;
  final double humidityMin;
  final double humidityMax;
  final double humidityAvg;
  final double temperatureMin;
  final double temperatureMax;
  final double temperatureAvg;
  final int maxAlertLevel;
  
  SessionStatistics({
    required this.co2Min,
    required this.co2Max,
    required this.co2Avg,
    required this.humidityMin,
    required this.humidityMax,
    required this.humidityAvg,
    required this.temperatureMin,
    required this.temperatureMax,
    required this.temperatureAvg,
    required this.maxAlertLevel,
  });
}
