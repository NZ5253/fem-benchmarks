#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Collect PFEM case bundles (source + dat + outputs + READ(10) map + context).

Usage:
  pfem_collect_all.sh --pfem-root <PFEM_ROOT> [--chap chap05 | --all-chaps]
                      [--out <OUT_DIR>] [--run] [--rebuild-first] [--single-tar]

Examples:
  # Just collect chap05 bundles (no running)
  scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --chap chap05

  # Collect chap05 and also run each case before bundling (creates outputs)
  scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --chap chap05 --run --rebuild-first

  # Collect all chapters
  scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --all-chaps

  # Collect all chapters + run all cases
  scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --all-chaps --run --rebuild-first
USAGE
}

PFEM_ROOT=""
OUT_DIR="./pfem_yaml_bundle"
CHAP_MODE=""
CHAP_ONE=""
DO_RUN=false
REBUILD_FIRST=false
SINGLE_TAR=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pfem-root) PFEM_ROOT="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --chap) CHAP_MODE="one"; CHAP_ONE="${2:-}"; shift 2 ;;
    --all-chaps) CHAP_MODE="all"; shift 1 ;;
    --run) DO_RUN=true; shift 1 ;;
    --rebuild-first) REBUILD_FIRST=true; shift 1 ;;
    --single-tar) SINGLE_TAR=true; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERR] Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$PFEM_ROOT" ]]; then
  echo "[ERR] --pfem-root is required"
  usage
  exit 1
fi

if [[ ! -d "$PFEM_ROOT/source" || ! -d "$PFEM_ROOT/executable" ]]; then
  echo "[ERR] PFEM root does not look valid: $PFEM_ROOT"
  echo "      Expected: $PFEM_ROOT/source and $PFEM_ROOT/executable"
  exit 1
fi

if [[ -z "$CHAP_MODE" ]]; then
  echo "[ERR] Choose --chap chapXX or --all-chaps"
  usage
  exit 1
fi

# Determine chapters
declare -a CHAPS=()
if [[ "$CHAP_MODE" == "one" ]]; then
  CHAPS=("$CHAP_ONE")
else
  mapfile -t CHAPS < <(find "$PFEM_ROOT/executable" -maxdepth 1 -type d -name "chap*" -printf "%f\n" | sort)
fi

mkdir -p "$OUT_DIR/cases" "$OUT_DIR/tars"

# Optional runner script (you already created something like this)
RUNNER_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pfem_build_and_run.sh"
HAS_RUNNER=false
if [[ -x "$RUNNER_SCRIPT" ]]; then
  HAS_RUNNER=true
fi

