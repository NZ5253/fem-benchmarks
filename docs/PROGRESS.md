<p align="center">
  <img src="figures/tudortmund_logo.svg" alt="Technische Universität Dortmund" height="60">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="figures/cre_logo.png" alt="Chair for Reliability Engineering (CRE)" height="60">
</p>

<h1 align="center">fem-benchmarks — Progress Report</h1>

<p align="center">
  <b>Probabilistic Analysis Framework for the PFEM 5<sup>th</sup>-Edition Benchmarks</b><br>
  <sub>Author: <b>Naeem Zainuddin</b> · Technische Universität Dortmund<br>
  Release: <a href="https://github.com/NZ5253/fem-benchmarks/releases/tag/v1.0-phase3-complete"><code>v1.0-phase3-complete</code></a><br>
  Period covered: December 2025 – July 2026</sub>
</p>

---

## TL;DR

Before this work, running one PFEM benchmark meant editing a `.dat` file
by hand and executing a Fortran binary. Now the same 87 benchmarks answer
**probabilistic** questions through a graphical Sweep Studio supporting
Monte Carlo, Latin Hypercube, correlated sampling and one-at-a-time
sensitivity, backed by a **pluggable runner** that also drives closed-form
analytic solutions and any external solver (Python, bash, or otherwise).
Every future change is regression-gated at four independent levels.

Latest verification snapshot:

| Layer | Result |
|---|---|
| `run_all_tests.py` — all 87 PFEM Fortran binaries at defaults | **87 / 87** |
| `test_golden_qoi` — QoI drift regression (92 records) | **92 / 92** |
| `test_all_analytic_oracles` — closed-form correctness (9 rows) | **9 / 9** |
| `test_stochastic_gate` — analytic + external at fixed seed | **2 / 2 backends locked** |
| `test_physics_sanity` — QoI monotonicity direction (20 rows) | **20 / 20** |
| `test_all_cases_stochastic` — broad 18-case Monte Carlo | **180 / 180** |
| `plot_analytic_vs_pfem` — correlation figure | **r = 0.968** (off-plateau, 27 samples) |
| Analytic vs PFEM p61 (Prandtl 514.16 vs 515) | **0.16 %** |

---

## 1. Starting state (December 2025)

| Capability | Status | Anchor |
|---|---|---|
| 87 PFEM benchmarks compiling on Linux gfortran | working | end of foundation phase |
| YAML catalogue with token-based `.dat` patching | working | ~30 commits |
| Multi-case sweep GUI (Lockstep / Grid) | working | first GUI iteration |
| Book Fig 6.54 / 6.55 match for the p612 slope | working | mesh + deformed-shape figures |
| Per-case-type QoI extraction | **absent** | – |
| Stochastic / probabilistic analysis | **absent** | – |
| Sensitivity analysis | **absent** | – |
| Pluggable runner | **absent** | – |

In short: any of the 87 benchmarks could be run deterministically, but
probabilistic analysis was not supported and the output extractor only
made sense for the ~8 slope cases (the other ~80 would silently return a
load-step index labelled as "FS").

---

## 2. Phase 1 — Foundation for stochastic analysis (April 2026)

### 2.1 Multi-case QoI dispatcher

Each of the 87 benchmarks is auto-classified into one of 8 case types
from its YAML metadata. The correct physical output is then extracted
from the `.res` file:

| Case type | Cases | QoI |
|---|---|---|
| `slope_srf` | 8 (chap 6: p64–p69, p612, p613) | Factor of Safety |
| `plasticity_load` | 11 (chap 6: p61–p63, p610, p611; chap 4: p45; chap 9: p96; chap 11: p118) | Limit load |
| `elastic_static` | 25 (chap 4, chap 5) | Max nodal displacement |
| `seepage_steady` | 6 (chap 7) | Max total head |
| `consolidation` | 16 (chap 8: p81–p88; chap 9: p91–p95) | Degree of consolidation |
| `eigenvalue` | 5 (chap 10) | ω² (with derived f₁ in Hz since 2026-05) |
| `dynamic_transient` | 15 (chap 4: p47; chap 7: p73; chap 8: dynamic; chap 11) | Peak displacement |
| `thermal` | 1 (chap 8: p811) | Max temperature |

Every one of 87 cases extracts a meaningful QoI from its default run.

### 2.2 Stochastic Monte Carlo in the GUI

Added a third dropdown entry: "Stochastic (distributions)". The Values
column now accepts named distributions:

