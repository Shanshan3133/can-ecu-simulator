from __future__ import annotations

import math
import time
from collections.abc import Iterator

from .protocol import Frame, crc8_sae_j1850, parse_gateway_line


def simulated_frames(period_s: float = 0.05) -> Iterator[Frame]:
    """Generate the same traffic as the two boards for hardware-free demos/tests."""
    start = time.monotonic()
    engine_counter = 0
    dashboard_counter = 0
    tick = 0
    latest_rpm_raw = 0
    latest_torque_raw = 600
    while True:
        elapsed = time.monotonic() - start
        now_ms = int(elapsed * 1000)
        if tick % 2 == 0:
            throttle = 35.0 + 30.0 * math.sin(elapsed * 0.7)
            rpm = 750.0 + throttle * 52.0
            latest_rpm_raw = int(rpm / 0.25)
            engine = bytearray(8)
            engine[0:2] = latest_rpm_raw.to_bytes(2, "little")
            engine[2] = int(throttle / 0.4)
            engine[3] = engine_counter & 0x0F
            engine[4] = 90
            engine[7] = crc8_sae_j1850(engine[:7])
            yield Frame(now_ms, 0x100, bytes(engine))

            torque = max(60.0, min(300.0, 80.0 + throttle * 2.2 - max(0.0, rpm - 3500.0) * 0.025))
            latest_torque_raw = int(torque * 10)
            response = bytearray(8)
            response[0:2] = latest_torque_raw.to_bytes(2, "little")
            response[2] = (1 if rpm > 3500 else 0) | (2 if throttle > 60 else 0)
            response[3] = engine_counter & 0x0F
            response[7] = crc8_sae_j1850(response[:7])
            yield Frame(now_ms + 2, 0x101, bytes(response))
            engine_counter += 1

        dashboard = bytearray(8)
        dashboard[0:2] = latest_rpm_raw.to_bytes(2, "little")
        dashboard[2:4] = latest_torque_raw.to_bytes(2, "little")
        dashboard[5] = dashboard_counter & 0x0F
        dashboard[7] = crc8_sae_j1850(dashboard[:7])
        yield Frame(now_ms + 4, 0x200, bytes(dashboard))
        dashboard_counter += 1
        if tick % 20 == 0:
            yield Frame(now_ms + 6, 0x701, bytes((1, 1, int(elapsed) & 0xFF, (int(elapsed) >> 8) & 0xFF)))
            yield Frame(now_ms + 7, 0x702, bytes((2, 1, int(elapsed) & 0xFF, (int(elapsed) >> 8) & 0xFF)))
        tick += 1
        time.sleep(period_s)


def serial_frames(port: str, baudrate: int = 115200) -> Iterator[Frame]:
    import serial

    with serial.Serial(port, baudrate, timeout=1) as connection:
        while True:
            line = connection.readline().decode("ascii", errors="replace")
            if not line:
                continue
            try:
                frame = parse_gateway_line(line)
            except ValueError as exc:
                print(f"warning: {exc}")
                continue
            if frame is not None:
                yield frame
