# FEM Benchmarks Guide

Complete guide for working with the PFEM benchmark catalogue.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Generating YAML Files](#generating-yaml-files)
3. [Running Benchmarks](#running-benchmarks)
4. [MATLAB Integration](#matlab-integration)
5. [Token-Based Patching](#token-based-patching)
6. [Validation](#validation)
7. [Repository Structure](#repository-structure)

---

## Quick Start

### Prerequisites

```bash
# Python dependencies
pip install pyyaml

# Verify PFEM source location (default)
ls ~/projects/fem-benchmarks/pfem/source/
```

### Basic Workflow

```bash
# 1. Generate YAMLs for a chapter
python3 scripts/generate_yamls_v2.py --chapter chap05

# 2. Or generate all chapters at once
python3 scripts/generate_yamls_v2.py --all-chapters

# 3. Validate generated files
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/*.yaml

# 4. Commit changes
git add benchmarks/pfem5/
git commit -m "Add YAML benchmarks"
git push
```

---

## Generating YAML Files

### Overview

The `generate_yamls_v2.py` script creates YAML benchmark files with **token-based patch coordinates**:
- Tokenizes `.dat` files preserving position information
- Extracts READ(10,*) statements (including Fortran `&` continuations) from source
- Detects tunable parameters with their token indices — see table below
- Generates structured YAML with `global_token_index` for each tunable

### Detected Tunable Parameter Types

| Category | Parameters detected |
|----------|-------------------|
| Elastic | E (Young's modulus), ν (Poisson's ratio) |
| Plasticity | yield_stress σ_y (von Mises) |
| Mohr-Coulomb | friction_angle_phi, cohesion_c, dilation_angle_psi, unit_weight_gamma, earth_pressure_coeff_k0 |
| Two-material | fill: E/ν/c/φ/ψ/γ; embankment: E/ν/c/φ/ψ/γ (p69-style) |
| Flow | permeability_kx/ky, conductivity_kx/ky, dynamic_viscosity |
| Dynamics | density_rho, dtim, nstep, theta, beta, gamma, fm, fk, dr, omega |
| Eigenvalue | nmodes, nev, ncv, maxitr |
| Solver | tol (convergence), limit (max iters), cg_tol, cg_limit |
| Loading | incs (load increments), presc (prescribed increment) |
| Consolidation | bulk_modulus_ke, initial_effective_stress (cons), k0 |
| Mesh | nels/nxe, nye (with topology-change warning) |

### Key Features

- **Token indexing**: Each tunable has a `global_token_index` for direct patching
- **Source-aware detection**: Walks READ statements in source order using a symbol table
- **Continuation handling**: Fortran `&` multi-line READs joined before parsing
- **All tokens stored**: Complete token list in `inputs.all_tokens` for verification

### Usage

**Generate single case:**
```bash
python3 scripts/generate_yamls_v2.py --chapter chap05 --case p54_1
```

**Generate all cases in a chapter:**
```bash
python3 scripts/generate_yamls_v2.py --chapter chap05
```

**Preview without generating:**
```bash
python3 scripts/generate_yamls_v2.py --chapter chap05 --dry-run
```

### Command Options

```
--chapter CHAP      Chapter to process (e.g., chap05)
--case CASE         Specific case (optional, default: all cases)
--all-chapters      Process all chapters 4-11 at once
--pfem-root PATH    PFEM source directory (default: ~/projects/fem-benchmarks/pfem)
--dry-run           Preview only
```

### Generate All Chapters

Process all 90 cases across chapters 4-11 with one command:

```bash
python3 scripts/generate_yamls_v2.py --all-chapters
```

### YAML Structure

Each generated YAML includes:

- **id, title, purpose** - Identification
- **authors** - Source info, created_by: "Naeem"
- **code** - Language, source file, READ statements with line numbers
- **fem** - Dimension, formulation, DOF, element type
- **analysis** - Physics, type, regime
- **units** - Unit system notes
- **tunable_parameters** - Parameters for studies (E, nu, loads, mesh)
- **input_schema** - Field descriptions for each READ statement
- **inputs** - Parsed .dat values by record
- **outputs** - Expected output files
- **how_to_run** - Linux and MATLAB commands
- **notes** - Usage notes

---

## Running Benchmarks

### Build and Execute

Use the build script to compile and run cases:

```bash
scripts/pfem_build_and_run.sh ~/projects/fem-benchmarks/pfem chap05 p51 p51_3 --rebuild
```

This will:
1. Build PFEM library modules
2. Compile the specific program
3. Run with the specified dataset
4. Output results to executable/chap05/

### Manual Execution

```bash
cd ~/projects/fem-benchmarks/pfem/executable/chap05
printf "p51_3\n" | ../../build/bin/p51
```

### Batch Build

Build all programs for a chapter at once:

```bash
# Build all chap04 programs
./scripts/pfem_build_chapter.sh ~/projects/fem-benchmarks/pfem chap04

# Force rebuild
./scripts/pfem_build_chapter.sh ~/projects/fem-benchmarks/pfem chap04 --rebuild
```

---

## MATLAB Integration

### Single Case Execution

```matlab
pfem_root = '~/projects/fem-benchmarks/pfem';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

Returns:
- `status`: 0 = success, 1 = failure
- `outputs`: struct with result file paths and contents

### Parameter Discovery

Use `pfem_show_tunables` to see available parameters for any case:

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

### Parametric Studies

```matlab
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
```

Each run creates an isolated, self-contained folder:
```
runs/chap05/p51_4/E_5e5/          ← parameter key in folder name
    p51_4.dat                      ← patched input
    p51                            ← compiled binary (chmod +x)
    p51_4.res  p51_4.msh           ← PFEM outputs
    case.yaml                      ← copy of YAML
    overrides.mat                  ← saved parameter overrides
    run_info.txt                   ← human-readable run summary
```

### Result Comparison

Compare original vs modified results with text tables and plots:

```matlab
% Text comparison only (displacement and stress tables)
pfem_compare_results(out, 'plot', false);

% Plot only (bar charts for single run)
pfem_compare_results(out, 'plot', true, 'text', false);

% Sweep summary (parameter vs displacement/stress plots)
pfem_compare_results(results_array, 'plot', true);
```

#### Comparison Output

Text output shows:
- Node-by-node displacement comparison (original vs modified)
- Element stress comparison
- Max absolute and relative differences

Plots include:
- **Single run**: Bar charts comparing X/Y displacements and stresses
- **Sweep**: Line plots showing how displacement/stress vary with parameter

### Complete Sweep Example (NZ.m)

```matlab
% Setup
yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p51_4.yaml');

% Discover tunables
tunables = pfem_show_tunables(yaml_path);

% Define sweep
sweep_param = 'youngs_modulus_E';
sweep_values = [500, 1000, 5000, 10000];

% Run sweep
for i = 1:length(sweep_values)
    overrides.(sweep_param) = sweep_values(i);
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    results(i).out = out;
    results(i).status = status;
end

% Text comparison for ALL runs
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', false);
end

% Sweep summary plot
pfem_compare_results(results, 'plot', true);

% Individual comparison plots for ALL runs
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', true, 'text', false);
end
```

### Batch Chapter Runner

Run all cases in a chapter:

```matlab
results = pfem_run_chapter(repo_root, pfem_root, 'chap04');
```

### Test Script

Verify the pipeline works:

```matlab
cd ~/projects/fem-benchmarks
pfem_test_run
```

---

## Token-Based Patching

The YAML files now include **token-based patch coordinates** for each tunable parameter. This enables generic patching across all PFEM chapters without hardcoded assumptions.

### How It Works

1. **Tokenization**: The `.dat` file is parsed into a flat list of tokens
2. **Global Index**: Each tunable parameter stores its `global_token_index` (1-based position)
3. **Patching**: The MATLAB patcher replaces tokens directly by index

### YAML Structure

```yaml
tunable_parameters:
  - name: youngs_modulus_E
    global_token_index: 9     # Position in flat token list
    line: 4                   # Original line number
    type: real
    description: "Young's modulus"
    current_value: '1.0e6'
    suggested_range: [1.0e4, 1.0e12]
```

### Using Overrides in MATLAB

```matlab
% Load YAML
yaml_path = 'benchmarks/pfem5/chap05/p51_3.yaml';

% Define overrides (keyed by tunable name)
overrides = struct();
overrides.youngs_modulus_E = 2e6;     % Double the stiffness
overrides.poisson_ratio_nu = 0.25;    % Change Poisson's ratio

% Run with patching
[status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
```

### Benefits

- **Generic**: Works for all chapters (4-11) without program-specific code
- **Robust**: No assumptions about record structure or property ordering
- **Traceable**: Token indices can be verified against the `.dat` file

### Viewing Token Information

Each YAML stores all tokens for reference:

```yaml
inputs:
  all_tokens:
    - "'plane'"
    - "'quadrilateral'"
    - '4'
    - "'y'"
    - '3'
    # ... (token index = position in this list)
```

---

## Validation

### Verify YAML Files

```bash
# Single file
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/p51_3.yaml

# Multiple files
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/*.yaml

# All chapters
python3 scripts/verify_yamls.py benchmarks/pfem5/**/*.yaml
```

Expected output:
```
✓ benchmarks/pfem5/chap05/p51_1.yaml
✓ benchmarks/pfem5/chap05/p51_2.yaml
...
Valid: 13/13
[SUCCESS] All YAML files are valid!
```

### Validation Checks

The script verifies:
- Valid YAML syntax
- Required top-level keys present
- Proper structure for nested sections
- Source information available

---

## Repository Structure

```
fem-benchmarks/
├── benchmarks/pfem5/      # YAML benchmark catalogue
│   ├── chap04/           # 13 cases
│   ├── chap05/           # 13 cases
│   ├── chap06/           # 15 cases
│   ├── chap07/           # 8 cases
│   ├── chap08/           # 16 cases
│   ├── chap09/           # 7 cases
│   ├── chap10/           # 5 cases
│   └── chap11/           # 8 cases (85 total)
│
├── scripts/
│   ├── generate_yamls_v2.py        # YAML generator (token-based)
│   ├── verify_yamls.py             # Validation tool
│   ├── pfem_build_and_run.sh       # Build & run script
│   └── pfem_build_chapter.sh       # Batch chapter build
│
├── matlab/
│   ├── pfem_runner.m               # Single case runner
│   ├── pfem_run_from_yaml.m        # YAML-driven runner with overrides
│   ├── pfem_show_tunables.m        # Display available tunables
│   ├── pfem_smart_sweep.m          # Auto-discovery sweep
│   ├── pfem_compare_results.m      # Result comparison & plotting
│   ├── pfem_run_chapter.m          # Batch chapter runner
│   ├── NZ.m                        # Example sweep script
│   └── utils/
│       ├── pfem_yaml_load.m        # YAML loader
│       └── pfem_patch_dat_using_yaml.m  # Token-based patcher
│
├── docs/
│   └── GUIDE.md                    # This file
│
└── README.md                        # Project overview
```

---

## Dataset Coverage

| Chapter | Programs | Cases | Topics |
|---------|----------|-------|--------|
| 4 | p41-p47   | 13 | 1D Problems |
| 5 | p51-p57   | 14 | 2D Linear Elasticity |
| 6 | p61-p69   | 19 | Material Nonlinearity (von Mises, Mohr-Coulomb) |
| 7 | p71-p75   | 8  | Steady State Flow |
| 8 | p81-p811  | 16 | Transient Problems |
| 9 | p91-p96   | 7  | Coupled Problems (Biot, Navier-Stokes) |
| 10 | p101-p104 | 5 | Eigenvalue Problems |
| 11 | p111-p118 | 8 | Dynamics & Explicit Plasticity |
| **Total** | | **90** | |

---

## Tips & Best Practices

### For YAML Generation

1. Always run validation after generating YAMLs
2. Review line numbers in io_reads_from_unit10 match source code
3. Verify parsed .dat values are correct
4. Check tunable_parameters paths work with your use case

### For Parametric Studies

1. Start with small parameter ranges to test
2. Use tunable_parameters paths from YAML files
3. Check dat_modifier function in pfem_parametric_sweep.m
4. Customize for your specific program's input format

### For Version Control

1. Generate YAMLs one chapter at a time
2. Validate before committing
3. Use descriptive commit messages
4. Keep YAML files separate from PFEM source code

---

## Troubleshooting


**Error: "Source file not found"**
- Check PFEM root path with `--pfem-root` flag
- Default: `~/projects/fem-benchmarks/pfem`

**Error: "Template YAML not found"**
- Ensure `benchmarks/pfem5/chap05/p54_1.yaml` exists
- This file is the template for all generations

**YAML validation fails**
- Check YAML syntax with online validator
- Ensure all required sections present
- Verify proper indentation

---

## References

- Smith, I.M., Griffiths, D.V., & Margetts, L. (2014). *Programming the Finite Element Method* (5th ed.)
- PFEM Website: http://www.pfem.org.uk/

---

## Contact

Repository: https://github.com/NZ5253/fem-benchmarks
Author: Naeem
