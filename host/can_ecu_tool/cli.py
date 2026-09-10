from __future__ import annotations

import argparse
from collections import defaultdict, deque
import csv
from datetime import datetime
import json
from pathlib import Path
import sys
import time

from .protocol import Database, DecodedMessage
from .monitoring import BusLoadMonitor, EngineSafetyMonitor
from .sources import serial_frames, simulated_frames


class LivePlot:
    def __init__(self, window: int = 200, refresh_s: float = 0.5):
        import matplotlib.pyplot as plt

        self.plt = plt
        self.window = window
        self.refresh_s = refresh_s
        self.x: dict[str, deque[float]] = defaultdict(lambda: deque(maxlen=window))
        self.y: dict[str, deque[float]] = defaultdict(lambda: deque(maxlen=window))
        self.fig, axes = plt.subplots(2, 2, figsize=(11, 7))
        self.axes = list(axes.flat)
        self.fig.canvas.manager.set_window_title("CAN ECU Live Telemetry")
        self.lines = {}
        for axis, key, label in zip(
            self.axes[:3],
            ("engine_rpm", "throttle_position", "torque_limit"),
            ("Engine RPM", "Throttle (%)", "Torque limit (Nm)"),
        ):
            (self.lines[key],) = axis.plot([], [], linewidth=1.6)
            axis.set_ylabel(label)
            axis.grid(True, alpha=0.3)
        self.axes[2].set_xlabel("Gateway time (s)")
        self.map_rpm: deque[float] = deque(maxlen=window)
        self.map_torque: deque[float] = deque(maxlen=window)
        self.latest_rpm: float | None = None
        self.latest_torque: float | None = None
        self.map_scatter = self.axes[3].scatter([], [], s=14, c=[], cmap="viridis", vmin=0, vmax=window)
        self.axes[3].set_title("Live Torque Map")
        self.axes[3].set_xlabel("Engine RPM")
        self.axes[3].set_ylabel("Torque limit (Nm)")
        self.axes[3].grid(True, alpha=0.3)
        plt.ion()
        plt.show(block=False)
        self.last_draw = 0.0

    def update(self, message: DecodedMessage) -> None:
        timestamp_s = message.frame.timestamp_ms / 1000.0
        for key in self.lines:
            if key in message.signals:
                self.x[key].append(timestamp_s)
                self.y[key].append(float(message.signals[key]))
        if "engine_rpm" in message.signals:
            self.latest_rpm = float(message.signals["engine_rpm"])
        if "torque_limit" in message.signals:
            self.latest_torque = float(message.signals["torque_limit"])
            if self.latest_rpm is not None:
                self.map_rpm.append(self.latest_rpm)
                self.map_torque.append(self.latest_torque)
        now = time.monotonic()
        if now - self.last_draw < self.refresh_s:
            return
        for key, line in self.lines.items():
            line.set_data(self.x[key], self.y[key])
            line.axes.relim()
            line.axes.autoscale_view()
        if self.map_rpm:
            offsets = list(zip(self.map_rpm, self.map_torque))
            self.map_scatter.set_offsets(offsets)
            self.map_scatter.set_array(list(range(len(offsets))))
            min_rpm, max_rpm = min(self.map_rpm), max(self.map_rpm)
            min_torque, max_torque = min(self.map_torque), max(self.map_torque)
            self.axes[3].set_xlim(min_rpm - 100, max_rpm + 100)
            self.axes[3].set_ylim(min_torque - 10, max_torque + 10)
        self.fig.canvas.draw_idle()
        self.fig.canvas.flush_events()
        self.last_draw = now


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Decode, record, and plot the ESP32 CAN gateway stream")
    parser.add_argument("--dbc", type=Path, required=True, help="path to vehicle.dbc.json")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--port", help="serial port, for example COM5 or /dev/ttyUSB0")
    source.add_argument("--simulate", action="store_true", help="run without hardware")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--output", type=Path, help="CSV destination (default: timestamped file)")
    parser.add_argument("--plot", action="store_true", help="show live RPM/throttle/torque plots")
    parser.add_argument(
        "--plot-refresh",
        type=float,
        default=0.5,
        help="minimum seconds between GUI redraws (default: 0.5)",
    )
    parser.add_argument("--duration", type=float, default=0, help="stop after N seconds; 0 runs until Ctrl+C")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.plot_refresh <= 0:
        raise SystemExit("--plot-refresh must be greater than zero")
    database = Database.load(args.dbc)
    bus_load = BusLoadMonitor(database.definition["bus"]["bitrate"])
    safety = EngineSafetyMonitor()
    output = args.output or Path(f"can_capture_{datetime.now():%Y%m%d_%H%M%S}.csv")
    output.parent.mkdir(parents=True, exist_ok=True)
    frames = simulated_frames() if args.simulate else serial_frames(args.port, args.baud)
    plot = LivePlot(refresh_s=args.plot_refresh) if args.plot else None
    started = time.monotonic()
    count = 0
    bad_crc = 0
    bad_dlc = 0

    print(f"logging to {output.resolve()} (Ctrl+C to stop)")
    try:
        with output.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["host_time_iso", "gateway_ms", "can_id", "dlc", "data_hex", "message", "crc_ok", "bus_load_pct", "safety_model_failsafe", "signals_json"])
            for frame in frames:
                load_pct = bus_load.add(frame.timestamp_ms, len(frame.data))
                try:
                    decoded = database.decode(frame)
                except ValueError as exc:
                    decoded = None
                    name, checksum, signals = "INVALID", False, {"error": str(exc)}
                    if frame.arbitration_id == 0x100:
                        bad_dlc += 1
                        safety.observe(frame.timestamp_ms, 0, False, dlc_ok=False)
                else:
                    name, checksum, signals = "UNKNOWN", "", {}
                if decoded is None:
                    pass
                else:
                    name, checksum, signals = decoded.name, decoded.checksum_ok, decoded.signals
                    if checksum is False:
                        bad_crc += 1
                    if plot:
                        plot.update(decoded)
                    if frame.arbitration_id == 0x100:
                        safety.observe(
                            frame.timestamp_ms,
                            int(signals["rolling_counter"]),
                            checksum is True,
                        )
                safety.check_timeout(frame.timestamp_ms)
                writer.writerow([
                    datetime.now().isoformat(timespec="milliseconds"), frame.timestamp_ms,
                    f"0x{frame.arbitration_id:03X}", len(frame.data), frame.data.hex().upper(),
                    name, checksum, f"{load_pct:.4f}", safety.state.failsafe,
                    json.dumps(signals, ensure_ascii=False, separators=(",", ":")),
                ])
                handle.flush()
                count += 1
                if count % 20 == 0:
                    print(
                        f"frames={count} bad_crc={bad_crc} bad_dlc={bad_dlc} "
                        f"counter_gap={safety.state.counter_gap_events} load={load_pct:.2f}% "
                        f"safe={safety.state.failsafe} last={name} {signals}"
                    )
                if args.duration and time.monotonic() - started >= args.duration:
                    break
    except KeyboardInterrupt:
        pass
    print(
        f"done: {count} frames, {bad_crc} CRC failures, {bad_dlc} DLC failures, "
        f"{safety.state.counter_gap_events} counter gaps, {output.resolve()}"
    )
    return 0 if bad_crc == 0 and bad_dlc == 0 and safety.state.counter_gap_events == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
