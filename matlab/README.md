# PFEM MATLAB Interface

This directory contains MATLAB scripts for running PFEM benchmarks and performing parametric studies.

## Files

### pfem_runner.m
Basic runner for executing a single PFEM case from MATLAB.

**Usage:**
```matlab
[status, outputs] = pfem_runner(pfem_root, chapter, program, case_name);
```

**Example:**
```matlab
pfem_root = '~/Downloads/pfem5/5th_ed';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');

if status == 0
    fprintf('Success! Generated %d output files\n', outputs.num_files);
    disp(outputs.files);
end
```

### pfem_parametric_sweep.m
Framework for running parametric studies by varying input parameters.

**Usage:**
```matlab
param_ranges.E = [1e5, 1e6, 1e7];
param_ranges.nu = [0.2, 0.3, 0.4];
results = pfem_parametric_sweep(pfem_root, chapter, program, base_case, param_ranges);
```

**Note:** The `dat_modifier` function inside needs to be customized for each program based on its specific READ(10,*) format. See YAML files for input schema.

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
% Initialize
pfem_root = '~/Downloads/pfem5/5th_ed';

% Run a case
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');

% Parse results
if status == 0 && isfield(outputs, 'res_info')
    fprintf('Equations: %d\n', outputs.res_info.num_equations);
    fprintf('Skyline storage: %d\n', outputs.res_info.skyline_storage);
end
```

### Parametric Study

1. Define parameter ranges
2. Run sweep
3. Analyze results

```matlab
pfem_root = '~/Downloads/pfem5/5th_ed';

% Define parameter variations
param_ranges.E = [1e5, 5e5, 1e6, 5e6, 1e7];  % Young's modulus
param_ranges.nu = [0.2, 0.25, 0.3, 0.35];     % Poisson's ratio

% Run sweep
results = pfem_parametric_sweep(pfem_root, 'chap05', 'p51', 'p51_3', ...
                                param_ranges, './runs/p51_param_study');

% Analyze results
success_count = 0;
for i = 1:length(results.runs)
    if results.runs{i}.status == 0
        success_count = success_count + 1;
    end
end
fprintf('Successful runs: %d/%d\n', success_count, length(results.runs));
```

## Customization

To use parametric sweeps with a specific program:

1. Examine the YAML file for the program (in `benchmarks/pfem5/chapXX/`)
2. Understand the READ(10,*) sequence (input schema)
3. Customize the `dat_modifier` function in `pfem_parametric_sweep.m` to:
   - Parse the base .dat file
   - Identify which lines/values correspond to tunable parameters
   - Modify those values
   - Maintain the correct format

## Future Enhancements

- Generic .dat parser based on YAML input schema
- Result parsers for different output formats
- Visualization utilities (mesh plots, deformation, stress)
- Result comparison against reference values

## References

- See `docs/HANDOVER.md` for complete documentation
- YAML benchmark files contain detailed input/output schemas
- PFEM book: "Programming the Finite Element Method (5th ed.)"
