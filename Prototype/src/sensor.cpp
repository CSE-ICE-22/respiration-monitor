#include "sensor.h"

SensorManager sensorManager;

SensorManager::SensorManager() : ens160(0x53) {
    initialized = false;
    lastReadTime = 0;
    lastReading = {0, 0, 0, false, 0};
    currentSampleIndex = 0;
    samplesCollected = 0;
    
    // Initialize sample buffer
    for (int i = 0; i < SAMPLES_PER_MINUTE; i++) {
        sampleBuffer[i] = {0, 0, 0, 0};
    }
}

bool SensorManager::begin() {
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    
    // Initialize AHT21 sensor for humidity and temperature
    if (!aht.begin(&Wire)) {
        return false;
    }    
    if (!ens160.begin()) {
        return false;
    }
    
    ens160.setMode(ENS160_OPMODE_RESET);
    delay(100);
    if (!ens160.setMode(ENS160_OPMODE_STD)) {
        return false;
    }
    delay(500); // Give sensor time to stabilize
    
    initialized = true;
    return true;
}

bool SensorManager::readSensors(SensorData& data) {
    if (!initialized) {
        data.valid = false;
        return false;
    }
    
    // Check if enough time has passed since last reading
    unsigned long currentTime = millis();
    if (currentTime - lastReadTime < SENSOR_READ_INTERVAL_MS && lastReading.valid) {
        data = lastReading;
        return true;
    }
    
    // Read from AHT21 (humidity and temperature)
    sensors_event_t humidity, temp;
    if (!aht.getEvent(&humidity, &temp)) {
        data.valid = false;
        return false;
    }
    
    // Read from ENS160 (CO2)
    if (!ens160.measure(true)) {
        data.valid = false;
        return false;
    }
    
    // Check if data is available
    if (!ens160.available()) {
        data.valid = false;
        return false;
    }
    
    // Get ENS160 readings
    uint16_t eco2 = ens160.geteCO2();
    // uint16_t tvoc = ens160.getTVOC();
    // uint8_t aqi = ens160.getAQI();
    
    // Populate sensor data structure
    data.co2_ppm = eco2;
    data.humidity_percent = humidity.relative_humidity;
    data.temperature_celsius = temp.temperature;
    data.valid = true;
    data.timestamp = currentTime;
    
    // Store as last reading
    lastReading = data;
    lastReadTime = currentTime;
    
    // Print readings for debugging
    Serial.printf("CO2: %.1f ppm, Humidity: %.1f%%, Temperature: %.1f°C\n", 
                  data.co2_ppm, data.humidity_percent, data.temperature_celsius);
    
    return true;
}

bool SensorManager::isReady() {
    return initialized && ens160.available();
}

void SensorManager::reset() {
    lastReadTime = 0;
    lastReading.valid = false;
    
    if (initialized) {
        // Reset ENS160 if needed
        ens160.setMode(ENS160_OPMODE_RESET);
        delay(100);
        ens160.setMode(ENS160_OPMODE_STD);
    }
}

SensorData SensorManager::getLastReading() {
    return lastReading;
}

AlertLevel SensorManager::getAlertLevel(AverageData& data) {
    if (data.avg_co2_ppm <= CO2_THRESHOLD_HIGH*2.5 && data.avg_humidity_percent <= HUMIDITY_THRESHOLD_HIGH && data.avg_temperature_celsius <= TEMP_THRESHOLD_HIGH) {
        return ALERT_NONE;
    } else if (CO2_THRESHOLD_HIGH * 2.5 < data.avg_co2_ppm <= CO2_THRESHOLD_HIGH * 5 || data.avg_temperature_celsius > TEMP_THRESHOLD_HIGH) {
        return ALERT_LOW;
    } else if (CO2_THRESHOLD_HIGH* 5 < data.avg_co2_ppm <= CO2_THRESHOLD_HIGH * 7.5 || data.avg_humidity_percent >  HUMIDITY_THRESHOLD_HIGH) {
        return ALERT_MEDIUM;
    } else {
        return ALERT_HIGH;
    }
}

void SensorManager::addSample(const SensorData& data) {
    if (!data.valid) {
        return;
    }
    
    sampleBuffer[currentSampleIndex] = data;
    currentSampleIndex = (currentSampleIndex + 1) % SAMPLES_PER_MINUTE;
    
    if (samplesCollected < SAMPLES_PER_MINUTE) {
        samplesCollected++;
    }
    
    Serial.printf("Sample added: %d/%d samples collected\n", samplesCollected, SAMPLES_PER_MINUTE);
}

// Check if we have enough samples for averaging
bool SensorManager::hasEnoughSamples() {
    return samplesCollected >= SAMPLES_PER_MINUTE;
}

// Calculate average from collected samples
AverageData SensorManager::calculateAverage() {
    AverageData avgData = {0, 0, 0, false, millis()};
    
    if (samplesCollected == 0) {
        return avgData;
    }
    
    float sumCO2 = 0;
    float sumHumidity = 0;
    float sumTemperature = 0;
    int validSamples = 0;
    
    for (int i = 0; i < samplesCollected; i++) {
        if (sampleBuffer[i].valid) {
            sumCO2 += sampleBuffer[i].co2_ppm;
            sumHumidity += sampleBuffer[i].humidity_percent;
            sumTemperature += sampleBuffer[i].temperature_celsius;
            validSamples++;
        }
    }
    
    if (validSamples > 0) {
        avgData.avg_co2_ppm = sumCO2 / validSamples;
        avgData.avg_humidity_percent = sumHumidity / validSamples;
        avgData.avg_temperature_celsius = sumTemperature / validSamples;
        avgData.valid = true;

    }
    
    return avgData;
}

// Reset samples for next averaging cycle
void SensorManager::resetSamples() {
    currentSampleIndex = 0;
    samplesCollected = 0;
    Serial.println("Sample buffer reset");
}

