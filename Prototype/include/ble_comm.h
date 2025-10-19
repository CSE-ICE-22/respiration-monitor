#ifndef BLE_COMM_H
#define BLE_COMM_H

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "config.h"

// BLE command types (received from smartphone)
enum BLECommand {
    CMD_NONE = 0,
    CMD_MUTE_BUZZER = 1,
    CMD_FORCE_SLEEP = 2,
    CMD_REQUEST_DATA = 3,
    CMD_RESET_ALERTS = 4,
};

struct SensorPacket {
    uint16_t co2;           // CO2 in ppm (2 bytes)
    int16_t humidity;       // Humidity * 10 (2 bytes) 
    int16_t temperature;    // Temperature * 10 (2 bytes)
    uint8_t alert;          // Alert level (1 byte)
    uint8_t status;         // Status flags (1 byte): Bit0=Valid, Bit1=Muted, Bit7=Average
    uint32_t timestamp;     // Timestamp in seconds since boot (4 bytes)
    uint32_t sequence;      // Sequence number (4 bytes)
    uint8_t reserved[5];    // Reserved for future use (5 bytes)
} __attribute__((packed));

class BLEManager {
private:
    BLEServer* server;
    BLEService* service;
    BLECharacteristic* dataCharacteristic;
    BLECharacteristic* controlCharacteristic;
    bool oldDeviceConnected;
    unsigned long bleStartTime;
    uint32_t sequenceNumber;
    
public:
    bool deviceConnected;
    BLECommand pendingCommand;

    BLEManager();
    bool begin();
    void sendSensorData(const SensorData& data, AlertLevel alertLevel);
    void sendAverageData(const AverageData& data, AlertLevel alertLevel);
    BLECommand getCommand();
    void clearCommand();
    bool isConnected();
    bool hasTimedOut();
    void stop();
    void restart();
    unsigned long getConnectionTime();
};

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer);
    void onDisconnect(BLEServer* pServer);
};

class ControlCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic);
};

extern BLEManager bleManager;

#endif // BLE_COMM_H
