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
│   ├── pfem_build_chapter.sh        # Batch chapter build
│   ├── generate_yamls_v2.py         # YAML generator (token-based)
│   └── verify_yamls.py              # YAML validation
├── matlab/              # MATLAB interface
│   ├── pfem_runner.m              # Single case runner
│   ├── pfem_run_from_yaml.m       # YAML-driven runner
│   ├── pfem_show_tunables.m       # Display available tunables
│   ├── pfem_smart_sweep.m         # Auto-discovery sweep
│   ├── pfem_compare_results.m     # Result comparison & plotting
│   ├── NZ.m                       # Example sweep script
│   └── utils/                     # Utility functions
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

### Parametric Study Example

```matlab
% Discover available tunables
pfem_show_tunables('benchmarks/pfem5/chap05/p51_4.yaml');

% Run parameter sweep
yaml_path = 'benchmarks/pfem5/chap05/p51_4.yaml';
for E = [500, 1000, 5000, 10000]
    overrides.youngs_modulus_E = E;
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    results(end+1).out = out;
end

% Compare results (text and plots)
for i = 1:length(results)
    pfem_compare_results(results(i).out, 'plot', false);  % Text comparison
end
pfem_compare_results(results, 'plot', true);  % Sweep summary plot
```

## Key Features

### 1. YAML Generation
The `generate_perfect_yamls.py` script creates comprehensive benchmark files:
- Extracts READ(10,*) statements with line numbers from Fortran source
- Parses .dat files to document input values organized by record
- Identifies tunable parameters for parametric studies (E, nu, loads, mesh)
- Generates complete YAML specifications following p54_1.yaml template
- Includes input_schema, tunable_parameters, and parsed inputs sections

### 2. MATLAB Integration
- **pfem_runner.m**: Execute any PFEM case from MATLAB
- **pfem_run_from_yaml.m**: YAML-driven runner with parameter overrides
- **pfem_show_tunables.m**: Discover available parameters for any case
- **pfem_smart_sweep.m**: Auto-discovery parameter sweeps
- **pfem_compare_results.m**: Compare original vs modified results with plots
- Organized output folders with parameter values in names

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
