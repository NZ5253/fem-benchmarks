<p align="center">
  <img src="figures/tudortmund_logo.svg" alt="Technische Universität Dortmund" height="60">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="figures/cre_logo.png" alt="Chair for Reliability Engineering (CRE)" height="60">
</p>

<h1 align="center">fem-benchmarks — Usage Guide</h1>

<p align="center">
  <sub>Practical guide to running the framework · GUI + MATLAB API + Python + report generation<br>
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> · <a href="ARCHITECTURE.md">ARCHITECTURE.md</a></sub>
</p>

---

## Table of contents

- [1. Quick start (5 min)](#1-quick-start-5-min)
- [2. Prerequisites and install](#2-prerequisites-and-install)
- [3. Regenerating YAMLs](#3-regenerating-yamls)
- [4. Running from the command line](#4-running-from-the-command-line)
- [5. GUI walkthrough](#5-gui-walkthrough)
- [6. MATLAB API](#6-matlab-api)
- [7. HTML report generator](#7-html-report-generator)
- [8. Test harness](#8-test-harness)
- [9. Adding new content](#9-adding-new-content)
- [10. Troubleshooting](#10-troubleshooting)

---

## 1. Quick start (5 min)

```bash
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks
pip install pyyaml
# put PFEM source at pfem/ (see HANDOVER §12.3)
scripts/pfem_build_chapter.sh ./pfem chap06
python3 scripts/run_all_tests.py                      # → 87/87
matlab -nodesktop -nosplash \
    -r "addpath matlab matlab/utils matlab/backends; pfem_sweep_gui"
```

In the GUI:

1. **Load preset ...** → **Prandtl demo (PFEM + analytic + external)**
2. Mode → **Stochastic (distributions)**, sample count 30
3. **Fill Ranges**, uncheck everything except `yield_stress`
4. **Run All**

Three overlapping P_lim distributions appear; PFEM matches the two closed-
form backends to 0.16 %.

---

## 2. Prerequisites and install

### System packages (Debian / Ubuntu)

```bash
sudo apt install gfortran make python3 python3-pip \
                 libarpack2t64 libarpack2-dev liblapack-dev libblas-dev
pip install pyyaml
```

MATLAB R2022b or newer (verified on R2025b).

### PFEM source

The Fortran source is gitignored (licensed textbook code). Two restore
options:

- **From USB backup** (fastest, patches applied):
  `cp -r "/media/<user>/USB Drive/fem-benchmarks-cleaned-*/pfem" ./`
- **Fresh download** from http://www.pfem.org.uk/ then apply patches:
  ```bash
  for p in scripts/pfem_patches/*.patch; do
      (cd pfem && patch -p1 < "../$p")
  done
  cp scripts/pfem_patches/*.f03 pfem/source/library/misc/
  ```

Details: [HANDOVER §12](HANDOVER.md#12-setup-on-a-fresh-system).

---

## 3. Regenerating YAMLs

Rarely needed — the 87 YAMLs are checked in. But if the Fortran source or
`.dat` files change:

```bash
# Single chapter
python3 scripts/generate_yamls_v2.py --chapter chap06

# Single case
python3 scripts/generate_yamls_v2.py --chapter chap06 --case p61

# All 87 cases at once
python3 scripts/generate_yamls_v2.py --all-chapters

# Preview only (no write)
python3 scripts/generate_yamls_v2.py --chapter chap06 --dry-run

# Validate
python3 scripts/verify_yamls.py benchmarks/pfem5/chap*/*.yaml
```

---

## 4. Running from the command line

### Every PFEM binary

```bash
python3 scripts/run_all_tests.py
# → 87/87 passed
```

### One case, from a shell

```bash
scripts/pfem_build_and_run.sh ./pfem chap06 p61 p61 --rebuild
# builds if needed, runs p61 with dataset p61, saves outputs
```

### From MATLAB, single case

```matlab
addpath matlab matlab/utils matlab/backends;
[status, out] = pfem_run_from_yaml(pwd, fullfile(pwd, 'pfem'), ...
    'benchmarks/pfem5/chap06/p61.yaml', ...
    struct('yield_stress', 150));
% status = 0 on success
% out.run_dir has all files
```

---

## 5. GUI walkthrough

Launch:

```matlab
addpath matlab matlab/utils matlab/backends;
pfem_sweep_gui
```

<p align="center">
  <img src="../presentation/abc/gui.png" alt="PFEM Sweep Studio" width="820">
</p>

### The five panels

| Panel | Contents |
|---|---|
| **Cases** (left) | Multi-select list of loaded YAMLs. Add / Remove / **Load preset ...** dropdown |
| **Tunable Parameters** (centre-top) | Union of every loaded case's tunables — enable / values / range / chapters |
| **Toolbar** (below params) | Mode dropdown · Fill Ranges · sample count ± · LHS toggle · Corr… · Preview Scenarios |
| **Log** (centre-bottom) | Per-case run progress with backend and case-type headers |
| **Results** (bottom) | One row per (case × scenario) — Case · Scenario · Status · QoI · Time · Run Dir |
| **Run controls** (bottom-left) | Run All · Stop |
| **Actions** (bottom-right) | Open Figures · Show Comparison · Clear Results |

### Load preset dropdown

Four one-click YAML combinations (added Jul 2026):

| Preset | Loads | Best for |
|---|---|---|
| Prandtl demo (PFEM + analytic + external) | 3 YAMLs | The canonical three-way cross-check |
| All analytic oracles (9) | 9 YAMLs | Full closed-form catalogue |
| One PFEM per case type (8) | 8 YAMLs | Coverage sanity |
| Analytic + External Prandtl (fast, no PFEM) | 2 YAMLs | Sub-second-per-sample smoke test |

The dropdown resets after each load so you can stack presets (e.g.,
"One PFEM per case type" + "All analytic oracles" = 17 cases in two clicks).

### Sweep modes

| Mode | Semantics | Typical use |
|---|---|---|
| **Lockstep** | Same-length arrays, parameters vary in parallel | Compare two or three explicit scenarios |
| **Grid** | Cartesian product of arrays (capped at 500) | Full factorial parameter study |
| **Stochastic** | Monte Carlo (LHS optional) from named distributions | Reliability, uncertainty quantification |
| **Sensitivity** | OAT: 2k+1 runs per case | Identify the dominant parameter |

### Fill Ranges

Auto-populates every checked parameter's Values cell. Behaviour depends on
the mode:

- **Deterministic modes**: N log-spaced values from the parameter's
  suggested range. Adjust N with the ± counter.
- **Stochastic mode**: `lognormal(μ, COV)` with physics-based defaults
  (see below). Sample count from the counter (default 50, range 10–500).

Physics-based COVs used by Fill Ranges in stochastic mode:

| Parameter family | Default COV |
|---|---|
| Strength (c, σ_y) | 0.40 |
| Angles (φ, ψ) | 0.10 |
| Stiffness (E, EI) | 0.30 |
| Poisson ratio ν | 0.10 |
| Unit weight γ | 0.05 |
| Permeability k | 0.50 |

Solver / mesh parameters (25 names — see
`pfem_backend.non_sampleable`) are **skipped** by Fill Ranges because
sampling them destabilises the Fortran solver.

### Corr… button

Opens a modal for entering pairwise rank correlations
`(param_i, param_j, ρ)`. Applied via Iman-Conover restricted pairing at
runtime. Verified for targets in `[-0.7, +0.5]` reproduced within 5 % on
n = 500.

### Recommended demo flow

1. **Load preset ... → Prandtl demo (PFEM + analytic + external)**
2. Mode → **Stochastic**, count → 30
3. **Fill Ranges** → auto-fills yield_stress lognormal + PFEM's other
   tunables
4. **Uncheck** everything except `yield_stress` (so the three cases
   receive matching draws)
5. **Preview Scenarios** (optional) → the log lists the joint samples
6. **Run All** → per-case blocks scroll:
   ```
   === Stochastic sweep: p61, 30 samples (LHS) ===
     backend: pfem     case type: plasticity_load
     [1/30] yield_stress=86.56    OK  P_lim=445 kPa  t=0.05s
     ...
   === Stochastic sweep: prandtl_bearing, 30 samples (LHS) ===
     backend: analytic case type: unknown
     [1/30] yield_stress=86.56    OK  P_lim=445      t=0.0s
     ...
   ```
7. **Open Figures** on any OK row → 3 windows per case (histogram, CDF,
   scatter). PFEM tracks the two analytic curves closely until PFEM's
   load-step ceiling saturates.
8. **generate_report** in a MATLAB prompt for a shareable HTML.

### Sensitivity mode

Same setup but with Mode → **Sensitivity (tornado)**. Each case gets
`2k + 1` runs (mean, and `μ ± σ` per parameter). Result row:

```
p61   tornado k=3   OK   P_lim base=515 top=yield_stress (spread=215)
```

The full tornado bar chart pops up per case.

---

## 6. MATLAB API

Every mode is scriptable if you prefer batch to the GUI.

### Load and run a single case

```matlab
addpath matlab matlab/utils matlab/backends;

repo_root = pwd;
pfem_root = fullfile(repo_root, 'pfem');
yaml_path = 'benchmarks/pfem5/chap06/p61.yaml';

[status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, ...
    struct('yield_stress', 150));

y  = pfem_yaml_load(yaml_path);
b  = get_backend(y);
ct = pfem_detect_case_type(y);
q  = b.extract_qoi(out, ct);
fprintf('%s = %.4f %s\n', q.label, q.value, q.unit);
```

### Latin Hypercube sample

```matlab
spec = struct('name', 'yield_stress', 'dist', 'lognormal', ...
              'mu', 100, 'cov', 0.4, 'bounds', []);
samples = pfem_lhs_sample(spec, 50, 'Seed', 42);
% samples: 50 x 1 column with stratified marginals
```

### Correlated multi-parameter LHS

```matlab
specs = struct('name', {'c', 'phi', 'E'}, ...
               'dist', {'lognormal', 'truncnormal', 'lognormal'}, ...
               'mu',   {60, 25, 1e5}, ...
               'cov',  {0.40, 0.10, 0.30}, ...
               'bounds', {[], [0, 45], []});
R = [1.0 -0.5  0.3;
    -0.5  1.0  0.0;
     0.3  0.0  1.0];
samples = pfem_lhs_sample(specs, 500, 'Seed', 42, 'Correlation', R);
```

### Sensitivity OAT

```matlab
specs = struct('name', {'yield_stress', 'youngs_modulus_E', 'poisson_ratio_nu'}, ...
               'dist', {'lognormal', 'lognormal', 'truncnormal'}, ...
               'mu',   {100, 1e5, 0.30}, ...
               'cov',  {0.40, 0.30, 0.10}, ...
               'bounds', {[], [], [0, 0.49]});
r = pfem_sensitivity_oat(pwd, fullfile(pwd,'pfem'), ...
    'benchmarks/pfem5/chap06/p61.yaml', specs);
pfem_plot_tornado(r);
```

### Full stochastic sweep

```matlab
for i = 1:size(samples, 1)
    ov.yield_stress = samples(i);
    [~, out] = pfem_run_from_yaml(pwd, fullfile(pwd,'pfem'), yaml_path, ov);
    q = b.extract_qoi(out, ct);
    P_lim(i) = q.value;
end
histogram(P_lim);
```

---

## 7. HTML report generator

After any sweep, produce a single-file shareable report:

```matlab
addpath matlab matlab/utils;

% Every sweep in the case directory
p = generate_report('runs/chap06/p61');
% → runs/chap06/p61/report.html (~3.6 MB for 11 sweeps)

% Latest sweep only, smaller
p = generate_report('runs/chap06/p61', 'LatestOnly', true);
% → ~900 KB

% Custom output path
p = generate_report('runs/chap06/p61', 'Out', '/tmp/p61_demo.html');
```

Fully self-contained — every PNG is embedded as base64. No external asset
dependencies. Can be emailed, archived, or served directly.

Structure:

- `<h1>` case name + generation timestamp
- Scenarios table (one row per subdirectory with run_info.txt status)
- One `<h2>` section per sweep (grouped by mode + timestamp)
- Every PNG in that sweep embedded and captioned

---

## 8. Test harness

Fast tests (< 5 seconds combined):

```matlab
addpath matlab matlab/utils matlab/backends matlab/tests;
test_all_analytic_oracles   %  9 / 9
test_stochastic_gate        %  2 / 2 backends locked
test_physics_sanity         % 20 / 20
test_analytic_backend       % PFEM cross-check + sensitivity
test_external_backend       % Python solver end-to-end
```

Medium (~40 seconds):

```matlab
test_all_cases_stochastic   % 180 / 180 samples across 18 cases
plot_analytic_vs_pfem       % correlation figure, r > 0.9 assertion
```

Slow (~5 min — the golden regression gate):

```matlab
test_golden_qoi             % 92 / 92 recorded QoI values unchanged
```

Legacy (~3 min):

```matlab
test_phase2_multi_case      % Phase 2 sensitivity + LHS + correlation
```

Post-hoc verification on a live sweep directory:

```matlab
verify_stochastic_backends  % numeric certificate on runs/
```

---

## 9. Adding new content

- **New backend**: [adding_a_backend.md](adding_a_backend.md), ~30 min
- **New analytic oracle**: [adding_an_oracle.md](adding_an_oracle.md), ~15 min
- **New external solver**: copy the `prandtl_bash.yaml` /
  `prandtl_external.yaml` pattern, ~15 min
- **New case type**: see [ARCHITECTURE.md §10](ARCHITECTURE.md#10-extension-points),
  ~1 h
- **New sweep mode**: see [ARCHITECTURE.md §10](ARCHITECTURE.md#10-extension-points),
  ~2 h

Every extension should add at least one regression test to keep the
four-level net comprehensive.

---

## 10. Troubleshooting

See [HANDOVER §20](HANDOVER.md#20-troubleshooting) for the full list. Most
common:

| Symptom | Cause | Fix |
|---|---|---|
| GUI parameter table empty after loading YAMLs | MATLAB has old bytecode cached | Quit MATLAB entirely, relaunch, re-add |
| "Build failed for p<N>" | `pfem_ensure_built` can't find binary | `scripts/pfem_build_chapter.sh ./pfem chap<N>` |
| External backend prints commas | Non-English locale | `LC_ALL=C` (already set in `prandtl.sh`) |
| Golden test fails on one case | Numeric drift (real regression or expected) | `git bisect run` or regenerate via `capture_golden_qoi` |
| Batch job produces no output | `-batch` disables `uigetfile` | Inject state directly (see `full_gui_drive.m` pattern) |

---

<p align="center"><sub>
  <a href="https://github.com/NZ5253/fem-benchmarks">github.com/NZ5253/fem-benchmarks</a> ·
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> ·
  Naeem Zainuddin, Technische Universität Dortmund
</sub></p>