```
lognormal(60, 0.40)              # mean and COV
normal(0.30, 0.10)               # mean and COV
truncnormal(0.30, 0.10, 0, 0.499) # mean, COV, low bound, high bound
uniform(40, 80)                  # low and high
```

**Fill Ranges** auto-fills with physics-based COVs (c 0.40, φ 0.10,
E 0.30, ν 0.10, γ 0.05, k 0.50). Solver / mesh parameters are excluded
because sampling them destabilises the Fortran solver.

Sample count widget (default 50, range 10–500), per-sample live log,
per-parameter scatter, histogram, CDF. For slope cases: `P(FS < 1)` and
reliability index `β = −√2 · erfinv(2·Pf − 1)`.

Base MATLAB only (no Statistics Toolbox).

---

## 3. Phase 2 — Variance reduction, correlation, sensitivity (May 2026)

### 3.1 Latin Hypercube Sampling

Stratified joint draw across all parameters; same number of simulations
as IID Monte Carlo but full marginal coverage of every parameter.

GUI: "LHS" checkbox on the stochastic toolbar (default on).

Measured variance reduction for a lognormal(60, 0.40) mean estimator:

| n | LHS std of estimator | IID std of estimator | Reduction |
|---|---|---|---|
| 25 | 0.754 | 4.915 | **6.5 ×** |
| 50 | 0.535 | 3.420 | 6.4 × |
| 100 | 0.198 | 2.332 | 11.8 × |
| 200 | 0.113 | 1.579 | **14.0 ×** |

Reference: McKay, Beckman, Conover (1979), *Technometrics* 21(2):239-245.

### 3.2 Iman–Conover correlated LHS

Many soil parameters are correlated in practice (c and φ typically
negatively correlated, ρ ≈ −0.5). Iman–Conover (1982) restricted-pairing
induces a target correlation while keeping each LHS marginal exactly.

GUI: **Corr…** button opens a modal for entering pairs
`(param_i, param_j, ρ)`.

Verification across n = 500:

| Target ρ | Observed ρ | Marginals (c: μ=60, σ=24) | Marginals (φ: μ=25, σ=2.5) |
|---|---|---|---|
| −0.70 | −0.654 | 60.16, 25.04 | 25.00, 2.51 |
| −0.30 | −0.275 | 60.16, 25.04 | 25.00, 2.51 |
| +0.00 | −0.002 | 60.16, 25.04 | 25.00, 2.51 |
| +0.50 | +0.494 | 60.16, 25.04 | 25.00, 2.51 |

Three-parameter target
`[1, −0.5, +0.3; −0.5, 1, −0.2; +0.3, −0.2, 1]` reproduced within 5 %
across n = 500.

### 3.3 Sensitivity (one-at-a-time, tornado plot)

Fourth dropdown entry: "Sensitivity (tornado)". For each enabled
parameter runs PFEM at `μ ± 1σ` (lognormal: geometric ±σ so the lower
value stays strictly positive at high COV). Cost: `2k + 1` PFEM runs
per case for `k` parameters.

Verification on p612 (slope) with c, E, ν:

| Rank | Parameter | QoI at −1σ | QoI at +1σ | Spread |
|---|---|---|---|---|
| 1 | cohesion_c | FS = 1.00 | FS = 1.58 | **0.58** |
| 2 | youngs_modulus_E | FS = 1.58 | FS = 1.58 | 0.00 |
| 3 | poisson_ratio_nu | FS = 1.58 | FS = 1.58 | 0.00 |

Exactly the textbook expectation for the strength-reduction method: only
strength (c, φ) affects FS; stiffness (E, ν) only affects pre-failure
displacement.

---

## 4. Phase 3 — Pluggable runner (July 2026)

Extracted the runner contract into a struct-of-function-handles interface
so non-PFEM codes can plug into every mode of the framework. Every legacy
YAML runs unchanged because the default backend is `pfem` when the
optional `runner.type` key is absent.

### 4.1 M0-M6 milestones

| # | Milestone | Commit | Gate result |
|---|---|---|---|
| M0 | Golden net (92 records) | `9d35e4f` | 92 / 92 baseline |
| M1 | Extract `pfem_backend` | `84b00f8` | 92 / 92 golden |
| M2 | `get_backend` factory + `runner.type` YAML key | `a9d085b` | 92 / 92 golden |
| M3 | Analytic backend + Prandtl cross-check vs PFEM p61 | `a94a5d5` | 0.16 %, 92 / 92 golden |
| M4 | Generic external backend + Python fixture | `bb72d11` | 4 exact assertions, 0.16 % cross-check, 92 / 92 golden |
| M5 | Surface backends in GUI via `b.non_sampleable(y)` | `4b7bab8` | 92 / 92 golden, 0 GUI regressions |
| M6 | Doc refresh | `2f41407` | – |

