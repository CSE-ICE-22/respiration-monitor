import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sensor_data.dart';

/// BLE service for communicating with RespirationMonitor ESP32 devices
class BleService extends ChangeNotifier {
  static const String targetDeviceName = 'RespirationMonitor';
  static const String serviceUuid = '12345678-1234-1234-1234-123456789abc';
  static const String dataCharacteristicUuid = '87654321-4321-4321-4321-cba987654321';
  static const String controlCharacteristicUuid = '11111111-2222-3333-4444-555555555555';
  static const String lastConnectedDeviceKey = 'last_connected_device';
  
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final StreamController<SensorData> _sensorDataController = StreamController<SensorData>.broadcast();
  final StreamController<BleConnectionState> _connectionStateController = StreamController<BleConnectionState>.broadcast();
  final StreamController<DiscoveredDevice> _scanResultsController = StreamController<DiscoveredDevice>.broadcast();

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;
  QualifiedCharacteristic? _dataCharacteristic;
  QualifiedCharacteristic? _controlCharacteristic;
  
  String? _connectedDeviceId;
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  bool _isScanning = false;
  bool _isMuted = false;
  bool _isNotificationScheduled = false;
  
  // Streams for external consumption
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<BleConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<DiscoveredDevice> get scanResults => _scanResultsController.stream;
  
  // Getters
  bool get isScanning => _isScanning;
  BleConnectionState get connectionState => _connectionState;
  String? get connectedDeviceId => _connectedDeviceId;
  bool get isMuted => _isMuted;

  @override
  void dispose() {
    stopScan();
    _disconnect();
    _sensorDataController.close();
    _connectionStateController.close();
    _scanResultsController.close();
    super.dispose();
  }

  /// Safely notify listeners after the current frame to avoid setState during build
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

