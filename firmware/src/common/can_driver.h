#pragma once

#include <Arduino.h>
#include <driver/twai.h>

struct CanFrame {
  uint32_t id = 0;
  uint8_t dlc = 0;
  uint8_t data[8] = {0};
};

class CanDriver {
 public:
  bool begin() {
    twai_general_config_t general =
        TWAI_GENERAL_CONFIG_DEFAULT(static_cast<gpio_num_t>(CAN_TX_PIN),
                                    static_cast<gpio_num_t>(CAN_RX_PIN),
                                    TWAI_MODE_NORMAL);
    general.tx_queue_len = 16;
    general.rx_queue_len = 32;
    twai_timing_config_t timing = TWAI_TIMING_CONFIG_500KBITS();
    twai_filter_config_t filter = TWAI_FILTER_CONFIG_ACCEPT_ALL();
    if (twai_driver_install(&general, &timing, &filter) != ESP_OK) return false;
    return twai_start() == ESP_OK;
  }

  bool send(uint32_t id, const uint8_t *data, uint8_t dlc,
            TickType_t wait = pdMS_TO_TICKS(10)) {
    if (dlc > 8) return false;
    twai_message_t msg = {};
    msg.identifier = id;
    msg.data_length_code = dlc;
    memcpy(msg.data, data, dlc);
    return twai_transmit(&msg, wait) == ESP_OK;
  }

  bool receive(CanFrame &frame, TickType_t wait = 0) {
    twai_message_t msg = {};
    if (twai_receive(&msg, wait) != ESP_OK) return false;
    if (msg.extd || msg.rtr) return false;
    frame.id = msg.identifier;
    frame.dlc = msg.data_length_code;
    memcpy(frame.data, msg.data, frame.dlc);
    return true;
  }
};

inline void printGatewayFrame(const CanFrame &frame) {
  Serial.printf("@CAN,%lu,%03lX,%u,", millis(), frame.id, frame.dlc);
  for (uint8_t i = 0; i < frame.dlc; ++i) Serial.printf("%02X", frame.data[i]);
  Serial.println();
}

