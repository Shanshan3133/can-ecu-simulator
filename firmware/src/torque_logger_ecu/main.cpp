#include <Arduino.h>
#include <SPI.h>
#include <SD.h>

#include "../common/can_driver.h"
#include "../common/can_protocol.h"

CanDriver canBus;
uint8_t rollingCounter = 0;
uint8_t dashboardCounter = 0;
uint32_t lastHeartbeatMs = 0;
uint32_t lastDashboardMs = 0;
uint32_t lastFailsafeTxMs = 0;
uint32_t lastValidEngineMs = 0;
uint32_t rxCount = 0;
uint16_t lastRpmRaw = 0;
uint16_t lastTorqueRaw = 600;
uint8_t expectedEngineCounter = 0;
uint8_t consecutiveFaults = 0;
uint8_t consecutiveValid = 0;
bool counterInitialized = false;
bool failsafeActive = true;
File logFile;

constexpr uint32_t ENGINE_TIMEOUT_MS = 300;
constexpr uint8_t FAULTS_TO_FAILSAFE = 3;
constexpr uint8_t VALID_FRAMES_TO_RECOVER = 3;

static void logToSd(const CanFrame &frame) {
#if ENABLE_SD_LOG
  if (!logFile) return;
  logFile.printf("%lu,%03lX,%u,", millis(), frame.id, frame.dlc);
  for (uint8_t i = 0; i < frame.dlc; ++i) logFile.printf("%02X", frame.data[i]);
  logFile.println();
  if ((rxCount % 20) == 0) logFile.flush();
#else
  (void)frame;
#endif
}

static void emitOutgoing(uint32_t id, const uint8_t *data, uint8_t dlc) {
  if (!canBus.send(id, data, dlc)) {
    Serial.printf("WARN: CAN transmit failed for ID %03lX\n", id);
    return;
  }
  CanFrame transmitted;
  transmitted.id = id;
  transmitted.dlc = dlc;
  memcpy(transmitted.data, data, dlc);
  printGatewayFrame(transmitted);
  logToSd(transmitted);
}

static void registerFault() {
  consecutiveValid = 0;
  if (consecutiveFaults < 255) ++consecutiveFaults;
  if (consecutiveFaults >= FAULTS_TO_FAILSAFE) failsafeActive = true;
}

static bool validateEngineFrame(const CanFrame &engine) {
  if (engine.dlc != 8) {
    registerFault();
    return false;
  }
  if (canproto::crc8SaeJ1850(engine.data, 7) != engine.data[7]) {
    registerFault();
    return false;
  }

  const uint8_t counter = engine.data[3] & 0x0F;
  if (counterInitialized && counter != expectedEngineCounter) {
    const uint8_t missed = (counter - expectedEngineCounter) & 0x0F;
    consecutiveFaults = static_cast<uint8_t>(
        min(255, static_cast<int>(consecutiveFaults) + max(1, static_cast<int>(missed))));
    consecutiveValid = 0;
    if (consecutiveFaults >= FAULTS_TO_FAILSAFE) failsafeActive = true;
  } else {
    consecutiveFaults = 0;
    if (consecutiveValid < VALID_FRAMES_TO_RECOVER) ++consecutiveValid;
    if (consecutiveValid >= VALID_FRAMES_TO_RECOVER) failsafeActive = false;
  }
  counterInitialized = true;
  expectedEngineCounter = (counter + 1) & 0x0F;
  lastValidEngineMs = millis();
  return true;
}

static void sendTorqueLimit(const CanFrame *engine) {
  float rpm = lastRpmRaw * 0.25f;
  float throttle = 0.0f;
  if (engine != nullptr) {
    lastRpmRaw = canproto::getU16LE(engine->data);
    rpm = lastRpmRaw * 0.25f;
    throttle = engine->data[2] * 0.4f;
  }

  float limitNm = 80.0f + throttle * 2.2f;
  if (rpm > 3500.0f) limitNm -= (rpm - 3500.0f) * 0.025f;
  limitNm = constrain(limitNm, 60.0f, 300.0f);

  uint8_t reason = 0;
  if (rpm > 3500.0f) reason |= 0x01;  // high-rpm derating
  if (throttle > 60.0f) reason |= 0x02;  // high-load flag
  if (failsafeActive) {
    reason |= 0x80;
    limitNm = 60.0f;
  }

  uint8_t data[8] = {0};
  lastTorqueRaw = static_cast<uint16_t>(limitNm * 10.0f);
  canproto::putU16LE(data, lastTorqueRaw);
  data[2] = reason;
  data[3] = rollingCounter++ & 0x0F;
  data[7] = canproto::crc8SaeJ1850(data, 7);
  emitOutgoing(canproto::ID_TORQUE_LIMIT, data, sizeof(data));
}

static void sendDashboardStatus() {
  uint8_t data[8] = {0};
  canproto::putU16LE(data, lastRpmRaw);
  canproto::putU16LE(&data[2], lastTorqueRaw);
  data[4] = failsafeActive ? 0x01 : 0x00;
  data[5] = dashboardCounter++ & 0x0F;
  data[7] = canproto::crc8SaeJ1850(data, 7);
  emitOutgoing(canproto::ID_DASHBOARD_STATUS, data, sizeof(data));
}

static void sendHeartbeat() {
  uint8_t data[4] = {canproto::NODE_ID_TORQUE_LOGGER, 1, 0, 0};
  canproto::putU16LE(&data[2], static_cast<uint16_t>(millis() / 1000));
  emitOutgoing(canproto::ID_TORQUE_HEARTBEAT, data, sizeof(data));
}

void setup() {
  Serial.begin(115200);
  delay(500);
#if ENABLE_SD_LOG
  if (SD.begin(SD_CS_PIN)) {
    logFile = SD.open("/canlog.csv", FILE_APPEND);
    if (logFile && logFile.size() == 0) logFile.println("timestamp_ms,id,dlc,data");
  } else {
    Serial.println("WARN: SD unavailable; USB logging still active");
  }
#endif
  if (!canBus.begin()) {
    Serial.println("ERROR: CAN driver failed to start");
    while (true) delay(1000);
  }
  lastValidEngineMs = millis();
  Serial.println("TORQUE_LOGGER_ECU ready: gateway lines start with @CAN");
}

void loop() {
  canBus.service();
  CanFrame frame;
  if (canBus.receive(frame, pdMS_TO_TICKS(10))) {
    ++rxCount;
    printGatewayFrame(frame);
    logToSd(frame);
    if (frame.id == canproto::ID_ENGINE_STATUS) {
      if (validateEngineFrame(frame)) sendTorqueLimit(&frame);
      else if (failsafeActive) sendTorqueLimit(nullptr);
    }
  }
  const uint32_t now = millis();
  if (lastValidEngineMs > 0 && now - lastValidEngineMs >= ENGINE_TIMEOUT_MS) {
    failsafeActive = true;
    consecutiveValid = 0;
    if (now - lastFailsafeTxMs >= 100) {
      lastFailsafeTxMs = now;
      sendTorqueLimit(nullptr);
    }
  }
  if (now - lastDashboardMs >= 50) {
    lastDashboardMs = now;
    sendDashboardStatus();
  }
  if (now - lastHeartbeatMs >= 1000) {
    lastHeartbeatMs = now;
    sendHeartbeat();
  }
}
