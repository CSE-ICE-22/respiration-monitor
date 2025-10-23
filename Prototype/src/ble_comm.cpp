#include "ble_comm.h"
#include "buzzer.h"
#include <esp_gap_ble_api.h>
#include <nvs_flash.h>

BLEManager bleManager;

// Global variables for callbacks
BLEManager* g_bleManager = nullptr;

BLEManager::BLEManager() {
    server = nullptr;
    service = nullptr;
    dataCharacteristic = nullptr;
    controlCharacteristic = nullptr;
    deviceConnected = false;
    oldDeviceConnected = false;
    pendingCommand = CMD_NONE;
    bleStartTime = 0;
    sequenceNumber = 0;
    
    // Set global pointer in constructor
    g_bleManager = this;
}

bool BLEManager::begin() {
    // Ensure global pointer is set
    g_bleManager = this;
    
    // Initialize NVS for storing bonding information
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        // NVS partition was truncated, erase and reinitialize
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    
    // Initialize BLE
    BLEDevice::init(BLE_DEVICE_NAME);
    
    // Configure BLE Security with proper authentication
    BLESecurity *pSecurity = new BLESecurity();
    // Use BOND only (without MITM) for better reconnection stability with Just Works pairing
    // MITM + NO_IO causes reconnection issues
    pSecurity->setAuthenticationMode(ESP_LE_AUTH_BOND); 
    pSecurity->setCapability(ESP_IO_CAP_NONE); // No input/output capability (Just Works pairing)
    pSecurity->setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
    pSecurity->setRespEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
    pSecurity->setKeySize(16);
    
    // Set security callbacks
    BLEDevice::setSecurityCallbacks(new SecurityCallbacks());
    
    Serial.println("BLE Security configured with bonding (reconnection-friendly)");
    
    // Create BLE Server
    server = BLEDevice::createServer();
    server->setCallbacks(new ServerCallbacks());
    
    // Create BLE Service
    service = server->createService(BLE_SERVICE_UUID);
    
    // Create BLE Characteristics
    dataCharacteristic = service->createCharacteristic(
        BLE_CHAR_DATA_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    dataCharacteristic->addDescriptor(new BLE2902());
    
    controlCharacteristic = service->createCharacteristic(
        BLE_CHAR_CONTROL_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    controlCharacteristic->setCallbacks(new ControlCallbacks());
    
    // Start the service
    service->start();
    
    // Start advertising
    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(BLE_SERVICE_UUID);
    advertising->setScanResponse(false);
    advertising->setMinPreferred(0x0);
    BLEDevice::startAdvertising();
    
    bleStartTime = millis();
    Serial.println("BLE service started and advertising...");
    
    return true;
}

void BLEManager::sendSensorData(const SensorData& data, AlertLevel alertLevel) {
    if (!deviceConnected || !dataCharacteristic) {
        return;
    }

    // Create compact binary packet
    SensorPacket packet;
    packet.co2 = (uint16_t)data.co2_ppm;
    packet.humidity = (int16_t)(data.humidity_percent * 10);
    packet.temperature = (int16_t)(data.temperature_celsius * 10);
    packet.alert = (uint8_t)alertLevel;
    packet.status = data.valid ? 0x01 : 0x00;
    if (buzzerManager.isBuzzerMuted()) {
        packet.status |= 0x02; // Set bit 1 for muted
    }
    packet.timestamp = (uint32_t)(millis() / 1000); // seconds since boot
    packet.sequence = sequenceNumber++;
    memset(packet.reserved, 0, sizeof(packet.reserved));

    // Send binary data
    dataCharacteristic->setValue((uint8_t*)&packet, sizeof(packet));
    dataCharacteristic->notify();

    Serial.printf("Sent packet - CO2: %d ppm, Temp: %d.%d°C, Hum: %d.%d%%, Alert: %d, Muted: %s, Seq: %d\n", 
                  packet.co2, 
                  packet.temperature / 10, abs(packet.temperature % 10),
                  packet.humidity / 10, abs(packet.humidity % 10),
                  packet.alert,
                  (packet.status & 0x02) ? "Yes" : "No",
                  packet.sequence);
}

void BLEManager::sendAverageData(const AverageData& data, AlertLevel alertLevel) {
    if (!deviceConnected || !dataCharacteristic) {
        return;
    }

    // Create compact binary packet with average data
    SensorPacket packet;
    packet.co2 = (uint16_t)data.avg_co2_ppm;
    packet.humidity = (int16_t)(data.avg_humidity_percent * 10);
    packet.temperature = (int16_t)(data.avg_temperature_celsius * 10);
    packet.alert = (uint8_t)alertLevel;
    packet.status = data.valid ? 0x81 : 0x80; // Bit 7 set indicates average data
    if (buzzerManager.isBuzzerMuted()) {
        packet.status |= 0x02; // Set bit 1 for muted
    }
    packet.timestamp = (uint32_t)(millis() / 1000); // seconds since boot
    packet.sequence = sequenceNumber++;
    memset(packet.reserved, 0, sizeof(packet.reserved));

    // Send binary data
    dataCharacteristic->setValue((uint8_t*)&packet, sizeof(packet));
    dataCharacteristic->notify();

    Serial.printf("Sent AVG packet - CO2: %d ppm, Temp: %d.%d°C, Hum: %d.%d%%, Alert: %d, Muted: %s, Seq: %d\n", 
                  packet.co2, 
                  packet.temperature / 10, abs(packet.temperature % 10),
                  packet.humidity / 10, abs(packet.humidity % 10),
                  packet.alert,
                  (packet.status & 0x02) ? "Yes" : "No",
                  packet.sequence);
}

BLECommand BLEManager::getCommand() {
    return pendingCommand;
}

void BLEManager::clearCommand() {
    pendingCommand = CMD_NONE;
}

bool BLEManager::isConnected() {
    return deviceConnected;
}

bool BLEManager::hasTimedOut() {
    return (millis() - bleStartTime) > BLE_TIMEOUT_MS;
}

void BLEManager::stop() {
    if (server) {
        server->getAdvertising()->stop();
    }
}

void BLEManager::restart() {
    if (server) {
        bleStartTime = millis(); // Reset timeout
        if (!deviceConnected) {
            server->startAdvertising();
            Serial.println("BLE advertising restarted");
        }
    }
}

unsigned long BLEManager::getConnectionTime() {
    return millis() - bleStartTime;
}

// Server callback implementations
void ServerCallbacks::onConnect(BLEServer* pServer) {
    if (g_bleManager != nullptr) {
        g_bleManager->deviceConnected = true;
        Serial.println("BLE client connected");
        pServer->getAdvertising()->stop();
    } else {
        Serial.println("Error: g_bleManager is null in onConnect");
    }
}

void ServerCallbacks::onDisconnect(BLEServer* pServer) {
    if (g_bleManager != nullptr) {
        g_bleManager->deviceConnected = false;
        Serial.println("BLE client disconnected");
        
        // Small delay before restarting advertising to allow proper cleanup
        delay(500);
        
        // Restart advertising for reconnection
        BLEAdvertising* pAdvertising = pServer->getAdvertising();
        pAdvertising->start();
        Serial.println("Advertising restarted - ready for reconnection");
    } else {
        Serial.println("Error: g_bleManager is null in onDisconnect");
    }
}


// Control characteristic callback implementation
void ControlCallbacks::onWrite(BLECharacteristic* pCharacteristic) {
    if (g_bleManager == nullptr) {
        Serial.println("Error: g_bleManager is null in onWrite");
        return;
    }
    
    std::string value = pCharacteristic->getValue();
    
    if (value.length() > 0) {
        Serial.print("Received BLE command: ");
        Serial.println(value.c_str());
        
        // Parse command
        int command = atoi(value.c_str());
        switch (command) {
            case 1:
                g_bleManager->pendingCommand = CMD_MUTE_BUZZER;
                Serial.println("Command: Mute buzzer");
                break;
            case 2:
                g_bleManager->pendingCommand = CMD_FORCE_SLEEP;
                Serial.println("Command: Force sleep");
                break;
            case 3:
                g_bleManager->pendingCommand = CMD_REQUEST_DATA;
                Serial.println("Command: Request data");
                break;
            case 4:
                g_bleManager->pendingCommand = CMD_RESET_ALERTS;
                Serial.println("Command: Reset alerts");
                break;
            default:
                Serial.println("Unknown command");
                break;
        }
    }
}

// Security callback implementations
uint32_t SecurityCallbacks::onPassKeyRequest() {
    Serial.println("PassKeyRequest - returning 0");
    return 0;
}

void SecurityCallbacks::onPassKeyNotify(uint32_t pass_key) {
    Serial.printf("PassKeyNotify: %d\n", pass_key);
}

bool SecurityCallbacks::onSecurityRequest() {
    Serial.println("SecurityRequest - accepting");
    return true;
}

void SecurityCallbacks::onAuthenticationComplete(esp_ble_auth_cmpl_t auth_cmpl) {
    if (auth_cmpl.success) {
        Serial.println("✓ BLE Authentication successful");
    } else {
        Serial.printf("✗ BLE Authentication failed! Reason: 0x%x\n", auth_cmpl.fail_reason);
        // Common fail reasons:
        // 0x01: Passkey entry failed
        // 0x02: OOB not available
        // 0x03: Authentication requirements
        // 0x04: Confirm value failed
        // 0x05: Pairing not supported
        // 0x06: Encryption key size
        // 0x08: SMP command not supported
        // 0x09: Unspecified reason
        // 0x0a: Repeated attempts
        // 0x0c: DHKey check failed
    }
}

bool SecurityCallbacks::onConfirmPIN(uint32_t pin) {
    Serial.printf("ConfirmPIN: %d\n", pin);
    return true;
}