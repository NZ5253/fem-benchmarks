# Architecture and End-to-End Flow

**Author**: Naeem Zainuddin
**Last updated**: 2026-06-30
**Purpose**: the single document that explains how the whole project fits
together: the pipeline stages, how every file connects to the next, the
exact call graph, the lifecycle of a run, the problems that were solved
along the way, and what is deliberately left for later.

If you are new to this repository, read this file first, then follow the
reading order in Section 1.

---

## 0. What this project is (in one paragraph)

"Programming the Finite Element Method" (PFEM, 5th ed., Smith / Griffiths /
Margetts) ships 87 small Fortran FE programs across chapters 4-11. This
repository (a) catalogues all 87 as machine-readable YAML, (b) builds the
Fortran source on Linux gfortran with a documented set of small patches,
and (c) wraps everything in a MATLAB layer that can run any case under
deterministic sweeps, Monte Carlo / Latin Hypercube sampling, correlated
sampling, and one-at-a-time sensitivity, then extract the physically
meaningful Quantity of Interest (QoI) per case type. Everything is verified
end to end: every case builds, runs, and returns a meaningful QoI.

---

## 1. Documentation map and reading order

Read in this order. Each entry says what the document is for and when to
stop and go elsewhere.

| # | Document | Read it to learn | When to read |
|---|----------|------------------|--------------|
| 1 | **docs/ARCHITECTURE.md** (this file) | How the pieces connect; the data flow; the call graph; problems solved; future work | First. Start here always. |
| 2 | [docs/HANDOVER.md](HANDOVER.md) | How to set up a fresh machine; current git/sync state; the exact "what is done / what is pending" snapshot; project-specific gotchas | Second, when picking the project up on a new system |
| 3 | [README.md](../README.md) | Top-level overview and the fastest possible quick start | Skim any time |
| 4 | [docs/GUIDE.md](GUIDE.md) | Detailed how-to: generating YAML, building, running, patching, validation | When you need to *do* a specific task |
| 5 | [matlab/README.md](../matlab/README.md) | Function-by-function reference for the MATLAB layer (signatures, examples, output folder layout) | When writing or calling MATLAB code |
| 6 | [docs/PROGRESS.md](PROGRESS.md) | Supervisor-facing narrative of Phase 1 and Phase 2 with validation evidence and numbers | When you need the "why it is correct" evidence |
| 7 | [scripts/pfem_patches/README.md](../scripts/pfem_patches/README.md) | The exact patches needed to compile the textbook source on Linux | When (re)building the Fortran source |

The Fortran source under `pfem/` is **gitignored** (third-party, licensed).
It is not in the repo; see HANDOVER Section 2.3 to restore it.

---

## 1.5 Zero to first result (linear runbook)

The single straight-line path from a fresh clone to seeing a figure. Each
step says which document has the detail if you get stuck.

```bash
# 0. Prerequisites (Linux) -- HANDOVER Section 2.1
sudo apt install gfortran make python3 python3-pip \
                 libarpack2-dev liblapack-dev libblas-dev
pip install pyyaml

# 1. Get the repo
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks

# 2. Restore the PFEM Fortran source into pfem/ (gitignored, licensed)
#    Then apply the patches -- scripts/pfem_patches/README.md, HANDOVER 2.3
#    (without the patches several cases SIGSEGV or fail to link)

# 3. Build one chapter (also builds the shared library)
scripts/pfem_build_chapter.sh ./pfem chap06

# 4. Smoke-test the whole catalogue (optional, ~3 min once built)
python3 scripts/run_all_tests.py        # expect 87/87 PASSED
```

```matlab
% 5. Run one case with an override and get artifacts -- matlab/README.md
addpath matlab matlab/utils
repo_root = pwd;  pfem_root = fullfile(repo_root, 'pfem');
[status, out] = pfem_run_from_yaml(repo_root, pfem_root, ...
    'benchmarks/pfem5/chap06/p61.yaml', struct('yield_stress', 200));
% -> runs/chap06/p61/sy_200/  with p61.res, p61.msh, case.yaml, run_info.txt

% 6. See it in the GUI (deterministic + stochastic + sensitivity) -- GUIDE.md
pfem_sweep_gui
%   Add YAML(s) -> pick p61.yaml -> Fill Ranges -> Run All -> Open Figures
```

