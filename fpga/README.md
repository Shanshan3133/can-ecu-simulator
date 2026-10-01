# FPGA CAN Controller Extension

This directory contains a vendor-neutral RTL implementation of a Classical CAN
2.0A standard-data-frame controller designed to become a third physical node
on the existing ESP32/SN65HVD230 network. No vendor CAN IP is used.

## Pre-hardware implementation status

The board-independent implementation is complete for the defined project
scope. Implemented and automatically verified:

- `can_crc15.v`: the link-layer CRC-15/CAN LFSR, initialized to zero and fed
  MSB first with destuffed bits.
- `can_bit_timing.v`: parameterized nominal time-quanta, bit-boundary, sample,
  bit-end, hard synchronization, and SJW-limited resynchronization.
- `can_destuffer.v` and `can_rx.v`: bit de-stuffing, standard 11-bit identifier
  parsing, DLC/data capture, CRC and form validation, acceptance filtering, and
  ACK generation.
- `can_tx.v`: standard data-frame serialization, CRC generation, bit stuffing,
  nondestructive arbitration monitoring, ACK/bit-error detection, and status.
- `can_error_state.v`: transmit/receive error counters, warning/passive states,
  bus-off entry, and 128 x 11-recessive-bit recovery.
- `can_controller_core.v`: one-entry TX buffer, automatic bounded retry, RX
  interface, bus-idle qualification, ACK wiring, and fault confinement.
- `can_transceiver_top.v`: double-flop RX synchronization, configurable bit
  timing, and board-independent TXD/RXD connection for a 3.3 V transceiver.
- Six self-checking Icarus Verilog testbenches and generic Yosys synthesis.

Run the tests after installing Icarus Verilog:

```powershell
python fpga/tests/run_rtl_tests.py
```

GitHub Actions installs Icarus Verilog and Yosys, executes the same tests, and
synthesizes `can_transceiver_top` on every push.

## Planned controller architecture

```text
host/ESP32 traffic
        |
SN65HVD230-compatible 3.3 V transceiver
        |
rx synchronizer -> bit timing -> destuffer -> RX frame FSM -> acceptance filter
        |                                                |
        +-> error monitor / CRC-15 ----------------------+-> register interface
                                                         |
TX frame FSM <- arbitration monitor <- bit stuffer <-----+
```

Completed development gates:

1. **Protocol primitives** — CRC-15 and synchronized nominal bit timing.
2. **Receive-only core** — synchronizer, hard synchronization/resynchronization,
   destuffing, standard-frame parser, CRC/format checks, and error counters.
3. **Transmit path** — standard data frames, bit stuffing, arbitration loss,
   ACK handling, retransmission, and error frames.
4. **System integration** — register/FIFO interface plus a small wrapper for the
   eventual FPGA board.

Remaining gate:

5. **Third-node hardware validation** — choose a board, add its clock/pin
   constraints, connect through a 3.3 V CAN transceiver, decode the existing
   IDs, inject errors, and retain captures from the Python analyzer.

The application CRC-8/SAE-J1850 already used in IDs `0x100` and `0x101` remains
unchanged. CRC-8 protects the project payload definition; CRC-15/CAN protects
the complete CAN frame at the data-link layer.

## Verification evidence

The CI suite checks:

- CRC-15/CAN check vector `123456789 -> 0x059E`
- nominal timing, hard synchronization, and phase resynchronization
- valid de-stuffing plus six-identical-bit rejection
- error-warning, error-passive, bus-off, and recovery thresholds
- bad-CRC rejection and missing-ACK detection
- two-controller frame exchange, payload recovery, ACK, stuffing, simultaneous
  arbitration, and automatic retry by the losing node
- technology-independent synthesis of the complete transceiver wrapper

See [PRE_HARDWARE_VERIFICATION.md](PRE_HARDWARE_VERIFICATION.md) for the
acceptance matrix and the exact hardware boundary.

## Scope and honesty

This is a complete pre-hardware implementation for Classical CAN 2.0A standard
data frames with 0-8 data bytes. Extended 29-bit identifiers, remote frames,
CAN FD, overload-frame generation, and production qualification are explicitly
out of scope. Passing simulation and generic synthesis does not prove analog
signal integrity, oscillator tolerance, device-specific timing closure, or
interoperability on a physical bus. Those claims require the remaining board
validation gate.

## Protocol reference

The CRC polynomial and processing order follow the NXP/Freescale
[Bosch CAN Protocol Specification Version 2.0](https://www.nxp.com/docs/en/reference-manual/BCANPSV2.pdf).
