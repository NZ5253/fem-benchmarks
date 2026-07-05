#!/usr/bin/env python3
"""Minimal external solver: read yield_stress from an input file, write
P_lim = (2 + pi) * yield_stress to an output file.

Purpose: known-answer fixture for the external_backend (Phase 3 M4).
Signature: prandtl.py <input_file> <output_file>
"""
import math
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write(f"usage: {sys.argv[0]} <input_file> <output_file>\n")
        return 2
    inp_path, out_path = sys.argv[1], sys.argv[2]
    with open(inp_path, "r") as f:
        text = f.read()
    m = re.search(r"yield_stress\s*=\s*([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)", text)
    if not m:
        sys.stderr.write(f"error: yield_stress not found in {inp_path}\n")
        return 3
    sigma_y = float(m.group(1))
    p_lim = (2.0 + math.pi) * sigma_y
    with open(out_path, "w") as f:
        f.write(f"P_lim = {p_lim:.15g}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
