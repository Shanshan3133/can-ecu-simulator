# CAN Protocol and Safety Design

The network uses classical CAN 2.0A, standard 11-bit identifiers, and a 500 kbit/s bit rate. Every multibyte signal explicitly uses **Intel/little-endian** byte order: the least-significant byte occupies the lowest payload address. This matches the ESP32 and host architecture and makes manual payload inspection straightforward.

The custom decoder intentionally rejects signals with missing or unsupported byte-order declarations instead of silently producing incorrect values. Unused bits are declared as reserved and transmitted as zero to support future protocol expansion. The machine-readable source of truth is `config/vehicle.dbc.json`.

## Message schedule and arbitration

When nodes begin transmitting simultaneously, CAN performs bitwise, non-destructive arbitration. A numerically lower identifier has higher priority.

| Priority | ID | Message | Nominal period | Transmitter |
|---:|---:|---|---:|---|
| 1 | 0x100 | ENGINE_STATUS | 100 ms | Engine ECU |
| 2 | 0x101 | TORQUE_LIMIT | Approximately 100 ms | Torque ECU |
| 3 | 0x200 | DASHBOARD_STATUS | 50 ms | Logical Dashboard ECU |
| 4 | 0x700 | NODE_HEARTBEAT | 1000 ms | Both physical nodes |

IDs 0x100 and 0x200 become ready together every 100 ms. ENGINE_STATUS wins arbitration, while DASHBOARD_STATUS waits and retries automatically without frame corruption.

## CRC-8/SAE-J1850

Byte 7 of IDs 0x100, 0x101, and 0x200 protects bytes 0–6 using:

- Polynomial: `0x1D`
- Initial value: `0xFF`
- Final XOR: `0xFF`
- Reflected input/output: false
- Standard check vector: ASCII `123456789` produces `0x4B`

## 0x100 — ENGINE_STATUS

Transmitted by Node A every 100 ms, DLC 8.

| Payload location | Signal | Conversion | Notes |
|---|---|---|---|
| Bytes 0–1 | engine_rpm | uint16 LE × 0.25 rpm | 0–16,000 rpm |
| Byte 2 | throttle_position | uint8 × 0.4% | 0–100% |
| Byte 3, bits 0–3 | rolling_counter | uint4 | Wraps from 15 to 0 |
| Byte 3, bits 4–7 | reserved_counter_upper | — | Transmitted as zero |
| Byte 4 | coolant_temperature | uint8 − 40 °C | −40 to 215 °C |
| Bytes 5–6 | reserved_future | — | Transmitted as zero |
| Byte 7 | crc | CRC-8/SAE-J1850 | Covers bytes 0–6 |

## 0x101 — TORQUE_LIMIT

Node B responds to each accepted Engine Status frame. During fail-safe operation it continues transmitting the safe value every 100 ms. DLC 8.

| Payload location | Signal | Conversion | Notes |
|---|---|---|---|
| Bytes 0–1 | torque_limit | uint16 LE × 0.1 Nm | Normal result or 60 Nm safe value |
| Byte 2 | limit_reason | Bit field | bit 0: high RPM; bit 1: high load; bit 7: fail-safe |
| Byte 3, bits 0–3 | rolling_counter | uint4 | Wraps from 15 to 0 |
| Byte 3, bits 4–7 | reserved_counter_upper | — | Transmitted as zero |
| Bytes 4–6 | reserved_future | — | Transmitted as zero |
| Byte 7 | crc | CRC-8/SAE-J1850 | Covers bytes 0–6 |

Normal torque calculation:

```text
clamp(80 + throttle × 2.2 - max(0, rpm - 3500) × 0.025, 60, 300) Nm
```

## 0x200 — DASHBOARD_STATUS

The third logical ECU function runs on Node B and broadcasts display data every 50 ms. It can later be moved unchanged to a third physical board. DLC 8.

| Payload location | Signal | Conversion | Notes |
|---|---|---|---|
| Bytes 0–1 | display_rpm | uint16 LE × 0.25 rpm | Most recent accepted RPM |
| Bytes 2–3 | display_torque_limit | uint16 LE × 0.1 Nm | Current torque limit |
| Byte 4 | warning_flags | Bit field | bit 0: fail-safe warning |
| Byte 5, bits 0–3 | rolling_counter | uint4 | Wraps from 15 to 0 |
| Byte 5, bits 4–7 and byte 6 | reserved_future | — | Transmitted as zero |
| Byte 7 | crc | CRC-8/SAE-J1850 | Covers bytes 0–6 |

## 0x700 — NODE_HEARTBEAT

Both physical nodes transmit this four-byte message every 1000 ms:

- Byte 0: node ID; 1 = Engine, 2 = Torque/Logger
- Byte 1: state; 1 = running
- Bytes 2–3: uint16 little-endian uptime in seconds

## Fail-safe state machine

Node B accepts an Engine Status frame only when the DLC is 8, CRC is correct, and sequence behavior is valid:

1. A wrong DLC or CRC increments the consecutive-fault count; its signals are not used.
2. A rolling-counter jump adds the calculated number of missing frames.
3. Three consecutive faults/missing frames, or 300 ms without a valid Engine Status frame, activates fail-safe mode.
4. Fail-safe mode fixes Torque Limit at 60.0 Nm, sets `limit_reason.bit7`, and transmits every 100 ms.
5. Three consecutive valid, sequential Engine Status frames are required to return to normal operation, preventing state oscillation.

The host tool implements the same policy as an independent reference model and writes its result to `safety_model_failsafe` for cross-checking against ECU output.

## Bus-load budget

The host estimates a conservative frame length including the maximum classical CAN bit stuffing and inter-frame spacing: 135 bits for an eight-byte frame and 95 bits for a four-byte frame.

```text
ENGINE_STATUS:      10 × 135 = 1350 bit/s
TORQUE_LIMIT:       10 × 135 = 1350 bit/s
DASHBOARD_STATUS:   20 × 135 = 2700 bit/s
HEARTBEAT:           2 ×  95 =  190 bit/s
Total                          5590 bit/s
Worst-case static load = 5590 / 500000 = 1.118%
```

The design acceptance limit is **1.5%**. This is a conservative schedule estimate based on observed frames and does not include error retransmissions. A CAN analyzer should be used when a physical utilization measurement is required.
