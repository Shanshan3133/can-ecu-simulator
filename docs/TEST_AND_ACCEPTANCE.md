# Test Procedure and Acceptance Criteria

## A. Hardware-free verification

Create the Python environment from the `host` directory and run:

```powershell
.venv\Scripts\python.exe -m unittest discover -s tests -v
.venv\Scripts\can-ecu.exe --dbc ..\config\vehicle.dbc.json --simulate --duration 10 --output simulated.csv
```

Acceptance criteria:

- All 12 automated tests pass.
- The logger exits with code 0.
- A 10-second capture contains approximately 420 frames.
- IDs 0x100, 0x101, 0x200, 0x701, and 0x702 are present.
- All protected application frames report `crc_ok=True`.
- Tests cover the CRC standard vector, wrong CRC, wrong DLC, three-fault threshold, rolling-counter loss, 300 ms timeout, three-frame recovery, and bus-load calculation.

## B. Unpowered electrical inspection

1. Confirm that each transceiver VCC connects only to ESP32 3V3.
2. Confirm common ground, CANH-to-CANH, and CANL-to-CANL wiring.
3. Measure resistance between CANH and CANL with both USB cables disconnected.

Acceptance criteria:

- CANH-to-CANL resistance is 55–65 Ω.
- No short exists between 3V3 and GND.
- No conductor is loose or exposed to an adjacent breadboard row.

## C. Individual-node startup

Connect one board at a time, open a 115200-baud serial terminal, and reset it.

Acceptance criteria:

- Node A prints `ENGINE_ECU ready` and lists its fault commands.
- Node B prints `TORQUE_LOGGER_ECU ready`.
- No reset loop or abnormal heating occurs.

A single node may report unsuccessful CAN transmissions because normal CAN requires another node to acknowledge the frame. This is expected.

## D. Two-node communication test

1. Close all serial monitors.
2. Power both nodes.
3. Run a 60-second capture from Node B:

```powershell
.venv\Scripts\can-ecu.exe --dbc ..\config\vehicle.dbc.json --port COM_B --duration 60 --output hardware_60s.csv
```

Acceptance criteria:

- At least 2,200 rows are captured in 60 seconds.
- IDs 0x100 and 0x101 have average periods of 90–110 ms.
- ID 0x200 has an average period of 45–55 ms.
- IDs 0x701 and 0x702 each have an average period of 950–1050 ms.
- No CRC failures occur during normal operation.
- All reserved signal values remain zero.
- RPM varies approximately from 950 to 4,100 rpm.
- Throttle varies approximately from 4% to 64%.
- Each valid 0x100 produces one 0x101, excluding capture boundaries.
- Steady-state `bus_load_pct` remains below 1.5%; the expected estimate is approximately 1.118%.
- Both nodes operate continuously for 10 minutes without resetting or overheating.

## E. Live visualization

```powershell
.venv\Scripts\can-ecu.exe --dbc ..\config\vehicle.dbc.json --port COM_B --plot --duration 60 --output plotted.csv
```

Acceptance criteria:

- RPM, throttle, and torque time-series panels update continuously.
- The RPM–torque map records the moving operating point.
- Torque generally rises with throttle and shows derating at high RPM.
- The terminal displays bus load and safety status.
- The CSV remains readable after the plotting window closes.

## F. Physical fault-injection test

Keep the host logger connected to Node B. Open a second 115200-baud terminal for Node A.

### Wrong-DLC test

Send:

```text
BADDLC3
```

Verify that the next three ID 0x100 frames have DLC 7, Node B rejects them, and Torque Limit switches to 60 Nm with reason bit 7 set.

### Bad-CRC test

Send:

```text
BADCRC3
```

Verify that the host reports three CRC failures, Node B does not use the corrupted signals, and Torque Limit switches to 60 Nm.

### Engine-timeout test

Send:

```text
PAUSE1000
```

Verify that Node B enters fail-safe mode 300 ms after the last valid Engine Status frame and continues broadcasting 60 Nm every 100 ms.

### Recovery test

Allow normal Engine Status transmission to resume. Verify that Node B leaves fail-safe mode only after three consecutive valid and sequential frames.

Send `NORMAL` to clear any pending injection. These tests require no USB-CAN adapter.

## G. Optional physical-layer experiments

- With power disconnected, remove one termination and confirm that CANH-to-CANL resistance changes to approximately 120 Ω. Restore it before normal testing.
- With power disconnected, swap CANH and CANL, then power the system and confirm that no valid traffic is received. Disconnect power and restore the correct wiring immediately.
- If an oscilloscope is available, capture CANH, CANL, and the differential waveform and verify the 100 ms and 50 ms message activity.

Never change breadboard wiring while the system is powered.

## H. Portfolio evidence checklist

- Labeled photograph of both ESP32 nodes, transceivers, CANH/CANL, and terminations
- Multimeter photograph showing approximately 60 Ω with power disconnected
- Successful PlatformIO build output for both firmware environments
- Final statistics and representative rows from a 60-second hardware CSV
- Live time-series and RPM–torque-map screenshot or short screen recording
- Fault-injection evidence showing normal, fail-safe, and recovered states
- One-page protocol table and network topology diagram
- Optional oscilloscope waveform and microSD log

## Troubleshooting

| Symptom | Check first |
|---|---|
| Both nodes start but no frames appear | CANH/CANL polarity, common ground, TX/RX direction, both transceiver supplies, and matching bit rate |
| Engine frames appear but no Torque response | Node B reception, DLC/CRC status, and selected Node B COM port |
| Serial port reports permission denied | Close PlatformIO Monitor, Arduino Serial Monitor, or any other program using the port |
| ESP32 repeatedly resets | USB cable and supply, 3V3 short circuit, transceiver wiring, and reset reason in startup output |
| Plot window does not appear | Confirm matplotlib installation and run from a local desktop session; retry without `--plot` first |
| Upload remains at `Connecting...` | Hold BOOT until writing starts and verify the selected COM port |
