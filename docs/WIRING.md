# Wiring and Power-Up Guide

## Physical topology

```text
USB / host PC                              USB / host PC (logger reads this port)
     |                                                   |
ESP32 A — Engine ECU                         ESP32 B — Torque/Logger ECU
GPIO5 TX  -> CTX  SN65HVD230 A              GPIO5 TX  -> CTX  SN65HVD230 B
GPIO4 RX  <- CRX                            GPIO4 RX  <- CRX
3V3       -> VCC                            3V3       -> VCC
GND       -> GND -------- common ground ---- GND       -> GND
                  CANH ===================== CANH
                  CANL ===================== CANL
                    |                         |
                  120 Ω                     120 Ω
                CANH–CANL                 CANH–CANL
```

Use a twisted pair for CANH and CANL. Keep the bench bus below 1 m, place both nodes at the physical ends, and avoid long stubs.

## ESP32-to-transceiver wiring

Apply the following connections to both nodes:

| ESP32 DevKit | SN65HVD230 module | Function |
|---|---|---|
| 3V3 | 3.3V / VCC | Transceiver supply |
| GND | GND | Logic and bus reference |
| GPIO5 | CTX / TXD / D | Controller transmit output |
| GPIO4 | CRX / RXD / R | Controller receive input |
| GND, if required | Rs / S | High-speed mode; verify the module schematic |

Vendor labels vary between `D/R`, `TX/RX`, and `CTX/CRX`. Confirm signal direction from the module schematic if the labels differ.

## CAN bus wiring

| Node A | Node B |
|---|---|
| CANH | CANH |
| CANL | CANL |
| GND | GND |

Install one 120 Ω resistor between CANH and CANL at each physical end. In this two-node network, place one resistor beside each transceiver. Do not add another resistor if the module already has an enabled 120 Ω termination resistor or jumper.

With all power disconnected, measure resistance between CANH and CANL:

- Approximately 60 Ω: correct; two 120 Ω resistors are in parallel.
- Approximately 120 Ω: one termination is missing.
- Approximately 40 Ω: three terminations may be installed.
- Near 0 Ω: probable short circuit; do not apply power.

## Optional microSD connection on Node B

| ESP32 B | SPI microSD module |
|---|---|
| GPIO18 | SCK / CLK |
| GPIO19 | MISO |
| GPIO23 | MOSI |
| GPIO13 | CS |
| 3V3 | VCC; verify 3.3 V compatibility |
| GND | GND |

Format the card as FAT32 and build the `torque_logger_ecu_sd` PlatformIO environment before reflashing Node B.

## Safe power-up sequence

1. Disconnect both USB cables.
2. Complete all wiring.
3. Check for shorts between 3V3 and GND.
4. Measure approximately 60 Ω between CANH and CANL.
5. Connect both USB cables.
6. Observe the system for 10 seconds and disconnect immediately if either board or transceiver becomes hot.
7. Open only Node B's serial port with the Python host tool.

Use only one ESP32 power-input method at a time. For this project, USB power is the recommended option.
