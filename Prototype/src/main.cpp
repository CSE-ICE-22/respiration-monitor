#include <Arduino.h>
#include <esp_bt_main.h>

#include "config.h"
#include "sensor.h"
#include "ble_comm.h"
#include "buzzer.h"
#include "button.h"

// Global state
SystemState currentState = STATE_WAKING_UP;
SensorData currentSensorData;
AverageData currentAverageData;
AlertLevel currentAlert = ALERT_NONE;
unsigned long lastSensorRead = 0;
unsigned long lastDataSend = 0;
bool systemInitialized = false;
bool bleInLightSleep = false;
bool co2Alert = false;
bool tempAlert = false;
bool humidityAlert = false;

// Function declarations
void setupSystem();
void enterDeepSleep();
void enterLightSleep();
void handleSystemStates();
void processAlerts();
void handleBLECommands();
void handleSmartphoneControlSignals(BLECommand command);

void setup() {
    Serial.begin(115200);
    delay(100);
    
    setupSystem();
    systemInitialized = true;
}

void loop() {
    if (!systemInitialized) {
        return;
    }

    buttonManager.update();
    buzzerManager.update();
    
    // Handle button interrupts
    if (buttonManager.wasPressed()) {
        Serial.println("Button pressed");
        
        // Stop buzzer if ringing
        if (buzzerManager.isBuzzerActive()) {
            buzzerManager.mute();
            Serial.println("Buzzer stopped by button press");
        }
        
        // Wake BLE if in light sleep
        if (bleInLightSleep) {
            Serial.println("Waking BLE from light sleep");
            bleManager.restart();
            bleInLightSleep = false;
            currentState = STATE_READING_SENSORS;
        }
    }
    
    if (buttonManager.wasHeld()) {
        Serial.println("Button held - entering deep sleep");
        currentState = STATE_PREPARING_DEEP_SLEEP;
    }
    
    // Handle BLE commands
    handleBLECommands();
    
    // Handle system state machine
    handleSystemStates();
    
    // Small delay to prevent excessive CPU usage
    delay(10);
}

void setupSystem() {
    // Initialize button
    if (!buttonManager.begin()) {
        Serial.println("Failed to initialize button!");
        return;
    }
    
    // Initialize buzzer
    if (!buzzerManager.begin()) {
        Serial.println("Failed to initialize buzzer!");
        return;
    }
    
    // Initialize sensors
    if (!sensorManager.begin()) {
        Serial.println("Failed to initialize sensor manager!");
        return;
    }
    
    // Initialize BLE
    if (!bleManager.begin()) {
        Serial.println("Failed to initialize BLE manager!");
        return;
    }
    
    // Configure GPIO wakeup for light sleep (level-triggered)
    gpio_wakeup_enable((gpio_num_t)BUTTON_PIN, GPIO_INTR_LOW_LEVEL);
    esp_sleep_enable_gpio_wakeup();
    
    Serial.println("System initialized successfully");
}

void handleSystemStates() {
    unsigned long currentTime = millis();
    
    switch (currentState) {
        case STATE_WAKING_UP:
            currentState = STATE_READING_SENSORS;
            break;
            
        case STATE_READING_SENSORS:
            // Read sensors every 15 seconds
            if (currentTime - lastSensorRead >= SENSOR_READ_INTERVAL_MS) {
                Serial.println("State: Reading Sensors");
                
                if (sensorManager.readSensors(currentSensorData)) {
                    lastSensorRead = currentTime;
                    
                    // Add sample to buffer
                    sensorManager.addSample(currentSensorData);
                    
                    currentState = STATE_PROCESSING_DATA;
                } else {
                    Serial.println("Failed to read sensors, retrying...");
                    delay(500);
                }
            }
            
            // Check BLE timeout (5 minutes)
            if (!bleInLightSleep && bleManager.hasTimedOut() && !bleManager.isConnected()) {
                Serial.println("BLE timeout reached - entering light sleep mode");
                currentState = STATE_LIGHT_SLEEP;
            }
            break;
            
        case STATE_PROCESSING_DATA:
            
            // Check if we have enough samples for averaging (4 samples = 1 minute)
            if (sensorManager.hasEnoughSamples()) {
                currentAverageData = sensorManager.calculateAverage();
                sensorManager.resetSamples();
                currentState = STATE_CHECKING_ALERTS;
            } else {
                // Not enough samples yet, continue reading
                currentState = STATE_READING_SENSORS;
            }
            break;
            
        case STATE_CHECKING_ALERTS:
            processAlerts();
            currentState = STATE_BLE_COMMUNICATION;
            break;
            
        case STATE_BLE_COMMUNICATION:
            Serial.println("State: BLE Communication");
            
            // Send average data every minute
            if (currentTime - lastDataSend >= DATA_SEND_INTERVAL_MS) {
                if (bleManager.isConnected()) {
                    bleManager.sendAverageData(currentAverageData, currentAlert);
                    lastDataSend = currentTime;
                }
            }
            
            // Check if we should enter light sleep (BLE timeout and not connected)
            if (!bleInLightSleep && bleManager.hasTimedOut() && !bleManager.isConnected()) {
                Serial.println("BLE timeout - entering light sleep");
                currentState = STATE_LIGHT_SLEEP;
            } else {
                currentState = STATE_READING_SENSORS;
            }
            break;
            
        case STATE_LIGHT_SLEEP:
            Serial.println("State: Light Sleep Mode");
            enterLightSleep();
            break;
            
        case STATE_PREPARING_DEEP_SLEEP:
            buzzerManager.mute();
            bleManager.stop();
            delay(1000);
            enterDeepSleep();
            break;
            
        default:
            currentState = STATE_WAKING_UP;
            break;
    }
}

