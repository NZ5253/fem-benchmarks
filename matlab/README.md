# PFEM MATLAB Interface

MATLAB scripts for running PFEM benchmarks and performing parametric studies
with automatic parameter discovery, multi-case sweeps, and result comparison.

## Core Scripts

### pfem_runner.m
Basic single-case executor.

```matlab
pfem_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks', 'pfem');
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

### pfem_run_from_yaml.m
YAML-driven runner with parameter overrides.  Creates isolated, self-contained
run folders.  When the PFEM book's pre-computed `.res` is absent (e.g. p63),
the first override run automatically generates a baseline in `runs/.../default/`
so `pfem_compare_results` always has a reference to compare against.

```matlab
overrides.youngs_modulus_E = 500;
[status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
% Creates: runs/chap05/p51_4/E_500/
%   p51_4.dat  p51  p51_4.res  p51_4.msh  case.yaml  overrides.mat  run_info.txt
% If pfem/executable/chap05/p51_4.res is missing, also creates:
%   runs/chap05/p51_4/default/   ← unmodified baseline used for comparison
```

---

## Scenario & Sweep Utilities

### pfem_make_scenarios.m
Build a scenario struct array for single- or multi-parameter sweeps.

```matlab
% Single parameter
scenarios = pfem_make_scenarios('yield_stress', [50, 100, 200, 500]);

% Multiple parameters varied in lockstep (same-length arrays)
scenarios = pfem_make_scenarios( ...
    'yield_stress',     [50,   100,  200,  500], ...
    'youngs_modulus_E', [5e4,  1e5,  2e5,  1e5]);
% → 4 scenarios, each with label e.g. 'sy=50 E=5e4'

% Fully manual
scenarios(1) = struct('label','soft', 'yield_stress', 50,  'youngs_modulus_E', 5e4);
scenarios(2) = struct('label','hard', 'yield_stress', 500, 'youngs_modulus_E', 2e5);
```

### pfem_plot_sweep_summary.m
Creates one figure window per available PFEM output type.

```matlab
figs = pfem_plot_sweep_summary(results, sweep_param, yaml_path, ...
    'Title', 'PFEM p61', 'Save', '/path/to/prefix');
% figs.res  — Load–Displacement summary (.res)
% figs.msh  — Reference mesh panels (.msh)
% figs.dis  — Deformed shape panels (.dis)
% figs.vec  — Displacement vector panels (.vec)
% Saved as: /path/to/prefix_res.png  _msh.png  _dis.png  _vec.png
```

### pfem_ensure_built.m
Auto-compiles a PFEM binary from source if missing.  Checks binary existence
rather than exit code (build scripts may exit non-zero when other programs
in the chapter fail even if the target binary was built successfully).

```matlab
ok = pfem_ensure_built(repo_root, pfem_root, 'p61', 'chap06');
```

---

## Parameter Discovery

### pfem_show_tunables.m
List available tunable parameters for any YAML case.

```matlab
pfem_show_tunables('benchmarks/pfem5/chap06/p63.yaml');
```

```
NAME                       TOKEN          CURRENT      TYPE  SUGGESTED RANGE
--------------------------------------------------------------------------------
friction_angle_phi             5             20.0      real  [0, 45]
cohesion_c                     6             10.0      real  [0, 1e6]
dilation_angle_psi             7             20.0      real  [0, 45]
unit_weight_gamma              8             16.0      real  [0, 100]
youngs_modulus_E               9           1.0e5      real  [1e3, 1e12]
poisson_ratio_nu              10              0.3      real  [0, 0.49]
convergence_tolerance         74           0.001      real  [1e-12, 0.1]
iteration_limit               75            500        int  [10, 10000]
load_increments               76             25        int  [1, 1000]
prescribed_increment          77          -0.001      real  [-1e6, 1e6]
```

### pfem_smart_sweep.m
Automatic sweep using the first tunable that has a `suggested_range`.

```matlab
results = pfem_smart_sweep('benchmarks/pfem5/chap05/p51_4.yaml', 'auto', 5);
results = pfem_smart_sweep('benchmarks/pfem5/chap05/p51_4.yaml', 'youngs_modulus_E', [500, 1000, 5000]);
```

---

## Result Comparison

### pfem_compare_results.m
Compare original vs modified results.  Supports two `.res` formats:
- **Format A** (elastic/structural): per-node displacement and stress table
- **Format B** (nonlinear load-step): `step load disp iters` table (e.g. p61 von Mises)

```matlab
% Text comparison only
pfem_compare_results(out, 'plot', false);

% Plot + text
pfem_compare_results(out, 'plot', true);
```

---

## NZ.m — Multi-Case × Multi-Scenario Sweep

`NZ.m` is the primary scripted sweep interface.  Edit the configuration
section and run the file.

```matlab
%% 1. YAML case(s)
yaml_paths = {
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p61.yaml'),
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p63.yaml'),
};

%% 2. Scenarios (choose one style)
% A — single parameter
scenarios = pfem_make_scenarios('yield_stress', [50, 100, 200, 500]);

% B — multiple parameters in lockstep
scenarios = pfem_make_scenarios( ...
    'yield_stress',     [50,   100,  200,  500], ...
    'youngs_modulus_E', [5e4,  1e5,  2e5,  1e5]);

% C — fully manual
scenarios(1) = struct('label','low',  'yield_stress', 50,  'youngs_modulus_E', 5e4);
scenarios(2) = struct('label','high', 'yield_stress', 500, 'youngs_modulus_E', 2e5);
```

**What NZ.m does for each case:**
1. Auto-builds binary via `pfem_ensure_built`
2. Runs every scenario with `pfem_run_from_yaml` (auto-generates baseline if needed)
3. Prints text comparison table (original vs each scenario)
4. Generates 4 separate figure windows via `pfem_plot_sweep_summary`
5. Saves figures to `runs/<chap>/<case>/<case>_sweep_{res,msh,dis,vec}.png`

---

## Output Structure

```
runs/
└── chap06/
    └── p61/
        ├── default/            ← auto-generated baseline (if book .res absent)
        │   ├── p61.dat         ← unmodified input
        │   ├── p61             ← compiled binary
        │   ├── p61.res         ← baseline results (used as comparison reference)
        │   └── run.log
        ├── sy_50_E_5e4/        ← scenario 1
        │   ├── p61.dat         ← patched input
        │   ├── p61             ← compiled binary (chmod +x)
        │   ├── p61.res  p61.msh  p61.dis  p61.vec
        │   ├── case.yaml       ← YAML snapshot
        │   ├── overrides.mat   ← saved override struct
        │   └── run_info.txt    ← human-readable summary
        ├── sy_100_E_1e5/
        │   └── ...
        ├── p61_sweep_res.png   ← load–displacement comparison
        ├── p61_sweep_msh.png   ← reference mesh panels
        ├── p61_sweep_dis.png   ← deformed shape panels
        └── p61_sweep_vec.png   ← displacement vector panels
```

Re-run any case from the shell (no MATLAB needed):
```bash
cd runs/chap06/p61/sy_50_E_5e4
printf "p61\n" | ./p61
```

---

## Prerequisites

1. **PFEM must be compiled** (NZ.m calls `pfem_ensure_built` automatically):
   ```bash
   scripts/pfem_build_chapter.sh ~/projects/fem-benchmarks/pfem chap06
   ```

2. **YAML files must exist** — generate them first if missing:
   ```bash
   python3 scripts/generate_yamls_v2.py --chapter chap06
   ```

---

## References

- YAML benchmark files contain detailed input/output schemas
- PFEM book: Smith, Griffiths & Margetts, *Programming the Finite Element Method* (5th ed.)
