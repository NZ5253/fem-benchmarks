# PFEM MATLAB Interface

This directory contains MATLAB scripts for running PFEM benchmarks and performing parametric studies with automatic parameter discovery and result comparison.

## Files

### Core Scripts

#### pfem_runner.m
Basic runner for executing a single PFEM case from MATLAB.

```matlab
pfem_root = '~/projects/fem-benchmarks/pfem';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

#### pfem_run_from_yaml.m
YAML-driven runner with parameter overrides. Creates isolated, self-contained run folders.

```matlab
yaml_path = 'benchmarks/pfem5/chap05/p51_4.yaml';
overrides = struct();
overrides.youngs_modulus_E = 500;
[status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
% Creates folder: runs/chap05/p51_4/E_500/
%   Contains: patched .dat, binary (chmod +x), .res/.msh, case.yaml, overrides.mat, run_info.txt
```

### Parameter Discovery

#### pfem_show_tunables.m
Display available tunable parameters for any YAML case.

```matlab
tunables = pfem_show_tunables('benchmarks/pfem5/chap05/p51_4.yaml');
```

Output (example for p63 — Mohr-Coulomb):
```
============================================================
Tunable Parameters for: p63
Program: p63 | Chapter: 6
============================================================

NAME                       TOKEN          CURRENT      TYPE  SUGGESTED RANGE
--------------------------------------------------------------------------------
friction_angle_phi             5             20.0      real  [0.00e+00, 4.50e+01]
cohesion_c                     6             10.0      real  [0.00e+00, 1.00e+06]
dilation_angle_psi             7             20.0      real  [0.00e+00, 4.50e+01]
unit_weight_gamma              8             16.0      real  [0.00e+00, 1.00e+02]
youngs_modulus_E               9           1.0e5      real  [1.00e+03, 1.00e+12]
poisson_ratio_nu              10              0.3      real  [0.00e+00, 4.90e-01]
convergence_tolerance         74           0.001      real  [1.00e-12, 1.00e-01]
iteration_limit               75            500        int  [10, 10000]
load_increments               76             25        int  [1, 1000]
prescribed_increment          77          -0.001      real  [-1.00e+06, 1.00e+06]
nels_or_nxe                    1             40        int  -
np_types_or_nye                2             20        int  -
```

#### pfem_smart_sweep.m
Run parameter sweeps with automatic tunable discovery.

```matlab
% Sweep a specific parameter
results = pfem_smart_sweep('benchmarks/pfem5/chap05/p51_4.yaml', 'youngs_modulus_E', [500, 1000, 5000]);

% Auto-select first tunable with suggested range
results = pfem_smart_sweep('benchmarks/pfem5/chap05/p51_4.yaml', 'auto', 5);
```

### Result Comparison

#### pfem_compare_results.m
Compare original vs modified results with tables and plots.

```matlab
% Text comparison only
pfem_compare_results(out, 'plot', false);

% Plot only (no text)
pfem_compare_results(out, 'plot', true, 'text', false);

% Compare sweep results (generates parameter vs displacement/stress plots)
pfem_compare_results(results_array, 'plot', true);
```

### Example Sweep Script (NZ.m)

Complete example showing parameter sweep with comparison:

```matlab
% Setup
yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p51_4.yaml');

% Discover tunables
tunables = pfem_show_tunables(yaml_path);

% Define sweep
sweep_param = 'youngs_modulus_E';
sweep_values = [500, 1000, 5000, 10000];

% Run sweep and compare
for i = 1:length(sweep_values)
    overrides.(sweep_param) = sweep_values(i);
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    results(i).out = out;
end

% Show ALL comparisons (text)
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', false);
end

% Generate ALL comparison plots
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', true, 'text', false);
end
```

## Prerequisites

1. **PFEM must be compiled:**
   ```bash
   cd ~/projects/fem-benchmarks
   scripts/pfem_build_and_run.sh ~/projects/fem-benchmarks/pfem chap05 p51 p51_3 --rebuild
   ```

2. **Dataset files must exist** in `pfem_root/executable/chapXX/`

## Workflow

### Single Run
```matlab
pfem_root = '~/projects/fem-benchmarks/pfem';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

### Parameter Sweep with Comparison

```matlab
% 1. Discover available tunables
pfem_show_tunables('benchmarks/pfem5/chap05/p51_4.yaml');

% 2. Run sweep
yaml_path = 'benchmarks/pfem5/chap05/p51_4.yaml';
overrides = struct();
results = [];

for E = [500, 1000, 5000, 10000]
    overrides.youngs_modulus_E = E;
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    results(end+1).out = out;
    results(end).value = E;
    results(end).status = status;
end

% 3. Compare all results
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', false);  % Text
end

% 4. Plot all comparisons
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', true, 'text', false);  % Plots only
end
```

### Batch Chapter Runner

Run all cases in a chapter:

```matlab
results = pfem_run_chapter(repo_root, pfem_root, 'chap04');
```

## Output Structure

Each run creates a self-contained folder (binary + inputs + outputs in one place):
```
runs/chap05/p51_4/E_500/        # parameter key in folder name
    p51_4.dat                   # patched input
    p51                         # compiled binary (chmod +x; re-runnable from shell)
    p51_4.res                   # PFEM results
    p51_4.msh                   # PFEM mesh output
    case.yaml                   # copy of YAML used
    overrides.mat               # saved parameter struct
    run_info.txt                # human-readable summary (program, params, file sizes)
```

Re-run any case directly from shell (no MATLAB needed):
```bash
cd runs/chap05/p51_4/E_500
printf "p51_4\n" | ./p51
```

## Comparison Features

### Text Output
- Node-by-node displacement comparison (original vs modified)
- Element stress comparison
- Max absolute/relative differences

### Plots
- **Single run**: Bar charts comparing displacements and stresses
- **Sweep**: Line plots of parameter vs displacement/stress

## References

- YAML benchmark files contain detailed input/output schemas
- PFEM book: "Programming the Finite Element Method (5th ed.)"
