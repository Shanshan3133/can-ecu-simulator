#include <Arduino.h>

#include "../common/can_driver.h"
#include "../common/can_protocol.h"

CanDriver canBus;
uint8_t rollingCounter = 0;
uint32_t lastEngineFrameMs = 0;
uint32_t lastHeartbeatMs = 0;
uint32_t pauseUntilMs = 0;
uint8_t badCrcFramesRemaining = 0;
uint8_t badDlcFramesRemaining = 0;

static void handleFaultInjectionCommands() {
  if (!Serial.available()) return;
  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toUpperCase();
  if (command == "BADCRC3") {
    badCrcFramesRemaining = 3;
    Serial.println("FAULT: next 3 Engine Status frames have invalid CRC");
  } else if (command == "BADDLC3") {
    badDlcFramesRemaining = 3;
    Serial.println("FAULT: next 3 Engine Status frames use DLC 7");
  } else if (command == "PAUSE1000") {
    pauseUntilMs = millis() + 1000;
    Serial.println("FAULT: Engine Status paused for 1000 ms");
  } else if (command == "NORMAL") {
    badCrcFramesRemaining = 0;
    badDlcFramesRemaining = 0;
    pauseUntilMs = 0;
    Serial.println("FAULT: cleared");
  } else {
    Serial.println("Commands: BADCRC3, BADDLC3, PAUSE1000, NORMAL");
  }
}

static void sendEngineStatus() {
  // Repeatable drive-cycle waveform: idle -> acceleration -> cruise -> decel.
  const float phase = (millis() % 20000UL) / 20000.0f;
  float throttlePct;
  if (phase < 0.25f) throttlePct = 4.0f + phase * 240.0f;
  else if (phase < 0.55f) throttlePct = 64.0f;
  else if (phase < 0.80f) throttlePct = 64.0f - (phase - 0.55f) * 224.0f;
  else throttlePct = 8.0f;

  const float rpm = 750.0f + throttlePct * 52.0f;
  const uint16_t rpmRaw = static_cast<uint16_t>(rpm / 0.25f);
  const uint8_t throttleRaw = static_cast<uint8_t>(throttlePct / 0.4f);

  uint8_t data[8] = {0};
  canproto::putU16LE(data, rpmRaw);
  data[2] = throttleRaw;
  data[3] = rollingCounter++ & 0x0F;
  data[4] = 90;  // coolant temperature: raw 90 means 50 deg C with -40 offset
  data[7] = canproto::crc8SaeJ1850(data, 7);
  uint8_t dlc = sizeof(data);
  if (badCrcFramesRemaining > 0) {
    data[7] ^= 0x01;
    --badCrcFramesRemaining;
  }
  if (badDlcFramesRemaining > 0) {
    dlc = 7;
    --badDlcFramesRemaining;
  }
  if (!canBus.send(canproto::ID_ENGINE_STATUS, data, dlc)) {
    Serial.println("WARN: Engine Status CAN transmit failed");
  }
}

static void sendHeartbeat() {
  uint8_t data[4] = {canproto::NODE_ID_ENGINE, 1, 0, 0};
  canproto::putU16LE(&data[2], static_cast<uint16_t>(millis() / 1000));
  if (!canBus.send(canproto::ID_ENGINE_HEARTBEAT, data, sizeof(data))) {
    Serial.println("WARN: Engine heartbeat CAN transmit failed");
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(20);
  delay(500);
  if (!canBus.begin()) {
    Serial.println("ERROR: CAN driver failed to start");
    while (true) delay(1000);
  }
  Serial.println("ENGINE_ECU ready: 500 kbit/s, status every 100 ms");
  Serial.println("Fault commands: BADCRC3, BADDLC3, PAUSE1000, NORMAL");
}

void loop() {
  canBus.service();
  handleFaultInjectionCommands();
  const uint32_t now = millis();
  if (now - lastEngineFrameMs >= 100) {
    lastEngineFrameMs = now;
    if (pauseUntilMs == 0 || static_cast<int32_t>(now - pauseUntilMs) >= 0) {
      pauseUntilMs = 0;
      sendEngineStatus();
    }
  }
  if (now - lastHeartbeatMs >= 1000) {
    lastHeartbeatMs = now;
    sendHeartbeat();
  }
  delay(1);
}