### 4.2 M7 coverage extension

| # | Milestone | Commit | Gate result |
|---|---|---|---|
| M7a | 8 more analytic oracles cover every case type | `a393ffd` | 9 / 9 oracles |
| M7b | `test_stochastic_gate` + `test_physics_sanity` | `4333e57` | 2 / 2 + 20 / 20 |
| M7c | Docs reflect the coverage-complete state | `33f98a8` | – |
| Polish | LaTeX-safe titles, sensitivity Status column, analytic input guards, correlation figure | `3b87787` | 0 GUI warnings, r > 0.9 asserted |
| Broad | `test_all_cases_stochastic` — 18 cases × 10 samples | `8302e24` | 180 / 180 |
| GUI | Preset loader | `da9ded8` | 4 / 4 presets load correct counts |
| Ship | LICENSE, bash external, HTML report, tutorials | `b78f5f7` | tag `v1.0-phase3-complete` |

### 4.3 Analytic oracle catalogue

Every case type has an independent closed-form reference in
`benchmarks/analytic/`:

| Model | Formula | Case type |
|---|---|---|
| `prandtl_bearing` | `(2 + π) · σ_y` | plasticity (Tresca) |
| `prandtl_terzaghi` | `c · Nc + 0.5 · γ · B · Nγ` (Vesic) | plasticity (MC) |
| `bar_elongation` | `P · L / (A · E)` | elastic_static |
| `ss_beam_eigen` | `(π/L)⁴ · EI / (ρA)` | eigenvalue |
| `sdof_step` | `2 · F / k` (undamped DLF = 2) | dynamic_transient |
| `terzaghi_1d` | `U_av(T_v) = 1 − Σ (2/M²) exp(−M²·T_v)` | consolidation |
| `slab_heat_gen` | `T_s + qgen · L² / (8k)` | thermal |
| `strip_seepage` | `h₀ + N · L² / (8k)` | seepage_steady |
| `infinite_slope` | `c / (γH sinβ cosβ) + tan(φ)/tan(β)` | slope_srf |

### 4.4 External solvers

Two ship as fixtures:

- **Python**: `benchmarks/external/prandtl.py` — 10-line solver, verified
  end-to-end.
- **bash / awk**: `benchmarks/external/prandtl.sh` — 10-line POSIX
  script (with `LC_ALL=C` guard), verified identical to Python control to
  1e-6.

Two languages side-by-side proves the external backend is
language-agnostic and needs no runtime dependencies beyond a POSIX shell.

---

## 5. Validation evidence

### 5.1 Output values match textbook and analytical references

| Case | Baseline QoI | Reference | Agreement |
|---|---|---|---|
| p612 slope, c = 60, φ = 0 | FS = 1.58 | PFEM Fig 6.54 | ✓ |
| p61 strip footing, σ_y = 100 | P_lim = 515 | Prandtl `(2+π)·σ_y = 514.16` | **0.16 %** |
| p611 triaxial, default | P_lim = 121 kPa (dev stress at failure) | Triaxial undrained shear | sensible |
| p81–p85 consolidation, final time | Uav ≈ 1.0 | full consolidation reached | ✓ |
| p101 simply-supported beam | ω² scales linearly with EI | `ω² ∼ EI / ρA` | ✓ exact |

### 5.2 87-case full extraction sweep

Every YAML run at defaults; QoI extracted:

```
slope_srf          8 / 8    extracted successfully
plasticity_load   11 / 11
elastic_static    25 / 25
seepage_steady     6 / 6
consolidation     16 / 16
eigenvalue         5 / 5
dynamic_transient 15 / 15
thermal            1 / 1
                  -------
Total            87 / 87
```

### 5.3 Broad per-case Monte Carlo (M7)

`test_all_cases_stochastic` runs 10 LHS samples per case across 18
representative cases (all 8 PFEM case types + 9 analytic + 1 external):

```
PFEM (8 cases)      80 /  80 samples
Analytic (9 cases)  90 /  90 samples
External (1 case)   10 /  10 samples
                    ---
Total              180 / 180 samples in 42 s
```

### 5.4 Analytic vs PFEM correlation

