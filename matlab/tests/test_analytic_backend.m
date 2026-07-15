function ok = test_analytic_backend()
% TEST_ANALYTIC_BACKEND  Phase 3 M3 accuracy proof.
%
% Runs the analytic backend on benchmarks/analytic/prandtl_bearing.yaml with
% yield_stress = 100 kPa and asserts P_lim = (2 + pi) * 100. Then runs PFEM
% p61 through the same pfem_run_from_yaml entry point and asserts the two
% answers agree within 1% (5.14e2 vs PFEM's 515 -> 0.2 %).
%
% This is the M3 shippable: two independent backends producing the same
% number on a known problem. Fail-hard on any drift.

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    yaml_analytic = fullfile(repo_root, 'benchmarks/analytic/prandtl_bearing.yaml');
    yaml_p61      = fullfile(repo_root, 'benchmarks/pfem5/chap06/p61.yaml');

    fprintf('\n=== M3 Analytic backend cross-check =====================\n');

    % 1. Analytic path
    [st_a, out_a] = pfem_run_from_yaml(repo_root, pfem_root, yaml_analytic, struct());
    assert(st_a == 0, 'analytic run failed with status %d', st_a);
    y_a = pfem_yaml_load(yaml_analytic);
    b_a = get_backend(y_a);
    q_a = b_a.extract_qoi(out_a, '');
    p_analytic = q_a.value;
    fprintf('  analytic prandtl_bearing  P_lim = %.4f %s\n', p_analytic, q_a.unit);
    assert(abs(p_analytic - (2 + pi) * 100) < 1e-9, 'analytic formula drifted');

    % 2. PFEM path (p61 at default sigma_y = 100)
    [st_p, out_p] = pfem_run_from_yaml(repo_root, pfem_root, yaml_p61, struct());
    assert(st_p == 0, 'p61 run failed with status %d', st_p);
    y_p = pfem_yaml_load(yaml_p61);
    b_p = get_backend(y_p);
    q_p = b_p.extract_qoi(out_p, pfem_detect_case_type(y_p));
    p_pfem = q_p.value;
    fprintf('  pfem     p61              P_lim = %.4f %s\n', p_pfem, q_p.unit);

    % 3. Cross-check
    rel = abs(p_pfem - p_analytic) / p_analytic;
    fprintf('  relative discrepancy      %.4f %% (limit: 1.00 %%)\n', 100 * rel);
    assert(rel < 0.01, 'PFEM vs analytic disagree by %.2f %% (>1 %%)', 100 * rel);

    fprintf('=========================================================\n');
    fprintf('  M3 accuracy proof PASSED\n');
    fprintf('=========================================================\n\n');

    % ---------------------------------------------------------------------
    % Sensitivity through pfem_sensitivity_oat exercises b.extract_qoi
    % across baseline + low + high runs; this proves the M5-followup patch
    % (dispatching QoI extraction through the backend) actually works for
    % a non-PFEM YAML.
    % ---------------------------------------------------------------------
    fprintf('=== M5-followup: sensitivity on analytic backend ==========\n');
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    specs = struct('name', 'yield_stress', 'dist', 'uniform', ...
                   'mu', 100, 'cov', 0, 'bounds', [80, 120]);
    r = pfem_sensitivity_oat(repo_root, pfem_root, yaml_analytic, specs, ...
                             'Verbose', false);
    fprintf('  baseline (mean)  P_lim = %.4f  (expect %.4f)\n', ...
        r.qoi_baseline, (2 + pi) * 100);
    fprintf('  -1 sigma  (80)   P_lim = %.4f  (expect %.4f)\n', ...
        r.qoi_low(1),  (2 + pi) * 80);
    fprintf('  +1 sigma (120)   P_lim = %.4f  (expect %.4f)\n', ...
        r.qoi_high(1), (2 + pi) * 120);
    assert(abs(r.qoi_baseline - (2 + pi) * 100) < 1e-9, ...
        'sensitivity baseline drift');
    assert(abs(r.qoi_low(1)  - (2 + pi) * 80)  < 1e-9, ...
        'sensitivity low drift');
    assert(abs(r.qoi_high(1) - (2 + pi) * 120) < 1e-9, ...
        'sensitivity high drift');
    assert(strcmp(r.qoi_label, 'P_lim'), 'label lost: %s', r.qoi_label);
    fprintf('=========================================================\n');
    fprintf('  M5-followup sensitivity via b.extract_qoi PASSED\n');
    fprintf('=========================================================\n\n');
    ok = true;
end
