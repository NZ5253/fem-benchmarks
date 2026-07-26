<p align="center">
  <img src="docs/figures/tudortmund_logo.svg" alt="Technische Universität Dortmund" height="70">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/figures/cre_logo.png" alt="Chair for Reliability Engineering (CRE)" height="70">
</p>

<h1 align="center">fem-benchmarks</h1>

<p align="center">
  <b>A pluggable, probabilistic study framework for the 87 PFEM 5<sup>th</sup>-edition benchmarks.</b><br>
  <sub>Latin Hypercube · Iman–Conover · sensitivity tornado · analytic + external oracles · four-level regression net</sub>
</p>

<p align="center">
  <a href="https://github.com/NZ5253/fem-benchmarks/releases/tag/v1.0-phase3-complete"><img src="https://img.shields.io/badge/release-v1.0--phase3--complete-4361ee?style=flat-square" alt="release"></a>
  &nbsp;
  <img src="https://img.shields.io/badge/PFEM_cases-87%2F87-2a9d8f?style=flat-square" alt="87/87 cases">
  &nbsp;
  <img src="https://img.shields.io/badge/golden_regression-92%2F92-2a9d8f?style=flat-square" alt="92/92 golden">
  &nbsp;
  <img src="https://img.shields.io/badge/analytic_oracles-9%2F9-2a9d8f?style=flat-square" alt="9/9 oracles">
  &nbsp;
  <img src="https://img.shields.io/badge/license-MIT-333?style=flat-square" alt="MIT">
</p>

---

## What it is

The PFEM textbook (Smith / Griffiths / Margetts, 5<sup>th</sup> ed.) ships
87 stand-alone Fortran benchmark programs. This repository wraps them in a
MATLAB + Python framework that turns each case into a **probabilistic
study platform**:

- Every benchmark is catalogued as a YAML with tunable parameters annotated
  by their token position in the `.dat` file.
- A graphical Sweep Studio drives every case through **Lockstep**,
  **Grid**, **Stochastic** (Monte Carlo + LHS + Iman–Conover), or
  **Sensitivity** (tornado) modes.
- A single-line YAML key (`runner.type`) can redirect any sweep to a
  **non-PFEM backend**: a closed-form analytic formula or an external
  program (Python, bash, or anything that reads a file and writes a file).
- Every future change is regression-gated at four independent levels: per-run
  value, closed-form correctness, distribution moments at fixed seed, and
  physical scaling direction.

## Quick start (5 minutes to first result)

```bash
# Prerequisites: gfortran, python3, matlab, libarpack2t64
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks
pip install pyyaml
# Restore the PFEM source at pfem/ (see docs/HANDOVER.md §12.3)
scripts/pfem_build_chapter.sh ./pfem chap06
python3 scripts/run_all_tests.py   # → 87/87 passed
```

Then launch the GUI:

```bash
matlab -nodesktop -nosplash -r "addpath matlab matlab/utils matlab/backends; pfem_sweep_gui"
```

<p align="center">
  <img src="presentation/abc/gui.png" alt="PFEM Sweep Studio" width="800">
</p>

In the GUI: **Load preset ... → Prandtl demo (PFEM + analytic + external)**,
mode → **Stochastic**, **Fill Ranges**, uncheck all except `yield_stress`,
**Run All**. Three sets of histograms will render, showing PFEM, analytic
and external all producing the same P_lim distribution to within 0.16 %.

## Documentation