bundle_case() {
  local chap="$1"
  local dat_path="$2"

  local case_base
  case_base="$(basename "$dat_path" .dat)"

  # program base: remove optional _<digits> suffix
  local prog
  prog="$(echo "$case_base" | sed -E 's/(_[0-9]+)$//')"

  local src_dir="$PFEM_ROOT/source/$chap"
  local exe_dir
  exe_dir="$(dirname "$dat_path")"

  # Find the program source (usually prog.f03)
  local src=""
  src="$(find "$src_dir" -maxdepth 1 -type f -iname "${prog}.f*" | head -n 1 || true)"
  if [[ -z "$src" ]]; then
    echo "[WARN] No source found for $chap/$prog (from $case_base). Skipping."
    return 0
  fi

  # Optionally run to generate outputs
  if $DO_RUN; then
    if ! $HAS_RUNNER; then
      echo "[WARN] --run requested but runner script not found/executable at: $RUNNER_SCRIPT"
      echo "       Skipping run; will bundle whatever outputs already exist."
    else
      if $REBUILD_FIRST; then
        echo "[RUN] (rebuild) $chap $prog $case_base"
        "$RUNNER_SCRIPT" "$PFEM_ROOT" "$chap" "$prog" "$case_base" --rebuild || true
        REBUILD_FIRST=false
      else
        echo "[RUN] $chap $prog $case_base"
        "$RUNNER_SCRIPT" "$PFEM_ROOT" "$chap" "$prog" "$case_base" || true
      fi
    fi
  fi

  local dest="$OUT_DIR/cases/$chap/$case_base"
  mkdir -p "$dest"

  # Copy core files
  cp -f "$src" "$dest/"
  cp -f "$dat_path" "$dest/"

  # Copy any outputs that exist in the executable folder (same basename)
  shopt -s nullglob
  for f in "$exe_dir/${case_base}."*; do
    # includes .dat too; keep it (harmless), or skip it:
    # [[ "$f" == "$dat_path" ]] && continue
    cp -f "$f" "$dest/"
  done
  shopt -u nullglob

  # Create READ(10) map + context
  local src_name
  src_name="$(basename "$src")"
  local read_lines="$dest/${prog}_READ10_lines.txt"
  local numbered="$dest/${prog}_numbered.txt"
  local context="$dest/${prog}_READ10_context.txt"

  grep -n "READ(10" "$src" > "$read_lines" || true
  nl -ba "$src" > "$numbered"

  : > "$context"
  if [[ -s "$read_lines" ]]; then
    awk -F: '{print $1}' "$read_lines" | while read -r ln; do
      local start=$((ln-15))
      local end=$((ln+15))
      [[ $start -lt 1 ]] && start=1
      echo "===== CONTEXT around line $ln ($src_name) =====" >> "$context"
      sed -n "${start},${end}p" "$numbered" >> "$context"
      echo "" >> "$context"
    done
  fi

  # Helpful library files for interpreting BC conventions and module meanings
  [[ -f "$PFEM_ROOT/source/library/geom/formnf.f03" ]] && cp -f "$PFEM_ROOT/source/library/geom/formnf.f03" "$dest/" || true
  [[ -f "$PFEM_ROOT/source/library/main/main_int.f03" ]] && cp -f "$PFEM_ROOT/source/library/main/main_int.f03" "$dest/" || true
  [[ -f "$PFEM_ROOT/source/library/geom/geom_int.f03" ]] && cp -f "$PFEM_ROOT/source/library/geom/geom_int.f03" "$dest/" || true

  # Result head (if .res exists)
  if [[ -f "$dest/${case_base}.res" ]]; then
    head -n 120 "$dest/${case_base}.res" > "$dest/${case_base}_res_head.txt" || true
  fi

  # Run info
  {
    echo "DATE: $(date -Is)"
    echo "HOST: $(hostname)"
    echo "GFORTRAN: $({ gfortran --version 2>/dev/null | head -n 1; } || echo 'not found')"
    echo "PFEM_ROOT: $PFEM_ROOT"
    echo "CHAPTER: $chap"
    echo "PROGRAM: $prog"
    echo "CASE_BASENAME: $case_base"
    echo "EXE_DIR: $exe_dir"
    echo "SOURCE: $src"
  } > "$dest/run_info.txt"

  # Make a tarball for this case
  local tar_out="$OUT_DIR/tars/${chap}_${case_base}_bundle.tar.gz"
  tar -czf "$tar_out" -C "$OUT_DIR/cases/$chap" "$case_base"
  echo "[OK] Bundled: $tar_out"
}

echo "[INFO] PFEM_ROOT=$PFEM_ROOT"
echo "[INFO] OUT_DIR=$OUT_DIR"
echo "[INFO] Chapters: ${CHAPS[*]}"
echo "[INFO] DO_RUN=$DO_RUN (runner present: $HAS_RUNNER)"

for chap in "${CHAPS[@]}"; do
  local_exe="$PFEM_ROOT/executable/$chap"
  if [[ ! -d "$local_exe" ]]; then
    echo "[WARN] Missing executable folder for $chap: $local_exe (skipping)"
    continue
  fi

  echo "========== CHAPTER $chap =========="

  shopt -s nullglob
  dats=("$local_exe"/*.dat)
  shopt -u nullglob

  if [[ ${#dats[@]} -eq 0 ]]; then
    echo "[WARN] No .dat files in $local_exe"
    continue
  fi

  for dat in "${dats[@]}"; do
    bundle_case "$chap" "$dat"
  done
done

if $SINGLE_TAR; then
  big_tar="$OUT_DIR/pfem_all_bundles.tar.gz"
  tar -czf "$big_tar" -C "$OUT_DIR" "cases" "tars"
  echo "[OK] Single archive created: $big_tar"
fi

echo "[DONE] All bundles collected in: $OUT_DIR"