  /// Initialize BLE and request necessary permissions
  Future<bool> initialize() async {
    try {
      // Check BLE status
      final bleStatus = await _ble.status;
      print('BLE Status: $bleStatus');
      
      if (bleStatus != BleStatus.ready) {
        print('BLE not ready: $bleStatus');
        return false;
      }

      // Request permissions
      final permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        print('BLE permissions not granted');
        return false;
      }

      print('BLE service initialized successfully');
      return true;
    } catch (e) {
      print('BLE initialization failed: $e');
      return false;
    }
  }

  /// Request necessary BLE and location permissions
  Future<bool> _requestPermissions() async {
    final permissionsToRequest = <Permission>[];

    // Location permission (required for BLE scanning on Android)
    if (Platform.isAndroid) {
      permissionsToRequest.add(Permission.location);
    }

    // Android 12+ BLE permissions
    if (Platform.isAndroid) {
      permissionsToRequest.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]);
    }

    if (permissionsToRequest.isEmpty) return true;

    final statuses = await permissionsToRequest.request();
    
    // Check if all required permissions are granted
    for (final permission in permissionsToRequest) {
      final status = statuses[permission];
      if (status != PermissionStatus.granted) {
        print('Permission $permission not granted: $status');
        
        // For critical permissions, return false
        if (permission == Permission.bluetoothScan || 
            permission == Permission.bluetoothConnect) {
          return false;
        }
      }
    }

    return true;
  }

  /// Start scanning for RespirationMonitor devices
  Future<void> startScan() async {
    if (_isScanning) {
      print('⚠️ Already scanning, ignoring duplicate scan request');
      return;
    }
    
    // Don't scan if already connected
    if (_connectionState == BleConnectionState.connected) {
      print('⚠️ Already connected to a device, not starting scan');
      return;
    }

    try {
      _isScanning = true;
      _safeNotifyListeners();

      print('🔍 Starting BLE scan for $targetDeviceName devices...');
      print('📡 Note: Connected devices do NOT advertise (normal BLE behavior)');
      
      // Scan without service filter for better device discovery
      // Connected devices won't appear because they stop advertising
      _scanSubscription = _ble.scanForDevices(
        withServices: [], // Empty list means scan for all devices
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: false,
      ).listen(
        (device) {
          // Only log devices with names to reduce noise
          if (device.name.isNotEmpty) {
            print('🔍 Discovered: "${device.name}" (${device.id.substring(0, 8)}...) RSSI: ${device.rssi}dBm');
          }
          
          // Filter devices by name (more flexible than service UUID)
          if (device.name.isNotEmpty && 
              (device.name == targetDeviceName || 
               device.name.toLowerCase().contains('respiration') ||
               device.name.toLowerCase().contains('monitor') ||
               device.name.contains('ESP32-Phone-Link'))) {
            print('✅ Found matching device: ${device.name} (${device.id})');
            _scanResultsController.add(device);
          }
        },
        onError: (error) {
          print('❌ Scan error: $error');
        },
      );

      // Stop scanning after 30 seconds
      Timer(const Duration(seconds: 30), () {
        if (_isScanning) {
          print('⏱️ Scan timeout (30s) - stopping scan');
          stopScan();
        }
      });
    } catch (e) {
      print('❌ Failed to start scan: $e');
      _isScanning = false;
      _safeNotifyListeners();
    }
  }

  /// Stop BLE scanning
  void stopScan() {
    if (!_isScanning) {
      print('⚠️ Scan already stopped');
      return;
    }

    _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    _safeNotifyListeners();
    print('🛑 BLE scan stopped');
  }

  /// Debug method to scan and show all nearby BLE devices
  Future<void> startDebugScan() async {
    if (_isScanning) return;

    try {
      _isScanning = true;
      _safeNotifyListeners();

      print('🔍 Starting DEBUG scan - showing ALL BLE devices...');
      
      _scanSubscription = _ble.scanForDevices(
        withServices: [], // Scan for all devices
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: false,
      ).listen(
        (device) {
          print('🔍 DEBUG: Found device "${device.name}" (${device.id}) - RSSI: ${device.rssi}dBm, Services: ${device.serviceUuids}');
          
          // Add ALL devices to results for debugging
          _scanResultsController.add(device);
        },
        onError: (error) {
          print('Debug scan error: $error');
        },
      );

      // Stop scanning after 30 seconds
      Timer(const Duration(seconds: 30), () {
        if (_isScanning) {
          stopScan();
        }
      });
    } catch (e) {
      print('Failed to start debug scan: $e');
      _isScanning = false;
      _safeNotifyListeners();
    }
  }

  /// Connect to a discovered BLE device
  Future<bool> connectToDevice(String deviceId) async {
    if (_connectionState == BleConnectionState.connecting) {
      print('Already connecting to a device');
      return false;
    }

    try {
      // CRITICAL: Stop scanning immediately when initiating connection
      stopScan();
      
      _updateConnectionState(BleConnectionState.connecting);

      print('🔗 Connecting to device: $deviceId');
      print('🔗 Device will stop advertising once connected (normal BLE behavior)');
      
      _connectionSubscription = _ble.connectToDevice(
        id: deviceId,
        connectionTimeout: const Duration(seconds: 15),
      ).listen(
        (connectionState) async {
          print('🔗 Connection state update: ${connectionState.connectionState}');
          
          switch (connectionState.connectionState) {
            case DeviceConnectionState.connecting:
              _updateConnectionState(BleConnectionState.connecting);
              break;
              
            case DeviceConnectionState.connected:
              print('✅ Device connected! Setting up characteristics...');
              _connectedDeviceId = deviceId;
              
              try {
                // Wait a moment for connection to stabilize (bonding may occur)
                await Future.delayed(const Duration(milliseconds: 500));
                
                await _setupCharacteristics(deviceId);
                _saveLastConnectedDevice(deviceId);
                
                print('✅ Connection fully established and characteristics configured');
                _updateConnectionState(BleConnectionState.connected);
              } catch (e) {
                print('❌ Failed to setup characteristics: $e');
                // Disconnect and cleanup if setup fails
                _disconnect();
              }
              break;
              
            case DeviceConnectionState.disconnecting:
              print('🔌 Device disconnecting...');
              _updateConnectionState(BleConnectionState.disconnecting);
              break;
              
            case DeviceConnectionState.disconnected:
              print('🔌 Device disconnected');
              print('📡 Device will resume advertising after ~500ms');
              _connectedDeviceId = null;
              _updateConnectionState(BleConnectionState.disconnected);
              _cleanup();
              
              // Auto-reconnect disabled - user must manually reconnect
              // if (_reconnectAttempts < maxReconnectAttempts) {
              //   _scheduleReconnect(deviceId);
              // }
              break;
          }
        },
        onError: (error) {
          print('❌ Connection error: $error');
          _connectedDeviceId = null;
          _updateConnectionState(BleConnectionState.disconnected);
          _cleanup();
        },
      );

      return true;
    } catch (e) {
      print('❌ Failed to connect: $e');
      _updateConnectionState(BleConnectionState.disconnected);
      return false;
    }
  }

  /// Setup BLE characteristics after connection
  Future<void> _setupCharacteristics(String deviceId) async {
    try {
      print('🔧 Setting up BLE characteristics for device: $deviceId');
      
      final serviceUuidParsed = Uuid.parse(serviceUuid);
      final dataCharUuidParsed = Uuid.parse(dataCharacteristicUuid);
      final controlCharUuidParsed = Uuid.parse(controlCharacteristicUuid);
      
      print('📋 Service UUID: $serviceUuid');
      print('📋 Data Characteristic UUID: $dataCharacteristicUuid');
      print('📋 Control Characteristic UUID: $controlCharacteristicUuid');
      
      // Discover services explicitly
      print('🔍 Explicitly discovering services...');
      try {
        await _ble.discoverServices(deviceId);
        print('✅ Services discovered successfully');
      } catch (e) {
        print('⚠️ Service discovery error (might be okay): $e');
      }
      
      // Wait a bit longer for service discovery to complete
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Setup data characteristic for notifications
      _dataCharacteristic = QualifiedCharacteristic(
        serviceId: serviceUuidParsed,
        characteristicId: dataCharUuidParsed,
        deviceId: deviceId,
      );
      
      // Setup control characteristic for writing commands
      _controlCharacteristic = QualifiedCharacteristic(
        serviceId: serviceUuidParsed,
        characteristicId: controlCharUuidParsed,
        deviceId: deviceId,
      );
      
      print('📝 Characteristics configured:');
      print('   Data: ${_dataCharacteristic?.characteristicId}');
      print('   Control: ${_controlCharacteristic?.characteristicId}');
      
      // Try to read the characteristic first to verify it's accessible
      print('🔍 Testing characteristic accessibility...');
      try {
        final testData = await _ble.readCharacteristic(_dataCharacteristic!);
        print('✅ Successfully read characteristic: ${testData.length} bytes');
        if (testData.isNotEmpty) {
          print('📊 Initial data: ${testData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          // Process initial data
          _handleNotificationData(testData);
        }
      } catch (e) {
        print('⚠️ Could not read characteristic: $e');
        print('⚠️ This is okay if characteristic only supports NOTIFY');
      }

      // Subscribe to DATA characteristic notifications
      print('🔔 Subscribing to DATA characteristic for sensor data...');
      print('🔔 This will enable notifications (write to CCCD descriptor)');
      print('🔔 Device ID: $deviceId');
      print('🔔 Service UUID: $serviceUuid');
      print('🔔 Data Char UUID: $dataCharacteristicUuid');
      
      // CRITICAL: Set up subscription and keep reference active
      _characteristicSubscription?.cancel(); // Cancel any existing subscription
      
      _characteristicSubscription = _ble.subscribeToCharacteristic(_dataCharacteristic!).listen(
        (data) {
          print('🔔 ✅ DATA NOTIFICATION RECEIVED! ${data.length} bytes');
          print('🔔 Raw bytes: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          _handleNotificationData(data);
        },
        onError: (error) {
          print('💥 DATA characteristic subscription error: $error');
          print('💥 Error type: ${error.runtimeType}');
          print('💥 This might mean:');
          print('   - Service/characteristic not found (check UUIDs)');
          print('   - Notifications not supported (check characteristic properties)');
          print('   - Device not properly paired/bonded (check Bluetooth settings)');
          print('   - Connection lost before subscription completed');
        },
        onDone: () {
          print('⚠️ Notification subscription stream closed');
        },
        cancelOnError: false, // Keep subscription active even if errors occur
      );
      
      print('✅ Subscription object created successfully');
      
      // Give subscription time to initialize and CCCD write to complete
      await Future.delayed(const Duration(milliseconds: 1500));

      // Request immediate data to verify the notification system is working
      print('📡 Requesting immediate data from device to test notification system...');
      await Future.delayed(const Duration(milliseconds: 500));
      final requestSuccess = await sendRequestDataCommand();
      if (requestSuccess) {
        print('✅ Data request command sent - device should send notification within 2-3 seconds');
      } else {
        print('⚠️ Failed to send data request command');
      }

      print('✅ BLE characteristics setup complete');
      print('✅ Waiting for notifications from device...');
      print('✅ Device should send data every ~60 seconds');
      print('💡 TIP: If no notifications arrive, try:');
      print('   1. Check device is sending (nRF Connect should show notifications)');
      print('   2. Press "Request Immediate Data" in Settings');
      print('   3. Check device bonding in system Bluetooth settings');
    } catch (e, stackTrace) {
      print('❌ Failed to setup characteristics: $e');
      print('❌ Stack trace: $stackTrace');
      throw e;
    }
  }

  /// Handle incoming notification data from the ESP32
  void _handleNotificationData(List<int> data) {
    try {
      print('═══════════════════════════════════════════════════════');
      print('📊 NOTIFICATION RECEIVED! Processing data...');
      print('📊 Timestamp: ${DateTime.now()}');
      print('📊 Data length: ${data.length} bytes (expected: 20 or 22 bytes)');
      print('📊 Raw bytes (hex): ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('───────────────────────────────────────────────────────');
      
      if (data.isEmpty) {
        print('⚠️ Received empty data packet!');
        return;
      }
      
      final sensorData = SensorDataParser.parseFromBytes(data);
      if (sensorData != null) {
        // Update mute status from status byte if available
        // Extract mute status from device (for reference only, trust local state)
        if (data.length >= 8) {
          final status = data[7];
          final deviceMuted = SensorDataParser.isMutedFromStatus(status);
          // Note: We don't update _isMuted here to preserve user's manual mute/unmute commands
          // The local _isMuted state is managed by sendMuteCommand(), sendUnmuteCommand(), and sendResetCommand()
          print('📊 Device muted status from hardware: $deviceMuted (local state: $_isMuted)');
        }
        
        print('✅ Sensor data parsed successfully!');
        print('📊 CO2: ${sensorData.co2} ppm');
        print('📊 Temperature: ${sensorData.temperature}°C');
        print('📊 Humidity: ${sensorData.humidity}%');
        print('📊 Alert Level: ${sensorData.alert}');
        print('📊 Has stream listeners: ${_sensorDataController.hasListener}');
        
        _sensorDataController.add(sensorData);
        print('✅ Sensor data emitted to stream');
      } else {
        print('❌ Failed to parse sensor data from notification');
        print('❌ Parser returned null');
      }
      print('═══════════════════════════════════════════════════════');
    } catch (e, stackTrace) {
      print('═══════════════════════════════════════════════════════');
      print('❌ ERROR handling notification data: $e');
      print('❌ Stack trace: $stackTrace');
      print('❌ Raw data length: ${data.length}');
      print('❌ Raw data (hex): ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('═══════════════════════════════════════════════════════');
    }
  }

  /// Send control command to ESP32 (single character ASCII)
  /// Commands: "0" = None, "1" = Mute Buzzer, "2" = Force Sleep, "3" = Request Data, "4" = Reset Alerts, "5" = Unmute Buzzer
  Future<bool> sendControlCommand(String command) async {
    if (_controlCharacteristic == null || _connectionState != BleConnectionState.connected) {
      print('Cannot send command: not connected or characteristic not available');
      return false;
    }
    
    if (command.length != 1) {
      print('Invalid command: must be single character');
      return false;
    }
    
    try {
      final bytes = command.codeUnits; // Convert to ASCII bytes
      
      print('Sending control command: "$command" (${bytes[0]})');
      
      await _ble.writeCharacteristicWithResponse(
        _controlCharacteristic!,
        value: bytes,
      );
      
      print('Control command sent successfully');
      return true;
    } catch (e) {
      print('Failed to send control command: $e');
      return false;
    }
  }

  /// Send mute command (command "1")
  Future<bool> sendMuteCommand() async {
    final success = await sendControlCommand("1");
    if (success) {
      _isMuted = true;
      _safeNotifyListeners();
    }
    return success;
  }

  /// Send force sleep command (command "2")
  Future<bool> sendSleepCommand() async {
    return await sendControlCommand("2");
  }

  /// Send request immediate data command (command "3")
  Future<bool> sendRequestDataCommand() async {
    return await sendControlCommand("3");
  }

  /// Send reset alerts command (command "4")
  Future<bool> sendResetCommand() async {
    final success = await sendControlCommand("4");
    if (success) {
      _isMuted = false;
      _safeNotifyListeners();
    }
    return success;
  }

  /// Send unmute buzzer command (command "5")
  Future<bool> sendUnmuteCommand() async {
    final success = await sendControlCommand("5");
    if (success) {
      _isMuted = false;
      _safeNotifyListeners();
    }
    return success;
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    await _disconnect();
  }

  /// Internal disconnect method
  Future<void> _disconnect() async {
    if (_connectionState == BleConnectionState.disconnected) return;

    print('Disconnecting from device');
    
    _cleanup();
    _connectedDeviceId = null;
    _updateConnectionState(BleConnectionState.disconnected);
  }

  /// Clean up subscriptions and characteristics
  void _cleanup() {
    print('🧹 Cleaning up BLE resources...');
    
    _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _dataCharacteristic = null;
    _controlCharacteristic = null;
    
    print('✅ Cleanup complete');
  }

  /// Update connection state and notify listeners
  void _updateConnectionState(BleConnectionState newState) {
    _connectionState = newState;
    _connectionStateController.add(newState);
    _safeNotifyListeners();
  }

  /// Save the last connected device ID to SharedPreferences
  Future<void> _saveLastConnectedDevice(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastConnectedDeviceKey, deviceId);
    } catch (e) {
      print('Failed to save last connected device: $e');
    }
  }

  /// Get the last connected device ID from SharedPreferences
  Future<String?> getLastConnectedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(lastConnectedDeviceKey);
    } catch (e) {
      print('Failed to get last connected device: $e');
      return null;
    }
  }

  /// Clear the saved last connected device
  Future<void> clearLastConnectedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastConnectedDeviceKey);
    } catch (e) {
      print('Failed to clear last connected device: $e');
    }
  }
}

/// Enum representing BLE connection states
enum BleConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

extension BleConnectionStateExtension on BleConnectionState {
  String get displayName {
    switch (this) {
      case BleConnectionState.disconnected:
        return 'Disconnected';
      case BleConnectionState.connecting:
        return 'Connecting';
      case BleConnectionState.connected:
        return 'Connected';
      case BleConnectionState.disconnecting:
        return 'Disconnecting';
    }
  }
}
