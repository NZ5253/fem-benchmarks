<p align="center">
  <img src="figures/tudortmund_logo.svg" alt="Technische Universität Dortmund" height="60">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="figures/cre_logo.png" alt="Chair for Reliability Engineering (CRE)" height="60">
</p>

<h1 align="center">Adding a new backend</h1>

<p align="center">
  <sub>Contributor tutorial · ~30 minutes if the solver already exists<br>
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> · <a href="ARCHITECTURE.md">ARCHITECTURE.md</a> · <a href="adding_an_oracle.md">adding_an_oracle.md</a></sub>
</p>

---

A backend teaches the framework how to run *one kind* of solver end-to-end
(PFEM, an analytic formula, a Python subprocess, an Abaqus job, ...). Phase 3
ships three: [`pfem_backend`](../matlab/backends/pfem_backend.m),
[`analytic_backend`](../matlab/backends/analytic_backend.m), and
[`external_backend`](../matlab/backends/external_backend.m). Adding a fourth
takes ~30 minutes if the solver already exists.

## Contract

A backend is a struct of function handles produced by a constructor. The
minimum shape is:

```matlab
function b = my_backend()
    b.name           = 'my';
    b.run            = @(ctx, y, overrides) [status, out];
    b.extract_qoi    = @(out, case_type)    qoi_struct;
    b.non_sampleable = @(y)                 cell_of_param_names;
end
```

Where:

| Field | Meaning |
|---|---|
| `name` | Short identifier used in the log and the `runner.type` YAML key |
| `run` | Executes one sample. `ctx` has `repo_root`, `pfem_root`, `yaml_path`. `y` is the loaded YAML. `overrides` is a struct of `{param_name -> value}`. Returns `status` (0 on success) and `out` (see below). |
| `extract_qoi` | Given the `out` returned by `run` and a `case_type` string, returns a QoI struct with fields `value`, `label`, `unit`, `ok`. For backends that produce the QoI directly (analytic, external), use the passthrough `@(out, ~) out.qoi`. |
| `non_sampleable` | Returns a cell of parameter names the stochastic guard must skip for this backend. PFEM returns solver / mesh names; analytic and external return `{}`. |

The `out` struct **must** expose `run_dir`, `case`, `files` so the existing
plotting / cache helpers work.

## Step-by-step

1. **Create the backend file** in [matlab/backends/](../matlab/backends/):

   ```
   matlab/backends/my_backend.m
   ```

   Copy the shape from [`analytic_backend.m`](../matlab/backends/analytic_backend.m).

2. **Wire the factory**. Open
   [`matlab/backends/get_backend.m`](../matlab/backends/get_backend.m) and add
   a case:

   ```matlab
   case 'my'
       b = my_backend();
   ```

3. **Add a `non_sampleable` list** if any of your backend's parameters would
   destabilise it if sampled stochastically (solver tolerances, integer
   flags). For most non-PFEM backends this is `{}`.

4. **Persist run artifacts** if the backend produces useful files. The
   pattern is:

   ```matlab
   if isfield(ctx, 'repo_root') && ~isempty(ctx.repo_root)
       run_dir = fullfile(ctx.repo_root, 'runs', b.name, yaml_stem, param_key(overrides));
       mkdir(run_dir);
       save(fullfile(run_dir, 'results.mat'), 'q', 'overrides');
       out.run_dir = run_dir;
       out.files   = {fullfile(run_dir, 'results.mat')};
   end
   ```

   This makes the backend visible in the GUI's Results table and lets
   `generate_report` include it.

5. **Write one benchmark YAML** for a known-answer problem the backend can
   solve:

   ```yaml
   id: my_bench_1
   title: "One-line description"
   authors:
     created_by: You
   runner:
     type: my
     model: name_of_your_first_model   # optional; useful if backend supports multiple
   tunable_parameters:
     - name: some_param
       current_value: 100.0
       type: real
       unit: kPa
       suggested_range: [10.0, 1000.0]
   ```

   Save it under `benchmarks/my/`.

6. **Add a cross-check test** at
   [`matlab/tests/test_my_backend.m`](../matlab/tests/). Run the backend
   at defaults through `pfem_run_from_yaml` (not the backend directly - you
   want to exercise the full dispatch chain via `get_backend`) and assert
   the returned QoI matches a hand-derived value. Also test at least one
   override to exercise the plumbing.

7. **Update the physics-sanity matrix** in
   [`matlab/tests/test_physics_sanity.m`](../matlab/tests/test_physics_sanity.m)
   with a row per tunable declaring the expected direction of the QoI when
   the parameter is bumped.

8. **Verify** you did not break anything:

   ```matlab
   test_golden_qoi           % 92/92 must remain unchanged
   test_all_analytic_oracles % pre-existing 9/9 unchanged
   test_stochastic_gate      % analytic + external unchanged
   test_physics_sanity       % 20+ rows including your new ones
   test_my_backend           % the one you just wrote
   ```

9. **Update [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)** Section 3 and
   [`docs/HANDOVER.md`](HANDOVER.md) Section 6 to mention the new backend.

## Gotchas

- **Do not modify** `pfem_backend.m`. That is the golden-locked path.
- **Do not touch** the guard in `pfem_sweep_gui.m/is_non_sampleable`. It
  already asks each loaded case's backend for its non_sampleable list, so
  your new backend automatically contributes to the union.
- If your backend runs a subprocess, force `LC_ALL=C` in the command (or
  in the solver script) so decimal separators are always `.` regardless of
  the user's locale.
- For deterministic backends (analytic, formula-only), make sure the same
  `overrides` always produces the same output - the stochastic gate at
  fixed seed relies on this.

## Reference

- The struct-of-function-handles contract is documented in
  [PHASE3_PLAN.md Section 2](PHASE3_PLAN.md).
- `pfem_backend.m` is the reference implementation for a persistent
  filesystem-heavy backend.
- `analytic_backend.m` is the reference implementation for an in-process
  backend.
- `external_backend.m` shows how to shell out to any executable.

---

<p align="center"><sub>
  <a href="https://github.com/NZ5253/fem-benchmarks">github.com/NZ5253/fem-benchmarks</a> ·
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> ·
  Naeem Zainuddin, Technische Universität Dortmund
</sub></p>
