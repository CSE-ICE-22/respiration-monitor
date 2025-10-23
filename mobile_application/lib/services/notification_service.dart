import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../models/sensor_data.dart';

/// Service for managing notifications and alerts
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  int _lastAlertLevel = 0;
  DateTime? _lastAlertTime;
  
  /// Initialize the notification service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      final initialized = await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      if (initialized == true) {
        _isInitialized = true;
        print('Notification service initialized successfully');
        
        // Request permissions for Android 13+
        await _requestPermissions();
        
        return true;
      }
      
      return false;
    } catch (e) {
      print('Failed to initialize notification service: $e');
      return false;
    }
  }
  
  /// Request notification permissions
  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }
  
  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Could navigate to dashboard or specific screen
  }
  
  /// Process sensor data and trigger alerts if needed
  Future<void> processSensorData(SensorData data) async {
    if (!_isInitialized) {
      print('Notification service not initialized');
      return;
    }
    
    // Only alert if level has increased or it's been more than 5 minutes since last alert
    final now = DateTime.now();
    final shouldAlert = data.alert > _lastAlertLevel ||
        (_lastAlertTime != null && now.difference(_lastAlertTime!).inMinutes >= 5);
    
    if (data.alert > 0 && shouldAlert) {
      await _showAlert(data);
      await _vibrate(data.alert);
      _lastAlertLevel = data.alert;
      _lastAlertTime = now;
    } else if (data.alert == 0) {
      // Reset alert level when back to normal
      _lastAlertLevel = 0;
    }
  }
  
  /// Show notification alert
  Future<void> _showAlert(SensorData data) async {
    try {
      final alertInfo = _getAlertInfo(data.alert);
      
      final androidDetails = AndroidNotificationDetails(
        'respiration_alerts',
        'Respiration Alerts',
        channelDescription: 'Alerts for air quality issues',
        importance: alertInfo.importance,
        priority: alertInfo.priority,
        icon: '@mipmap/ic_launcher',
        color: alertInfo.colorValue,
        enableVibration: true,
        playSound: true,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(
        data.alert, // Use alert level as notification ID
        alertInfo.title,
        alertInfo.message(data),
        notificationDetails,
        payload: 'alert_${data.alert}',
      );
      
      print('Alert notification shown: ${alertInfo.title}');
    } catch (e) {
      print('Error showing alert notification: $e');
    }
  }
  
  /// Vibrate device based on alert level
  Future<void> _vibrate(int alertLevel) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;
      
      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      
      if (hasCustom == true) {
        // Custom vibration patterns
        switch (alertLevel) {
          case 1: // Low
            await Vibration.vibrate(duration: 200);
            break;
          case 2: // Medium
            await Vibration.vibrate(pattern: [0, 200, 100, 200]);
            break;
          case 3: // High
            await Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300]);
            break;
        }
      } else {
        // Simple vibration
        await Vibration.vibrate(duration: 500);
      }
    } catch (e) {
      print('Error vibrating device: $e');
    }
  }
  
  /// Get alert information based on alert level
  _AlertInfo _getAlertInfo(int alertLevel) {
    switch (alertLevel) {
      case 1:
        return _AlertInfo(
          title: 'Low Air Quality Alert',
          message: (data) => 'CO₂: ${data.co2.toStringAsFixed(0)} ppm - Consider ventilating the room',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          colorValue: const Color(0xFFFFEB3B),
        );
      case 2:
        return _AlertInfo(
          title: 'Medium Air Quality Alert',
          message: (data) => 'CO₂: ${data.co2.toStringAsFixed(0)} ppm - Please ventilate the room',
          importance: Importance.high,
          priority: Priority.high,
          colorValue: const Color(0xFFFF9800),
        );
      case 3:
        return _AlertInfo(
          title: 'High Air Quality Alert!',
          message: (data) => 'CO₂: ${data.co2.toStringAsFixed(0)} ppm - Immediate ventilation required!',
          importance: Importance.max,
          priority: Priority.max,
          colorValue: const Color(0xFFF44336),
        );
      default:
        return _AlertInfo(
          title: 'Air Quality Normal',
          message: (data) => 'CO₂: ${data.co2.toStringAsFixed(0)} ppm',
          importance: Importance.low,
          priority: Priority.low,
          colorValue: const Color(0xFF4CAF50),
        );
    }
  }
  
  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
  
  /// Cancel specific notification
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
  
  /// Reset alert tracking
  void resetAlerts() {
    _lastAlertLevel = 0;
    _lastAlertTime = null;
  }
}

/// Alert information helper class
class _AlertInfo {
  final String title;
  final String Function(SensorData) message;
  final Importance importance;
  final Priority priority;
  final Color colorValue;
  
  _AlertInfo({
    required this.title,
    required this.message,
    required this.importance,
    required this.priority,
    required this.colorValue,
  });
}
