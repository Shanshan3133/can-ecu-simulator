from __future__ import annotations

from collections import deque
from dataclasses import dataclass


def worst_case_classic_can_bits(dlc: int) -> int:
    """Conservative CAN 2.0A frame length including maximum bit stuffing and intermission."""
    if not 0 <= dlc <= 8:
        raise ValueError("classic CAN DLC must be between 0 and 8")
    stuffable = 34 + 8 * dlc
    return 47 + 8 * dlc + (stuffable - 1) // 4


class BusLoadMonitor:
    def __init__(self, bitrate: int, window_ms: int = 1000):
        self.bitrate = bitrate
        self.window_ms = window_ms
        self.samples: deque[tuple[int, int]] = deque()

    def add(self, timestamp_ms: int, dlc: int) -> float:
        self.samples.append((timestamp_ms, worst_case_classic_can_bits(dlc)))
        cutoff = timestamp_ms - self.window_ms
        while self.samples and self.samples[0][0] < cutoff:
            self.samples.popleft()
        bits = sum(sample[1] for sample in self.samples)
        return bits / (self.bitrate * self.window_ms / 1000.0) * 100.0


@dataclass
class SafetyState:
    failsafe: bool = True
    consecutive_faults: int = 0
    consecutive_valid: int = 0
    expected_counter: int | None = None
    last_valid_ms: int | None = None
    bad_crc_frames: int = 0
    bad_dlc_frames: int = 0
    counter_gap_events: int = 0


class EngineSafetyMonitor:
    """Host-side reference model of the torque ECU three-fault safety policy."""

    def __init__(self, timeout_ms: int = 300, faults_to_safe: int = 3, valid_to_recover: int = 3):
        self.timeout_ms = timeout_ms
        self.faults_to_safe = faults_to_safe
        self.valid_to_recover = valid_to_recover
        self.state = SafetyState()

    def observe(self, timestamp_ms: int, counter: int, integrity_ok: bool, dlc_ok: bool = True) -> SafetyState:
        if not dlc_ok:
            self.state.bad_dlc_frames += 1
            self.state.consecutive_faults += 1
            self.state.consecutive_valid = 0
        elif not integrity_ok:
            self.state.bad_crc_frames += 1
            self.state.consecutive_faults += 1
            self.state.consecutive_valid = 0
        elif self.state.expected_counter is not None and counter != self.state.expected_counter:
            missed = (counter - self.state.expected_counter) & 0x0F
            self.state.counter_gap_events += 1
            self.state.consecutive_faults += max(1, missed)
            self.state.consecutive_valid = 0
            self.state.expected_counter = (counter + 1) & 0x0F
            self.state.last_valid_ms = timestamp_ms
        else:
            self.state.consecutive_faults = 0
            self.state.consecutive_valid += 1
            self.state.expected_counter = (counter + 1) & 0x0F
            self.state.last_valid_ms = timestamp_ms
        if self.state.consecutive_faults >= self.faults_to_safe:
            self.state.failsafe = True
        elif self.state.consecutive_valid >= self.valid_to_recover:
            self.state.failsafe = False
        return self.state

    def check_timeout(self, timestamp_ms: int) -> SafetyState:
        if self.state.last_valid_ms is None or timestamp_ms - self.state.last_valid_ms >= self.timeout_ms:
            self.state.failsafe = True
            self.state.consecutive_valid = 0
        return self.state
