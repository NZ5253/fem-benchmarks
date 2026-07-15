#!/usr/bin/env bash
# Minimal external solver: read yield_stress from an input file, write
# P_lim = (2 + pi) * yield_stress to an output file.
#
# Purpose: prove the external backend is language-agnostic. Pure shell +
# awk, no dependencies beyond a POSIX system. Same physics as prandtl.py.
#
# Signature: prandtl.sh <input_file> <output_file>
set -eu
# Force period as decimal separator so the output parses on any locale.
export LC_ALL=C

if [ "$#" -ne 2 ]; then
    printf 'usage: %s <input_file> <output_file>\n' "$0" >&2
    exit 2
fi
inp="$1"; out="$2"

# Extract yield_stress (accept decimals + optional exponent notation).
sy=$(awk '/yield_stress[[:space:]]*=/ {
    if (match($0, /[-+]?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) {
        print substr($0, RSTART, RLENGTH); exit
    }
}' "$inp")

if [ -z "$sy" ]; then
    printf 'error: yield_stress not found in %s\n' "$inp" >&2
    exit 3
fi

# P_lim = (2 + pi) * sy. awk gives us floats and pi via atan2.
awk -v s="$sy" 'BEGIN { pi = atan2(0, -1); printf("P_lim = %.15g\n", (2 + pi) * s) }' \
    > "$out"