That is the end-to-end thread. Stages 1-6 here map onto the five pipeline
stages in Section 2 (build = stage 2, run = stage 3, GUI figures = stages 4-5).

---

## 2. The pipeline: five stages

Everything in the repo is one of five stages. Data flows left to right.

```
  (1) GENERATE          (2) BUILD            (3) RUN              (4) EXTRACT          (5) ANALYZE / PLOT
  ────────────          ─────────            ───────              ───────────          ──────────────────
  Fortran source   ┐                                                                  ┌ deterministic figs
  + .dat files     ├─► YAML catalogue ─► compiled binary ─► .res/.msh/.dis/.vec ─► QoI value ─► histograms/CDF
  (pfem/source)    ┘    (benchmarks/)      (pfem/build/bin)     (runs/.../)          (per type)   tornado plots

  scripts/             scripts/             matlab/              matlab/utils/        matlab/utils/
  generate_yamls_v2.py pfem_build_*.sh      pfem_run_from_yaml.m pfem_extract_qoi.m   pfem_plot_*.m
                       pfem_patches/        + pfem_sweep_gui.m   pfem_detect_case_type
```

### Stage 1 — Generate the YAML catalogue (offline, Python)

- **`scripts/generate_yamls_v2.py`** parses each `pfem/source/chapXX/pNN.f03`
  program and its `.dat` data file. It walks the Fortran `READ(10,*)`
  statements in source order using a symbol table, tokenises the `.dat`
  file into a flat list, and writes `benchmarks/pfem5/chapXX/pNN.yaml`.
  Each tunable parameter is recorded with a `global_token_index` (its
  1-based position in the flat token list) so it can be patched later
  without any program-specific code.
- **`scripts/verify_yamls.py`** validates the generated YAML (syntax,
  required keys, structure).
- The tunable-detection logic (how `nprops`, `nodof`, scalar names map to
  physical parameters) is documented in detail in the project memory and
  in GUIDE.md Section "Generating YAML Files". This is the most intricate
  Python code; treat the per-`nprops` classification table as the spec.

Output of this stage: the `benchmarks/pfem5/chap*/p*.yaml` catalogue, which
is the contract every downstream stage reads.

### Stage 2 — Build the Fortran binaries

- **`scripts/pfem_build_chapter.sh <pfem_root> <chapter>`** compiles the
  PFEM library plus every program in a chapter into `pfem/build/bin/pNN`.
  It auto-detects ARPACK/BLAS usage and links `-larpack -llapack -lblas`
  when needed. The `misc/` library subdirectory is compiled by wildcard.
- **`scripts/pfem_build_and_run.sh`** builds one program and runs it.
- **`scripts/pfem_patches/`** holds the patches that make the textbook
  source compile on Linux gfortran (missing `USE geom`, unallocated UMAT
  arrays, a `system_clock` timer, a Lanczos eigensolver, an elastic UMAT
  stub). Without these, several cases SIGSEGV or fail to link. See that
  folder's README.

Binaries are Linux ELF in `pfem/build/bin/`; the Windows `.exe` files under
`pfem/executable/` are NOT used by the runner.

### Stage 3 — Run a case

- **`matlab/pfem_run_from_yaml.m`** is the low-level runner and the single
  choke point every higher-level tool funnels through. Given a YAML path
  and an `overrides` struct it: loads the YAML, copies the `.dat` into an
  isolated run folder, applies the token-based parameter patch, ensures the
  binary is built, runs it, and locates (or auto-generates) a baseline
  `.res` for comparison. See Section 4 for the step-by-step.
- For multi-case datasets the program name and the dataset name differ
  (e.g. program `p41`, dataset `p41_1`); the runner handles this.

### Stage 4 — Extract the Quantity of Interest

- **`matlab/utils/pfem_detect_case_type.m`** classifies a YAML into one of
  8 case types from its metadata (chapter, program, physics, regime).
- **`matlab/utils/pfem_extract_qoi.m`** dispatches on the case type to the
  right extractor and returns `q.value`, `q.label`, `q.unit`, `q.ok`. This
  is where all the `.res` file format quirks are handled (Section 6).

