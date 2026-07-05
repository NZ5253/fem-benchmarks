# Phase 3 Plan — Pluggable Runner Interface

**Author**: Naeem Zainuddin
**Status**: scaffolding in progress on branch `phase3-pluggable-runner`
**Goal**: let non-PFEM codes plug into the same probabilistic / sensitivity
framework, without changing the behaviour of any existing (legacy) mode and
while staying accurate for every case.

Read [ARCHITECTURE.md](ARCHITECTURE.md) first for how the pipeline works today.

---

## 1. Why this is tractable

Every mode (deterministic sweep, Monte Carlo, LHS, correlated sampling,
sensitivity) funnels through ONE run choke point, `pfem_run_from_yaml.m`, and
one QoI dispatcher, `pfem_extract_qoi.m`. If only that seam becomes
backend-aware, every mode inherits pluggability for free.

## 2. The backend contract (struct of function handles)

A backend is a struct produced by a constructor. PFEM is the first
implementation; new codes are others. Decided representation: **struct of
function handles** (matches the repo's function-based style; no OO overhead).

```matlab
b.name           = 'pfem';
b.run            = @(ctx, y, overrides) ...;   % write input, execute -> [status, out]
b.extract_qoi    = @(out, case_type) ...;      % parse the QoI from the output
b.non_sampleable = @(y) { ... };               % params the stochastic guard must skip
```

- `ctx` carries `repo_root`, `pfem_root`, `yaml_path`.
- `out` must expose `run_dir`, `case`, and `files` (cell of output paths) so
  the existing extractor helpers keep working.
- A backend that produces its answer directly (e.g. analytic) may return the
  QoI inside `out.qoi` and set `b.extract_qoi = @(out,~) out.qoi`.

### Factory and YAML key

`get_backend(y)` reads a new optional YAML key and defaults to `pfem`:

```yaml
runner:              # ABSENT on all 87 legacy cases -> defaults to pfem
  type: analytic
  model: prandtl_bearing
```

`pfem_run_from_yaml.m` keeps its exact signature; internally (milestone M1) it
will do `b = get_backend(y)` and call the handles. Every caller stays unchanged.

## 3. File layout

```
matlab/backends/
  README.md            contract + status
  get_backend.m        factory, default -> pfem
  pfem_backend.m       wraps the existing PFEM entry points
  analytic_backend.m   closed-form oracle (M3)
  external_backend.m   generic template runner (M4, later)
matlab/tests/
  capture_golden_qoi.m writes golden_qoi.json for all 87 cases
  golden_qoi.json      checked-in reference values (generated on a good tree)
  test_golden_qoi.m    the regression gate
```

## 4. Milestones (each shippable, each gated by the golden test)

| # | Milestone | Guarantee |
|---|-----------|-----------|
| M0 | **Golden net**: capture QoI (value+label) for all 87 at defaults + a few override points; `test_golden_qoi.m` asserts equality | the "don't break legacy / accurate for all" gate |
| M1 | **Extract `pfem_backend`**; `pfem_run_from_yaml` delegates to it (pure refactor) | golden test passes identically |
| M2 | **Factory + `runner.type` key** (absent -> pfem) | legacy YAMLs need zero edits |
| M3 | **Analytic oracle** (`prandtl_bearing`: `P_lim=(2+pi) sigma_y`) + cross-check vs PFEM p61 (515 vs 514, assert < 1%) | proves a non-PFEM backend is accurate against two independent references |
| M4 | **Generic external backend** (input template + command + output-parse spec), validated on a small known-answer program | reaches the goal: any code that reads input, writes output |
| M5 | **Surface in GUI/modes**; convert the stochastic solver/mesh guard to `b.non_sampleable(y)` | all modes get pluggability; guard identical for PFEM |
| M6 | **Docs + tests**: update the ARCHITECTURE pipeline diagram with the backend layer | handover stays current |

After M3 there is a working two-backend pluggable system with an accuracy
proof. M4 is the stretch to arbitrary codes.

## 5. The two guardrails, concretely

**Legacy untouched**
- default `runner = pfem`; unchanged `pfem_run_from_yaml` signature
- M0 golden test asserted after M1, M2, M5
- feature branch, gated by `run_all_tests.py` + `test_golden_qoi.m`
- the one PFEM-specific assumption to abstract: the stochastic guard becomes
  `b.non_sampleable(y)` (PFEM's list stays identical)

**Accurate for all**
- M0 golden net covers the 87 PFEM cases
- every new backend ships its own validated extractor and is cross-checked
  against an independent oracle (a PFEM run and/or closed form) on
  known-answer problems before it is trusted

## 6. golden_qoi.json schema

```json
{
  "meta": { "captured": "YYYY-MM-DD", "commit": "<sha>", "n_cases": 87 },
  "cases": [
    { "case": "p61", "yaml": "benchmarks/pfem5/chap06/p61.yaml",
      "overrides": {}, "case_type": "plasticity_load",
      "value": 515.0, "label": "P_lim", "unit": "kPa", "ok": true }
  ]
}
```

`test_golden_qoi.m` re-runs each recorded case, and asserts: `case_type` and
`label` match exactly, `ok` matches, and `value` matches within a small
relative tolerance (PFEM is deterministic).

## 7. Sequencing note (important)

M0 and M1 need MATLAB and built PFEM binaries, so they run **on the
workstation after the pending git reconciliation** (see the workstation-sync
memory). Do not branch the behaviour-changing work off an unmerged tree.

Order of operations when back on the workstation:
1. reconcile `master` with the workstation's local edits, verify
2. `git checkout phase3-pluggable-runner` (this branch), rebase onto the
   reconciled master if needed
3. run `capture_golden_qoi` once to generate `golden_qoi.json` (M0)
4. proceed M1 -> M6, running `test_golden_qoi` after each behaviour-touching step

## 8. Current status (this branch)

Only this plan document is committed so far. The code was deliberately NOT
written blind: every code milestone (M0 golden harness onward) needs MATLAB
and built PFEM binaries to verify, which only exist on the workstation. So the
first workstation coding task is to create the scaffolding described in
Sections 2-3 (all inert, additive, `master` behaviour unchanged) and generate
`golden_qoi.json` before any refactor.
