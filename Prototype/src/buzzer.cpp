#include "buzzer.h"

BuzzerManager buzzerManager;

bool BuzzerManager::begin() {
    isMuted = false;
    ledcSetup(0, 1000, 8);
    ledcAttachPin(BUZZER_PIN, 0);
    ledcWrite(0, 0);
    
    playWelcomeSound();    
    return true;
}

void BuzzerManager::playWelcomeSound() {
    // Low tone
    ledcSetup(0, 800, 8);
    ledcWrite(0, 128);
    delay(150);
    
    // Mid tone
    ledcSetup(0, 1200, 8);
    delay(150);
    
    // High tone
    ledcSetup(0, 1600, 8);
    delay(200);

    ledcSetup(0, 1000, 8);
    
    ledcWrite(0, 0);
}

void BuzzerManager::startAlert(AlertLevel level) {
    if (isMuted || level != ALERT_HIGH) {
        return;
    }

    currentAlert = level;
    currentRepeat = 0;
    lastToggleTime = millis();

    ledcSetup(0, 1600, 8);
    ledcWrite(0, 128); 
}

void BuzzerManager::stopAlert() {
    currentAlert = ALERT_NONE;
    ledcWrite(0, 0);
}

void BuzzerManager::mute() {
    isMuted = true;
    ledcWrite(0, 0);
    Serial.println("Buzzer muted");
}

void BuzzerManager::unmute() {
    isMuted = false;
    Serial.println("Buzzer unmuted");
}

void BuzzerManager::update() {
    if (currentAlert != ALERT_HIGH || isMuted) {
        return;
    }

    unsigned long currentTime = millis();

    if (currentTime - lastToggleTime >= 500) {
        lastToggleTime = currentTime;
        currentRepeat++;

        if (currentRepeat % 2 == 0) {
            ledcWrite(0, 128); // Turn buzzer on
        } else {
            ledcWrite(0, 0); // Turn buzzer off
        }

        // Stop after a fixed number of repeats
        if (currentRepeat >= 10) {
            mute();
        }
    }
}

bool BuzzerManager::isBuzzerActive() {
    return (currentAlert == ALERT_HIGH && !isMuted);
}

bool BuzzerManager::isBuzzerMuted() {
    return isMuted;
}