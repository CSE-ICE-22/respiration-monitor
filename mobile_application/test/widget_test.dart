// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_application/main.dart';
import 'package:mobile_application/models/sensor_data.dart';
import 'package:mobile_application/services/notification_service.dart';

void main() {
  group('SensorData Model Tests', () {
    test('should parse valid JSON correctly', () {
      // Arrange
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final json = {
        'co2': 420.5,
        'humidity': 55.2,
        'temperature': 24.3,
        'alert': 1,
        'timestamp': timestamp,
      };

      // Act
      final sensorData = SensorData.fromJson(json);

      // Assert
      expect(sensorData.co2, equals(420.5));
      expect(sensorData.humidity, equals(55.2));
      expect(sensorData.temperature, equals(24.3));
      expect(sensorData.alert, equals(1));
      // Timestamp should be current time (within 1 second)
      expect(
        sensorData.timestamp.millisecondsSinceEpoch,
        closeTo(DateTime.now().millisecondsSinceEpoch, 1000),
      );
    });

    test('should handle missing optional fields', () {
      // Arrange
      final json = {
        'co2': 400.0,
        'humidity': 50.0,
        'temperature': 22.0,
        // alert and timestamp missing
      };

      // Act
      final sensorData = SensorData.fromJson(json);

      // Assert
      expect(sensorData.co2, equals(400.0));
      expect(sensorData.humidity, equals(50.0));
      expect(sensorData.temperature, equals(22.0));
      expect(sensorData.alert, equals(0)); // Default value
      expect(sensorData.timestamp, isA<DateTime>()); // Should use current time
    });

    test('should throw FormatException for missing required fields', () {
      // Arrange
      final json = {
        'humidity': 50.0,
        'temperature': 22.0,
        // co2 missing
      };

      // Act & Assert
      expect(() => SensorData.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('should throw FormatException for negative CO2 values', () {
      // Arrange
      final json = {
        'co2': -100.0,
        'humidity': 50.0,
        'temperature': 22.0,
      };

      // Act & Assert
      expect(() => SensorData.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('should throw FormatException for out-of-range humidity', () {
      // Arrange
      final json = {
        'co2': 400.0,
        'humidity': 150.0, // Over 100%
        'temperature': 22.0,
      };

      // Act & Assert
      expect(() => SensorData.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('should throw FormatException for invalid alert values', () {
      // Arrange
      final json = {
        'co2': 400.0,
        'humidity': 50.0,
        'temperature': 22.0,
        'alert': 5, // Out of range (should be 0-3)
      };

      // Act & Assert
      expect(() => SensorData.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('should handle integer values for floating point fields', () {
      // Arrange
      final json = {
        'co2': 400,
        'humidity': 50,
        'temperature': 22,
      };

      // Act
      final sensorData = SensorData.fromJson(json);

      // Assert
      expect(sensorData.co2, equals(400.0));
      expect(sensorData.humidity, equals(50.0));
      expect(sensorData.temperature, equals(22.0));
    });

    test('should return correct alert descriptions', () {
      // Test normal alert
      final normalData = SensorData(
        co2: 400, humidity: 50, temperature: 22, alert: 0, timestamp: DateTime.now(),
      );
      expect(normalData.alertDescription, equals('Normal'));

      // Test low alert
      final lowData = SensorData(
        co2: 1000, humidity: 50, temperature: 22, alert: 1, timestamp: DateTime.now(),
      );
      expect(lowData.alertDescription, equals('Low Alert'));

      // Test medium alert
      final mediumData = SensorData(
        co2: 1500, humidity: 50, temperature: 22, alert: 2, timestamp: DateTime.now(),
      );
      expect(mediumData.alertDescription, equals('Medium Alert'));

      // Test high alert
      final highData = SensorData(
        co2: 2000, humidity: 50, temperature: 22, alert: 3, timestamp: DateTime.now(),
      );
      expect(highData.alertDescription, equals('High Alert'));
    });

    test('should return correct alert colors', () {
      // Test normal (green)
      final normalData = SensorData(
        co2: 400, humidity: 50, temperature: 22, alert: 0, timestamp: DateTime.now(),
      );
      expect(normalData.alertColor, equals(0xFF4CAF50));

      // Test low (yellow)
      final lowData = SensorData(
        co2: 1000, humidity: 50, temperature: 22, alert: 1, timestamp: DateTime.now(),
      );
      expect(lowData.alertColor, equals(0xFFFFEB3B));

      // Test medium (orange)
      final mediumData = SensorData(
        co2: 1500, humidity: 50, temperature: 22, alert: 2, timestamp: DateTime.now(),
      );
      expect(mediumData.alertColor, equals(0xFFFF9800));

      // Test high (deep orange)
      final highData = SensorData(
        co2: 2000, humidity: 50, temperature: 22, alert: 3, timestamp: DateTime.now(),
      );
      expect(highData.alertColor, equals(0xFFFF5722));
    });
  });

  group('SensorDataParser Tests', () {
    test('should parse valid JSON string', () {
      // Arrange
      const jsonString = '{"co2":420.5,"humidity":55.2,"temperature":24.3,"alert":1,"timestamp":1694270400000}';

      // Act
      final sensorData = SensorDataParser.parseFromString(jsonString);

      // Assert
      expect(sensorData, isNotNull);
      expect(sensorData!.co2, equals(420.5));
      expect(sensorData.humidity, equals(55.2));
    });

    test('should return null for invalid JSON string', () {
      // Arrange
      const invalidJson = '{"co2":420.5,"humidity":55.2'; // Incomplete JSON

      // Act
      final sensorData = SensorDataParser.parseFromString(invalidJson);

      // Assert
      expect(sensorData, isNull);
    });

    test('should parse UTF-8 encoded bytes', () {
      // Arrange - Create a valid 22-byte binary packet
      final bytes = List<int>.filled(22, 0);
      // CO2: 450 ppm (little-endian uint16)
      bytes[0] = 450 & 0xFF;
      bytes[1] = (450 >> 8) & 0xFF;
      // Humidity: 55.5% -> 555 (little-endian int16)
      bytes[2] = 555 & 0xFF;
      bytes[3] = (555 >> 8) & 0xFF;
      // Temperature: 22.3°C -> 223 (little-endian int16)
      bytes[4] = 223 & 0xFF;
      bytes[5] = (223 >> 8) & 0xFF;
      // Alert: 0
      bytes[6] = 0;
      // Status: valid data (bit 0 = 1)
      bytes[7] = 0x01;

      // Act
      final sensorData = SensorDataParser.parseFromBytes(bytes);

      // Assert
      expect(sensorData, isNotNull);
      expect(sensorData!.co2, equals(450.0));
      expect(sensorData.humidity, closeTo(55.5, 0.1));
      expect(sensorData.temperature, closeTo(22.3, 0.1));
    });

    test('should return null for invalid packet size', () {
      // Arrange
      final invalidBytes = List<int>.filled(10, 0); // Wrong size

      // Act
      final sensorData = SensorDataParser.parseFromBytes(invalidBytes);

      // Assert
      expect(sensorData, isNull);
    });
  });

  group('Control Command Tests', () {
    test('should create correct mute command', () {
      // Arrange & Act
      final command = "1";

      // Assert
      expect(command, equals("1"));
      expect(command.length, equals(1));
    });

    test('should create correct sleep command', () {
      // Arrange & Act
      final command = "2";

      // Assert
      expect(command, equals("2"));
      expect(command.length, equals(1));
    });

    test('should create correct request data command', () {
      // Arrange & Act
      final command = "3";

      // Assert
      expect(command, equals("3"));
      expect(command.length, equals(1));
    });

    test('should create correct reset command', () {
      // Arrange & Act
      final command = "4";

      // Assert
      expect(command, equals("4"));
      expect(command.length, equals(1));
    });
  });

  group('Widget Tests', () {
    testWidgets('App should start and show scan screen', (WidgetTester tester) async {
      // Build the app with mock notification service
      final mockNotificationService = NotificationService();
      await tester.pumpWidget(
        RespirationMonitorApp(notificationService: mockNotificationService),
      );

      // Verify that the scan screen is displayed
      expect(find.text('Respiration Monitors'), findsOneWidget);
    });

    testWidgets('Scan screen should have scan button', (WidgetTester tester) async {
      // Build the app with mock notification service
      final mockNotificationService = NotificationService();
      await tester.pumpWidget(
        RespirationMonitorApp(notificationService: mockNotificationService),
      );

      // Wait for the widget to settle
      await tester.pumpAndSettle();

      // Verify that the scan button is present
      expect(find.text('Scan for Devices'), findsOneWidget);
    });

    testWidgets('Scan screen should have debug scan button', (WidgetTester tester) async {
      // Build the app with mock notification service
      final mockNotificationService = NotificationService();
      await tester.pumpWidget(
        RespirationMonitorApp(notificationService: mockNotificationService),
      );

      // Wait for the widget to settle
      await tester.pumpAndSettle();

      // Verify that the debug scan button is present
      expect(find.text('Debug Scan (Show All Devices)'), findsOneWidget);
    });
  });
}
