<p align="center">
  <img src="figures/tudortmund_logo.svg" alt="Technische Universität Dortmund" height="60">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="figures/cre_logo.png" alt="Chair for Reliability Engineering (CRE)" height="60">
</p>

<h1 align="center">fem-benchmarks — Roadmap for the Next Contributor</h1>

<p align="center">
  <sub>What remains after <code>v1.0-phase3-complete</code> · Sorted by supervisor priority<br>
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> · <a href="ARCHITECTURE.md">ARCHITECTURE.md</a></sub>
</p>

---

> **Written 2026-07-26.** At that date the project had ~2 weeks of active
> work remaining, framed by a re-scoping discussion with Dr. Natalia
> (Naty) Manque (direct supervisor) reflecting Prof. Matthias Faes's
> (chair holder) request that the framework be broadened beyond the
> geotechnical book examples.
>
> **This doc sorts the outstanding work into priority tiers so that
> whoever picks up next knows where to start.** Documentation was
> explicitly ranked above completion — the standing instruction is
> *"whatever is finished must be well documented; unfinished threads
> must be picked-up-able".*

## Table of contents

- [1. Executive summary](#1-executive-summary)
- [2. Task A — Solver isolation from book examples](#2-task-a--solver-isolation-from-book-examples)
- [3. Task B — Comprehensive project presentation](#3-task-b--comprehensive-project-presentation)
- [4. Additional Phase 4 candidates](#4-additional-phase-4-candidates)
- [5. Robustness / polish backlog](#5-robustness--polish-backlog)
- [6. Documentation improvements](#6-documentation-improvements)
- [7. Software-engineering nice-to-haves](#7-software-engineering-nice-to-haves)
- [8. How to hand off if time runs out](#8-how-to-hand-off-if-time-runs-out)

---

## 1. Executive summary

Everything in `v1.0-phase3-complete` is regression-locked and shipped.
The remaining work is grouped into two directly-supervisor-requested
tasks and four extension categories.

| Priority | Item | Effort |
|---|---|---|
| **P0** | **Task A — Solver isolation** (§2). Investigate whether PFEM's Fortran solver library can be decoupled from the geotechnical book examples so that a NEW mechanics problem (any geometry, any physics) can be assembled in MATLAB and solved via a PFEM library call. | 1–2 weeks, likely partial |
| **P0** | **Task B — Comprehensive presentation** (§3). A more detailed deck than the last one: implementation process, main challenges, GUI design + usage, how everything ties to repo documentation. Naty explicitly permitted GPT-assisted drafting. | ~2 days |
| P1 | Phase 4 candidates (§4) — mesh refinement, Sobol indices, FORM / SORM, multi-fidelity, ... | Multi-week each |
| P2 | Robustness / polish (§5) — probe-node QoIs, `parfor`, run caching, ... | Half-day each |
| P2 | Documentation improvements (§6) | Half-day each |
| P3 | Software engineering (§7) — CI, Docker, DOI | Varies |

The remainder of this doc is one section per row, with acceptance
criteria, starting-point pointers, and (where relevant) worked examples
for the next contributor.

---

## 2. Task A — Solver isolation from book examples

### 2.1 The goal (verbatim from Naty)

> "The idea is to keep using these Fortran solvers, but make them
> independent from the original geotechnical examples in the book. In
> other words, we would like to investigate whether the solver itself
> can be separated from the example-specific input and workflow, so that
> later someone in the Chair could provide a different mechanics
> problem, prepare the corresponding input files from MATLAB, and still
> use the same solver. The geotechnical examples would remain as
> validation cases, but the long-term goal is to have a reusable
> MATLAB–Fortran framework rather than a framework tied only to the
> book examples. Matthias's main point was that, since we work at the
> Faculty of Mechanics, we should aim for something that can eventually
> be used beyond geotechnical applications."

### 2.2 What "isolation" concretely means

PFEM ships as ~87 monolithic Fortran programs (p41 through p118), each of
which:

1. Reads a case-specific `.dat` file (geometry + material + BCs + loading).
2. Sets up problem-specific arrays (nodal coordinates, element
   connectivity, DOF numbering).
3. Assembles the stiffness / mass / damping matrices from element-level
   quantities using PFEM's library routines.
4. Applies BCs.
5. Calls PFEM's solver routines (`sparin_gauss`, `spabac_gauss`, `bisect`,
   `bandred`, ARPACK `dsaupd` / `dseupd`, ...).
6. Writes output `.res` / `.msh` / `.dis` / `.vec`.

Steps 1–4 and 6 are **problem-specific**. Step 5 is **generic**. Today
the framework runs whole p<N> executables end-to-end. The goal is to
expose step 5 as a callable interface so a MATLAB script that has
already done its own steps 1–4 can invoke PFEM's solver on its own
assembled matrix.

### 2.3 Concrete deliverable for the two-week window

**Reachable** (proof-of-concept):

- Pick ONE simple mechanics case (recommendations below).
- Assemble the stiffness matrix K and load vector f in MATLAB.
- Call ONE PFEM solver routine on it via one of the three approaches in
  §2.5.
- Solve for u.
- Compare against a MATLAB `\` reference.
- Document the calling convention and array layout precisely enough
  that the same route works for a second problem.

**Not reachable** (long-term):

- A general framework covering all 8 case types.
- Wrappers for every PFEM library routine.
- A YAML-driven interface for problem specification.

Naty was explicit: partial completion is fine as long as the direction
is proven and documented.

### 2.4 Suggested first problem

Naty said to use "any simple FEM mechanical example". Three concrete
recommendations, easiest first:

- **1D bar in tension** with `n` linear elements. K is tridiagonal.
  Solver route: `sparin_gauss` / `spabac_gauss` from the PFEM library.
  This mirrors the `bar_elongation` analytic oracle already in
  `benchmarks/analytic/bar_elongation.yaml`.
- **2D plane-stress linear elasticity** on a coarse quadrilateral mesh
  (say 4×4 elements) — like p51_3 but with the MATLAB side doing
  assembly.
- **Simply-supported beam eigenvalue** — matches the `ss_beam_eigen`
  analytic oracle. Solver route: `bandred` + `bisect`, same as p101.
  This one has the strongest cross-check because analytic, PFEM p101,
  AND a new MATLAB-assembled-and-PFEM-solved version can all be
  compared.

MATLAB itself has FEM tutorials with pre-assembled matrices (Naty
mentioned this in the chat) that you can crib the assembly code from.

### 2.5 Three ways to reach the Fortran solver

Sorted from easiest to most flexible:

- **A — Shared library + `loadlibrary`.** Compile the PFEM library
  routines into a `libpfemsolver.so` (Linux) / `.dylib` (macOS) / `.dll`
  (Windows). Load it in MATLAB via `loadlibrary` and call functions with
  `calllib`. Pros: no MEX, no C bindings. Cons: needs a manual header
  file, argument marshalling can be tricky with Fortran array
  conventions.
- **B — MEX wrapper.** Write a thin C or Fortran MEX file that receives
  a MATLAB double array, hands it to the PFEM solver, and returns the
  result. Pros: MATLAB handles the marshalling. Cons: needs `mex -setup`
  configured and one wrapper per routine.
- **C — File-based bridge.** Write a small generic Fortran program that
  reads a matrix from disk (Matrix Market / plain text), calls one PFEM
  solver, and writes the result back. Then a MATLAB script writes the
  matrix, `system()`s the binary, reads the result. Slowest for large
  problems (disk I/O per call) but requires zero MEX or shared-library
  work. Fits `external_backend`'s existing pattern exactly.

Recommendation: **start with C** (file bridge) — you can prototype it in
a day, verify the round-trip works, and only then consider MEX (B) for
performance if the disk I/O is unacceptable. Shared library (A) is the
most elegant end-state but has the highest upfront setup cost.

### 2.6 Acceptance criteria for the two-week window

- One MATLAB script (`matlab/tests/test_solver_isolation.m` or similar)
  that:
  - Assembles a small mechanics problem end-to-end in MATLAB.
  - Sends it through the chosen route (A / B / C).
  - Compares the PFEM solver's answer against MATLAB `\` within a
    documented tolerance.
- A new `matlab/backends/` entry (probably `pfem_lib_backend.m` or
  `pfem_solver_backend.m`) plus a YAML fixture — so the pluggable
  framework can drive the new backend, matching Phase 3's pattern.
- Doc entry (`docs/adding_a_solver_call.md` or similar tutorial) that
  the next person can follow to extend to a second problem.

### 2.7 Starting-point pointers

- PFEM library sources live under `pfem/source/library/main/` (main
  routines) and `pfem/source/library/misc/` (utilities added by our
  patches). Key files to skim: `sparin_gauss.f03`, `spabac_gauss.f03`,
  `bandred.f03`, `bisect.f03`, and — for the Lanczos path — the
  patched `lancz.f03`.
- The current `pfem_run_from_yaml.m` shows the dispatcher pattern; a
  new backend fits right in via `matlab/backends/get_backend.m`.
- Naty's papers (from her chair page) have linear FEM problems worked
  through explicitly with matrix listings — she offered to share one
  code example on the following Monday if you want a concrete numeric
  target to reproduce.
- `bar_elongation` and `ss_beam_eigen` under `benchmarks/analytic/`
  already carry the closed-form answer, giving you a triple check
  (analytic ↔ MATLAB assembly + `\` ↔ MATLAB assembly + PFEM solver).

---

## 3. Task B — Comprehensive project presentation

### 3.1 The goal (verbatim from Naty)

> "It would be great if the presentation could be detailed enough to
> explain the implementation process, the main challenges you
> encountered, how the different examples were developed, how the GUI
> was designed and how it is used, and how everything fits together
> with the repository documentation. Feel free to use GPT to help you
> prepare the presentation, that is absolutely fine. The important
> thing is that it is comprehensive, well organized, and closely
> aligned with the documentation you have been preparing for the code
> repository."

### 3.2 Suggested outline

Every section maps to a doc that is already written, so the presentation
is a **visual reformatting** of the existing handover, not new writing.

| Section | Source | Slides |
|---|---|---|
| Title + affiliations + release tag | README header | 1 |
| One-paragraph project purpose | HANDOVER §1 executive summary | 1 |
| Problem statement — 87 book programs → probabilistic study platform | HANDOVER §2 | 2 |
| Development timeline (Gantt) | HANDOVER §3 | 1 |
| Architecture overview + dispatcher diagram | HANDOVER §4 · ARCHITECTURE §4 | 3 |
| Five-stage pipeline with data-flow diagram | ARCHITECTURE §5 | 2 |
| Backend contract (Phase 3 heart) | HANDOVER §6 · ARCHITECTURE §7 | 2 |
| 8 case types + QoI dispatcher | HANDOVER §7 | 1 |
| Analytic oracle catalogue (9 formulas) | HANDOVER §8 · PROGRESS §4.3 | 2 |
| External backend examples (Python + bash) | HANDOVER §9 | 1 |
| Sweep modes + physics-based COVs | HANDOVER §10 · GUIDE §5 | 2 |
| Four-level regression net | HANDOVER §11 · PROGRESS §5.5 | 2 |
| GUI walkthrough with screenshots | GUIDE §5 · presentation/abc/gui.png | 3 |
| **Challenges I ran into and how I solved them** | ARCHITECTURE §9 register + PROGRESS narrative | 3–4 |
| Verification numbers (87/87 · 92/92 · 9/9 · 20/20 · 180/180 · r = 0.968) | README verification table | 1 |
| Correlation figure (analytic vs PFEM p61) | figures/analytic_vs_pfem_p61.png | 1 |
| Known limitations | HANDOVER §18 | 1 |
| Future work (this doc §2–§7) | ROADMAP.md | 1 |
| Q&A | – | 1 |

**Total**: ~30 slides. Fits a 30–40 minute presentation.

### 3.3 The "challenges" section is the differentiator

Matthias specifically asked for the *implementation process and main
challenges*. The best content for those slides is
[ARCHITECTURE §9 "Challenges solved (register)"](ARCHITECTURE.md#9-challenges-solved-register).
Highlights worth demoing:

- **B1–B6 build gotchas**: SIGSEGV in `formnf`, unallocated UMAT
  arrays, missing Lanczos routine, ARPACK linking, `libarpack.so.2`
  runtime.
- **R1–R4 run plumbing**: program vs dataset mismatch, unreliable
  build exit codes, missing book `.res` files, integer-parameter
  patching gotcha.
- **Q1–Q6 QoI extraction quirks**: multi-block `.res` files, split
  time-history blocks (p95, p96), multi-word headers, p118's missing
  iterations column, p69's free-text output, MATLAB `\b` regex bug.
- **S7–S9 stochastic / sensitivity**: solver-param sampling guard,
  eigenvalue-label misdiagnosis (`lambda_1` → `omega^2` fix), LHS
  marginals vs Iman–Conover correlation.
- **P14–P18 Phase-3-specific fixes**: `refresh_params` dropping
  tunables silently, non-PFEM YAML crashed pre-build,
  `out.elapsed_sec` guard, LaTeX interpreter warnings, locale decimal
  separator on bash external.

Each of those is a story that took real time to solve and is worth 1–2
minutes of presentation.

### 3.4 Recommended visuals

- **README screenshot**: shows the badges + logos at the top of the
  presentation deck.
- **GUI screenshot** at `presentation/abc/gui.png` (already used in
  README): shows the tool in action.
- **Mermaid diagrams** in HANDOVER §4 / ARCHITECTURE §5 render cleanly
  as static images if you use mermaid-cli (`mmdc`) to export SVG.
- **Correlation figure** `figures/analytic_vs_pfem_p61.png`: single most
  compelling numeric proof point.
- **Sample stochastic sweep output** — run the Prandtl demo preset and
  screenshot the three histograms.

### 3.5 Tools

Any of: PowerPoint, Keynote, Beamer (LaTeX), Google Slides, or a
markdown-to-PDF pipeline (marp, quarto). The existing
`presentation/main.tex` (Beamer) at commit `dfba883` is a starting
template.

### 3.6 Acceptance criteria

- A single deliverable (PDF or PPTX) in `presentation/` at repo root.
- Covers every row in §3.2 above.
- Explicit "how to run this yourself" appendix pointing at the GUI
  Prandtl-demo preset — so an audience member can reproduce the
  headline result.
- Committed to the repo (source + rendered) so it stays with the code.

---

## 4. Additional Phase 4 candidates

These were listed as Phase 4 in the original planning docs before Task A
took priority. Any of them is fair game as a next step after Task A.

| # | Item | Effort | Why interesting |
|---|---|---|---|
| **F1** | Mesh-refinement / convergence-rate mode — new sweep mode that varies `nxe`, `nye`, produces log-log convergence curves per case | ~half day + polish | Answers "does PFEM converge at the theoretical rate for each case type?" — natural research follow-up. |
| **F2** | Sobol variance-decomposition indices — beyond OAT tornado, quantifies main + interaction effects | ~half day | Publication-quality sensitivity analysis. |
| **F3** | FORM / SORM reliability method — analytic alternative to Monte Carlo for `P(FS<1)` | ~half day | Faster + smoother reliability estimates than raw MC; classic CRE-relevant method. |
| **F4** | Multi-fidelity sampling — mix cheap analytic evaluations with expensive PFEM runs, use analytic as control variate | multi-day | 10–100× effective sample count for the same PFEM cost. |
| **F5** | Response-surface / Gaussian-process surrogates | multi-day | Ties in directly with the chair's stated research focus. |
| **F6** | Bayesian updating — posterior over material parameters given observed field data | multi-day | Real applied research use case. |

---

## 5. Robustness / polish backlog

Small self-contained improvements. Any of these could be knocked out in
one session by the next contributor when they're familiarising themselves
with the codebase.

| # | Item | Effort | Payoff |
|---|---|---|---|
| **R1** | **`qoi_probe_node` YAML feature** — unlocks p51_3, p111, p811 for stochastic sensitivity (currently BC-bound, insensitive to material sampling). Add YAML field, extend `pfem_extract_qoi.m` to prefer that node when present. | ~2 h | 3–5 more PFEM cases become actually sampleable. See HANDOVER §18 item 1. |
| **R2** | Investigate the 1 PFEM overshoot in `verify_stochastic_backends` (one sample > 10 % over analytic). Look at the specific overrides, understand the physics, either fix or document. | ~30 min | Removes the "WARNING: 1 sample" noise. |
| **R3** | p69 embankment lift: only 7/10 LHS samples converge. Tighter solver tolerances or a smaller sampling envelope. | ~2 h | Enables slope-lift case in stochastic sweeps. |
| **P1** | `parfor` sample parallelisation in the stochastic path | ~1 h | 4–16× speedup on multi-core. |
| **P2** | Result caching by parameter hash — skip re-running identical overrides | ~1 h | Faster sensitivity + repeated sweeps. |
| **P3** | Skip cases whose enabled parameters are all absent from the YAML | ~30 min | Multi-case sweeps don't waste time on no-op runs. |
| **R4** | Progress bar with time estimate in the GUI log | ~30 min | UX. |

---

## 6. Documentation improvements

The `v1.0-phase3-complete` doc set is complete for a v1.0. Two nice
additions for a v1.1:

| # | Item | Effort |
|---|---|---|
| **D1** | Case-by-case guides — one short page per PFEM YAML explaining the physics + expected QoI range + a "typical stochastic sweep" recipe. 87 pages = big. | Multi-day; auto-generatable if approached template-first. |
| **D2** | Live scripts (`.mlx`) demoing each sweep mode with inline plots. | Half day. |

---

## 7. Software-engineering nice-to-haves

Deferred deliberately at v1.0 because they don't unblock the science.

| # | Item | Why deferred |
|---|---|---|
| **I1** | CI on GitHub Actions running the fast tests on every push | MATLAB Actions needs a licence configuration; sole-author repo doesn't benefit as much as a multi-contributor one. Add when a collaborator lands. |
| **I2** | Docker container with MATLAB Runtime + pre-built PFEM binaries | Large upfront work; users can already replicate the environment via `docs/SETUP.md`. Add when the project ships beyond the chair. |
| **I3** | Zenodo DOI for citation | 15-minute task if you decide to formally cite v1.0-phase3-complete in a paper. |

---

## 8. How to hand off if time runs out

If you (Naeem, or whoever picks this up) reach the end of the window
without finishing Task A:

1. **Commit whatever works, even in a rough state**, on a
   `wip-solver-isolation` branch. Push it. Don't wait for polish.
2. **Add a short section to this ROADMAP** under §2.6 explaining exactly
   where you stopped: what works, what doesn't, what the next person
   should try first.
3. **Update memory** at `~/.claude/projects/-home-cre-tu-Projects-fem-benchmarks/memory/project_state.md`
   with the same status update (if you're using Claude Code).
4. **Screen-record** or write out a 5-minute demo of what you've built
   so far — Naty explicitly asked for the documentation to survive,
   not necessarily the code being finished.
5. **Include a "Where I stopped" slide** in the Task B presentation
   with the same information — a supervisor rewatching after the
   handover date sees exactly what's ready and what's next.

The over-arching instruction from Naty:

> "Whatever is completed will be a very valuable contribution, and good
> documentation will ensure that all the work you have done remains
> useful for the Chair in the future."

Meet that bar. Everything else is a bonus.

---

<p align="center"><sub>
  <a href="https://github.com/NZ5253/fem-benchmarks">github.com/NZ5253/fem-benchmarks</a> ·
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> ·
  Naeem Zainuddin, Technische Universität Dortmund
</sub></p>