### Stage 5 — Analyze and visualize

- **Deterministic**: `matlab/utils/pfem_plot_sweep_summary.m` builds up to
  four figure windows (load-displacement, reference mesh, deformed shape,
  displacement vectors), using `pfem_extract_coords.m` for node coordinates
  and `parse_pfem_ensi.m` for 3D EnSight output.
- **Stochastic**: histogram, CDF, and per-parameter scatter plots; for
  slope cases also `P(failure)` and reliability index `beta`.
- **Sensitivity**: `matlab/utils/pfem_plot_tornado.m` draws the tornado bar
  chart from `pfem_sensitivity_oat.m`.

---

## 3. Call graph: who calls whom

This is the actual call structure (verified against the source). Indentation
is "calls".

```
ENTRY POINTS (what a user launches)
│
├── pfem_sweep_gui.m ........................ the GUI; all four modes
│   │
│   ├── pfem_yaml_load ....................... load YAML -> struct (every mode)
│   ├── pfem_make_scenarios ................. Lockstep / Grid: build scenario list
│   ├── pfem_lhs_sample ..................... Stochastic: Latin Hypercube + Iman-Conover
│   ├── pfem_sample_distribution ............ Stochastic: IID draws (fallback / per-param)
│   ├── pfem_sensitivity_oat ................ Sensitivity mode: 2k+1 runs
│   │      └── pfem_run_from_yaml (per run)
│   ├── pfem_ensure_built ................... auto-compile missing binary
│   ├── pfem_run_from_yaml .................. THE run choke point (see below)
│   ├── pfem_detect_case_type ............... Stochastic: classify case
│   ├── pfem_extract_qoi .................... Stochastic: extract QoI per sample
│   ├── pfem_plot_sweep_summary ............. deterministic figures
│   └── pfem_plot_tornado ................... sensitivity figure
│
├── NZ.m .................................... scripted multi-case x multi-scenario sweep
│   ├── pfem_make_scenarios
│   ├── pfem_ensure_built
│   ├── pfem_run_from_yaml
│   ├── pfem_compare_results ................ text diff table (Format A / B)
│   └── pfem_plot_sweep_summary
│
├── pfem_stochastic_sweep.m ................. scripted Monte Carlo (CLI-style)
│   ├── pfem_sample_distribution
│   └── pfem_run_from_yaml
│
└── scripts/run_all_tests.py ................ Python smoke test; mirrors pfem_run_from_yaml
                                              in Python and runs all 87 cases

THE RUN CHOKE POINT
│
pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides)
   ├── pfem_yaml_load ....................... parse YAML
   ├── pfem_patch_dat_using_yaml ........... token-based .dat patch from overrides
   ├── pfem_ensure_built ................... compile binary if missing
   │      └── (shells out to) pfem_build_chapter.sh
   ├── system(printf dataset | ./prog) ..... actually run the Fortran binary
   └── generate_baseline_run (local) ....... cache an unmodified .res if the book one is absent

THE QoI DISPATCHER
│
pfem_extract_qoi(out, case_type)   case_type from pfem_detect_case_type
   ├── qoi_slope_srf ........... Factor of Safety (last converged SRF)
   ├── qoi_plasticity_load ..... limit load at last converged step
   ├── qoi_elastic_static ...... max nodal displacement
   ├── qoi_seepage_steady ...... max total head
   ├── qoi_consolidation ....... degree of consolidation at final time
   ├── qoi_eigenvalue .......... omega^2 (smallest eig), derived f1 in Hz
   ├── qoi_dynamic_transient ... peak displacement
   ├── qoi_thermal ............. max temperature
   └── qoi_generic_fallback .... widest numeric table fallback
   (shared helpers: read_widest_numeric_table, read_blocks, header_is_time_axis,
    find_header_tokens, identify_columns_from_tokens)
```

### Files NOT in the main pipeline (so you can ignore them)

A few files live in `matlab/` but are not part of the run/sweep flow above.
They are labelled as such in their own headers; listed here so a newcomer
does not mistake them for live code:

| File | What it is |
|------|-----------|
| `pfem_parametric_sweep.m` | LEGACY. An older program-specific sweeper, superseded by `pfem_run_from_yaml` + the GUI/NZ.m. Kept for reference. |
| `pfem_test_run.m` | DEV SCRATCH. Manual smoke check of load/run/patch. Not an automated test. |
| `pfem_diagram_test.m` | DEV SCRATCH. Manual visual check of `pfem_diagram`. |

The one reproducible, automated test is
`matlab/tests/test_phase2_multi_case.m` (see Section 10).

---

## 4. Lifecycle of a single run (concrete walkthrough)

What happens when you run one case with overrides, e.g.
`pfem_run_from_yaml(repo_root, pfem_root, 'benchmarks/pfem5/chap06/p61.yaml',
struct('yield_stress', 200))`:

1. **Load** the YAML (`pfem_yaml_load`) -> struct `y` with `program`,
   `chap`, `dataset`, `tunable_parameters` (each with `global_token_index`),
   `inputs.all_tokens`, `outputs`.
2. **Make the run folder** `runs/<chap>/<case>/<param_key>/` (e.g.
   `runs/chap06/p61/sy_200/`). The key is derived from the overrides.
3. **Copy** the source `.dat` into the run folder.
4. **Patch** (`pfem_patch_dat_using_yaml`): for each override, look up the
   tunable's `global_token_index`, replace that token in the flat token
   list, and rewrite the `.dat`. No program-specific logic; integer params
   (e.g. `load_increments`) get special handling so dependent arrays such as
   `qinc` are regenerated.
5. **Ensure built** (`pfem_ensure_built`): if `pfem/build/bin/p61` is
   missing, shell out to `pfem_build_chapter.sh`. It checks for the binary's
   existence, not the script exit code (the chapter build may exit non-zero
   because some *other* program failed).
6. **Run**: copy the binary into the run folder, `chmod +x`, then
   `printf "<dataset>\n" | ./p61`. PFEM reads `<dataset>.dat` and writes
   `<dataset>.res` (and often `.msh`, `.dis`, `.vec`, or EnSight `.ensi.*`).
7. **Baseline**: locate the book's pre-computed `.res` in
   `pfem/executable/<chap>/`. If absent (e.g. p63), call
   `generate_baseline_run` to run the case once unmodified and cache the
   result in `runs/<chap>/<case>/default/`, so comparisons always have a
   reference.
8. **Record**: write `case.yaml`, `overrides.mat`, `run_info.txt`. Return
   `(status, out)` where `out.run_dir`, `out.case`, `out.files` let the
   caller find every artifact.

Result: a self-contained run folder you can re-run from a plain shell with
`printf "p61\n" | ./p61`.

---

## 5. Lifecycle of a stochastic sweep (GUI)

1. **Add YAML(s)** -> `pfem_yaml_load` -> the Tunable Parameters table is the
   union of all loaded cases' tunables.
2. **Mode = Stochastic** -> each Values cell holds a distribution spec:
   `lognormal(mu, COV)`, `normal(mu, COV)`, `truncnormal(mu, COV, lo, hi)`,
   `uniform(lo, hi)`. **Fill Ranges** auto-fills `lognormal(mu, COV)` from
   the YAML default with a physics-based COV per family (c 0.40, phi 0.10,
   E 0.30, nu 0.10, gamma 0.05, k 0.50). Solver and mesh parameters return
   `NaN` COV and are skipped (Section 6, gotcha S7).
3. **Sample** `n` joint realisations: `pfem_lhs_sample` (Latin Hypercube,
   default on; optional Iman-Conover correlation) or
   `pfem_sample_distribution` (IID).
4. For each sample: `pfem_run_from_yaml` -> `pfem_detect_case_type` ->
   `pfem_extract_qoi`.
5. **Report**: histogram, CDF, per-parameter scatter (PDF + PNG in
   `runs/<chap>/<case>/<case>_stochastic_<ts>_*`). For `slope_srf`:
   `P(FS < 1)` and `beta = -sqrt(2) * erfinv(2*Pf - 1)`.

Sensitivity mode is the same wiring but uses `pfem_sensitivity_oat` (runs at
`mu` and `mu +/- 1 sigma` per parameter, `2k+1` runs for `k` parameters) and
`pfem_plot_tornado`.

---

## 6. Challenges solved (register)

