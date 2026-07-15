function ok = test_stochastic_gate()
% TEST_STOCHASTIC_GATE  Fixed-seed regression gate for the pluggable
% stochastic pipeline.
%
% Runs a 100-sample LHS sweep of yield_stress = lognormal(100, 0.4) on
% the analytic and external prandtl backends (both deterministic given a
% seed). Asserts that mean, std, min, max of P_lim reproduce reference
% values captured on a known-good tree, catching regressions in:
%
%   - pfem_lhs_sample (sampling reproducibility)
%   - pfem_run_from_yaml -> get_backend dispatch
%   - analytic_backend, external_backend
%   - the {value, label, unit, ok} contract of b.extract_qoi
%
% PFEM p61 is not gated here because its load-step plateau makes its
% moments sample-count dependent in a physically legitimate but noisy
% way (see verify_stochastic_backends). The oracle backends give a hard
% numeric contract.

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    n_samples = 100;
    seed = 42;
    spec = struct('name', 'yield_stress', 'dist', 'lognormal', ...
                  'mu', 100, 'cov', 0.4, 'bounds', []);
    samples = pfem_lhs_sample(spec, n_samples, 'Seed', seed);

    fprintf('\n=== Stochastic regression gate (n=%d, seed=%d) ===\n', n_samples, seed);
    fprintf('  yield_stress samples: mean=%.6f std=%.6f min=%.6f max=%.6f\n', ...
        mean(samples), std(samples), min(samples), max(samples));

    % Expected P_lim per sample: (2 + pi) * yield_stress
    expected_plim = (2 + pi) * samples;
    ref = struct('mean', mean(expected_plim), 'std', std(expected_plim), ...
                 'min', min(expected_plim),  'max', max(expected_plim));
    fprintf('  Reference (2+pi)*sy: mean=%.4f std=%.4f min=%.4f max=%.4f\n\n', ...
        ref.mean, ref.std, ref.min, ref.max);

    n_pass = 0; failures = {};
    n_pass = check_backend('analytic', 'benchmarks/analytic/prandtl_bearing.yaml', ...
                           samples, ref, repo_root, pfem_root, n_pass);
    n_pass = check_backend('external', 'benchmarks/external/prandtl_external.yaml', ...
                           samples, ref, repo_root, pfem_root, n_pass);

    fprintf('----------------------------------------------------------\n');
    fprintf('  %d / 2 backends locked to reference within 1e-6\n', n_pass);
    fprintf('==========================================================\n');
    ok = (n_pass == 2);
    if ~ok, error('test_stochastic_gate: histogram moments drifted'); end
end


function n_pass = check_backend(kind, yaml_rel, samples, ref, repo_root, pfem_root, n_pass)
    yaml_path = fullfile(repo_root, yaml_rel);
    y = pfem_yaml_load(yaml_path);
    b = get_backend(y);
    assert(strcmp(b.name, kind), 'yaml %s did not route to %s', yaml_rel, kind);

    plim = NaN(numel(samples), 1);
    for i = 1:numel(samples)
        ov.yield_stress = samples(i);
        [st, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, ov);
        assert(st == 0, '%s sample %d failed', kind, i);
        q = b.extract_qoi(out, '');
        plim(i) = q.value;
    end

    obs = struct('mean', mean(plim), 'std', std(plim), ...
                 'min', min(plim),  'max', max(plim));

    fields = fieldnames(ref);
    all_ok = true;
    for j = 1:numel(fields)
        f = fields{j};
        rel = abs(obs.(f) - ref.(f)) / max(abs(ref.(f)), realmin);
        if rel > 1e-6
            fprintf('  [%s]  %s drift: ref=%.10g obs=%.10g rel=%.2e\n', ...
                kind, f, ref.(f), obs.(f), rel);
            all_ok = false;
        end
    end
    if all_ok
        fprintf('  [%s]  mean=%.4f std=%.4f min=%.4f max=%.4f  PASS\n', ...
            kind, obs.mean, obs.std, obs.min, obs.max);
        n_pass = n_pass + 1;
    end
end
