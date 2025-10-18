#ifndef SENSOR_H
#define SENSOR_H

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_AHTX0.h>
#include "ScioSense_ENS160.h"
#include "config.h"

class SensorManager {
private:
    Adafruit_AHTX0 aht;
    ScioSense_ENS160 ens160;
    bool initialized;
    unsigned long lastReadTime;
    SensorData lastReading;
    
    // Data averaging
    SensorData sampleBuffer[SAMPLES_PER_MINUTE];
    int currentSampleIndex;
    int samplesCollected;

public:
    SensorManager();
    bool begin();
    bool readSensors(SensorData& data);
    bool isReady();
    void reset();
    SensorData getLastReading();
    AlertLevel getAlertLevel(AverageData& data);
    
    // New averaging functions
    void addSample(const SensorData& data);
    bool hasEnoughSamples();
    AverageData calculateAverage();
    void resetSamples();
};

extern SensorManager sensorManager;

#endif // SENSOR_H
