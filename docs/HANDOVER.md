# Handover — fem-benchmarks Project

**Author**: Naeem Zainuddin
**Last updated**: 2026-06-30
**Repo**: https://github.com/NZ5253/fem-benchmarks (master in sync with origin at `fe0803c`, plus local commits for the 3D-viz work and this doc)
**Local backup**: USB drive labelled "USB Drive" -> `fem-benchmarks-cleaned-20260522_140600`

This document is the single source of truth for picking the project up on
a new system. Read in order: Section 1 (what the project is), Section 2
(set up the new system), Section 3 (what is done), Section 4 (what is
next), Section 5 (gotchas). At the very end, Section 9 has a ready-to-paste
prompt for the new Claude session.

---

## 1. Project context

PFEM ("Programming the Finite Element Method", 5th ed., Smith / Griffiths
/ Margetts) ships 87 Fortran benchmark cases spanning 8 physical case
types: elastic, plasticity, slope stability (SRF), seepage, consolidation,
Biot coupled, eigenvalue, transient dynamics, and thermal. This repo:

1. Catalogues all 87 cases as machine-readable YAML files.
2. Builds the Fortran source on Linux (gfortran), with a documented set of
   small patches that make the textbook source compile and run cleanly.
3. Provides a MATLAB GUI ("PFEM Sweep Studio") that runs any subset of
   cases under deterministic or stochastic parameter sweeps and extracts
   the physically meaningful Quantity of Interest (QoI) per case type.

The whole catalogue is verified end-to-end: every case builds, runs, and
returns a meaningful QoI from its default-parameter run.

---

## 2. Setting up a new system

### 2.1 Prerequisites

```bash
sudo apt install gfortran make python3 python3-pip libarpack2-dev liblapack-dev libblas-dev
pip install pyyaml
# MATLAB R2022b or newer (the GUI uses uifigure)
```

### 2.2 Restore the repo

Option A (git, recommended):
```bash
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks
```

Option B (USB backup):
```bash
cp -r "/media/<user>/USB Drive/fem-benchmarks-cleaned-20260522_140600" ~/projects/fem-benchmarks
cd ~/projects/fem-benchmarks
```

### 2.3 Restore the PFEM source

`pfem/` is gitignored (third-party, licensed). Either copy from the USB
backup (which contains the patched tree, 56 MB) or download a fresh copy
from http://www.pfem.org.uk/ and re-apply the patches in
`scripts/pfem_patches/`. The README in that folder explains what to patch
and why.

### 2.4 Build all chapters

```bash
# Build the library + one chapter (also builds all dependent libs):
scripts/pfem_build_chapter.sh ./pfem chap06

# Or build every chapter:
for ch in chap04 chap05 chap06 chap07 chap08 chap09 chap10 chap11; do
    scripts/pfem_build_chapter.sh ./pfem "$ch"
done
```

### 2.5 Smoke test

```bash
# Run all 87 cases at defaults (~3 min once binaries are built):
python3 scripts/run_all_tests.py

# Or from MATLAB:
matlab -nodesktop -nosplash
>> addpath matlab matlab/utils matlab/tests
>> pfem_sweep_gui    % launches the GUI
```

---

## 3. What is done

### 3.1 Foundation (pre-April 2026)

- All 87 cases catalogued as YAML (`benchmarks/pfem5/chap*/p*.yaml`)
- YAML generator parses the Fortran READ statements and the .dat files to
  detect tunable parameters automatically (`scripts/generate_yamls_v2.py`)
- Token-based .dat patcher (`matlab/utils/pfem_patch_dat_using_yaml.m`)
  applies parameter overrides without manual file editing
- Sweep GUI (`matlab/pfem_sweep_gui.m`) with Lockstep and Grid modes
- Per-case visualisation: deformed mesh, displacement vectors, load-vs-displacement curves
- All 87 cases verified to build and run on Linux gfortran
- Matched book Figures 6.54 and 6.55 for the p612 slope case

### 3.2 Phase 1 — Multi-case QoI + Stochastic mode (April 2026)

