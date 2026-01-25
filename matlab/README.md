# PFEM MATLAB Interface

This directory contains MATLAB scripts for running PFEM benchmarks and performing parametric studies with automatic parameter discovery and result comparison.

## Files

### Core Scripts

#### pfem_runner.m
Basic runner for executing a single PFEM case from MATLAB.

```matlab
pfem_root = '~/Downloads/pfem5/5th_ed';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

#### pfem_run_from_yaml.m
YAML-driven runner with parameter overrides. Creates isolated run folders with parameter values in the name.

```matlab
yaml_path = 'benchmarks/pfem5/chap05/p51_4.yaml';
overrides = struct();
overrides.youngs_modulus_E = 500;
[status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
% Creates folder: runs/single/chap05/p51/p51_4/260125_160124_E_500/
```

### Parameter Discovery

#### pfem_show_tunables.m
Display available tunable parameters for any YAML case.

```matlab
tunables = pfem_show_tunables('benchmarks/pfem5/chap05/p51_4.yaml');
```

Output:
```
============================================================
Tunable Parameters for: p51_4
Program: p51 | Chapter: 5
============================================================

NAME                       TOKEN          CURRENT      TYPE  SUGGESTED RANGE
--------------------------------------------------------------------------------
youngs_modulus_E               9            1.0e6      real  [1.00e+04, 1.00e+12]
poisson_ratio_nu              10              0.3      real  [0.00e+00, 4.90e-01]
nels_or_nxe                    3                8       int  -
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
   scripts/pfem_build_and_run.sh ~/Downloads/pfem5/5th_ed chap05 p51 p51_3 --rebuild
   ```

2. **Dataset files must exist** in `pfem_root/executable/chapXX/`

## Workflow

### Single Run
```matlab
pfem_root = '~/Downloads/pfem5/5th_ed';
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

Each run creates an isolated folder:
```
runs/single/chap05/p51/p51_4/
  260125_160124_E_500/          # Timestamp + parameter values
    p51_4_XXXX.dat              # Modified input
    p51_4_XXXX.res              # Results
    case.yaml                   # Copy of YAML
    overrides.mat               # Parameter overrides
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
