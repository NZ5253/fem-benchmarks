# Adding a new analytic oracle

An oracle is a closed-form solution the framework uses as an independent
reference against PFEM (or against another backend). Phase 3 ships 9 of them
in [`analytic_backend.m`](../matlab/backends/analytic_backend.m); adding a
tenth takes about 15 minutes.

Use this when you find a benchmark case that has a textbook formula and you
want the framework to validate PFEM against theory - not just at defaults,
but under Monte Carlo, sensitivity, and correlated sampling.

## Step-by-step

1. **Pick a case type** the oracle covers - one of `slope_srf`,
   `plasticity_load`, `elastic_static`, `seepage_steady`, `consolidation`,
   `eigenvalue`, `dynamic_transient`, `thermal`, or something new.

2. **Add a `case` clause** inside `eval_model` in
   [`matlab/backends/analytic_backend.m`](../matlab/backends/analytic_backend.m).
   Example (bar in tension):

   ```matlab
   case 'my_new_model'
       P = fetch_param(y, overrides, 'force_P');
       L = fetch_param(y, overrides, 'length_L');
       A = fetch_param(y, overrides, 'area_A');
       E = fetch_param(y, overrides, 'youngs_modulus_E');
       q.label = 'u_max'; q.unit = 'm';
       if ~(guard_positive(L, 'length_L') && ...
            guard_positive(A, 'area_A')   && ...
            guard_positive(E, 'youngs_modulus_E')), return; end
       q.value = P * L / (A * E);
       q.ok    = true;
   ```

   Guards (`guard_positive`, `guard_nonneg`, `guard_bounded`) are helpers
   already defined; use them wherever the formula becomes singular. When
   they fire the QoI degrades cleanly (`ok = false, value = NaN`) instead
   of returning `Inf` or crashing the sweep.

3. **Write the YAML** under `benchmarks/analytic/my_new_model.yaml`:

   ```yaml
   id: analytic_my_new_model
   title: "One-line description of the closed form"
   purpose: >
     Two or three lines. State the formula, its assumptions, and the
     expected value at the defaults so a reader can verify by hand.
   authors:
     created_by: You
     reference: "Author (year), textbook chapter"
   runner:
     type: analytic
     model: my_new_model
   tunable_parameters:
     - name: force_P
       current_value: 2.0e4
       type: real
       unit: N
       description: "Axial force."
       suggested_range: [1.0e3, 2.0e5]
     # ... one entry per parameter your formula uses
   ```

   Use the standard PFEM parameter names where they overlap
   (`cohesion_c`, `friction_angle_phi`, `youngs_modulus_E`,
   `mass_per_length_rhoA`, `permeability_k_or_cv`, etc.) so YAMLs from
   different backends can share parameters in a single sweep.

4. **Add a row to
   [`test_all_analytic_oracles`](../matlab/tests/test_all_analytic_oracles.m)**
   with the hand-derived expected value:

   ```matlab
   'elastic_static',    'benchmarks/analytic/my_new_model.yaml',
                        2.0e4 * 1.0 / (1.0e-4 * 2.0e11),  'u_max';
   ```

   Run `test_all_analytic_oracles` - the new row should print `OK`.

5. **Add per-parameter rows to
   [`test_physics_sanity`](../matlab/tests/test_physics_sanity.m)**
   declaring the direction the QoI moves when each tunable is bumped:

   ```matlab
   'my_new_model.yaml',  'force_P',           2.0,   'up';
   'my_new_model.yaml',  'youngs_modulus_E',  2.0,   'down';
   ```

   Run `test_physics_sanity`. Every row you added must pass.

6. **Update
   [`test_all_cases_stochastic`](../matlab/tests/test_all_cases_stochastic.m)**
   to include the new YAML in the 18-case broad verification. One row
   picking a sensible parameter + distribution suffices.

7. **Cross-check against PFEM** (optional but strongly recommended). If a
   PFEM case exists that solves the same or a related problem, run a small
   sweep of both side by side and either add a new test file or extend
   [`plot_analytic_vs_pfem`](../matlab/tests/plot_analytic_vs_pfem.m).

8. **Update
   [`PHASE3_PLAN.md`](PHASE3_PLAN.md) Section 3** and
   [`HANDOVER.md`](HANDOVER.md) Section 6 file trees to mention the new
   YAML.

## Choosing a good oracle

- A **closed form** with an assumption set that matches (or bounds) the
  PFEM setup you want to validate against.
- **Numerically stable** across the parameter range you plan to sample.
  If the formula has a singularity (e.g., Vesic Nq at phi = 45), guard
  it explicitly.
- **Physically meaningful QoI** - the same label PFEM emits for that
  case type (`FS`, `P_lim`, `u_max`, `omega^2`, `Uav_end`, `T_max`,
  `h_max`, `u_peak`).
- **A single scalar output**. The framework's QoI dispatcher expects
  one number. Multi-QoI oracles are a separate feature.

## Anti-patterns

- **Do not encode empirical / regression fits** as oracles. The whole
  point of an oracle is that it's derivable from first principles.
- **Do not fold multiple formulas** into one model with `if/else`. Split
  into separate `case` blocks with distinct model names so each has a
  clean YAML and a clean test row.
- **Do not skip the physics-sanity row**. The oracle test asserts the
  value; the sanity test asserts the *direction* - those two together are
  what catches formula transcription errors.

## Reference

- Existing oracles for shape: [`analytic_backend.m` `eval_model` switch](../matlab/backends/analytic_backend.m)
- Existing YAML pattern: any file under [`benchmarks/analytic/`](../benchmarks/analytic/)
- Test row templates: [`test_all_analytic_oracles.m`](../matlab/tests/test_all_analytic_oracles.m) and [`test_physics_sanity.m`](../matlab/tests/test_physics_sanity.m)
