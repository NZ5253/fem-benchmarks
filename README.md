# FEM Benchmarks Catalogue

A comprehensive benchmark catalogue for **Programming the Finite Element Method (5th Edition)** with MATLAB integration and parametric study capabilities.

## Overview

This repository provides:
- **Structured YAML metadata** for 87 PFEM benchmark cases across chapters 4-11
- **Build and execution scripts** for all PFEM programs
- **MATLAB interface** for running cases and performing deterministic + stochastic parametric studies
- **Per-case-type output extraction** (FS, limit load, max displacement, settlement, eigenvalue, peak response, etc.)
- **Validation tools** to ensure YAML correctness and completeness

## Quick Start

### Prerequisites
- Linux environment with `gfortran`
- Python 3 with `pyyaml`
- MATLAB (optional, for parametric studies)
- PFEM 5th edition source code (place at `pfem/` inside the repo — see below)

### Installation
```bash
# Clone repository
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks

# Install Python dependencies
pip install pyyaml

# Place PFEM source at pfem/ (not included due to licensing)
# e.g. move from wherever you have it:
mv ~/Downloads/pfem5/5th_ed pfem/
```

### Running a Benchmark
```bash
# Build and run a specific case
scripts/pfem_build_and_run.sh pfem chap05 p51 p51_3 --rebuild
```

### From MATLAB — Sweep GUI (recommended, no code editing)
```matlab
% Launch the graphical sweep studio
pfem_sweep_gui()
```
- Click **Add YAML(s)** → select any benchmark files from `benchmarks/pfem5/`
- Parameters auto-populate from YAML defaults; enter comma-separated values or click **Fill Ranges**
- Choose sweep mode:
  - **Lockstep**: parameters vary in parallel; arrays must be same length
  - **Grid**: Cartesian product of all parameter values
  - **Stochastic (distributions)**: Monte Carlo with `lognormal(mu, COV)`, `normal`, `truncnormal`, `uniform`; counter sets sample count (10 to 500)
- Click **Run All** → binaries are compiled automatically if missing; live log shows progress
- Click **Open Figures** after the run to view per-case-type results (FS distribution, load-displacement, mesh, deformed shape, etc.)

### From MATLAB — PFEM Studio (single-case interactive)
```matlab
% Open the interactive study environment (file picker opens)
pfem_studio()

% Or load a specific case directly
pfem_studio('benchmarks/pfem5/chap06/p61.yaml')
```

### From MATLAB — programmatic runner
```matlab
repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
pfem_root = fullfile(repo_root, 'pfem');
[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', 'p51_3');
```

### From MATLAB — scripted multi-case sweep (NZ.m)
```matlab
% Run two cases (p61 + p63) across 4 simultaneous-parameter scenarios
yaml_paths = {
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p61.yaml'),
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p63.yaml'),
};
scenarios = pfem_make_scenarios( ...
    'yield_stress',     [50,  100, 200, 500], ...
    'youngs_modulus_E', [5e4, 1e5, 2e5, 1e5]);
% Edit yaml_paths + scenarios in NZ.m, then run it.
% Generates 4 separate figure windows (res/msh/dis/vec) saved to runs/<chap>/<case>/
```

## Repository Structure

