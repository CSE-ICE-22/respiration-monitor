# Respiration Monitor Mobile App

A Flutter Android application that discovers, connects, and communicates with ESP32 BLE RespirationMonitor devices to provide real-time environmental monitoring of CO₂ levels, humidity, and temperature.

## Features

- **BLE Device Discovery**: Automatically scans for and connects to RespirationMonitor devices
- **Real-time Dashboard**: Live display of CO₂, humidity, and temperature with visual charts
- **Alert System**: Color-coded alerts based on air quality levels (Normal/Warning/Critical)
- **Device Control**: Remote control of device settings (mute, volume, power off)
- **Data Visualization**: Interactive charts with sparklines and time-series data
- **Mock Mode**: Test the app without physical hardware
- **Auto-reconnect**: Automatic reconnection with exponential backoff
- **Material 3 Design**: Modern, accessible UI with light/dark theme support

## Screenshots

> Screenshots would be added here in a production README

## BLE Device Specifications

The app is designed to work with ESP32-based RespirationMonitor devices with the following specifications:

### Device Identity
- **Advertised Name**: `RespirationMonitor`
- **Service UUID**: `12345678-1234-1234-1234-123456789abc`

### Characteristics
- **Data Characteristic (Notify)**: `87654321-4321-4321-4321-cba987654321`
- **Control Characteristic (Write)**: `11111111-2222-3333-4444-555555555555`

### Data Format
The device sends JSON-formatted sensor data via notifications:
```json
{
  "co2": 420.5,
  "humidity": 55.2,
  "temperature": 24.3,
  "alert": 1,
  "timestamp": 1694270400000
}
```

### Control Commands
Send JSON commands to control the device:
```json
{"cmd": "mute", "value": true}
{"cmd": "volume", "value": 75}
{"cmd": "power", "value": "off"}
```

## Requirements

- **Flutter SDK**: 3.8.1 or later
- **Android SDK**: API level 21 (Android 5.0) or later
- **Target SDK**: API level 34 (Android 14)
- **Bluetooth LE**: Required hardware feature

## Installation & Setup

### Prerequisites

1. Install Flutter SDK (3.8.1+)
2. Install Android Studio with Android SDK
3. Enable Developer Options on your Android device
4. Ensure Bluetooth is available on your device

### Build Instructions

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd mobile_application
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Check Flutter configuration:**
   ```bash
   flutter doctor
   ```

4. **Connect your Android device or start an emulator**

5. **Build and run:**
   ```bash
   # Debug build
   flutter run

   # Release build
   flutter build apk --release
   ```

### Android Permissions

The app automatically requests the following permissions at runtime:

#### Required Permissions
- `BLUETOOTH_SCAN` - For discovering BLE devices (Android 12+)
- `BLUETOOTH_CONNECT` - For connecting to BLE devices (Android 12+)
- `ACCESS_FINE_LOCATION` - Required for BLE scanning on some Android versions

#### Legacy Permissions (Android < 12)
- `BLUETOOTH` - Basic Bluetooth functionality
- `BLUETOOTH_ADMIN` - Administrative Bluetooth functions

### Permission Handling

The app includes proper runtime permission handling:

1. **First Launch**: App will request necessary permissions
2. **Permission Denied**: User will see explanatory dialogs
3. **Settings Navigation**: Direct links to app settings if permissions are permanently denied

## Usage Guide

### 1. Scanning for Devices

- Launch the app to see the **Scan Screen**
- Tap **"Scan for Devices"** to search for RespirationMonitor devices
- Devices will appear in the list with signal strength indicators
- Tap **"Connect"** next to your device

### 2. Dashboard View

Once connected, the dashboard displays:

- **Status Card**: Current air quality alert level
- **Metric Cards**: Live CO₂, humidity, and temperature with sparkline charts
- **Time Series Chart**: Interactive chart with metric selection
- **Connection Indicator**: Green dot for connected status

### 3. Device Settings

Access settings via the gear icon (⚙️) in the dashboard:

- **Mute Toggle**: Enable/disable audio alerts
- **Volume Slider**: Adjust alert volume (0-100)
- **Power Off**: Safely shut down the device

### 4. Mock Mode

For testing without hardware:

1. On the scan screen, tap **"Mock Mode"**
2. Confirm in the dialog
3. View simulated sensor data and test UI components

### 5. Auto-Reconnection