Commit `a9c45b0`: stochastic mode added to the GUI.
- New "Stochastic (distributions)" dropdown entry
- Distribution specs: `lognormal(mu, COV)`, `normal(mu, COV)`,
  `truncnormal(mu, COV, lo, hi)`, `uniform(lo, hi)`
- Auto-fill from YAML defaults with physics-based COV per parameter family
  (c=40%, phi=10%, E=30%, nu=10%, gamma=5%, k=50%; solver/mesh params
  excluded because varying them stochastically destabilises the solver)
- Per-sample log + progress, plots: histogram, CDF, scatter per parameter
- For slope cases, reliability metrics: `P(FS<1)` and `beta = -sqrt(2)*erfinv(2*Pf-1)`
- Base MATLAB only (no Statistics Toolbox)

Commit `0ad00a8`: per-case-type QoI dispatcher.
- 8 case types auto-detected from YAML metadata (chapter, program,
  physics, regime)
- Per-type extractor: slope_srf -> FS, plasticity_load -> P_lim,
  elastic_static -> u_max, seepage_steady -> h_max,
  consolidation -> Uav_end, eigenvalue -> omega^2,
  dynamic_transient -> u_peak, thermal -> T_max
- 87/87 cases verified to extract a meaningful QoI from their default run

### 3.3 Phase 2 — LHS, correlated parameters, sensitivity (May 2026)

Commit `c6f5e57`: Latin Hypercube Sampling.
- `matlab/utils/pfem_lhs_sample.m`: stratified joint draw across all
  parameters; same number of simulations as IID Monte Carlo, far better
  marginal coverage
- LHS toggle on the stochastic toolbar (default on)
- Verified 6 to 14x reduction in the variance of the mean estimator vs IID

Commit `7ee3e26`: correlated parameters (Iman-Conover).
- Same `pfem_lhs_sample` accepts a `'Correlation'` option
- Iman-Conover restricted-pairing preserves LHS marginals while inducing
  the target rank correlation
- "Corr..." button on the GUI opens a modal for entering pairs
  (`parameter 1`, `parameter 2`, `rho`)
- Verified: targets in `[-0.7, +0.5]` reproduced within 5%

Commit `c6c2c32`: sensitivity (one-at-a-time, tornado plots).
- `matlab/utils/pfem_sensitivity_oat.m`: runs PFEM at mu and mu +/- 1 sigma
  per parameter (`2k + 1` runs for k parameters)
- `matlab/utils/pfem_plot_tornado.m`: horizontal bar chart sorted by
  spread, baseline reference line
- New "Sensitivity (tornado)" mode in the dropdown
- Verified on p612: cohesion drives FS (spread 0.58), E and nu zero
  spread — exactly the textbook expectation for SRF slope stability

Commit `0f25147`: extractor fix for split time-history blocks.
- p95, p96_1, p96_2 .res files have a 5-column row at t=0 then 6-column
  rows for t>0; the dominant-block picker was selecting the 1-row t=0
  block. Now picks the LARGEST block tagged with a time-axis header.
