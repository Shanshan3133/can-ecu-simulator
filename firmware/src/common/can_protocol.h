#pragma once

#include <Arduino.h>

namespace canproto {

constexpr uint32_t ID_ENGINE_STATUS = 0x100;
constexpr uint32_t ID_TORQUE_LIMIT = 0x101;
constexpr uint32_t ID_DASHBOARD_STATUS = 0x200;
constexpr uint32_t ID_NODE_HEARTBEAT = 0x700;

constexpr uint8_t NODE_ID_ENGINE = 1;
constexpr uint8_t NODE_ID_TORQUE_LOGGER = 2;

inline void putU16LE(uint8_t *data, uint16_t value) {
  data[0] = static_cast<uint8_t>(value & 0xFF);
  data[1] = static_cast<uint8_t>((value >> 8) & 0xFF);
}

inline uint16_t getU16LE(const uint8_t *data) {
  return static_cast<uint16_t>(data[0]) |
         (static_cast<uint16_t>(data[1]) << 8);
}

// CRC-8/SAE-J1850: poly=0x1D, init=0xFF, refin=false, refout=false, xorout=0xFF.
inline uint8_t crc8SaeJ1850(const uint8_t *data, size_t length) {
  uint8_t crc = 0xFF;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x1D)
                         : static_cast<uint8_t>(crc << 1);
    }
  }
  return static_cast<uint8_t>(crc ^ 0xFF);
}

}  // namespace canproto