| Document | Purpose |
|---|---|
| **[docs/HANDOVER.md](docs/HANDOVER.md)** | **Master handover.** Start here on any new system. |
| [docs/SETUP.md](docs/SETUP.md) | Cross-platform install (Linux · Windows via WSL2 · macOS) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Deep technical architecture with call graph |
| [docs/GUIDE.md](docs/GUIDE.md) | Detailed usage guide (GUI + programmatic) |
| [docs/PROGRESS.md](docs/PROGRESS.md) | Supervisor-facing progress report with validation evidence |
| **[docs/ROADMAP.md](docs/ROADMAP.md)** | **What's next for the project.** Task A (solver isolation) · Task B (presentation) · Phase 4 backlog |
| [docs/PHASE3_PLAN.md](docs/PHASE3_PLAN.md) | Phase 3 milestone plan (M0 through M7, all done) |
| [docs/adding_a_backend.md](docs/adding_a_backend.md) | Contributor tutorial: add a new backend in ~30 min |
| [docs/adding_an_oracle.md](docs/adding_an_oracle.md) | Contributor tutorial: add a new analytic oracle in ~15 min |

## Features

- **87 PFEM cases** covering 8 physical families (slope stability, plasticity,
  elastic, seepage, consolidation, eigenvalue, dynamic transient, thermal),
  every one verified end-to-end
- **Four sweep modes** (Lockstep, Grid, Stochastic, Sensitivity), each
  backend-agnostic since Phase 3
- **Latin Hypercube sampling** with 6–14× variance reduction vs IID Monte
  Carlo, plus **Iman–Conover** correlated-parameter draws (targets in
  `[-0.7, +0.5]` reproduced within 5 %)
- **9 analytic oracles**, one per case type, giving every physical family
  an independent reference
- **2 external backends** (Python and bash/awk) proving the framework is
  language-agnostic
- **Four-level regression net**: golden 92/92, oracles 9/9, stochastic gate
  2/2, physics sanity 20/20
- **Auto-generated HTML report** per sweep — one self-contained file with
  every figure embedded
- **Preset loader** in the GUI for one-click loading of common
  YAML combinations

## Verification

The four-level regression net catches different classes of drift:

| Test | Coverage | Runtime | Result |
|---|---|---|---|
| [`run_all_tests.py`](scripts/run_all_tests.py) | 87 PFEM binaries at defaults | ~30 s | **87 / 87** |
| [`test_golden_qoi`](matlab/tests/test_golden_qoi.m) | 87 defaults + 5 override probes | ~5 min | **92 / 92** |
| [`test_all_analytic_oracles`](matlab/tests/test_all_analytic_oracles.m) | 9 closed-form correctness | <1 s | **9 / 9** |
| [`test_stochastic_gate`](matlab/tests/test_stochastic_gate.m) | Fixed-seed distribution moments | ~2 s | **2 / 2 backends locked** |
| [`test_physics_sanity`](matlab/tests/test_physics_sanity.m) | QoI monotonicity direction | <1 s | **20 / 20** |
| [`test_all_cases_stochastic`](matlab/tests/test_all_cases_stochastic.m) | 18-case Monte Carlo | ~40 s | **180 / 180** |
| [`plot_analytic_vs_pfem`](matlab/tests/plot_analytic_vs_pfem.m) | Analytic vs PFEM correlation | ~1 min | **r = 0.968 off-plateau** |

<p align="center">
  <img src="figures/analytic_vs_pfem_p61.png" alt="Analytic Prandtl vs PFEM p61" width="580">
</p>

## License

MIT for the framework code (`matlab/`, `scripts/`, `benchmarks/`, `docs/`,
`figures/`). The PFEM textbook source under `pfem/` is **not** covered by
MIT — it is proprietary code by Smith / Griffiths / Margetts distributed
via http://www.pfem.org.uk/ and gitignored in this repository. See
[LICENSE](LICENSE) for the full text.

## Citation

If this framework contributes to a publication, please cite the
tagged release:

```
Zainuddin, N. (2026). fem-benchmarks: Pluggable probabilistic study
framework for the PFEM 5th-edition benchmarks (v1.0-phase3-complete).
Technische Universität Dortmund.
https://github.com/NZ5253/fem-benchmarks/releases/tag/v1.0-phase3-complete
```

---

<p align="center"><sub>
  Naeem Zainuddin · Technische Universität Dortmund · 2026
</sub></p>