The app automatically handles connection issues:

- **Auto-retry**: Up to 3 reconnection attempts with exponential backoff
- **User Notification**: Alerts when device disconnects
- **Manual Reconnect**: Return to scan screen for manual reconnection

## Project Structure

```
lib/
├── main.dart                 # App entry point with Material 3 theme
├── models/
│   └── sensor_data.dart     # Data models for sensor readings
├── services/
│   ├── ble_service.dart     # BLE communication logic
│   └── mock_ble_service.dart # Mock service for testing
├── screens/
│   ├── scan_screen.dart     # Device discovery and connection
│   ├── dashboard_screen.dart # Real-time data visualization
│   └── settings_screen.dart # Device control interface
└── widgets/
    └── charts.dart          # Reusable chart components

test/
└── widget_test.dart         # Unit and widget tests

android/
└── app/src/main/
    └── AndroidManifest.xml  # Android permissions and configuration
```

## Dependencies

### Core Dependencies
- `flutter_reactive_ble: ^5.3.1` - BLE communication
- `fl_chart: ^0.69.0` - Interactive charts
- `provider: ^6.1.2` - State management
- `shared_preferences: ^2.3.2` - Local storage
- `permission_handler: ^11.3.1` - Runtime permissions

### Development Dependencies
- `flutter_test` - Testing framework
- `flutter_lints: ^5.0.0` - Code linting

## Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/widget_test.dart
```

### Test Coverage

The test suite includes:

- **Unit Tests**: JSON parsing, data validation, error handling
- **Widget Tests**: UI component functionality
- **Integration Tests**: Mock BLE service integration

### Manual Testing

1. **Real Device Testing**: Connect to actual ESP32 RespirationMonitor
2. **Mock Mode Testing**: Use built-in mock mode for UI validation
3. **Permission Testing**: Test on fresh install and permission denial scenarios
4. **Connection Testing**: Test disconnect/reconnect scenarios

## Troubleshooting

### Common Issues

#### BLE Scanning Fails
- Ensure Location Services are enabled (required on some Android versions)
- Check that Bluetooth is turned on
- Verify app has necessary permissions
- Try restarting Bluetooth on the device

#### Connection Timeout
- Move closer to the RespirationMonitor device
- Ensure device is powered on and advertising
- Check that device isn't connected to another app
- Restart the app and try reconnecting

#### Permission Denied
- Go to Android Settings > Apps > Respiration Monitor > Permissions
- Enable all requested permissions
- Restart the app

#### Charts Not Displaying
- Ensure device is connected and sending data
- Try switching between chart metrics
- Check for any error messages in the app

### Debug Mode

For development debugging:

1. Enable Flutter Inspector in your IDE
2. Use `flutter run --debug` for detailed logging
3. Check device logs with `adb logcat`

## Performance Considerations

### Memory Usage
- Sensor data history is limited to 300 samples
- Charts display only the most recent 60 samples
- Old data is automatically pruned

### Battery Optimization
- BLE scanning stops automatically after 30 seconds
- Connection uses low-power BLE protocols
- App handles background/foreground transitions properly

### Network Efficiency
- Local BLE communication only (no internet required)
- Efficient JSON parsing with error handling
- Debounced control commands to prevent flooding

## Known Limitations

1. **Android Only**: iOS version not included in this implementation
2. **Single Device**: Can only connect to one device at a time
3. **BLE Range**: Limited by Bluetooth Low Energy range (typically 10-50 meters)
4. **Android 5.0+**: Minimum API level 21 required for BLE features

## Contributing

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make changes and test thoroughly
4. Follow Flutter/Dart style guidelines
5. Submit a pull request

### Code Style

- Follow Flutter/Dart conventions
- Use meaningful variable and function names
- Add comments for complex logic
- Maintain test coverage

## License

> License information would be specified here

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review existing GitHub issues
3. Create a new issue with:
   - Device information (Android version, device model)
   - App version
   - Steps to reproduce the problem
   - Any error messages or screenshots

## Changelog

### Version 1.0.0
- Initial release
- BLE device discovery and connection
- Real-time sensor data visualization
- Device control interface
- Mock mode for testing
- Material 3 design implementation
- Comprehensive test suite

---

**Note**: This app is designed specifically for RespirationMonitor ESP32 devices. Ensure your device firmware matches the BLE specifications outlined in this README.
