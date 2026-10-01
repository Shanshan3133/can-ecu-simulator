"""Compile and execute the vendor-neutral RTL testbenches with Icarus."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

CASES = (
    ("can_crc15", ROOT / "rtl" / "can_crc15.v", ROOT / "sim" / "tb_can_crc15.v"),
    (
        "can_bit_timing",
        ROOT / "rtl" / "can_bit_timing.v",
        ROOT / "sim" / "tb_can_bit_timing.v",
    ),
)


def main() -> int:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if not iverilog or not vvp:
        print("Icarus Verilog is required: install iverilog and vvp.", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="can-fpga-") as build_dir:
        for name, rtl, testbench in CASES:
            output = Path(build_dir) / f"{name}.vvp"
            subprocess.run(
                [iverilog, "-g2012", "-Wall", "-o", str(output), str(rtl), str(testbench)],
                check=True,
            )
            subprocess.run([vvp, str(output)], check=True)

    print(f"PASS: {len(CASES)} RTL testbenches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