```
fem-benchmarks/
├── pfem/                # PFEM 5th ed. source/executables (not in git — obtain separately)
│   ├── source/          # Fortran source code
│   ├── build/           # Compiled binaries (build/bin/, build/mod/, build/obj/)
│   └── executable/      # Working directories for each chapter
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
│   ├── pfem_sweep_gui.m           # GUI sweep studio (multi-case × multi-param, auto-build)
│   ├── pfem_studio.m              # Interactive study environment (single case)
│   ├── pfem_diagram.m             # Textbook-style mesh diagram renderer
│   ├── pfem_runner.m              # Single case runner
│   ├── pfem_run_from_yaml.m       # YAML-driven runner with overrides + auto-baseline
│   ├── pfem_plot_mesh.m           # Deformed mesh visualisation (with mesh lines)
│   ├── pfem_batch_figs.m          # Batch sweep figures for all cases in a chapter
│   ├── pfem_show_tunables.m       # Display available tunables
│   ├── pfem_smart_sweep.m         # Auto-discovery sweep
│   ├── pfem_compare_results.m     # Result comparison & plotting (Format A + B)
│   ├── NZ.m                       # Multi-case, multi-parameter sweep script
│   └── utils/                     # Utility functions
│       ├── pfem_yaml_load.m                # YAML parser
│       ├── pfem_extract_coords.m           # Node coordinate extraction
│       ├── pfem_patch_dat_using_yaml.m     # Token-based .dat patcher
│       ├── pfem_make_scenarios.m           # Build scenario struct arrays
│       ├── pfem_plot_sweep_summary.m       # Separate figure per output type
│       └── pfem_ensure_built.m             # Auto-compile PFEM binary if missing
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
python3 scripts/generate_yamls_v2.py --chapter chap05

# All chapters at once
python3 scripts/generate_yamls_v2.py --all-chapters

# Verify generated YAMLs
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/*.yaml
```

See [docs/GUIDE.md](docs/GUIDE.md) for complete instructions.

### Parametric Study — Sweep GUI (recommended)

```matlab
pfem_sweep_gui()
```

1. **Add YAML(s)** — pick any combination of benchmark files; parameters auto-populate
2. **Configure** — enable parameters, enter values (`50, 100, 200, 500`) or use **Fill Ranges [-][4][+]**
3. **Preview** — verify scenario list in log before running
4. **Run All** — auto-builds missing binaries; runs every case × every scenario; live log
5. **Open Figures** — view Load–Disp, mesh, deformed shape, vector panels on demand

Supports any number of cases and scenarios simultaneously.  Parameters not present in a
given case's YAML are silently skipped, so one scenario set covers all cases.

### Parametric Study, Stochastic (Monte Carlo)

Select **Stochastic (distributions)** from the Mode dropdown to run Monte Carlo
sweeps over named distributions. The counter widget sets the sample count
(default 50, range 10 to 500, step 10).

**Fill Ranges** auto-fills `lognormal(mu, COV)` using the YAML default as `mu`
and a physics-based COV per parameter type:

| Parameter family | Default COV | Rationale |
|---|---|---|
| Cohesion (`cohesion_c`, `cohesion_fill`, `cohesion_embankment`, `yield_stress`) | 0.40 | High natural variability |
| Friction angle, dilation angle | 0.10 | Tighter physical bounds |
| Young's modulus | 0.30 | Stiffness scatter |
| Poisson's ratio | 0.10 | Bounded in (0, 0.5) |
| Unit weight, density | 0.05 | Low variability |
| Permeability | 0.50 | Multi-order-of-magnitude |
| Solver / mesh parameters (tolerance, iteration limit, time step, nxe, ...) | skipped | Must remain at YAML default to keep Fortran solver stable |

You can override the auto-fill manually:

```
lognormal(60, 0.30)
normal(0.3, 0.10)
truncnormal(0.3, 0.10, 0, 0.499)
uniform(40, 80)
```

For each case the GUI:
1. Detects the case type and the QoI to extract (FS, P_lim, u_max, ...)
2. Generates samples (seed fixed at 42 for reproducibility)
3. Runs Monte Carlo with `pfem_run_from_yaml`; the log updates per sample
4. Extracts the QoI from each run's `.res` file via `pfem_extract_qoi`
5. Reports `mean`, `std`, `COV`, range; for `slope_srf` cases also `P(failure)` and reliability index `beta`
6. Saves histogram, CDF, and per-parameter scatter plots as PDF + PNG

### Parametric Study, Single Case Interactive (pfem_studio)

```matlab
% Open studio with file picker
pfem_studio()

% Or specify a case
pfem_studio('benchmarks/pfem5/chap06/p61.yaml')
% → Edit yield_stress to: 50, 100, 200, 500
% → Press Run → sweep figure opens automatically
```

