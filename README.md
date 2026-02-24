# FEM Benchmarks Catalogue

A comprehensive benchmark catalogue for **Programming the Finite Element Method (5th Edition)** with MATLAB integration and parametric study capabilities.

## Overview

This repository provides:
- 📋 **Structured YAML metadata** for 85+ PFEM benchmark cases across chapters 4-11
- 🔧 **Build and execution scripts** for all PFEM programs
- 📊 **MATLAB interface** for running cases and performing parametric studies
- 📝 **Comprehensive documentation** with detailed input/output schemas
- ✅ **Validation tools** to ensure YAML correctness and completeness

## Quick Start

### Prerequisites
- Linux environment with `gfortran`
- Python 3 with `pyyaml`
- MATLAB (optional, for parametric studies)
- PFEM 5th edition source code at `~/Downloads/pfem5/5th_ed`

### Installation
```bash
# Clone repository
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks

# Install Python dependencies
pip install pyyaml
```

### Running a Benchmark
```bash
# Build and run a specific case
scripts/pfem_build_and_run.sh ~/Downloads/pfem5/5th_ed chap05 p51 p51_3 --rebuild
```

### From MATLAB — PFEM Studio (interactive)
```matlab
% Open the interactive study environment (file picker opens)
pfem_studio()

% Or load a specific case directly
pfem_studio('benchmarks/pfem5/chap06/p61.yaml')
```

### From MATLAB — programmatic runner
```matlab
pfem_root = '~/Downloads/pfem5/5th_ed';
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

## Repository Structure

```
fem-benchmarks/
├── benchmarks/           # YAML benchmark catalogue
│   └── pfem5/
│       ├── chap04/      # Chapter 4: 13 cases
│       ├── chap05/      # Chapter 5: 13 cases
│       ├── chap06/      # Chapter 6: 15 cases
│       ├── chap07/      # Chapter 7: 8 cases
│       ├── chap08/      # Chapter 8: 16 cases
│       ├── chap09/      # Chapter 9: 7 cases
│       ├── chap10/      # Chapter 10: 5 cases
│       └── chap11/      # Chapter 11: 8 cases
├── scripts/             # Build and utility scripts
│   ├── pfem_build_and_run.sh        # Build & execute PFEM programs
│   ├── pfem_build_chapter.sh        # Batch chapter build
│   ├── generate_yamls_v2.py         # YAML generator (token-based)
│   └── verify_yamls.py              # YAML validation
├── matlab/              # MATLAB interface
│   ├── pfem_studio.m              # Interactive study environment (main UI)
│   ├── pfem_diagram.m             # Textbook-style mesh diagram renderer
│   ├── pfem_runner.m              # Single case runner
│   ├── pfem_run_from_yaml.m       # YAML-driven runner with overrides
│   ├── pfem_plot_mesh.m           # Deformed mesh visualisation
│   ├── pfem_show_tunables.m       # Display available tunables
│   ├── pfem_smart_sweep.m         # Auto-discovery sweep
│   ├── pfem_compare_results.m     # Result comparison & plotting
│   ├── NZ.m                       # Example sweep script (launches studio)
│   └── utils/                     # Utility functions
│       ├── pfem_yaml_load.m       # YAML parser
│       ├── pfem_extract_coords.m  # Node coordinate extraction
│       └── pfem_patch_dat_using_yaml.m  # Token-based .dat patcher
├── docs/                # Documentation
│   └── GUIDE.md                   # Complete usage guide
└── README.md            # This file
```

## Benchmark Catalogue Format

Each YAML file contains:
- **Identification**: ID, title, purpose, source reference
- **FEM Details**: Element type, dimension, formulation, physics
- **Analysis Type**: Linear/nonlinear, steady/transient
- **Input Schema**: Parsed READ(10,*) sequence with parameter descriptions
- **Tunable Parameters**: Which values can be changed for parametric studies
- **Expected Outputs**: File list and key result values
- **Execution Instructions**: Build and run commands

Example: [benchmarks/pfem5/chap05/p51_3.yaml](benchmarks/pfem5/chap05/p51_3.yaml)

## Workflow

### Generate YAMLs

```bash
# Single chapter
python3 scripts/generate_perfect_yamls.py --chapter chap05

# All chapters at once
python3 scripts/generate_perfect_yamls.py --all-chapters

