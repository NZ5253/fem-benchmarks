#!/bin/bash
# Build all PFEM programs for a specific chapter
#
# Usage:
#   ./scripts/pfem_build_chapter.sh [pfem_root] <chapter> [--rebuild]
#
# Example (pfem/ is inside the repo):
#   ./scripts/pfem_build_chapter.sh chap04
#   ./scripts/pfem_build_chapter.sh pfem chap04 --rebuild
#
# This script:
# 1. Finds all unique programs needed for a chapter (from .dat filenames)
# 2. Builds the PFEM library if needed (same approach as pfem_build_and_run.sh)
# 3. Compiles each program

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PFEM_ROOT="${1:-$REPO_ROOT/pfem}"
CHAPTER="${2:-chap05}"
REBUILD="${3:-}"

# Expand ~
PFEM_ROOT="${PFEM_ROOT/#\~/$HOME}"

echo "============================================================"
echo "Building PFEM programs for $CHAPTER"
echo "PFEM root: $PFEM_ROOT"
echo "============================================================"

# Check PFEM root exists
if [ ! -d "$PFEM_ROOT" ]; then
    echo "Error: PFEM root not found: $PFEM_ROOT"
    exit 1
fi

# Check chapter directory exists
EXEC_DIR="$PFEM_ROOT/executable/$CHAPTER"
if [ ! -d "$EXEC_DIR" ]; then
    echo "Error: Chapter directory not found: $EXEC_DIR"
    exit 1
fi

# Build directory structure (same as pfem_build_and_run.sh)
BUILD="$PFEM_ROOT/build"
MOD="$BUILD/mod"
OBJ="$BUILD/obj"
BIN="$BUILD/bin"
LIB="$OBJ/libpfem.a"

# Find unique programs from .dat files
PROGRAMS=$(ls "$EXEC_DIR"/*.dat 2>/dev/null | xargs -n1 basename | sed 's/_[0-9]*\.dat$//' | sed 's/\.dat$//' | sort -u)

if [ -z "$PROGRAMS" ]; then
    echo "Warning: No .dat files found in $EXEC_DIR"
    exit 0
fi

echo ""
echo "Programs to build:"
for prog in $PROGRAMS; do
    echo "  - $prog"
done
echo ""

# Function to compile a module
compile_module_if_exists() {
    local src="$1"
    local objname="$2"
    if [ -f "$src" ]; then
        echo "  Compiling module: $(basename $src)"
        gfortran -c -O2 "$src" -J"$MOD" -I"$MOD" -o "$OBJ/$objname"
    fi
}

# Build library if needed
build_library() {
    echo "Building PFEM library..."
    rm -rf "$BUILD"
    mkdir -p "$MOD" "$OBJ" "$BIN"

    # Compile key modules first
    compile_module_if_exists "$PFEM_ROOT/source/library/main/main_int.f03" "main_int.o"
    compile_module_if_exists "$PFEM_ROOT/source/library/geom/geom_int.f03" "geom_int.o"

    # Compile remaining library sources
    while IFS= read -r -d '' f; do
        # Skip already compiled module sources
        [[ "$f" == "$PFEM_ROOT/source/library/main/main_int.f03" ]] && continue
        [[ "$f" == "$PFEM_ROOT/source/library/geom/geom_int.f03" ]] && continue

        out="$OBJ/$(basename "${f%.*}").o"
        echo "  Compiling: $(basename $f)"
        gfortran -c -O2 "$f" -J"$MOD" -I"$MOD" -o "$out"
    done < <(find "$PFEM_ROOT/source/library" -type f \( -iname "*.f" -o -iname "*.f90" -o -iname "*.f95" -o -iname "*.f03" \) -print0)

    ar rcs "$LIB" "$OBJ"/*.o
    echo "  ✓ Library built: $LIB"
}

# Check if library rebuild needed
need_rebuild=false
if [ "$REBUILD" == "--rebuild" ]; then
    need_rebuild=true
elif [ ! -f "$LIB" ]; then
    need_rebuild=true
fi

if $need_rebuild; then
    build_library
else
    mkdir -p "$MOD" "$OBJ" "$BIN"
    echo "Using existing library: $LIB"
fi

# Build each program
echo ""
echo "Building programs..."
SOURCE_DIR="$PFEM_ROOT/source/$CHAPTER"

success_count=0
fail_count=0

for prog in $PROGRAMS; do
    SOURCE_FILE="$SOURCE_DIR/$prog.f03"
    EXE_FILE="$BIN/$prog"

    if [ ! -f "$SOURCE_FILE" ]; then
        echo "  ✗ $prog: source not found"
        ((fail_count++)) || true
        continue
    fi

    # Check if rebuild needed
    if [ -f "$EXE_FILE" ] && [ "$EXE_FILE" -nt "$SOURCE_FILE" ] && [ "$REBUILD" != "--rebuild" ]; then
        echo "  ✓ $prog: up to date"
        ((success_count++)) || true
        continue
    fi

    echo "  Building $prog..."

    # Compile program (same as pfem_build_and_run.sh)
    if gfortran -O2 "$SOURCE_FILE" -I"$MOD" "$LIB" -o "$EXE_FILE" 2>&1; then
        echo "    ✓ $prog: built successfully"
        ((success_count++)) || true
    else
        echo "    ✗ $prog: build failed"
        ((fail_count++)) || true
    fi
done

echo ""
echo "============================================================"
echo "Summary: $success_count built, $fail_count failed"
echo "============================================================"

if [ $fail_count -gt 0 ]; then
    exit 1
fi

exit 0
