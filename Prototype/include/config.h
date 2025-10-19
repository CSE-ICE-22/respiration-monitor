#ifndef CONFIG_H
#define CONFIG_H

// Pin definitions
#define I2C_SDA_PIN         8
#define I2C_SCL_PIN         9
#define BUTTON_PIN          0
#define BUZZER_PIN          20

#define CO2_THRESHOLD_HIGH       1000
#define TEMP_THRESHOLD_HIGH      40.0
#define HUMIDITY_THRESHOLD_HIGH  80.0

// Alert levels
enum AlertLevel {
    ALERT_NONE = 0,
    ALERT_LOW = 1,
    ALERT_MEDIUM = 2,
    ALERT_HIGH = 3,
};

// Sensor data structure
struct SensorData {
    float co2_ppm;
    float humidity_percent;
    float temperature_celsius;
    bool valid;
    unsigned long timestamp;
};

// Average data structure (for 1-minute averages)
struct AverageData {
    float avg_co2_ppm;
    float avg_humidity_percent;
    float avg_temperature_celsius;
    bool valid;
    unsigned long timestamp;
};

// Timing constants
#define BUTTON_DEBOUNCE_MS          50
#define BUTTON_HOLD_TIME_MS         2000
#define SENSOR_READ_INTERVAL_MS     15000    // Read sensors every 15 seconds
#define SAMPLES_PER_MINUTE          4        // 4 samples of 15s = 1 minute
#define DATA_SEND_INTERVAL_MS       60000    // Send data every 1 minute
#define BLE_TIMEOUT_MS              300000   // 5 minutes (300,000 ms)
#define BUZZER_TIMEOUT_MS           10000

// BLE constants
#define BLE_DEVICE_NAME         "RespirationMonitor"
#define BLE_SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define BLE_CHAR_DATA_UUID      "87654321-4321-4321-4321-cba987654321"
#define BLE_CHAR_CONTROL_UUID   "11111111-2222-3333-4444-555555555555"

// System states
enum SystemState {
    STATE_WAKING_UP = 0,
    STATE_READING_SENSORS = 1,
    STATE_PROCESSING_DATA = 2,
    STATE_CHECKING_ALERTS = 3,
    STATE_BLE_COMMUNICATION = 4,
    STATE_LIGHT_SLEEP = 5,
    STATE_PREPARING_DEEP_SLEEP = 6
};

extern SystemState currentState;

#endif // CONFIG_H
