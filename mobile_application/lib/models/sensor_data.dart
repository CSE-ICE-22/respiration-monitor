import 'dart:convert';
import 'dart:typed_data';

/// Represents sensor data received from the ESP32 BLE peripheral
class SensorData {
  final double co2;
  final double humidity;
  final double temperature;
  final int alert;
  final DateTime timestamp;

  SensorData({
    required this.co2,
    required this.humidity,
    required this.temperature,
    required this.alert,
    required this.timestamp,
  });

  /// Creates a SensorData instance from a JSON map
  /// 
  /// Validates all fields and provides safe defaults where needed.
  /// Throws FormatException for invalid or missing required fields.
  factory SensorData.fromJson(Map<String, dynamic> json) {
    try {
      // Validate and convert CO₂ reading (must be non-negative)
      final co2Value = _parseDouble(json['co2'], 'co2');
      if (co2Value < 0) {
        throw FormatException('CO₂ value cannot be negative: $co2Value');
      }

      // Validate and convert humidity (should be 0-100%)
      final humidityValue = _parseDouble(json['humidity'], 'humidity');
      if (humidityValue < 0 || humidityValue > 100) {
        throw FormatException('Humidity value out of range: $humidityValue');
      }

      // Temperature can be negative (e.g., below freezing)
      final temperatureValue = _parseDouble(json['temperature'], 'temperature');

      // Alert code validation (0-4 from ESP32: NONE, LOW, MEDIUM, HIGH, CRITICAL)
      final alertValue = json['alert'] is num ? (json['alert'] as num).toInt() : 0;
      if (alertValue < 0 || alertValue > 4) {
        throw FormatException('Alert value out of range: $alertValue');
      }

      // Parse timestamp - ESP32 sends millis() which needs to be converted to DateTime
      DateTime timestampValue;
      if (json['timestamp'] != null) {
        // ESP32 millis() is relative to boot time, so use current time instead
        timestampValue = DateTime.now();
      } else {
        timestampValue = DateTime.now();
      }

      return SensorData(
        co2: co2Value,
        humidity: humidityValue,
        temperature: temperatureValue,
        alert: alertValue,
        timestamp: timestampValue,
      );
    } catch (e) {
      throw FormatException('Invalid sensor data JSON: $e');
    }
  }

  /// Helper method to safely parse double values from JSON
  static double _parseDouble(dynamic value, String fieldName) {
    if (value == null) {
      throw FormatException('Missing required field: $fieldName');
    }
    if (value is num) {
      return value.toDouble();
    }
    throw FormatException('Invalid type for field $fieldName: expected number, got ${value.runtimeType}');
  }

  /// Converts the sensor data to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'co2': co2,
      'humidity': humidity,
      'temperature': temperature,
      'alert': alert,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Returns a formatted string representation of the sensor data
  @override
  String toString() {
    return 'SensorData(co2: ${co2.toStringAsFixed(1)} ppm, '
           'humidity: ${humidity.toStringAsFixed(1)}%, '
           'temperature: ${temperature.toStringAsFixed(1)}°C, '
           'alert: $alert, '
           'timestamp: $timestamp)';
  }

  /// Returns the alert level as a descriptive string
  String get alertDescription {
    switch (alert) {
      case 0:
        return 'Normal';
      case 1:
        return 'Low Alert';
      case 2:
        return 'Medium Alert';
      case 3:
        return 'High Alert';
      case 4:
        return 'Critical Alert';
      default:
        return 'Unknown';
    }
  }

  /// Returns the appropriate color for the alert level
  /// Used for UI indicators
  int get alertColor {
    switch (alert) {
      case 0:
        return 0xFF4CAF50; // Green
      case 1:
        return 0xFFFFEB3B; // Yellow
      case 2:
        return 0xFFFF9800; // Orange
      case 3:
        return 0xFFFF5722; // Deep Orange
      case 4:
        return 0xFFF44336; // Red
      default:
        return 0xFF9E9E9E; // Grey
    }
  }