Consolidated from the work to date. Each item is a real problem that cost
time; keep this list so the next person does not rediscover them.

### Build / Fortran (Stage 2)
- **B1. `formnf` SIGSEGV (p42, p44)**: `formnf` takes assumed-shape arrays;
  without `USE geom` providing the explicit interface, gfortran emits a bad
  call. Fix: add `USE geom`. (`pfem_patches/`)
- **B2. Unallocated UMAT arrays (p57)**: `statev`, `stran`, `drot`,
  `dfgrd0/1` are declared ALLOCATABLE but never allocated in the textbook.
  Fix: allocate them.
- **B3. Missing timer / interface (p57)**: needs `elap_time()` with an
  explicit interface under `IMPLICIT NONE`. Fix: new `elap_time.f03` (a
  `system_clock` wrapper) plus an interface in `main_int.f03`.
- **B4. Missing Lanczos solver (p103)**: `lancz1`/`lancz2` were in the 4th
  edition library but dropped from the 5th. Fix: new `lancz.f03`.
- **B5. ARPACK (p104)**: needs `libarpack2-dev`; the build script
  auto-links it.
- **B6. Wrong dataset for p56**: the executable `.dat` is a huge 20x60x40
  mesh; the small `source/chap05/p56.dat` is the intended benchmark.

### Run plumbing (Stage 3)
- **R1. program != dataset**: multi-case programs (e.g. p41 with datasets
  p41_1, p41_2) require running the program binary while feeding the dataset
  name on stdin.
- **R2. Build exit code is unreliable**: a chapter build can exit non-zero
  because a *sibling* program failed. `pfem_ensure_built` checks for the
  binary file instead.
- **R3. Missing book `.res`**: some cases (e.g. p63) ship no precomputed
  result. `generate_baseline_run` creates and caches one.
- **R4. Integer parameter patching**: changing `load_increments` must
  regenerate the dependent `qinc` increment array, not just swap one token.

### QoI extraction (Stage 4) — `.res` file quirks
- **Q1. Multi-block files**: many `.res` files contain several numeric
  blocks (time history + depth profile, per-node + summary).
  `read_widest_numeric_table` / `read_blocks` pick the largest block tagged
  with a time-axis header.
- **Q2. Split time-history blocks (p95, p96_1, p96_2)**: a 5-column row at
  t=0 then 6-column rows for t>0 (an iteration-count column appears once
  iterations start). The dominant-block picker was choosing the 1-row t=0
  block; fixed to pick the largest time-tagged block.
- **Q3. Multi-word headers (p611, p63)**: "dev stress", "pore press" must be
  merged before tokenisation.
- **Q4. p118**: 4 columns (time / load / x-disp / y-disp), no iterations
  column.
- **Q5. p69 embankment lift**: free-text output ("Max displacement is X")
  handled by a regex fallback.
- **Q6. MATLAB `\b` regex bug**: `regexp(s, '^\s*time\b', 'once')` returns 0
  even when `s` starts with "time". Use `(\s|$)` after `^\s*`.

### Stochastic / sensitivity (Stage 5)
- **S7. Never sample solver/mesh parameters**: sampling
  `convergence_tolerance`, `iteration_limit`, `nels/nxe`, `time_step` etc.
  causes Fortran integer-read crashes or solver divergence. `default_cov()`
  returns `NaN` for these so Fill Ranges skips them, and the same NaN guard
  is applied in the runner. Do not weaken this guard.
- **S8. Eigenvalue label (p101, resolved 2026-05-27)**: the chap10 solver
  (`bandred` + `bisect` on `M^(-1/2) K M^(-1/2)`) returns `omega^2`
  directly. An earlier note claiming it returned `1/omega^2` was a
  misdiagnosis. The QoI is now labelled `omega^2` with a derived `f1` in Hz.
- **S9. LHS marginals vs correlation**: Iman-Conover restricted pairing
  induces the target rank correlation while preserving each LHS marginal
  exactly. Verified for targets in `[-0.7, +0.5]` within 5%.

### MATLAB structural
- **M10. Nested vs local functions**: nested functions require the outer
  function to end with `end`. Prefer top-level local functions in the same
  file.