- Tightened the time-axis header check to a column-position regex
  (MATLAB's `\b` after `^\s*` is unreliable; used explicit `(\s|$)`)

Commit `08634a6`: `docs/PROGRESS.md` and
`matlab/tests/test_phase2_multi_case.m`.

Commit `fe0803c`: relabel the eigenvalue QoI from `lambda_1` to `omega^2`
(unit `rad^2/s^2`) and add a derived `q.f1 = sqrt(omega^2)/(2*pi)` natural
frequency in Hz. The earlier note that the chap10 solver returned
`1/omega^2` was a misdiagnosis: `bandred` + `bisect` on the
mass-orthogonalised `M^(-1/2) K M^(-1/2)` returns `omega^2` directly
(verified analytically against the p101 cantilever first mode). The change
is relabel-only; `q.value` still equals `min(eigs)`.

### 3.4 Verification artifacts

| Where | What |
|---|---|
| `docs/PROGRESS.md` | Supervisor-facing progress report with validation evidence |
| `matlab/tests/test_phase2_multi_case.m` | Reproducible 3-min script: sensitivity on p61, p101, p81_5; LHS marginals for 4 distributions; Iman-Conover correlation check |
| `runs/chap06/p612/p612_stochastic_*_fs_hist.png` | FS distribution example |
| `runs/chap06/p612/p612_tornado_3param_*.pdf` | Tornado example showing c >> E, nu |
| `runs/chap06/p612/p612_sweep_*_res.pdf` | Deterministic baseline matching book Fig 6.54 |

### 3.5 Numerical sanity checks (cited in `docs/PROGRESS.md`)

| Case | Computed | Reference | Match |
|---|---|---|---|
| p612 baseline FS at c=60, phi=0 | 1.58 | Book Fig 6.54 | matches |
| p61 baseline P_lim at sigma_y=100 | 515 | Prandtl `(2+pi)*sigma_y = 514` | within 0.2% |
| p611_1 baseline P_lim | 121 kPa | deviatoric stress at failure (triaxial) | sensible |
| p101 omega^2 sensitivity wrt EI | linear in EI | omega^2 ~ EI/rhoA | exactly linear |
| p101 omega^2 sensitivity wrt rhoA | ratio 0.82 at +1 sigma | 1/1.22 = 0.82 | exact |

---

## 4. What is NOT done (future work)

### 4.1 Original roadmap items

| Phase | Item | Status |
|---|---|---|
| 3 | Pluggable runner interface for non-PFEM codes (any code reading an input file, writing an output) | DONE (branch `phase3-pluggable-runner`, M0-M6). See `docs/PHASE3_PLAN.md`. |
| 3 | Cross-verification against analytical solutions or commercial codes | DONE for Prandtl (analytic + external backends, 0.16 % vs PFEM p61); still informal for omega^2 |
| 4 | Mesh-refinement sweeps (nxe, nye) to study discretisation convergence | not started |
| 4 | Automated regression testing against reference outputs | Phase 3 M0 built `test_golden_qoi.m` for QoI drift (92 records); `run_all_tests.py` still checks status only |

### 4.2 Known limitations (from `docs/PROGRESS.md` Section 5)

1. ~~**p101 lambda label**~~ RESOLVED 2026-05-27 (commit `fe0803c`). The
   solver returns `omega^2` directly; relabelled and a derived `f1` (Hz)
   added in `qoi_eigenvalue()`. The earlier "returns `1/omega^2`" note was
   a misdiagnosis.
2. **BC-bound QoIs**: some elastic and thermal cases (e.g. p51_3 u_max,
   p811 T_max) return a boundary-condition value that does not vary with
   material sampling. The extractor works; the chosen QoI is just not
   sensitive. Could add a per-case YAML field like `qoi_probe_node` so
   the extractor tracks an internal point.
3. **p69 (embankment lift)**: only 7 of 10 LHS samples converge across
   the full c-phi-gamma range. The QoI extracts correctly when the
   solver converges. Could investigate the solver tolerances and report
   convergence rate per case.
4. **chap05 p56_1, p57**: very heavy meshes (250 s per run for p56_1).
   Excluded from the n=10 LHS timing run. Extractor works; just slow.

### 4.3 3D-figure work (now committed)

The earlier in-progress 3D-figure work was reviewed and committed
(`Add 2D element connectivity and EnSight material-ID parsing to sweep
figures`):

```
matlab/utils/parse_pfem_ensi.m          EnSight per-element material-ID parsing (matid)
matlab/utils/pfem_extract_coords.m      generate_2d_elem_conn() for Q4/Q8/Q9 meshes
matlab/utils/pfem_plot_sweep_summary.m  dark-theme layout, deformed-shape + EnSight 3D rendering
```

Not yet runtime-verified in MATLAB on this system (no MATLAB run was done
when committing); the code is structurally complete with no TODO markers.
Worth a smoke-run of `pfem_sweep_gui` on p612 to confirm the figures render.

### 4.4 Sync state

Local master is in sync with origin at `9d78780` (post the earlier laptop
work). Phase 3 development happens on branch `phase3-pluggable-runner`
which has 7 additional commits on top of master:

| # | SHA (local) | Milestone |
|---|---|---|
| 0 | `0e3d1c9` | Add PHASE3_PLAN.md |
| 1 | `9d35e4f` | M0 golden harness + `golden_qoi.json` (92 records) |
| 2 | `84b00f8` | M1 extract `pfem_backend` |
| 3 | `a9d085b` | M2 `get_backend` factory + `runner.type` YAML key |
| 4 | `a94a5d5` | M3 analytic backend + Prandtl cross-check (0.16 %) |
| 5 | `bb72d11` | M4 generic external backend + Python fixture |
| 6 | `4b7bab8` | M5 `b.non_sampleable(y)` guard in the GUI |
| 7 | (M6) | Docs update (this section + ARCHITECTURE + PHASE3_PLAN) |

Push when ready. Merging into master is a straight fast-forward (branch
is ahead of master; no divergence).

---

## 5. Project-specific gotchas (read before editing)

### 5.1 Git commit conventions

- **Sole author / owner is naeem** (NZ5253 <naeem.zainuddin@tu-dortmund.de>)
- **NEVER** add `Co-Authored-By: Claude` or any AI attribution trailer
- Commit messages must NOT mention Claude, AI, agents, or generation tooling
- Use HEREDOC for commit message formatting

### 5.2 Style preferences

- Concise responses
- NO em dashes
- NO emojis
- Use markdown link syntax for file references in chat: `[name](path)` or `[name:line](path#Lline)`

### 5.3 Push cadence

Push to origin only after major milestones, not after every small edit.

### 5.4 PFEM source patches

`pfem/` is gitignored. The 5 patches required to make the textbook
source compile and pass all 87 cases on Linux gfortran are documented
in `scripts/pfem_patches/README.md`. Critical ones:

- p42, p44: missing `USE geom` causes SIGSEGV at `CALL formnf`
- p57: unallocated UMAT arrays (statev, stran, drot, dfgrd0/1)
- New library files: `elap_time.f03`, `umat_elastic.f03`, `lancz.f03`
- p104 needs `libarpack2-dev` installed

### 5.5 .res file quirks (when adding new QoI extractors)

- Many .res files have multiple numeric blocks (time history + depth
  profile, or per-node listing + summary). The block-based reader
  `read_widest_numeric_table()` in `matlab/utils/pfem_extract_qoi.m`
  picks the largest block tagged with a time-axis header.
- p95, p96 have a 5-column row at t=0 then 6-column rows after (the
  iteration count column appears once iterations start).
- p611, p63 have multi-word headers ("dev stress", "pore press") that
  must be merged before tokenisation.
- p118 has 4 columns (time / load / x-disp / y-disp) with no iters
  column.
- p69 (embankment lift) has free-text output like "Max displacement is X"
  per lift; handled by a regex fallback in `qoi_slope_srf`.

### 5.6 MATLAB quirks discovered the hard way

- `regexp(s, '^\s*time\b', 'once')` returns `0` even when `s` starts
  with "time". Use `(\s|$)` instead of `\b` after `^\s*`.
- Nested functions inside other functions require the outer function to
  end with `end`. Use local functions (separate top-level definitions in
  the same file) when possible.
- `uitable` in older MATLAB does not accept `FontColor`, `BackgroundColor`,
  `RowName` — already worked around.

### 5.7 Solver and mesh parameters are NEVER sampled in stochastic mode

Sampling `convergence_tolerance`, `iteration_limit`, `nels_or_nxe`,
`time_step_dtim` etc. causes Fortran integer-read crashes or solver
divergence. The `default_cov()` function in `matlab/pfem_sweep_gui.m`
returns NaN for these so Fill Ranges skips them. The same NaN check is
applied in `cb_run_stochastic` so a user-typed solver-param distribution
is also silently ignored. Do not weaken this guard.

### 5.8 Backup conventions

The 1.4 GB working tree before cleanup is on USB at
`fem-benchmarks-backup-20260522_125358` (full snapshot including the
1.2 GB of regenerable run subdirectories). The cleaned 196 MB version
is at `fem-benchmarks-cleaned-20260522_140600`. Restore either as needed
with `cp -r`.

---

## 6. Architecture map

```
fem-benchmarks/
├── README.md                            user-facing intro
├── docs/
│   ├── GUIDE.md                         full usage guide
│   ├── PROGRESS.md                      supervisor progress report
│   └── HANDOVER.md                      this file
├── benchmarks/
│   ├── pfem5/chap{04..11}/*.yaml        87 benchmark specifications (PFEM)
│   ├── analytic/prandtl_bearing.yaml    Phase 3 M3: closed-form oracle
│   └── external/prandtl_external.yaml   Phase 3 M4: generic external solver
├── matlab/
│   ├── pfem_sweep_gui.m                 main GUI entry point
│   ├── pfem_stochastic_sweep.m          CLI-style stochastic runner
│   ├── pfem_run_from_yaml.m             30-line dispatcher (delegates to backend)
│   ├── pfem_studio.m                    single-case interactive GUI
│   ├── pfem_runner.m, pfem_diagram.m, ...    earlier utilities
│   ├── backends/                        Phase 3 backends
│   │   ├── get_backend.m                factory (reads y.runner.type)
│   │   ├── pfem_backend.m               PFEM pipeline + non_sampleable list
│   │   ├── analytic_backend.m           closed-form models (prandtl_bearing)
│   │   └── external_backend.m           template + command + regex parse
│   ├── utils/
│   │   ├── pfem_yaml_load.m             YAML parser
│   │   ├── pfem_patch_dat_using_yaml.m  token-based parameter patcher
│   │   ├── pfem_ensure_built.m          auto-compile missing binaries
│   │   ├── pfem_make_scenarios.m        build scenario struct arrays
│   │   ├── pfem_sample_distribution.m   IID distribution sampler
│   │   ├── pfem_lhs_sample.m            LHS + Iman-Conover correlated LHS
│   │   ├── pfem_detect_case_type.m      YAML -> case type classifier
│   │   ├── pfem_extract_qoi.m           per-case-type QoI dispatcher
│   │   ├── pfem_sensitivity_oat.m       OAT sensitivity runner
│   │   ├── pfem_plot_tornado.m          tornado bar chart
│   │   ├── pfem_extract_coords.m        node coordinates from YAML
│   │   ├── parse_pfem_ensi.m            EnSight viz parser
│   │   └── pfem_plot_sweep_summary.m    deterministic sweep figures
│   └── tests/
│       ├── test_phase2_multi_case.m     Phase 2 verification (~3 min)
│       ├── capture_golden_qoi.m         Phase 3 M0 golden capture
│       ├── golden_qoi.json              92-record reference (~4.6 min to regen)
│       ├── test_golden_qoi.m            QoI regression gate (~5 min per pass)
│       ├── test_analytic_backend.m      Phase 3 M3 cross-check
│       └── test_external_backend.m      Phase 3 M4 end-to-end
├── scripts/
│   ├── generate_yamls_v2.py             YAML generator from Fortran source
│   ├── pfem_build_chapter.sh            build one chapter
│   ├── pfem_build_and_run.sh            build + run + save outputs
│   ├── run_all_tests.py                 smoke-test all 87 cases
│   ├── verify_yamls.py                  YAML validator
│   └── pfem_patches/                    patches required for the PFEM source
├── pfem/                                Fortran source (GITIGNORED)
│   ├── source/chap{04..11}/*.f03        textbook source
│   ├── library/                         PFEM library
│   └── build/bin/p*                     compiled binaries
├── runs/                                outputs (gitignored, 120 MB after cleanup)
│   └── chap*/<case>/default/            87 baseline runs preserved
├── presentation/                        Beamer slides for the supervisor talk
├── figures/                             chap06 example figures
└── .git/                                12 MB git history
```

---

## 7. How to verify the install works (end-to-end smoke test)

```bash
cd ~/projects/fem-benchmarks

# 1. All 87 cases build and run:
python3 scripts/run_all_tests.py
# Expected: "87/87 PASSED" or similar

# 2. The QoI extractor works on every case:
matlab -batch "addpath matlab matlab/utils; \
  for f = dir('benchmarks/pfem5/chap*/*.yaml')'; \
    yp = fullfile(f.folder, f.name); \
    y  = pfem_yaml_load(yp); \
    ct = pfem_detect_case_type(y); \
    [~, c] = fileparts(yp); \
    fprintf('%-22s %s\n', c, ct); \
  end"
# Expected: 87 lines, one per case, no errors

# 3. Phase 2 multi-case verification:
matlab -batch "addpath matlab matlab/utils matlab/tests; test_phase2_multi_case"
# Expected: ~3 min, prints sensitivity rankings + LHS marginals + correlation

# 4. GUI launches:
matlab -nodesktop -nosplash -r "addpath matlab matlab/utils; pfem_sweep_gui"
# Expected: window opens; click "Add YAML(s)" to load a case

# 5. Phase 3 QoI regression (branch phase3-pluggable-runner or after merge):
matlab -batch "addpath matlab matlab/utils matlab/tests matlab/backends; test_golden_qoi"
# Expected: ~5 min, 92/92 passed
```

---

## 8. Immediate next task (suggested)

Phase 3 is complete on branch `phase3-pluggable-runner` (M0-M6). The
natural next-task options are all Phase 4 material:

**A. Start Phase 4 — mesh-refinement sweeps** (`nxe`, `nye`) to study
discretisation convergence. This changes mesh topology mid-sweep, which
is why the current stochastic guard excludes those parameters; a
convergence study needs a different mode that respects the topology
change explicitly.

**B. Extend the regression net beyond QoI drift**. `test_golden_qoi.m`
covers the 92 QoI values but not intermediate `.res` block sizes,
per-node displacements, or the sweep-summary figure files. A
`test_run_artifacts.m` would catch subtler regressions.

**C. Refine BC-bound QoI cases** (p51_3, p811) with a `qoi_probe_node`
YAML field so the extractor tracks an internal displacement / temperature
that actually varies with material sampling. See Section 4.2 item 2.

---

## 9. Ready-to-paste prompt for the new Claude session

Copy this entire block into the first message of a fresh Claude Code
session on the new system. It gives the new agent enough context to
start working immediately without re-asking everything.

```text
I'm continuing work on the fem-benchmarks project on a new system. Please
read docs/HANDOVER.md first — it has the full project history, what's
done, what's pending, the architecture, gotchas, and setup steps. Then
read docs/PROGRESS.md for the supervisor-facing status and
docs/GUIDE.md for usage details.

Project context:
- This is a PFEM (Programming the Finite Element Method, 5th ed.)
  benchmark catalogue with 87 Fortran cases and a MATLAB GUI for
  deterministic and stochastic parameter sweeps.
- Phase 1 (multi-case QoI extraction + stochastic Monte Carlo) is
  complete and verified.
- Phase 2 (Latin Hypercube Sampling, Iman-Conover correlated parameters,
  one-at-a-time sensitivity with tornado plots) is complete and verified.
- Phase 3 (pluggable runner interface: pfem / analytic / external
  backends chosen via a `runner.type` YAML key) is COMPLETE on branch
  `phase3-pluggable-runner`. `test_golden_qoi.m` is the QoI regression
  gate (92 records). See docs/PHASE3_PLAN.md for milestones and commits.

My preferences (these override any defaults):
- I'm the sole author. NEVER add Co-Authored-By: Claude or any AI
  attribution trailer to commits. Commit messages must not mention
  Claude, AI, agents, or generation tooling.
- Concise responses. No em dashes. No emojis.
- Push to origin only after major milestones, not every edit.

Before doing anything destructive:
- A clean backup is on USB at fem-benchmarks-cleaned-20260522_140600
  (192 MB). The 1.4 GB pre-cleanup snapshot is at
  fem-benchmarks-backup-20260522_125358 on the same drive.
- master should be in sync with origin. Phase 3 work sits on branch
  phase3-pluggable-runner (7 commits ahead of master); check with
  `git fetch --all && git log --oneline --graph master..phase3-pluggable-runner`.
- The QoI regression test writes new run directories under runs/ each
  time it fires; runs/ is gitignored, so it is safe to re-run.

First task: please confirm the new system is set up correctly. Run the
4-step smoke test in HANDOVER.md Section 7 and, additionally,
`matlab -batch "addpath matlab matlab/utils matlab/tests matlab/backends; test_golden_qoi"`
(expect 92/92 green in about 5 min).

After that, ask me which of the three next-task options in HANDOVER.md
Section 8 to start on.
```

End of handover.
