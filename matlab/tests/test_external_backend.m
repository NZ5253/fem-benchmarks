function ok = test_external_backend()
% TEST_EXTERNAL_BACKEND  Phase 3 M4 gate.
%
% Exercises the generic external backend end-to-end on the
% benchmarks/external/prandtl_external.yaml fixture (a small Python solver
% that computes Prandtl bearing capacity). Verifies:
%
%   1. Default run: P_lim matches (2 + pi) * 100 exactly (the mechanism only
%      involves template substitution + shell exec + regexp parse, so any
%      drift here is a plumbing bug).
%   2. Override runs: yield_stress = 200 and 400 propagate through the
%      template into the Python solver and back.
%   3. Cross-check against PFEM p61: external solver's answer at defaults
%      agrees with PFEM p61 within 1 %.
%
% Failure of any step is a hard error.

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    yaml_ext = fullfile(repo_root, 'benchmarks/external/prandtl_external.yaml');
    yaml_p61 = fullfile(repo_root, 'benchmarks/pfem5/chap06/p61.yaml');

    fprintf('\n=== M4 External backend gate =============================\n');

    % 1. Default
    [st, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_ext, struct());
    assert(st == 0, 'external default run failed with status %d', st);
    b = get_backend(pfem_yaml_load(yaml_ext));
    q = b.extract_qoi(out, '');
    fprintf('  default   yield_stress=100  P_lim = %.4f %s\n', q.value, q.unit);
    assert(abs(q.value - (2 + pi) * 100) < 1e-9, ...
        'default drift: got %.10g, expected %.10g', q.value, (2 + pi) * 100);
    assert(strcmp(q.label, 'P_lim'), 'label drift: got "%s"', q.label);
    assert(strcmp(q.unit,  'kPa'),   'unit drift: got "%s"',  q.unit);

    % 2a. Override sigma_y = 200
    [st, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_ext, ...
        struct('yield_stress', 200));
    assert(st == 0);
    q2 = b.extract_qoi(out, '');
    fprintf('  override  yield_stress=200  P_lim = %.4f %s\n', q2.value, q2.unit);
    assert(abs(q2.value - (2 + pi) * 200) < 1e-9, ...
        'override 200 drift: got %.10g', q2.value);

    % 2b. Override sigma_y = 400
    [st, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_ext, ...
        struct('yield_stress', 400));
    assert(st == 0);
    q4 = b.extract_qoi(out, '');
    fprintf('  override  yield_stress=400  P_lim = %.4f %s\n', q4.value, q4.unit);
    assert(abs(q4.value - (2 + pi) * 400) < 1e-9, ...
        'override 400 drift: got %.10g', q4.value);

    % 3. Cross-check against PFEM p61 at defaults
    [st, out_p] = pfem_run_from_yaml(repo_root, pfem_root, yaml_p61, struct());
    assert(st == 0);
    bp = get_backend(pfem_yaml_load(yaml_p61));
    qp = bp.extract_qoi(out_p, pfem_detect_case_type(pfem_yaml_load(yaml_p61)));
    fprintf('  pfem      p61 default       P_lim = %.4f %s\n', qp.value, qp.unit);
    rel = abs(qp.value - q.value) / q.value;
    fprintf('  external vs PFEM p61        rel   = %.4f %% (limit 1 %%)\n', 100 * rel);
    assert(rel < 0.01, 'PFEM vs external disagree by %.2f %% (>1 %%)', 100 * rel);

    fprintf('=========================================================\n');
    fprintf('  M4 external backend PASSED\n');
    fprintf('=========================================================\n\n');
    ok = true;
end
