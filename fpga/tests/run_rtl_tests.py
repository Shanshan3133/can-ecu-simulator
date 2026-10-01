"""Compile and execute the vendor-neutral RTL testbenches with Icarus."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

CASES = {
    "can_crc15": ("can_crc15.v",),
    "can_bit_timing": ("can_bit_timing.v",),
    "can_destuffer": ("can_destuffer.v",),
    "can_error_state": ("can_error_state.v",),
    "can_error_flag": ("can_error_flag.v",),
    "can_fault_paths": ("can_destuffer.v", "can_rx.v", "can_tx.v"),
    "can_controller_core": (
        "can_destuffer.v",
        "can_rx.v",
        "can_tx.v",
        "can_error_state.v",
        "can_error_flag.v",
        "can_controller_core.v",
    ),
}


def main() -> int:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if not iverilog or not vvp:
        print("Icarus Verilog is required: install iverilog and vvp.", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="can-fpga-") as build_dir:
        for name, rtl_names in CASES.items():
            output = Path(build_dir) / f"{name}.vvp"
            sources = [str(ROOT / "rtl" / rtl_name) for rtl_name in rtl_names]
            testbench = ROOT / "sim" / f"tb_{name}.v"
            subprocess.run(
                [iverilog, "-g2012", "-Wall", "-o", str(output), *sources, str(testbench)],
                check=True,
            )
            subprocess.run([vvp, str(output)], check=True)

    print(f"PASS: {len(CASES)} RTL testbenches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