  /// Creates a copy of this sensor data with optionally updated values
  SensorData copyWith({
    double? co2,
    double? humidity,
    double? temperature,
    int? alert,
    DateTime? timestamp,
  }) {
    return SensorData(
      co2: co2 ?? this.co2,
      humidity: humidity ?? this.humidity,
      temperature: temperature ?? this.temperature,
      alert: alert ?? this.alert,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorData &&
        other.co2 == co2 &&
        other.humidity == humidity &&
        other.temperature == temperature &&
        other.alert == alert &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return co2.hashCode ^
        humidity.hashCode ^
        temperature.hashCode ^
        alert.hashCode ^
        timestamp.hashCode;
  }
}

/// Utility class for parsing JSON strings to SensorData
class SensorDataParser {
  /// Parses a UTF-8 JSON string to a SensorData object
  /// 
  /// Returns null if the JSON is malformed or invalid.
  /// This is the main entry point for parsing BLE notification data.
  static SensorData? parseFromString(String jsonString) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      return SensorData.fromJson(json);
    } catch (e) {
      // Log error in production app - for now just return null
      print('Failed to parse sensor data: $e');
      return null;
    }
  }

  /// Parses raw bytes from ESP32 SensorPacket to a SensorData object
  /// 
  /// ESP32 sends binary data in SensorPacket format (20 or 22 bytes):
  /// uint16_t co2;           // CO2 in ppm (2 bytes, offset 0)
  /// int16_t humidity;       // Humidity * 10 (2 bytes, offset 2) 
  /// int16_t temperature;    // Temperature * 10 (2 bytes, offset 4)
  /// uint8_t alert;          // Alert level 0-3 (1 byte, offset 6)
  /// uint8_t status;         // Status flags (1 byte, offset 7)
  /// uint32_t timestamp;     // Timestamp in seconds since boot (4 bytes, offset 8)
  /// uint32_t sequence;      // Sequence number (4 bytes, offset 12)
  /// uint8_t[4-6] reserved;  // Reserved for future use (4-6 bytes, offset 16)
  static SensorData? parseFromBytes(List<int> bytes) {
    try {
      // Validate packet size - accept both 20 and 22 byte packets
      // (ESP32 may send 20 bytes instead of 22)
      if (bytes.length < 16) {
        print('Invalid binary packet size: minimum 16 bytes required, got ${bytes.length}');
        return null;
      }
      
      if (bytes.length != 20 && bytes.length != 22) {
        print('Warning: unexpected packet size ${bytes.length} bytes (expected 20 or 22)');
        // Continue parsing anyway if we have at least the core data
      }
      
      // Parse binary data (little-endian format)
      final ByteData byteData = Uint8List.fromList(bytes).buffer.asByteData();
      
      final int co2 = byteData.getUint16(0, Endian.little);
      final int humidityRaw = byteData.getInt16(2, Endian.little);
      final int temperatureRaw = byteData.getInt16(4, Endian.little);
      final int alert = byteData.getUint8(6);
      final int status = byteData.getUint8(7);
      final int deviceTimestamp = byteData.getUint32(8, Endian.little);
      final int sequence = byteData.getUint32(12, Endian.little);
      
      // Convert scaled values back to doubles
      final double humidity = humidityRaw / 10.0;
      final double temperature = temperatureRaw / 10.0;
      
      // Validate ranges
      if (co2 < 0 || co2 > 65535) {
        print('CO2 value out of range: $co2');
        return null;
      }
      
      if (humidity < 0 || humidity > 100) {
        print('Humidity value out of range: $humidity');
        return null;
      }
      
      if (alert < 0 || alert > 3) {
        print('Alert value out of range: $alert');
        return null;
      }
      
      // Parse status flags
      final bool isValidData = (status & 0x01) != 0;
      final bool isMuted = (status & 0x02) != 0;
      final bool isAverage = (status & 0x80) != 0;
      
      if (!isValidData) {
        print('Received invalid sensor data packet');
        return null;
      }
      
      print('Parsed ${bytes.length}-byte binary sensor data:');
      print('  CO2: ${co2}ppm (raw: 0x${co2.toRadixString(16)})');
      print('  Temp: ${temperature}°C (raw: 0x${temperatureRaw.toRadixString(16)})');
      print('  Humidity: ${humidity}% (raw: 0x${humidityRaw.toRadixString(16)})');
      print('  Alert: $alert');
      print('  Status: 0x${status.toRadixString(16)} - Valid=$isValidData, Muted=$isMuted, Average=$isAverage');
      print('  Device Timestamp: ${deviceTimestamp}s');
      print('  Sequence: $sequence');
      
      return SensorData(
        co2: co2.toDouble(),
        humidity: humidity,
        temperature: temperature,
        alert: alert,
        timestamp: DateTime.now(), // Use current time since ESP32 timestamp is relative
      );
      
    } catch (e) {
      print('Failed to parse binary sensor data: $e');
      return null;
    }
  }
  
  /// Get mute status from status byte
  static bool isMutedFromStatus(int status) {
    return (status & 0x02) != 0;
  }
  
  /// Get data validity from status byte
  static bool isValidFromStatus(int status) {
    return (status & 0x01) != 0;
  }
  
  /// Get data type from status byte (instantaneous vs average)
  static bool isAverageFromStatus(int status) {
    return (status & 0x80) != 0;
  }
}
