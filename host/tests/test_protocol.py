import unittest
from itertools import islice

from can_ecu_tool.monitoring import BusLoadMonitor, EngineSafetyMonitor, worst_case_classic_can_bits
from can_ecu_tool.protocol import Database, Frame, crc8_sae_j1850, parse_gateway_line
from can_ecu_tool.sources import simulated_frames


DEFINITION = {
    "messages": {
        "0x100": {
            "name": "ENGINE_STATUS", "dlc": 8,
            "crc": {"type": "crc8_sae_j1850", "start_byte": 0, "length": 7, "crc_byte": 7},
            "signals": [
                {"name": "rpm", "start_bit": 0, "length": 16, "byte_order": "little_endian", "scale": 0.25, "offset": 0},
                {"name": "counter", "start_bit": 24, "length": 4, "byte_order": "little_endian", "scale": 1, "offset": 0},
                {"name": "temperature", "start_bit": 32, "length": 8, "byte_order": "little_endian", "scale": 1, "offset": -40}
            ]
        }
    }
}


class ProtocolTests(unittest.TestCase):
    def test_gateway_line(self):
        frame = parse_gateway_line("@CAN,123,100,8,204E64015A000071")
        self.assertIsNotNone(frame)
        self.assertEqual(frame.timestamp_ms, 123)
        self.assertEqual(frame.arbitration_id, 0x100)
        self.assertEqual(len(frame.data), 8)

    def test_crc_standard_check_vector(self):
        self.assertEqual(crc8_sae_j1850(b"123456789"), 0x4B)

    def test_decode_scaling_and_crc(self):
        data = bytearray.fromhex("204E64015A000000")
        data[7] = crc8_sae_j1850(data[:7])
        decoded = Database(DEFINITION).decode(Frame(1, 0x100, bytes(data)))
        self.assertIsNotNone(decoded)
        self.assertEqual(decoded.signals["rpm"], 5000.0)
        self.assertEqual(decoded.signals["temperature"], 50)
        self.assertTrue(decoded.checksum_ok)

    def test_bad_crc_is_reported(self):
        data = bytearray(8)
        data[7] = crc8_sae_j1850(data[:7]) ^ 0x01
        decoded = Database(DEFINITION).decode(Frame(1, 0x100, bytes(data)))
        self.assertIsNotNone(decoded)
        self.assertFalse(decoded.checksum_ok)

    def test_wrong_dlc_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "expected DLC 8"):
            Database(DEFINITION).decode(Frame(1, 0x100, bytes(7)))


class SafetyTests(unittest.TestCase):
    def test_three_bad_frames_force_safe_state(self):
        monitor = EngineSafetyMonitor()
        for timestamp in (0, 100, 200):
            monitor.observe(timestamp, 0, integrity_ok=False)
        self.assertTrue(monitor.state.failsafe)
        self.assertEqual(monitor.state.consecutive_faults, 3)
        self.assertEqual(monitor.state.bad_crc_frames, 3)
        self.assertEqual(monitor.state.bad_dlc_frames, 0)

    def test_counter_jump_of_three_forces_safe_state(self):
        monitor = EngineSafetyMonitor(valid_to_recover=1)
        monitor.observe(0, 0, integrity_ok=True)
        self.assertFalse(monitor.state.failsafe)
        monitor.observe(400, 4, integrity_ok=True)
        self.assertTrue(monitor.state.failsafe)
        self.assertEqual(monitor.state.counter_gap_events, 1)

    def test_wrong_dlc_has_a_separate_counter(self):
        monitor = EngineSafetyMonitor()
        monitor.observe(0, 0, integrity_ok=False, dlc_ok=False)
        self.assertEqual(monitor.state.bad_crc_frames, 0)
        self.assertEqual(monitor.state.bad_dlc_frames, 1)

    def test_engine_timeout_forces_safe_state(self):
        monitor = EngineSafetyMonitor(valid_to_recover=1)
        monitor.observe(0, 0, integrity_ok=True)
        self.assertFalse(monitor.state.failsafe)
        monitor.check_timeout(300)
        self.assertTrue(monitor.state.failsafe)

    def test_three_valid_frames_recover(self):
        monitor = EngineSafetyMonitor()
        for counter in range(3):
            monitor.observe(counter * 100, counter, integrity_ok=True)
        self.assertFalse(monitor.state.failsafe)


class BusLoadTests(unittest.TestCase):
    def test_worst_case_frame_size(self):
        self.assertEqual(worst_case_classic_can_bits(8), 135)
        self.assertEqual(worst_case_classic_can_bits(4), 95)

    def test_load_calculation(self):
        monitor = BusLoadMonitor(500_000)
        load = 0.0
        for timestamp in range(0, 1000, 100):
            load = monitor.add(timestamp, 8)
        self.assertAlmostEqual(load, 0.27, places=2)


class SimulationTests(unittest.TestCase):
    def test_first_cycle_contains_unique_heartbeat_ids(self):
        frames = list(islice(simulated_frames(), 5))
        self.assertEqual(
            {frame.arbitration_id for frame in frames},
            {0x100, 0x101, 0x200, 0x701, 0x702},
        )


if __name__ == "__main__":
    unittest.main()