### Parametric Study — Scripted (NZ.m)

`NZ.m` is the primary scripted workflow. Edit three sections and run:

```matlab
%% 1. YAML case(s) to run — any number of benchmarks
yaml_paths = {
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p61.yaml'),
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p63.yaml'),
};

%% 2. Scenarios — single param or multiple params changed simultaneously
% Option A: sweep one parameter
scenarios = pfem_make_scenarios('yield_stress', [50, 100, 200, 500]);

% Option B: vary two parameters in lockstep (arrays must be same length)
scenarios = pfem_make_scenarios( ...
    'yield_stress',     [50,   100,  200,  500], ...
    'youngs_modulus_E', [5e4,  1e5,  2e5,  1e5]);

% Option C: fully manual with custom labels
scenarios(1) = struct('label','soft',   'yield_stress', 50,  'youngs_modulus_E', 5e4);
scenarios(2) = struct('label','hard',   'yield_stress', 500, 'youngs_modulus_E', 2e5);
```

The script runs every scenario for every case, saves four comparison figures
(`*_res.png`, `*_msh.png`, `*_dis.png`, `*_vec.png`) in `runs/<chap>/<case>/`,
and prints a text comparison table for each scenario.

### Batch Figure Generation

Generate sweep comparison figures (deformed mesh + parameter-vs-displacement curve) for all cases in a chapter:

```matlab
% All cases in chap06 (requires compiled binaries)
pfem_batch_figs('chap06')

% Single case
pfem_batch_figs('benchmarks/pfem5/chap05/p51_4.yaml')

% All 90 cases (takes a while — compile all chapters first)
pfem_batch_figs('all')
```

For each case, `pfem_batch_figs` automatically:
1. Selects the primary tunable parameter (first with a `suggested_range`)
2. Runs 4 sweep values (log-spaced within suggested range)
3. Generates a figure: parameter-vs-max|u| curve + tiled deformed mesh panels
4. Saves PNG to `figures/<chap>/<case>_<param>.png`

