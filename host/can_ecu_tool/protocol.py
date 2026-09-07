from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Frame:
    timestamp_ms: int
    arbitration_id: int
    data: bytes


@dataclass(frozen=True)
class DecodedMessage:
    frame: Frame
    name: str
    signals: dict[str, float | int]
    units: dict[str, str]
    checksum_ok: bool | None


def crc8_sae_j1850(data: bytes) -> int:
    """CRC-8/SAE-J1850: poly 0x1D, init 0xFF, xorout 0xFF, no reflection."""
    crc = 0xFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1D) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc ^ 0xFF


def parse_gateway_line(line: str) -> Frame | None:
    """Parse @CAN,<ms>,<hex id>,<dlc>,<hex bytes>; ignore diagnostic lines."""
    line = line.strip()
    if not line.startswith("@CAN,"):
        return None
    parts = line.split(",")
    if len(parts) != 5:
        raise ValueError(f"invalid gateway field count: {line}")
    timestamp_ms = int(parts[1])
    arbitration_id = int(parts[2], 16)
    dlc = int(parts[3])
    payload = bytes.fromhex(parts[4])
    if not (0 <= arbitration_id <= 0x7FF):
        raise ValueError("only standard 11-bit CAN identifiers are supported")
    if dlc != len(payload) or dlc > 8:
        raise ValueError("DLC does not match payload length")
    return Frame(timestamp_ms, arbitration_id, payload)


class Database:
    def __init__(self, definition: dict[str, Any]):
        self.definition = definition
        self.messages = {int(key, 0): value for key, value in definition["messages"].items()}

    @classmethod
    def load(cls, path: str | Path) -> "Database":
        with Path(path).open(encoding="utf-8") as handle:
            return cls(json.load(handle))

    def decode(self, frame: Frame) -> DecodedMessage | None:
        spec = self.messages.get(frame.arbitration_id)
        if spec is None:
            return None
        if len(frame.data) != spec["dlc"]:
            raise ValueError(f"{spec['name']}: expected DLC {spec['dlc']}, got {len(frame.data)}")

        packed = int.from_bytes(frame.data, byteorder="little", signed=False)
        values: dict[str, float | int] = {}
        units: dict[str, str] = {}
        for signal in spec.get("signals", []):
            byte_order = signal.get("byte_order")
            if byte_order != "little_endian":
                raise ValueError(
                    f"{spec['name']}.{signal['name']}: only explicit Intel/little_endian signals are supported"
                )
            length = int(signal["length"])
            raw = (packed >> int(signal["start_bit"])) & ((1 << length) - 1)
            if signal.get("signed") and raw & (1 << (length - 1)):
                raw -= 1 << length
            scale = signal.get("scale", 1)
            offset = signal.get("offset", 0)
            physical = raw * scale + offset
            values[signal["name"]] = int(physical) if scale == 1 and offset == int(offset) else round(physical, 6)
            units[signal["name"]] = signal.get("unit", "")

        checksum_ok: bool | None = None
        crc_spec = spec.get("crc")
        if crc_spec:
            if crc_spec["type"] != "crc8_sae_j1850":
                raise ValueError(f"unsupported CRC: {crc_spec['type']}")
            start = crc_spec["start_byte"]
            end = start + crc_spec["length"]
            calculated = crc8_sae_j1850(frame.data[start:end])
            checksum_ok = calculated == frame.data[crc_spec["crc_byte"]]

        return DecodedMessage(frame, spec["name"], values, units, checksum_ok)
