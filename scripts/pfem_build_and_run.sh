#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/pfem_build_and_run.sh <PFEM_ROOT> <chapXX> <program> <case_basename> [--rebuild]
#
# Example:
#   scripts/pfem_build_and_run.sh ~/Downloads/pfem5/5th_ed chap05 p51 p51_3 --rebuild

PFEM_ROOT="${1:-}"
CHAP="${2:-}"
PROG="${3:-}"
CASE="${4:-}"
REBUILD="${5:-}"

if [[ -z "$PFEM_ROOT" || -z "$CHAP" || -z "$PROG" || -z "$CASE" ]]; then
  echo "Usage: $0 <PFEM_ROOT> <chapXX> <program> <case_basename> [--rebuild]"
  exit 1
fi

BUILD="$PFEM_ROOT/build"
MOD="$BUILD/mod"
OBJ="$BUILD/obj"
BIN="$BUILD/bin"
LIB="$OBJ/libpfem.a"

need_rebuild=false
if [[ "$REBUILD" == "--rebuild" ]]; then
  need_rebuild=true
elif [[ ! -f "$LIB" ]]; then
  need_rebuild=true
fi

compile_module_if_exists () {
  local src="$1"
  local objname="$2"
  if [[ -f "$src" ]]; then
    echo "[LIB] Compiling module: $src"
    gfortran -c -O2 "$src" -J"$MOD" -I"$MOD" -o "$OBJ/$objname"
  fi
}

build_library () {
  echo "[LIB] Rebuilding PFEM library..."
  rm -rf "$BUILD"
  mkdir -p "$MOD" "$OBJ" "$BIN"

  # Compile key modules first (these two exist in your PFEM tree)
  compile_module_if_exists "$PFEM_ROOT/source/library/main/main_int.f03" "main_int.o"
  compile_module_if_exists "$PFEM_ROOT/source/library/geom/geom_int.f03" "geom_int.o"

  # Compile remaining library sources recursively (skip the two already compiled above)
  while IFS= read -r -d '' f; do
    # Skip already compiled module sources
    [[ "$f" == "$PFEM_ROOT/source/library/main/main_int.f03" ]] && continue
    [[ "$f" == "$PFEM_ROOT/source/library/geom/geom_int.f03" ]] && continue

    out="$OBJ/$(basename "${f%.*}").o"
    echo "[LIB] Compiling $f"
    gfortran -c -O2 "$f" -J"$MOD" -I"$MOD" -o "$out"
  done < <(find "$PFEM_ROOT/source/library" -type f \( -iname "*.f" -o -iname "*.f90" -o -iname "*.f95" -o -iname "*.f03" \) -print0)

  ar rcs "$LIB" "$OBJ"/*.o
  echo "[LIB] Built: $LIB"
}

if $need_rebuild; then
  build_library
else
  mkdir -p "$MOD" "$OBJ" "$BIN"
  echo "[LIB] Using existing library: $LIB"
fi

# Compile the chapter program
SRC="$PFEM_ROOT/source/$CHAP/${PROG}.f03"
EXE="$BIN/$PROG"

if [[ ! -f "$SRC" ]]; then
  echo "[ERR] Program source not found: $SRC"
  echo "      (If it’s .f90/.f95, adjust the script or rename accordingly.)"
  exit 1
fi

echo "[PROG] Compiling $SRC -> $EXE"
gfortran -O2 "$SRC" -I"$MOD" "$LIB" -o "$EXE"

# Locate the .dat input (usually in executable/<chapXX>)
WORKDIR="$PFEM_ROOT/executable/$CHAP"
DAT="$WORKDIR/${CASE}.dat"

if [[ ! -f "$DAT" ]]; then
  echo "[WARN] Not found in expected folder: $DAT"
  echo "[INFO] Searching for ${CASE}.dat under $PFEM_ROOT/executable ..."
  found="$(find "$PFEM_ROOT/executable" -type f -name "${CASE}.dat" | head -n 1 || true)"
  if [[ -z "$found" ]]; then
    echo "[ERR] Could not find ${CASE}.dat anywhere under $PFEM_ROOT/executable"
    exit 1
  fi
  DAT="$found"
  WORKDIR="$(dirname "$DAT")"
  echo "[INFO] Found: $DAT"
fi

# Run (PFEM programs typically prompt for basename; we feed it via stdin)
echo "[RUN] cd '$WORKDIR' && printf '${CASE}\\n' | '$EXE'"
cd "$WORKDIR"
printf "%s\n" "$CASE" | "$EXE"

echo "[DONE] Outputs for ${CASE}:"
ls -lah "${CASE}."* 2>/dev/null || echo "No output files matching ${CASE}.* found (check program output above)."
