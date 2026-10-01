# FPGA CAN Controller Extension

This directory starts a vendor-neutral RTL implementation of a Classical CAN
2.0A controller that will become a third physical node on the existing
ESP32/SN65HVD230 network. No vendor CAN IP is used.

## Current milestone: protocol primitives

Implemented and automatically verified:

- `can_crc15.v`: the link-layer CRC-15/CAN LFSR, initialized to zero and fed
  MSB first with destuffed bits.
- `can_bit_timing.v`: parameterized nominal time-quanta, bit-boundary, sample,
  and bit-end pulses. At 40 MHz, 500 kbit/s, and 16 TQ/bit it divides the input
  clock by five and samples at 81.25% of the nominal bit time.
- Self-checking Icarus Verilog testbenches, including the CRC check value
  `0x059E` for the ASCII string `123456789`.

Run the tests after installing Icarus Verilog:

```powershell
python fpga/tests/run_rtl_tests.py
```

GitHub Actions installs Icarus and executes the same command on every push.

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

Development gates:

1. **Protocol primitives** — CRC-15 and nominal bit timing (current milestone).
2. **Receive-only core** — synchronizer, hard synchronization/resynchronization,
   destuffing, standard-frame parser, CRC/format checks, and error counters.
3. **Transmit path** — standard data frames, bit stuffing, arbitration loss,
   ACK handling, retransmission, and error frames.
4. **System integration** — register/FIFO interface plus a small wrapper for the
   selected FPGA board.
5. **Third-node hardware validation** — connect through a 3.3 V CAN transceiver,
   decode the existing IDs, inject errors, and retain captures from the Python
   analyzer.

The application CRC-8/SAE-J1850 already used in IDs `0x100` and `0x101` remains
unchanged. CRC-8 protects the project payload definition; CRC-15/CAN protects
the complete CAN frame at the data-link layer.

## Scope and honesty

The directory is an incremental hardware design, not yet a complete CAN
controller. Extended 29-bit identifiers, remote frames, CAN FD, listen-only
mode, and full fault-confinement behavior are out of the first implementation
scope. Hardware is intentionally not selected until the receive and transmit
cores pass simulation, so board choice follows verified I/O and clock needs.

## Protocol reference

The CRC polynomial and processing order follow the NXP/Freescale
[Bosch CAN Protocol Specification Version 2.0](https://www.nxp.com/docs/en/reference-manual/BCANPSV2.pdf).