Supported output: all structural cases (chap04-06, 08, 11). Flow/eigenvalue/coupled cases are skipped gracefully when no per-node displacement output is present.

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
> gfortran -O2 pfem/source/chap06/p61.f03 \
>   -o pfem/build/bin/p61 \
>   -I pfem/build/mod \
>   pfem/build/obj/libpfem.a
> ```

## Key Features

### 1. YAML Generation
The `generate_yamls_v2.py` script creates comprehensive benchmark files:
- Extracts READ(10,*) statements (including `&` continuation) with line numbers from Fortran source
- Parses .dat files to document input values organized by record
- Identifies tunable parameters for parametric studies including:
  - Elastic: E, ν (Young's modulus, Poisson's ratio)
  - Mohr-Coulomb: φ, c, ψ, γ (friction angle, cohesion, dilation angle, unit weight)
  - Two-material (fill/embankment): separate E, ν, c, φ, ψ, γ per material
  - Solver: tol, limit, incs, presc, dtim, nstep, cg_tol, …
  - Mesh topology: nels/nxe, nye
- Generates complete YAML specifications with `global_token_index` for each tunable
- Includes input_schema, tunable_parameters, and parsed inputs sections

### 2. MATLAB Integration

| Function | Purpose |
|---|---|
| `pfem_sweep_gui` | **Sweep GUI**: multi-case x multi-param, deterministic + stochastic modes, auto-build, live log, on-demand figures |
| `pfem_stochastic_sweep` | CLI-style Monte Carlo runner independent of the GUI |
| `pfem_studio` | Single-case interactive GUI: load YAML, edit params, run, see deformed mesh |
| `pfem_diagram` | Standalone textbook-style mesh diagram with BC/load annotations |
| `pfem_run_from_yaml` | Programmatic runner: patches .dat from YAML overrides, auto-generates baseline |
| `pfem_extract_coords` | Extract exact node coordinates from YAML tokens (all chapters) |
| `pfem_plot_mesh` | Visualise deformed mesh with element edges from run output |
| `pfem_batch_figs` | Auto-generate sweep comparison figures for a whole chapter |
| `pfem_show_tunables` | Print tunable parameters for any YAML case |
| `pfem_smart_sweep` | Auto-discovery parametric sweep |
| `pfem_compare_results` | Compare original vs modified results (Format A per-node + Format B load-step) |
| `pfem_make_scenarios` | Build scenario struct arrays for single- or multi-parameter sweeps |
| `pfem_plot_sweep_summary` | One figure window per output type (res/msh/dis/vec) for sweep results |
| `pfem_ensure_built` | Auto-compile a PFEM binary from source if the binary is missing |
| `NZ.m` | Configurable multi-case x multi-scenario sweep script |
| `utils/pfem_sample_distribution` | Draw n samples from lognormal / normal / truncnormal / uniform; no Statistics Toolbox needed |
| `utils/pfem_detect_case_type` | Classify a YAML into one of 8 case types from chapter, program, physics, regime |
| `utils/pfem_extract_qoi` | Extract the correct Quantity of Interest per case type (FS, P_lim, u_max, h_max, Uav_end, lambda_1, u_peak, T_max) |

Runs are saved to `runs/<chap>/<case>/<param_key>/`, for example:
- `runs/chap06/p61/default/` — auto-generated baseline (used when book .res absent)
- `runs/chap06/p61/sy_200/` — single override: yield stress = 200
- `runs/chap06/p61/sy_50_E_5e4/` — multi-parameter override

## Documentation

- **[docs/GUIDE.md](docs/GUIDE.md)**: Complete usage guide with examples
- **[matlab/README.md](matlab/README.md)**: MATLAB interface guide
- **YAML files**: Each benchmark has inline documentation

## Dataset Coverage

| Chapter | Program Range | Cases | Topics |
|---------|---------------|-------|--------|
| 4       | p41-p47      | 13    | 1D Problems |
| 5       | p51-p57      | 15    | 2D Linear Elasticity |
| 6       | p61-p613     | 15    | Material Nonlinearity (von Mises, Mohr-Coulomb, SRF) |
| 7       | p71-p75      | 8     | Steady State Flow |
| 8       | p81-p811     | 16    | Transient Problems (consolidation, thermal, dynamic) |
| 9       | p91-p96      | 7     | Coupled Problems (Biot, dynamic) |
| 10      | p101-p104    | 5     | Eigenvalue Problems |
| 11      | p111-p118    | 8     | Dynamics & Explicit Plasticity |
| **Total** |            | **87** | |

## Case Types and Quantities of Interest

Each case is auto-classified into one of 8 types via `pfem_detect_case_type`. The
correct Quantity of Interest is extracted by `pfem_extract_qoi`:

| Case type | Where it applies | QoI | Label |
|---|---|---|---|
| `slope_srf` | chap6: p64-p69, p612, p613 | Factor of Safety (last converged SRF) | FS |
| `plasticity_load` | chap6: p61-p63, p610, p611; chap4: p45; chap9: p96; chap11: p118 | Limit load at last converged step | P_lim |
| `elastic_static` | chap4: p41-p46; chap5: all; chap9: p93-p95 | Max nodal displacement | u_max |
| `seepage_steady` | chap7: p71, p72, p74, p75 | Max total head | h_max |
| `consolidation` | chap8: p81-p88 (excluding dynamic/thermal); chap9: p91, p92 | Degree of consolidation at final time | Uav_end |
| `eigenvalue` | chap10: all | First eigenvalue | lambda_1 |
| `dynamic_transient` | chap4: p47; chap7: p73; chap8: p810, p84, p89; chap11: all | Peak displacement | u_peak |
| `thermal` | chap8: p811 | Max temperature | T_max |

## Licensing Note

⚠️ **Important**: This repository contains YAML metadata and utility scripts ONLY.
PFEM source code and datasets are NOT included due to licensing restrictions.
Users must obtain PFEM 5th edition separately and place it at `pfem/` inside the repo.

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
