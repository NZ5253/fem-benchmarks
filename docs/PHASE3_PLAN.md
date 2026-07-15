# Phase 3 Plan — Pluggable Runner Interface

**Author**: Naeem Zainuddin
**Status**: COMPLETE. Original scope M0-M6 landed on `master` (`2f41407`);
follow-up coverage extension M7 landed on branch `phase3-complete-coverage`.
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
  get_backend.m        factory, default -> pfem
  pfem_backend.m       wraps the existing PFEM entry points
  analytic_backend.m   closed-form oracles (9 models, M3 + M7)
  external_backend.m   generic template runner (M4)
matlab/tests/
  capture_golden_qoi.m           writes golden_qoi.json for all 87 cases
  golden_qoi.json                checked-in reference values (M0)
  test_golden_qoi.m              the regression gate (M0)
  test_analytic_backend.m        prandtl_bearing vs PFEM p61 (M3)
  test_external_backend.m        external Python solver end-to-end (M4)
  test_all_analytic_oracles.m    9-row matrix, one per case type (M7)
  test_stochastic_gate.m         fixed-seed histogram moments locked (M7)
  test_physics_sanity.m          per-case-type monotonicity (M7)
  verify_stochastic_backends.m   post-hoc numeric certificate for a live sweep
benchmarks/analytic/
  prandtl_bearing.yaml           (2+pi)*sigma_y                 plasticity Tresca
  prandtl_terzaghi.yaml          c*Nc + 0.5*gamma*B*Ng          plasticity MC
  bar_elongation.yaml            P*L/(A*E)                      elastic
  ss_beam_eigen.yaml             (pi/L)^4 * EI/(rhoA)           eigenvalue
  sdof_step.yaml                 2*F/k                          dynamic transient
  terzaghi_1d.yaml               Uav(Tv) series                 consolidation
  slab_heat_gen.yaml             Ts + qgen*L^2/(8k)             thermal
  strip_seepage.yaml             h0 + N*L^2/(8k)                seepage
  infinite_slope.yaml            c/(gamma*H*sin*cos) + tan(phi)/tan(beta)  slope_srf
benchmarks/external/
  prandtl.py + prandtl_input.tmpl + prandtl_external.yaml  Python-solver fixture (M4)
```

## 4. Milestones (each shippable, each gated by the golden test)

| # | Milestone | Commit | Gate result |
|---|-----------|--------|-------------|
| M0 | **Golden net**: capture QoI for all 87 at defaults + 5 override probes; `test_golden_qoi.m` asserts equality | `9d35e4f` | 92/92 baseline |
| M1 | **Extract `pfem_backend`**; `pfem_run_from_yaml` delegates to it (pure refactor) | `84b00f8` | 92/92 golden |
| M2 | **Factory + `runner.type` key** (absent -> pfem) | `a9d085b` | 92/92 golden |
| M3 | **Analytic oracle** (`prandtl_bearing`: `P_lim=(2+pi) sigma_y`) + cross-check vs PFEM p61 (assert < 1 %) | `a94a5d5` | analytic 514.16 vs PFEM 515: 0.16 % (< 1 %); 92/92 golden |
| M4 | **Generic external backend** (input template + command + output-parse spec), validated on a small known-answer program | `bb72d11` | Python Prandtl solver: 4 assertions exact + 0.16 % cross-check; 92/92 golden |
| M5 | **Surface in GUI/modes**; convert the stochastic solver/mesh guard to `b.non_sampleable(y)` | `4b7bab8` | 92/92 golden; GUI opens/closes cleanly |
| M6 | **Docs**: update ARCHITECTURE.md, HANDOVER.md, this plan | `2f41407` | handover stays current |
| M7 | **Coverage extension**: 8 analytic models (one per PFEM case type), stochastic-mode regression gate, per-case-type physics-sanity suite, backend-persisted run directories | branch `phase3-complete-coverage` | oracle matrix 9/9, stochastic gate 2/2, monotonicity 20/20, golden 92/92 |

After M3 there was a working two-backend pluggable system with an accuracy
proof. M4 delivered the stretch goal (arbitrary codes plug in via YAML
alone). M7 made "complete" concrete by adding an independent oracle for
every one of the 8 physical case types and locking the stochastic pipeline
against future regressions.

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

## 8. Current status

**M0-M7 complete.** The framework has an independent analytic oracle for
every one of the 8 physical case types, the stochastic pipeline is
regression-locked at fixed seed, and every future refactor is gated at
four levels:

| Gate | Locks | Runtime |
|---|---|---|
| `test_golden_qoi` (M0) | Per-run QoI value for 87 defaults + 5 override probes | ~5 min |
| `test_all_analytic_oracles` (M7) | Each closed-form matches its own physics | <1 s |
| `test_stochastic_gate` (M7) | Histogram mean/std/min/max on a 100-sample LHS sweep, fixed seed | ~2 s |
| `test_physics_sanity` (M7) | Monotonicity direction of the QoI wrt each tunable, per case type | <1 s |

Every legacy YAML in `benchmarks/pfem5/chap*/` still runs unmodified; the
optional `runner:` key is absent on all 87 of them.
