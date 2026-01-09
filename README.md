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
- Python 3 with `pyyaml` package
- MATLAB (for parametric studies)
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

### From MATLAB
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
│   ├── pfem_collect_all.sh          # Collect bundles for YAML generation
│   ├── generate_yaml_from_bundles.py # YAML generator
│   ├── verify_yamls.py              # YAML validation
│   └── git_publish.sh               # Git helper
├── matlab/              # MATLAB interface
│   ├── pfem_runner.m              # Single case runner
│   ├── pfem_parametric_sweep.m    # Parametric study framework
│   └── README.md
├── docs/                # Documentation
│   └── HANDOVER.md                # Complete technical handover
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

### Complete Pipeline (Generate All YAMLs)

```bash
# Step 1: Collect bundles and run all cases
scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --all-chaps --run --rebuild-first


# Step 3: Verify all YAMLs
python3 scripts/verify_yamls.py

# Step 4: Commit and push
scripts/git_publish.sh "Add complete PFEM benchmark catalogue"
```

### Parametric Study Example

```matlab
% Define parameter variations
param_ranges.E = [1e5, 5e5, 1e6, 5e6, 1e7];   % Young's modulus
param_ranges.nu = [0.2, 0.25, 0.3, 0.35];      % Poisson's ratio

% Run parametric sweep
results = pfem_parametric_sweep('~/Downloads/pfem5/5th_ed', 'chap05', ...
                                'p51', 'p51_3', param_ranges);

% Results saved to ./runs/sweep_<timestamp>/
```

## Key Features

### 1. Bundle Collection
The `pfem_collect_all.sh` script:
- Finds all `.dat` datasets across chapters
- Compiles and runs each program
- Extracts `READ(10,*)` statements with context
- Collects outputs for verification
- Creates self-contained "evidence packs"

### 2. YAML Generation
The `generate_yaml_from_bundles.py` script:
- Analyzes Fortran source code structure
- Extracts FEM metadata (element types, physics, etc.)
- Parses dataset files to document input values
- Identifies tunable parameters for parametric studies
- Generates structured, validated YAML files

### 3. MATLAB Integration
- **pfem_runner.m**: Execute any PFEM case from MATLAB
- **pfem_parametric_sweep.m**: Framework for parameter studies
- Result parsing and organization
- Extensible for custom analyses

## Documentation

- **[docs/HANDOVER.md](docs/HANDOVER.md)**: Complete technical handover with detailed explanations
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
