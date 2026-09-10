# Physical Hardware Results

The baseline two-node network was assembled and exercised on September 9, 2026 using two ESP32 development boards and two SN65HVD230 transceiver modules. Both transceiver termination jumpers were enabled, CANH and CANL were connected between the nodes, and the boards shared a ground reference.

![Physical two-node ESP32 CAN bench](evidence/hardware-bench.jpg)

## Recorded nominal-traffic result

The Torque/Logger node streamed real CAN frames to the host through its CP210x USB serial interface. The retained capture contains 289 frames over 7.131 seconds of gateway time.

| Metric | Observed result |
|---|---:|
| Total frames | 289 |
| Engine Status (`0x100`) | 71 |
| Torque Limit (`0x101`) | 71 |
| Dashboard Status (`0x200`) | 133 |
| Engine heartbeat (`0x701`) | 7 |
| Torque heartbeat (`0x702`) | 7 |
| CRC failures | 0 |
| Peak estimated bus load | 1.118% |
| Observed engine-speed range | 1,166–4,078 rpm |
| Observed throttle range | 8.0–64.0% |
| Observed torque-limit range | 97.6–206.3 Nm |

The host safety model began in fail-safe, as designed, and returned to normal after three valid sequential Engine Status frames. The capture then remained out of fail-safe for the remaining 280 frames.

![Decoded telemetry from the physical CAN bench](evidence/hardware-telemetry.png)

## Timing observations

- `0x100` and `0x101` were observed at approximately 100 ms.
- `0x200` was observed at approximately 50 ms.
- `0x701` and `0x702` were observed at approximately 1,000 ms.
- Every captured `0x100` frame had a corresponding `0x101` frame, excluding capture-boundary effects.

The host command was left open for approximately 57 seconds with live plotting enabled, but the retained gateway timestamps cover 7.131 seconds. Live plot rendering limited how quickly the original host process drained the serial stream. The evidence is therefore labeled as a 7.131-second physical trace, not a completed 60-second acceptance run.

The original CSV is retained at [`evidence/hardware-capture-2026-09-09.csv`](evidence/hardware-capture-2026-09-09.csv).

## Validation boundary

This run verifies physical two-node CAN communication, message decoding, nominal CRC integrity, application timing, safety-model startup recovery, and the expected low bus-load estimate. It does not claim completion of the 10-minute endurance test, physical fault-injection tests, oscilloscope measurements, or optional microSD logging.
