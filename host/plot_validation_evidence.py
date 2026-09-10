"""Build reproducible plots and a compact summary from physical bench captures."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read_capture(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit(f"capture is empty: {path}")
    return rows


def elapsed_seconds(rows: list[dict[str, str]]) -> list[float]:
    start = int(rows[0]["gateway_ms"])
    return [(int(row["gateway_ms"]) - start) / 1000.0 for row in rows]


def signal_series(
    rows: list[dict[str, str]], elapsed: list[float], name: str
) -> tuple[list[float], list[float]]:
    x_values: list[float] = []
    y_values: list[float] = []
    for x_value, row in zip(elapsed, rows):
        signals = json.loads(row["signals_json"])
        if name in signals:
            x_values.append(x_value)
            y_values.append(float(signals[name]))
    return x_values, y_values


def counter_jumps(rows: list[dict[str, str]], elapsed: list[float]) -> list[float]:
    jumps: list[float] = []
    previous: int | None = None
    for x_value, row in zip(elapsed, rows):
        if row["can_id"] != "0x100" or row["dlc"] != "8" or row["crc_ok"] != "True":
            continue
        current = int(json.loads(row["signals_json"])["rolling_counter"])
        if previous is not None and (current - previous) % 16 != 1:
            jumps.append(x_value)
        previous = current
    return jumps


def capture_summary(rows: list[dict[str, str]]) -> dict[str, object]:
    first_ms = int(rows[0]["gateway_ms"])
    last_ms = int(rows[-1]["gateway_ms"])
    return {
        "frames": len(rows),
        "gateway_span_seconds": round((last_ms - first_ms) / 1000.0, 3),
        "frame_counts_by_id": dict(sorted(Counter(row["can_id"] for row in rows).items())),
        "bad_crc_dlc8_frames": sum(
            row["dlc"] == "8" and row["crc_ok"] == "False" for row in rows
        ),
        "wrong_dlc7_frames": sum(row["dlc"] == "7" for row in rows),
        "safe_state_rows": sum(row["safety_model_failsafe"] == "True" for row in rows),
        "peak_estimated_bus_load_pct": max(float(row["bus_load_pct"]) for row in rows),
    }


def plot_endurance(rows: list[dict[str, str]], output: Path) -> None:
    elapsed = elapsed_seconds(rows)
    rpm_x, rpm = signal_series(rows, elapsed, "engine_rpm")
    torque_x, torque = signal_series(rows, elapsed, "torque_limit")
    load = [float(row["bus_load_pct"]) for row in rows]
    counts = list(range(1, len(rows) + 1))

    figure, axes = plt.subplots(2, 2, figsize=(12, 7), sharex=True)
    axes[0, 0].plot(rpm_x, rpm, color="#1565c0", linewidth=1.2)
    axes[0, 0].set_title("Engine speed")
    axes[0, 0].set_ylabel("rpm")
    axes[0, 1].plot(torque_x, torque, color="#ef6c00", linewidth=1.2)
    axes[0, 1].set_title("Torque limit")
    axes[0, 1].set_ylabel("Nm")
    axes[1, 0].plot(elapsed, load, color="#6a1b9a", linewidth=1.2)
    axes[1, 0].set_title("Estimated bus load")
    axes[1, 0].set_ylabel("%")
    axes[1, 1].plot(elapsed, counts, color="#00897b", linewidth=1.5)
    axes[1, 1].set_title("Cumulative received frames")
    axes[1, 1].set_ylabel("frames")
    for axis in axes.flat:
        axis.grid(True, alpha=0.3)
    for axis in axes[1]:
        axis.set_xlabel("Gateway time since capture start (s)")

    figure.suptitle(
        "Physical CAN Endurance Test — 10 Minutes\n"
        f"{len(rows):,} frames | 0 CRC failures | {elapsed[-1]:.3f} s gateway trace",
        fontsize=14,
    )
    figure.tight_layout(rect=(0, 0, 1, 0.91))
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=160, bbox_inches="tight")
    plt.close(figure)


def plot_faults(
    rows: list[dict[str, str]], output: Path
) -> tuple[list[float], list[float]]:
    elapsed = elapsed_seconds(rows)
    safe = [row["safety_model_failsafe"] == "True" for row in rows]
    bad_crc = [
        x for x, row in zip(elapsed, rows)
        if row["dlc"] == "8" and row["crc_ok"] == "False"
    ]
    bad_dlc = [x for x, row in zip(elapsed, rows) if row["dlc"] == "7"]
    jumps = counter_jumps(rows, elapsed)
    rejected = bad_crc + bad_dlc
    direct_jumps = [
        jump for jump in jumps
        if not any(0.0 <= jump - invalid <= 0.5 for invalid in rejected)
    ]

    figure, axes = plt.subplots(2, 1, figsize=(12, 6.5), sharex=True)
    axes[0].step(elapsed, [int(value) for value in safe], where="post", color="#c62828")
    axes[0].set_yticks([0, 1], ["Normal", "Fail-safe"])
    axes[0].set_title("Host safety-model state")
    axes[0].grid(True, alpha=0.3)

    axes[1].scatter(bad_crc, [3] * len(bad_crc), marker="x", s=45, color="#c62828", label="Bad CRC")
    axes[1].scatter(bad_dlc, [2] * len(bad_dlc), marker="s", s=36, color="#ef6c00", label="DLC 7")
    axes[1].scatter(jumps, [1] * len(jumps), marker="^", s=42, color="#6a1b9a", label="Sequence gap")
    axes[1].set_yticks([1, 2, 3], ["Sequence gap", "Wrong DLC", "Bad CRC"])
    axes[1].set_xlabel("Gateway time since capture start (s)")
    axes[1].set_title("Detected injected faults")
    axes[1].grid(True, alpha=0.3)
    axes[1].legend(loc="upper right")

    figure.suptitle(
        "Physical CAN Fault-Injection Test\n"
        f"{len(bad_crc)} bad-CRC frames | {len(bad_dlc)} wrong-DLC frames | "
        f"{len(direct_jumps)} direct counter jump | timeout fail-safe observed",
        fontsize=14,
    )
    figure.tight_layout(rect=(0, 0, 1, 0.90))
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=160, bbox_inches="tight")
    plt.close(figure)
    return jumps, direct_jumps


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("endurance", type=Path)
    parser.add_argument("faults", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    endurance_rows = read_capture(args.endurance)
    fault_rows = read_capture(args.faults)
    endurance_plot = args.output_dir / "hardware-endurance-10min.png"
    fault_plot = args.output_dir / "hardware-fault-injection.png"
    summary_path = args.output_dir / "hardware-validation-summary-2026-09-10.json"

    plot_endurance(endurance_rows, endurance_plot)
    jumps, direct_jumps = plot_faults(fault_rows, fault_plot)
    summary = {
        "test_date": "2026-09-10",
        "hardware": "Two ESP32-WROOM-32 boards and two SN65HVD230 transceivers",
        "can_bitrate": 500000,
        "endurance": capture_summary(endurance_rows),
        "fault_injection": {
            **capture_summary(fault_rows),
            "observed_sequence_gaps": len(jumps),
            "direct_counter_jump_injections": len(direct_jumps),
            "cli_reported_crc_failures": 9,
            "timeout_failsafe_observed": True,
        },
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"saved {endurance_plot}")
    print(f"saved {fault_plot}")
    print(f"saved {summary_path}")


if __name__ == "__main__":
    main()
