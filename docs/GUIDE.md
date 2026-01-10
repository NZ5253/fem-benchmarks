# FEM Benchmarks Guide

Complete guide for working with the PFEM benchmark catalogue.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Generating YAML Files](#generating-yaml-files)
3. [Running Benchmarks](#running-benchmarks)
4. [MATLAB Integration](#matlab-integration)
5. [Validation](#validation)
6. [Repository Structure](#repository-structure)

---

## Quick Start

### Prerequisites

```bash

# Verify PFEM source location (default)
ls ~/Downloads/pfem5/5th_ed/source/
```

### Basic Workflow

```bash
# 1. Generate YAMLs for a chapter
python3 scripts/generate_perfect_yamls.py --chapter chap05

# 2. Validate generated files
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/*.yaml

# 3. Commit changes
git add benchmarks/pfem5/chap05/
git commit -m "Add Chapter 5 benchmarks"
git push
```

---

## Generating YAML Files

### Overview

The `generate_perfect_yamls.py` script creates comprehensive YAML benchmark files by:
- Analyzing Fortran source code to extract READ statements with line numbers
- Parsing .dat input files
- Generating structured YAML with complete metadata

### Usage

**Generate single case:**
```bash
python3 scripts/generate_perfect_yamls.py --chapter chap05 --case p54_1
```

**Generate all cases in a chapter:**
```bash
python3 scripts/generate_perfect_yamls.py --chapter chap05
```

**Preview without generating:**
```bash
python3 scripts/generate_perfect_yamls.py --chapter chap05 --dry-run
```

### Command Options

```
--chapter CHAP     Chapter to process (e.g., chap05)
--case CASE        Specific case (optional, default: all cases)
--pfem-root PATH   PFEM source directory (default: ~/Downloads/pfem5/5th_ed)
--api-key KEY      API key (or use ANTHROPIC_API_KEY env var)
--dry-run          Preview only
```

### Generate All Chapters

Process all 85 cases across chapters 4-11:

```bash
for chapter in chap04 chap05 chap06 chap07 chap08 chap09 chap10 chap11; do
  python3 scripts/generate_perfect_yamls.py --chapter $chapter
  python3 scripts/verify_yamls.py benchmarks/pfem5/$chapter/*.yaml
done
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
scripts/pfem_build_and_run.sh ~/Downloads/pfem5/5th_ed chap05 p51 p51_3 --rebuild
```

This will:
1. Build PFEM library modules
2. Compile the specific program
3. Run with the specified dataset
4. Output results to executable/chap05/

### Manual Execution

```bash
cd ~/Downloads/pfem5/5th_ed/executable/chap05
printf "p51_3\n" | ../../build/bin/p51
```

---

## MATLAB Integration

### Single Case Execution

```matlab
pfem_root = '~/Downloads/pfem5/5th_ed';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

Returns:
- `status`: 0 = success, 1 = failure
- `outputs`: struct with result file paths and contents

### Parametric Studies

```matlab
% Define parameter ranges
param_ranges.E = [1e5, 5e5, 1e6, 5e6, 1e7];
param_ranges.nu = [0.2, 0.25, 0.3, 0.35];

% Run sweep
results = pfem_parametric_sweep('~/Downloads/pfem5/5th_ed', 'chap05', ...
                                'p51', 'p51_3', param_ranges);

% Results saved to ./runs/sweep_<timestamp>/
```

### Tunable Parameters

Check YAML files for parameter paths:

```yaml
tunable_parameters:
  - name: youngs_modulus_E
    path: "inputs.record2.material.E.value"
    suggested_range: [1.0e4, 1.0e9]
```

Use these paths to modify .dat files programmatically.

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
│   ├── chap05/           # 13 cases (complete with perfect YAMLs)
│   ├── chap06/           # 15 cases
│   ├── chap07/           # 8 cases
│   ├── chap08/           # 16 cases
│   ├── chap09/           # 7 cases
│   ├── chap10/           # 5 cases
│   └── chap11/           # 8 cases (85 total)
│
├── scripts/
│   ├── generate_perfect_yamls.py   # YAML generator
│   ├── verify_yamls.py             # Validation tool
│   ├── pfem_build_and_run.sh       # Build & run script
│   └── git_publish.sh              # Git helper
│
├── matlab/
│   ├── pfem_runner.m               # Single case runner
│   └── pfem_parametric_sweep.m     # Parametric studies
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
| 4 | p41-p47 | 13 | 1D Problems |
| 5 | p51-p57 | 13 | 2D Linear Elasticity |
| 6 | p61-p69 | 15 | Material Nonlinearity |
| 7 | p71-p75 | 8 | Steady State Flow |
| 8 | p81-p89 | 16 | Transient Problems |
| 9 | p91-p96 | 7 | Coupled Problems |
| 10 | p101-p104 | 5 | Eigenvalue Problems |
| 11 | p111-p115 | 8 | Parallel Processing |
| **Total** | | **85** | |

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
- Default: `/home/naeem/Downloads/pfem5/5th_ed`

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
