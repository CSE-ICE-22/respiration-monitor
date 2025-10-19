#include "button.h"

ButtonManager buttonManager;

volatile bool ButtonManager::wasPressed_flag = false;
volatile bool ButtonManager::wasHeld_flag = false;
volatile bool ButtonManager::buttonDown = false;
volatile unsigned long ButtonManager::buttonPressTime = 0;
volatile unsigned long ButtonManager::lastInterruptTime = 0;

bool ButtonManager::begin() {
    pinMode(BUTTON_PIN, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), buttonISR, FALLING);
    return true;
}

void ButtonManager::update() {
    if (buttonDown && !wasHeld_flag) {
        if ((millis() - buttonPressTime) >= BUTTON_HOLD_TIME_MS) {
            wasHeld_flag = true;
            wasPressed_flag = false;
        }
    }
    
    if (buttonDown && digitalRead(BUTTON_PIN) == HIGH) {
        buttonDown = false;
        buttonPressTime = 0;
    }
}

bool ButtonManager::wasPressed() {
    if (wasPressed_flag) {
        wasPressed_flag = false;
        return true;
    }
    return false;
}

bool ButtonManager::wasHeld() {
    if (wasHeld_flag) {
        wasHeld_flag = false;
        return true;
    }
    return false;
}

void IRAM_ATTR ButtonManager::buttonISR() {
    unsigned long currentTime = millis();

    if ((currentTime - lastInterruptTime) > BUTTON_DEBOUNCE_MS) {
        if (!buttonDown) {
            wasPressed_flag = true;
            buttonDown = true;
            buttonPressTime = currentTime;
        }
        lastInterruptTime = currentTime;
    }
}