void processAlerts() {
    if (!currentAverageData.valid) {
        return;
    }
    
    AlertLevel alert = sensorManager.getAlertLevel(currentAverageData); 
    currentAlert = alert;  // Update current alert level
    
    if (alert == ALERT_HIGH) {   
        buzzerManager.startAlert(alert);
        Serial.printf("Alert triggered: Level %d\n", (int)alert);
    } else {
        // No alerts, stop buzzer if it was ringing
        if (currentAlert != ALERT_NONE) {
            buzzerManager.stopAlert();
            Serial.println("Alert cleared");
        }
    }
}

void handleBLECommands() {
    BLECommand command = bleManager.getCommand();
    
    if (command != CMD_NONE) {
        handleSmartphoneControlSignals(command);
        bleManager.clearCommand();
    }
}

void handleSmartphoneControlSignals(BLECommand command) {
    switch (command) {
        case CMD_MUTE_BUZZER:
            buzzerManager.mute();
            Serial.println("Executed: Mute buzzer");
            break;
            
        case CMD_FORCE_SLEEP:
            Serial.println("Executed: Force sleep");
            currentState = STATE_PREPARING_DEEP_SLEEP;
            break;
            
        case CMD_REQUEST_DATA:
            Serial.println("Executed: Request data");
            if (currentAverageData.valid) {
                bleManager.sendAverageData(currentAverageData, currentAlert);
            } else if (currentSensorData.valid) {
                bleManager.sendSensorData(currentSensorData, currentAlert);
            }
            break;
        
        case CMD_UNMUTE_BUZZER:
            buzzerManager.unmute();
            break;
            
        case CMD_RESET_ALERTS:
            Serial.println("Executed: Reset alerts");
            buzzerManager.stopAlert();
            buzzerManager.unmute();
            currentAlert = ALERT_NONE;
            co2Alert = false;
            tempAlert = false;
            humidityAlert = false;
            break;
            
        default:
            Serial.printf("Unknown command: %d\n", (int)command);
            break;
    }
}

void enterLightSleep() {
    // Disable BLE to save power
    bleManager.stop();
    bleInLightSleep = true;
    
    Serial.println("Entering light sleep mode (BLE off, sensors active)");
    Serial.flush();
    
    // Configure light sleep with lower CPU frequency
    setCpuFrequencyMhz(40);
    
    // Continue sensor reading at 15s intervals but don't transmit
    currentState = STATE_READING_SENSORS;
}

void enterDeepSleep() {
    Serial.println("Entering deep sleep mode");
    
    // Wait for button release
    while (digitalRead(BUTTON_PIN) == LOW) {
        delay(100);
    }
    
    uint64_t button_mask = (1ULL << BUTTON_PIN);
    esp_deep_sleep_enable_gpio_wakeup(button_mask, ESP_GPIO_WAKEUP_GPIO_LOW);
    
    // Play goodbye sound
    buzzerManager.playWelcomeSound();
    Serial.flush();
    
    // Power down BLE
    esp_bluedroid_disable();
    esp_bt_controller_disable();
    
    // Enter deep sleep (will wake on button press)
    esp_deep_sleep_start();
}
