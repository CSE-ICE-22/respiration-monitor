import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sensor_data.dart';
import '../services/ble_service.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';
import '../widgets/charts.dart';
import 'settings_screen_new.dart';
import 'session_history_screen.dart';
import 'scan_screen.dart';

/// Main dashboard screen showing real-time sensor data and charts
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final Queue<SensorData> _sensorDataHistory = Queue<SensorData>();
  static const int maxHistoryLength = 300; // Keep last 300 samples
  static const int chartDisplayLength = 60; // Show last 60 in sparklines
  
  SensorData? _latestData;
  String _selectedChartMetric = 'co2';
  StreamSubscription<SensorData>? _sensorDataSubscription;
  StreamSubscription<BleConnectionState>? _connectionStateSubscription;
  
  // Connection state
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  String? _connectedDeviceName;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeDashboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sensorDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes for background monitoring
    if (state == AppLifecycleState.resumed) {
      print('App resumed - refreshing connection status');
    } else if (state == AppLifecycleState.paused) {
      print('App paused - notifications will continue in background');
    }
  }

  void _initializeDashboard() {
    final bleService = context.read<BleService>();
    final sessionService = context.read<SessionService>();
    final notificationService = context.read<NotificationService>();
    
    print('📱 Dashboard initializing...');
    
    // Start a new session
    sessionService.startSession();
    print('📱 Session started');
    
    // Listen to sensor data
    print('📱 Setting up sensor data stream listener...');
    _sensorDataSubscription = bleService.sensorDataStream.listen(
      (data) {
        print('📱 ✅ Dashboard received sensor data!');
        if (mounted) {
          _addSensorData(data);
          sessionService.addSensorData(data);
          notificationService.processSensorData(data);
        }
      },
      onError: (error) {
        print('📱 ❌ Error in sensor data stream: $error');
      },
      onDone: () {
        print('📱 ⚠️ Sensor data stream closed');
      },
    );
    print('📱 Sensor data stream listener active');
    
    // Listen to connection state changes
    _connectionStateSubscription = bleService.connectionStateStream.listen((state) {
      print('📱 Connection state changed: $state');
      if (mounted) {
        setState(() {
          _connectionState = state;
          if (state == BleConnectionState.disconnected) {
            _connectedDeviceName = null;
          } else if (state == BleConnectionState.connected) {
            _connectedDeviceName = bleService.connectedDeviceId?.substring(0, 8);
          }
        });
        
        // Handle disconnection
        if (state == BleConnectionState.disconnected) {
          _handleDisconnection();
        }
      }
    });
    
    // Get current connection state
    _connectionState = bleService.connectionState;
    _connectedDeviceName = bleService.connectedDeviceId?.substring(0, 8);
    print('📱 Dashboard initialized. Connection state: $_connectionState');
  }

  void _addSensorData(SensorData data) {
    print('📱 Adding sensor data to history: CO2=${data.co2}, Temp=${data.temperature}, Humidity=${data.humidity}');
    setState(() {
      _latestData = data;
      _sensorDataHistory.addLast(data);
      
      // Keep only the last maxHistoryLength samples
      while (_sensorDataHistory.length > maxHistoryLength) {
        _sensorDataHistory.removeFirst();
      }
    });
  }

  Future<void> _handleDisconnection() async {
    if (!mounted) return;
    
    final sessionService = context.read<SessionService>();
    
    // End the session
    await sessionService.endSession();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Device Disconnected',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: const Text(
            'The RespirationMonitor device has been disconnected. '
            'Your session data has been saved.'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog only - stay on dashboard
              },
              child: const Text('Stay Here'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const ScanScreen(),
                  ),
                );
              },
              child: const Text('Reconnect'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _disconnect() async {
    final bleService = context.read<BleService>();
    final sessionService = context.read<SessionService>();
    
    // Save session before disconnecting
    await sessionService.endSession();
    
    await bleService.disconnect();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ScanScreen(),
        ),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SessionHistoryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bleService = context.watch<BleService>();
    final sessionService = context.watch<SessionService>();
    
    final displayData = _sensorDataHistory.length > chartDisplayLength 
        ? _sensorDataHistory.toList().sublist(_sensorDataHistory.length - chartDisplayLength)
        : _sensorDataHistory.toList();
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Respiration Monitor'),
            if (_connectedDeviceName != null)
              Text(
                'Device: $_connectedDeviceName',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          // Mute status indicator
          if (bleService.isMuted)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('MUTED'),
                avatar: const Icon(Icons.volume_off, size: 16),
                backgroundColor: theme.colorScheme.errorContainer,
                labelStyle: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          // Connection status indicator
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getConnectionColor(),
            ),
          ),
          // History button
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
            tooltip: 'Session History',
          ),
          // Settings button
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
        automaticallyImplyLeading: false,
      ),
      body: _latestData == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Waiting for sensor data...',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your device is connected',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                // Request immediate data from device
                await bleService.sendRequestDataCommand();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Session info card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.fiber_manual_record,
                                  color: Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording Session',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const Spacer(),
                                Text(
                                  '${sessionService.currentSessionDataCount} samples',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            if (sessionService.sessionStartTime != null)
                              Text(
                                'Started: ${_formatTime(sessionService.sessionStartTime!)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Status card with alert indicator
                    Card(
                      color: Color(_latestData!.alertColor).withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(_latestData!.alertColor),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Air Quality: ${_latestData!.alertDescription}',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Last updated: ${_formatTimestamp(_latestData!.timestamp)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Metric cards
                    Column(
                      children: [
                        MetricCard(
                          title: 'CO₂ Level',
                          value: _latestData!.co2,
                          unit: 'ppm',
                          data: displayData,
                          metric: 'co2',
                          color: const Color(0xFF2196F3),
                          icon: Icons.co2,
                        ),
                        const SizedBox(height: 12),
                        MetricCard(
                          title: 'Humidity',
                          value: _latestData!.humidity,
                          unit: '%',
                          data: displayData,
                          metric: 'humidity',
                          color: const Color(0xFF00BCD4),
                          icon: Icons.water_drop,
                        ),
                        const SizedBox(height: 12),
                        MetricCard(
                          title: 'Temperature',
                          value: _latestData!.temperature,
                          unit: '°C',
                          data: displayData,
                          metric: 'temperature',
                          color: const Color(0xFFFF5722),
                          icon: Icons.thermostat,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Time series chart
                    TimeSeriesChart(
                      data: _sensorDataHistory.toList(),
                      selectedMetric: _selectedChartMetric,
                      onMetricChanged: (metric) {
                        setState(() {
                          _selectedChartMetric = metric;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Quick actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await bleService.sendRequestDataCommand();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Requesting immediate data update'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Request Data'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _disconnect,
                            icon: const Icon(Icons.stop),
                            label: const Text('End Session'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.errorContainer,
                              foregroundColor: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Color _getConnectionColor() {
    switch (_connectionState) {
      case BleConnectionState.connected:
        return Colors.green;
      case BleConnectionState.connecting:
        return Colors.orange;
      case BleConnectionState.disconnecting:
        return Colors.orange;
      case BleConnectionState.disconnected:
        return Colors.red;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