# Verify generated YAMLs
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/*.yaml
```

See [docs/GUIDE.md](docs/GUIDE.md) for complete instructions.

### Parametric Study — Interactive (recommended)

```matlab
% Open studio with file picker
pfem_studio()

% Or specify a case
pfem_studio('benchmarks/pfem5/chap06/p61.yaml')
% → Edit yield_stress to: 50, 100, 200, 500
% → Press Run → sweep figure opens automatically
```

### Parametric Study — Scripted

```matlab
% Via NZ.m: edit yaml_path + sweep_param + sweep_values, then run.
% The script runs the sweep and opens pfem_studio for visualisation.
```

## PFEM Studio

`pfem_studio` is the primary interactive interface — it replaces manual scripting in `NZ.m`.

```
┌─────────────────────────────┬──────────────────────────────────────┐
│  Undeformed mesh            │  Tunable Parameters                  │
│  (updates after each run)   │  ┌───────────────────┬────────────┐  │
│                             │  │ von Mises yield σ │  100.0     │  │
│     ┌───┬───┬───┐           │  │ Young's modulus E │  1e5       │  │
│     │   │   │   │           │  │ Poisson ratio ν   │  0.3       │  │
│     ├───┼───┼───┤           │  │ load increments   │  10        │  │
│     │   │   │   │           │  └───────────────────┴────────────┘  │
│     └───┴───┴───┘           │                                      │
│                             │     [ Run Simulation ]               │
├─────────────────────────────┼──────────────────────────────────────┤
│                             │  Results Summary                     │
│   Deformed mesh             │  max|ux| = +1.23e-02  (node 45)     │
│   coloured by |u|           │  max|uy| = -7.14e-02  (node 10)     │
│                             │  max|u|  = +7.24e-02  (node 10)     │
└─────────────────────────────┴──────────────────────────────────────┘
```

**Sweep mode** — type comma-separated values in any edit field:

```matlab
% In the yield_stress field, type:   50, 100, 200, 500
% Press Run → runs all four, opens sweep summary figure with:
%   - Load–displacement curve for each value
%   - Tiled deformed mesh panels
```

### Recommended test case: p61 (elastic-plastic bearing capacity)

```matlab
pfem_studio('benchmarks/pfem5/chap06/p61.yaml')
```

| Parameter | Default | Interesting sweep | Physical effect |
|---|---|---|---|
| `yield_stress` | 100 | `50, 100, 200, 500` | Controls when plasticity activates; σ_y=50 collapses at load 300, σ_y=500 stays elastic |
| `youngs_modulus_E` | 1e5 | `5e4, 1e5, 2e5` | Linear scaling of all displacements |
| `load_increments` | 10 | `5, 10, 20` | More steps = more accurate plastic zone |

> **Note**: build p61 first if not already compiled:
> ```bash
> gfortran -O2 ~/Downloads/pfem5/5th_ed/source/chap06/p61.f03 \
>   -o ~/Downloads/pfem5/5th_ed/build/bin/p61 \
>   -I ~/Downloads/pfem5/5th_ed/build/mod \
>   ~/Downloads/pfem5/5th_ed/build/obj/libpfem.a
> ```

## Key Features

### 1. YAML Generation
The `generate_perfect_yamls.py` script creates comprehensive benchmark files:
- Extracts READ(10,*) statements with line numbers from Fortran source
- Parses .dat files to document input values organized by record
- Identifies tunable parameters for parametric studies (E, nu, loads, mesh)
- Generates complete YAML specifications following p54_1.yaml template
- Includes input_schema, tunable_parameters, and parsed inputs sections

### 2. MATLAB Integration

| Function | Purpose |
|---|---|
| `pfem_studio` | Interactive GUI — load YAML, edit params, run, see deformed mesh |
| `pfem_diagram` | Standalone textbook-style mesh diagram with BC/load annotations |
| `pfem_run_from_yaml` | Programmatic runner: patches .dat from YAML overrides, runs PFEM |
| `pfem_extract_coords` | Extract exact node coordinates from YAML tokens (all chapters) |
| `pfem_plot_mesh` | Visualise deformed mesh + displacement vectors from run output |
| `pfem_show_tunables` | Print tunable parameters for any YAML case |
| `pfem_smart_sweep` | Auto-discovery parametric sweep |
| `pfem_compare_results` | Compare original vs modified results with plots |

Runs are saved to `runs/single/<chap>/<program>/<case>/<timestamp>/` with the parameter values embedded in the folder name.

## Documentation

- **[docs/GUIDE.md](docs/GUIDE.md)**: Complete usage guide with examples
- **[matlab/README.md](matlab/README.md)**: MATLAB interface guide
- **YAML files**: Each benchmark has inline documentation

## Dataset Coverage

| Chapter | Program Range | Cases | Topics |
|---------|---------------|-------|--------|
| 4       | p41-p47      | 13    | 1D Problems |
| 5       | p51-p54      | 13    | 2D Linear Elasticity |
| 6       | p61-p69      | 15    | Material Nonlinearity |
| 7       | p71-p75      | 8     | Steady State Flow |
| 8       | p81-p89      | 16    | Transient Problems |
| 9       | p91-p96      | 7     | Coupled Problems |
| 10      | p101-p104    | 5     | Eigenvalue Problems |
| 11      | p111-p115    | 8     | Parallel Processing |
| **Total** |            | **85** | |

## Licensing Note

⚠️ **Important**: This repository contains YAML metadata and utility scripts ONLY.
PFEM source code and datasets are NOT included due to licensing restrictions.
Users must obtain PFEM 5th edition separately.

## Contributing

Contributions welcome! Areas for improvement:
- Enhanced .dat parsers for automatic parameter modification
- Result visualization tools
- Additional validation checks
- Support for other FEM textbooks/codes

## References

- Smith, I.M., Griffiths, D.V., & Margetts, L. (2014). *Programming the Finite Element Method* (5th ed.)
- PFEM Website: http://www.pfem.org.uk/

## Contact

Repository: https://github.com/NZ5253/fem-benchmarks