- **M11. Old `uitable`**: does not accept `FontColor`/`BackgroundColor`/
  `RowName`; worked around.

---

## 7. Known limitations and future work (on hold)

### Known limitations (work, but with caveats)
1. **BC-bound QoIs**: some elastic / thermal cases (p51_3 `u_max`, p811
   `T_max`) report a boundary-condition value that does not vary with
   material sampling. The extractor is correct; the chosen QoI just is not
   sensitive. Possible fix: a per-case `qoi_probe_node` YAML field so the
   extractor tracks an internal point.
2. **p69 embankment lift**: only 7 of 10 LHS samples converge across the
   full c-phi-gamma range. The QoI extracts correctly when the solver
   converges. Possible work: report convergence rate per case.
3. **Heavy meshes (p56_1, p57)**: ~250 s per run; excluded from the n=10
   LHS timing run. Extractor works; just slow.

### Future work (not started)
- **Phase 3 — pluggable runner interface**: today `pfem_run_from_yaml.m` is
  hardcoded to PFEM. Extract the runner contract (write input from overrides,
  execute, parse output) into an interface and add a second backend (e.g. an
  analytical Prandtl solver as a regression check) to prove the abstraction.
- **Phase 4 — mesh-refinement sweeps** (`nxe`, `nye`) to study discretisation
  convergence. Note this changes mesh topology, so it is excluded from the
  current stochastic guard on purpose.
- **Regression testing against reference outputs**: `run_all_tests.py`
  currently checks run status only, not output values.
- **3D-figure work smoke test**: the EnSight material-zone / deformed-mesh
  rendering (commit `d279883`) is structurally complete but has not been
  runtime-verified in MATLAB on the current system. Run `pfem_sweep_gui` on
  p612 and a 2D structured case to confirm the figures render.

The authoritative, dated "what is done / pending / next" snapshot lives in
[docs/HANDOVER.md](HANDOVER.md) Sections 3, 4 and 8.

---

## 8. The 8 case types and their QoIs

Case type is decided by `pfem_detect_case_type.m`; the QoI extractor for each
lives in `pfem_extract_qoi.m`. Per-type case counts are best read from
`pfem_detect_case_type.m` directly (they shift if a case is reclassified);
the totals below sum to 87.

| Case type | QoI | Physical meaning |
|---|---|---|
| `slope_srf` | FS | Factor of Safety (last converged strength-reduction factor) |
| `plasticity_load` | P_lim | limit load at the last converged increment |
| `elastic_static` | u_max | maximum nodal displacement |
| `seepage_steady` | h_max | maximum total head |
| `consolidation` | Uav_end | degree of consolidation at the final time |
| `eigenvalue` | omega^2 | smallest eigenvalue (+ derived `f1` in Hz) |
| `dynamic_transient` | u_peak | peak transient displacement |
| `thermal` | T_max | maximum temperature |

---

## 9. Chapter coverage (87 cases)

| Chapter | Cases | Topic |
|---|---|---|
| chap04 | 13 | 1D problems, rods, beams, simple elasticity |
| chap05 | 15 | 2D / 3D linear elasticity |
| chap06 | 15 | material nonlinearity: von Mises, Mohr-Coulomb, slope stability (SRF) |
| chap07 | 8 | steady-state flow (seepage) |
| chap08 | 16 | transient: consolidation, thermal, dynamics |
| chap09 | 7 | coupled problems (Biot, Navier-Stokes) |
| chap10 | 5 | eigenvalue problems |
| chap11 | 8 | dynamics and explicit plasticity |
| **Total** | **87** | |

(Verified count of `benchmarks/pfem5/chap*/*.yaml` on 2026-06-30.)

---

## 10. Validation evidence (pointers)

The numbers that show the catalogue is correct, not just runnable, are in
[docs/PROGRESS.md](PROGRESS.md) Section 3. Highlights: p612 slope FS = 1.58
matches book Fig. 6.54; p61 limit load 515 matches Prandtl `(2+pi) sigma_y`
within 0.2%; p101 `omega^2 ~ 0.00382` matches the analytic cantilever first
mode (0.00402) for a 5-element lumped-mass beam. The reproducible script is
`matlab/tests/test_phase2_multi_case.m` (about 3 minutes once binaries are
built).
