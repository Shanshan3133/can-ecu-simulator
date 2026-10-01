# FPGA CAN Core: Pre-Hardware Verification

## Acceptance status

| Capability | Automated evidence | Status |
|---|---|---|
| CAN CRC-15 polynomial and bit order | `tb_can_crc15.v`, standard check value `0x059E` | Pass |
| Nominal bit timing | 5-clock TQ and complete bit-period assertions | Pass |
| Hard sync and bounded resync | `tb_can_bit_timing.v` | Pass |
| Bit de-stuffing | valid stuffed stream reconstruction | Pass |
| Stuff error detection | sixth identical physical bit rejected | Pass |
| Standard 11-bit data frame TX/RX | two-controller resolved-bus simulation | Pass |
| DLC and 0-8-byte payload transport | decoded ID, DLC, and payload assertions | Pass |
| CRC rejection | deliberately corrupted generated CRC | Pass |
| ACK generation/detection | receiver ACK and missing-ACK assertion | Pass |
| Nondestructive arbitration | simultaneous IDs `0x100` and `0x300` | Pass |
| Automatic retry | losing `0x300` node transmits after bus becomes idle | Pass |
| Fault confinement | warning/passive/bus-off thresholds | Pass |
| Bus-off recovery | 128 occurrences of 11 recessive bits | Pass |
| Synthesizable complete top | Yosys `synth -top can_transceiver_top` | Pass |
| Physical third-node interoperability | requires FPGA board and transceiver | Pending |

The automated run is visible in the repository's **Continuous Integration**
GitHub Actions workflow. The same six simulations can be executed locally with:

```powershell
python fpga/tests/run_rtl_tests.py
```

## Stable application interface

The board wrapper accepts a one-cycle `tx_request` with `tx_id`, `tx_dlc`, and
`tx_data`, and reports `tx_busy`, `tx_success`, or `tx_failed`. Received frames
appear for one cycle on `rx_valid`, `rx_id`, `rx_dlc`, and `rx_data`. Payload
byte zero occupies `*_data[7:0]`, matching the project's existing little-endian
application layout.

`can_txd` and `can_rxd` use normal CAN-transceiver logic polarity: zero is
dominant and one is recessive. They must connect to the TXD/RXD logic pins of a
3.3 V CAN transceiver, never directly to CANH or CANL.

## Work intentionally deferred until a board exists

Only these board-dependent items remain:

1. Select a board with enough logic, a documented oscillator, and 3.3 V GPIO.
2. Add the vendor/board clock and pin-constraint file.
3. Choose `TQ_PER_BIT`, `SAMPLE_TQ`, and `SJW_TQ` values that divide the actual
   oscillator cleanly at 500 kbit/s.
4. Run vendor place-and-route and static timing analysis.
5. Connect an SN65HVD230-class transceiver and the existing terminated CAN bus.
6. Capture the FPGA node's frames with the existing Python tool and repeat CRC,
   timeout, arbitration, and endurance tests.

No board-specific resource, timing-closure, or physical-interoperability claim
is made before those steps are performed.
