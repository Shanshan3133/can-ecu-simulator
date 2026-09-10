# Physical Hardware Results

The two-node network was assembled on September 9, 2026 and completed its endurance and fault-injection validation on September 10, 2026. The bench used two ESP32-WROOM-32 development boards, two SN65HVD230 transceiver modules, 120-ohm termination at both ends, a shared ground, and a 500 kbit/s CAN bus.

![Physical two-node ESP32 CAN bench](evidence/hardware-bench.jpg)

## Ten-minute endurance test

The Torque/Logger node streamed real CAN frames to the host through its CP210x USB serial interface for 599.874 seconds.

| Metric | Observed result |
|---|---:|
| Total frames | 24,109 |
| Engine Status (`0x100`) | 5,999 |
| Torque Limit (`0x101`) | 5,999 |
| Dashboard Status (`0x200`) | 10,911 |
| Engine heartbeat (`0x701`) | 600 |
| Torque heartbeat (`0x702`) | 600 |
| CRC failures | 0 |
| Peak estimated bus load | 1.145% |
| Gateway timestamp span | 599.874 s |

All five designed identifiers remained present. The nearly linear cumulative-frame trace shows that the gateway continued draining the bus throughout the run. The host safety model recovered from its expected startup state after three valid sequential Engine Status frames and remained normal for the rest of the endurance capture.

![Ten-minute physical CAN endurance result](evidence/hardware-endurance-10min.png)

## Physical fault-injection test

Fault commands were sent to the Engine ECU through its independent USB serial connection while the Torque/Logger node continued recording the physical CAN bus.

| Injected condition | Physical observation | Result |
|---|---|---:|
| Bad CRC | 9 corrupted eight-byte Engine Status frames detected | Pass |
| Wrong DLC | 3 Engine Status frames received with DLC 7 | Pass |
| Rolling-counter jump | One direct three-count skip detected | Pass |
| One-second Engine Status pause | Host entered fail-safe for 989 ms | Pass |
| Fail-safe torque | 33 recorded Torque Limit frames commanded exactly 60 Nm while the host model was in fail-safe | Pass |
| Recovery | Safety state returned to normal after valid traffic resumed | Pass |

The trace contains five observed sequence gaps: three follow the rejected bad-CRC groups, one follows the rejected wrong-DLC group, and one is the direct `BADCOUNTER3` injection. This is expected because rejected Engine Status frames also create a discontinuity in the next accepted rolling counter.

![Physical CAN fault-injection detections and safety response](evidence/hardware-fault-injection.png)

The machine-readable aggregate evidence is retained in [`evidence/hardware-validation-summary-2026-09-10.json`](evidence/hardware-validation-summary-2026-09-10.json). The plotting and summary procedure is reproducible with `host/plot_validation_evidence.py` from the locally retained raw captures.

## Earlier nominal trace

The first physical capture retained 289 frames over 7.131 seconds with zero CRC failures and demonstrated decoded engine speed, throttle, torque limit, and bus load.

![Decoded telemetry from the first physical CAN capture](evidence/hardware-telemetry.png)

The original small trace remains available at [`evidence/hardware-capture-2026-09-09.csv`](evidence/hardware-capture-2026-09-09.csv).

## Validation boundary

The completed work verifies physical two-node CAN communication, all five message identifiers, decoding, application timing, CRC integrity during nominal operation, a ten-minute continuous run, bad-CRC rejection, wrong-DLC rejection, rolling-counter loss detection, timeout entry into fail-safe, the 60 Nm fail-safe command, and recovery after valid traffic resumes.

Bus utilization is calculated conservatively from received gateway frames rather than measured by a dedicated CAN analyzer. Bus-off recovery timing, signal voltages, edge quality, and optional microSD behavior still require separate physical equipment or hardware tests.