50 LHS samples of `yield_stress ~ lognormal(100, 0.4)` evaluated by both
`analytic_backend.prandtl_bearing` and PFEM p61:

<p align="center">
  <img src="../figures/analytic_vs_pfem_p61.png" alt="Analytic Prandtl vs PFEM p61" width="580">
</p>

- Pearson r on 27 off-plateau samples: **0.968**
- Pearson r on all 50 samples: 0.806 (dragged down by the PFEM
  load-step ceiling at ~515 kPa, a p61 discretisation limit not a
  framework issue)
- Hard `r > 0.9` assertion in `plot_analytic_vs_pfem.m`

### 5.5 Four-level regression net

Since Phase 3 M7:

| Level | Test | Catches | Runtime |
|---|---|---|---|
| Per-run value | `test_golden_qoi` | Any of 92 QoI values drift | ~5 min |
| Formula correctness | `test_all_analytic_oracles` | Closed-form transcription errors | <1 s |
| Distribution dispatch | `test_stochastic_gate` | Sampling / factory / dispatch drift | ~2 s |
| Physical scaling | `test_physics_sanity` | Sign flips in QoI wrt parameters | <1 s |

Every future refactor either passes all four or fails loudly with a
specific diagnostic.

---

## 6. How to see the results

### 6.1 Cold-start GUI

```bash
cd /path/to/fem-benchmarks
matlab -nodesktop -nosplash \
    -r "addpath matlab matlab/utils matlab/backends; pfem_sweep_gui"
```

Workflow:

1. **Load preset ... → Prandtl demo (PFEM + analytic + external)**
2. Mode → **Stochastic**, count → 30
3. **Fill Ranges**, uncheck all except `yield_stress`
4. **Run All** — three per-case blocks scroll through the log
5. **Open Figures** on any OK row

### 6.2 Batch regeneration

```bash
# Fast gates (< 1 min total)
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    test_all_analytic_oracles; test_stochastic_gate; test_physics_sanity; \
    test_analytic_backend; test_external_backend; test_all_cases_stochastic"

# Correlation figure
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    plot_analytic_vs_pfem"

# Golden regression gate (~5 min)
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    test_golden_qoi"
```

### 6.3 Auto-generated HTML report

```matlab
addpath matlab matlab/utils;
generate_report('runs/chap06/p61');
% → runs/chap06/p61/report.html (self-contained, embed-all-images)
```

---

## 7. Known limitations

Documented in [HANDOVER §18](HANDOVER.md#18-known-limitations); none are
shipping-blockers.

1. **BC-bound QoIs** on p51_3, p111, p811 — Dirichlet boundary
   dominates the max/peak, so material sampling doesn't move the QoI. The
   extractor is correct; the chosen QoI is just insensitive. Fixable with
   a `qoi_probe_node` YAML feature (~2 h).
2. **p69 embankment lift** — 7 of 10 samples converge. Fixable with
   tighter solver tolerances.
3. **Heavy meshes (p56_1, p57)** — 250 s per run; excluded from the
   10-sample broad verification. Fixable with `parfor`.
4. **Load-step ceiling on p61** — for yield_stress > ~100, PFEM saturates
   at ~515 kPa. Fixable by raising `load_increments` in the YAML.

---

## 8. What is next

Priority ordering per [HANDOVER §19](HANDOVER.md#19-future-work). Nothing
here is required for the current release; each is independently useful
when the specific need arises:

- **R1** `qoi_probe_node` YAML feature
- **P1** `parfor` sample parallelisation (4–16× speedup)
- **F1** Mesh-refinement / convergence-rate mode (Phase 4 headline)
- **F3** FORM / SORM reliability method
- **C1** Compiled C external example
- **I3** Zenodo DOI for citation

---

## 9. Commit summary

120+ commits by NZ5253 (Dec 2025 – Jul 2026), all under the MIT-licensed
framework code plus the pfem/ textbook exclusion.

Full history: `git log --oneline` in the repo, or the browsable page
https://github.com/NZ5253/fem-benchmarks/commits/master. Milestone
commits are enumerated in [HANDOVER §17](HANDOVER.md#17-commit-history-highlights).

---

<p align="center"><sub>
  <a href="https://github.com/NZ5253/fem-benchmarks">github.com/NZ5253/fem-benchmarks</a> ·
  <a href="https://github.com/NZ5253/fem-benchmarks/releases/tag/v1.0-phase3-complete"><code>v1.0-phase3-complete</code></a> ·
  Naeem Zainuddin, Technische Universität Dortmund
</sub></p>
