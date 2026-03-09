# PFEM Source Patches

The `pfem/` directory is gitignored (obtain from pfem.org.uk). These files
document the patches required to build and run all 87 benchmark cases on Linux
with gfortran. Apply after cloning the PFEM 5th edition source.

## Patch summary

| File | Change | Reason |
|------|--------|--------|
| `source/chap04/p42.f03` | Add `USE geom` after `USE main` | `formnf` uses assumed-shape arrays; without an explicit interface, gfortran generates a bad call → SIGSEGV |
| `source/chap04/p44.f03` | Add `USE geom` after `USE main` | Same as p42 |
| `source/chap05/p57.f03` | Add UMAT array allocations (see patch) | ALLOCATABLE arrays `statev`, `stran`, `drot`, `dfgrd0/1`, etc. are declared but never allocated in the original source |
| `source/library/main/main_int.f03` | Add `elap_time()` interface | p57 uses `IMPLICIT NONE`; without an explicit interface the function has no implicit type |

## New library files to add

Place these in `source/library/misc/` (create the directory if needed):

| File | Purpose |
|------|---------|
| `elap_time.f03` | Wall-clock timer using `system_clock` — replaces the missing timing function called by p57 |
| `umat_elastic.f03` | Isotropic linear-elastic Abaqus UMAT stub — required by p57 (Abaqus UMAT version of p56) |
| `lancz.f03` | Lanczos eigensolver (`lancz1`/`lancz2`) — required by p103; these routines were part of the PFEM 4th edition library and are absent from the 5th edition source |

## How to apply

```bash
# 1. Apply source patches
patch pfem/source/chap04/p42.f03           < scripts/pfem_patches/p42_add_use_geom.patch
patch pfem/source/chap04/p44.f03           < scripts/pfem_patches/p44_add_use_geom.patch
patch pfem/source/library/main/main_int.f03 < scripts/pfem_patches/main_int_elap_time_interface.patch

# For p57.f03 apply manually (the UMAT allocation block after ALLOCATE(props(nprops))):
#   see scripts/pfem_patches/p57_umat_alloc.patch

# 2. Copy new library source files
mkdir -p pfem/source/library/misc
cp scripts/pfem_patches/elap_time.f03     pfem/source/library/misc/
cp scripts/pfem_patches/umat_elastic.f03  pfem/source/library/misc/
cp scripts/pfem_patches/lancz.f03         pfem/source/library/misc/

# 3. Rebuild all chapters
for chap in chap04 chap05 chap06 chap07 chap08 chap09 chap10 chap11; do
  bash scripts/pfem_build_chapter.sh pfem $chap
done
```

## External dependencies (chap10)

- `p104` requires ARPACK: `sudo apt install libarpack2-dev`
- The build script (`pfem_build_chapter.sh`) auto-detects ARPACK usage and
  links `-larpack -llapack -lblas` when needed.
- `p103` requires the Lanczos routines provided in `lancz.f03` (included above).

## Notes

- `p57` is the Abaqus UMAT version of `p56`. The `umat_elastic.f03` stub
  implements a standard isotropic linear-elastic constitutive model matching
  the UMAT interface. Results should match `p56` for the same mesh and material.
- `lancz1`/`lancz2` implement reverse-communication Lanczos with Sturm-sequence
  convergence checking. The eigenvalues produced by p103 should be consistent
  with those from p104 (ARPACK) for the same problem.
