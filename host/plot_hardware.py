"""Create a portfolio-ready summary plot from a hardware capture."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, default=Path("hardware_60s.csv"))
    parser.add_argument("--output", type=Path, default=Path("hardware_plot.png"))
    return parser


def main() -> None:
    args = build_parser().parse_args()
    with args.input.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit(f"capture is empty: {args.input}")

    start_ms = int(rows[0]["gateway_ms"])
    elapsed = [(int(row["gateway_ms"]) - start_ms) / 1000.0 for row in rows]
    signals = [json.loads(row["signals_json"]) for row in rows]

    def series(name: str) -> tuple[list[float], list[float]]:
        x_values: list[float] = []
        y_values: list[float] = []
        for x_value, values in zip(elapsed, signals):
            if name in values:
                x_values.append(x_value)
                y_values.append(float(values[name]))
        return x_values, y_values

    figure, axes = plt.subplots(2, 2, figsize=(12, 7), sharex=True)
    panels = (
        ("engine_rpm", "Engine RPM", "RPM", "#1565c0"),
        ("throttle_position", "Throttle Position", "%", "#00897b"),
        ("torque_limit", "Torque Limit", "Nm", "#ef6c00"),
    )
    for axis, (key, title, unit, color) in zip(axes.flat[:3], panels):
        x_values, y_values = series(key)
        axis.plot(x_values, y_values, color=color, linewidth=1.8)
        axis.set_title(title)
        axis.set_ylabel(unit)
        axis.grid(True, alpha=0.3)

    load = [float(row["bus_load_pct"]) for row in rows]
    axes.flat[3].plot(elapsed, load, color="#6a1b9a", linewidth=1.8)
    axes.flat[3].set_title("Estimated CAN Bus Load")
    axes.flat[3].set_ylabel("%")
    axes.flat[3].grid(True, alpha=0.3)
    for axis in axes[1]:
        axis.set_xlabel("Gateway time since capture start (s)")

    frame_count = len(rows)
    crc_failures = sum(row["crc_ok"] == "False" for row in rows)
    span_s = elapsed[-1]
    peak_load = max(load)
    figure.suptitle(
        "Physical ESP32 CAN Bench — Captured Telemetry\n"
        f"{frame_count} frames | {crc_failures} CRC failures | "
        f"{span_s:.2f} s gateway trace | {peak_load:.3f}% peak estimated load",
        fontsize=14,
    )
    figure.tight_layout(rect=(0, 0, 1, 0.91))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=160, bbox_inches="tight")
    print(f"saved {args.output} from {frame_count} frames")


if __name__ == "__main__":
    main()
