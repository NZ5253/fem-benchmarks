function ok = test_all_cases_stochastic(varargin)
% TEST_ALL_CASES_STOCHASTIC  Broad per-case verification.
%
% For each PFEM representative (one per case type), each of the 9 analytic
% YAMLs, and the external YAML, run a 10-sample stochastic sweep of the
% case's primary parameter through pfem_run_from_yaml -> get_backend and
% assert every sample returns a valid QoI. This is the coverage-across-
% cases counterpart to test_golden_qoi (which is coverage-across-values
% for PFEM only).
%
% Prints a per-case OK/N summary. Fails hard if any case has zero OK
% samples.
%
% Usage:
%   test_all_cases_stochastic()          n = 10 samples, seed = 42
%   test_all_cases_stochastic('N', 30)

    p = inputParser;
    addParameter(p, 'N',    10);
    addParameter(p, 'Seed', 42);
    parse(p, varargin{:});
    n = p.Results.N; seed = p.Results.Seed;

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    % yaml (relative), primary parameter, dist, mu, cov
    checks = {
      % PFEM: one per case type. Parameter chosen to actually vary the QoI.
      'benchmarks/pfem5/chap06/p61.yaml',            'yield_stress',            'lognormal', 100,   0.2;
      'benchmarks/pfem5/chap06/p612.yaml',           'cohesion_c',              'lognormal', 60,    0.2;
      'benchmarks/pfem5/chap05/p51_3.yaml',          'youngs_modulus_E',        'lognormal', 1e6,   0.2;
      'benchmarks/pfem5/chap07/p71_1.yaml',          'permeability_k_or_cv',    'lognormal', 1e-3,  0.3;
      'benchmarks/pfem5/chap08/p81_5.yaml',          'permeability_k_or_cv',    'lognormal', 1e-3,  0.3;
      'benchmarks/pfem5/chap10/p101.yaml',           'stiffness_E_or_EI',       'lognormal', 0.0833,0.2;
      'benchmarks/pfem5/chap11/p111.yaml',           'youngs_modulus_E',        'lognormal', 1e6,   0.2;
      'benchmarks/pfem5/chap08/p811.yaml',           'permeability_k_or_cv',    'lognormal', 1e-3,  0.3;
      % Analytic
      'benchmarks/analytic/prandtl_bearing.yaml',    'yield_stress',            'lognormal', 100,   0.3;
      'benchmarks/analytic/prandtl_terzaghi.yaml',   'cohesion_c',              'lognormal', 10,    0.3;
      'benchmarks/analytic/bar_elongation.yaml',     'force_P',                 'lognormal', 2e4,   0.3;
      'benchmarks/analytic/ss_beam_eigen.yaml',      'stiffness_E_or_EI',       'lognormal', 0.0833,0.3;
      'benchmarks/analytic/sdof_step.yaml',          'force_F',                 'lognormal', 1000,  0.3;
      'benchmarks/analytic/terzaghi_1d.yaml',        'time_factor_Tv',          'lognormal', 0.2,   0.3;
      'benchmarks/analytic/slab_heat_gen.yaml',      'heat_generation_qgen',    'lognormal', 1e5,   0.3;
      'benchmarks/analytic/strip_seepage.yaml',      'recharge_N',              'lognormal', 1e-6,  0.3;
      'benchmarks/analytic/infinite_slope.yaml',     'cohesion_c',              'lognormal', 5,     0.3;
      % External
      'benchmarks/external/prandtl_external.yaml',   'yield_stress',            'lognormal', 100,   0.3;
    };

    fprintf('\n=== BROAD PER-CASE STOCHASTIC (n=%d per case, %d cases) ==\n', n, size(checks, 1));
    fprintf('  %-42s  %-24s  %s\n', 'yaml', 'param, dist', 'samples OK / n (qoi range)');
    fprintf('  %-42s  %-24s  %s\n', '----', '-----------', '-----------------------------------');

    total_ok = 0; total_n = 0; failed = {};
    t_start = tic;

    for i = 1:size(checks, 1)
        [yaml_rel, pname, dist, mu, cov] = deal(checks{i, :});
        yaml_path = fullfile(repo_root, yaml_rel);

        spec = struct('name', pname, 'dist', dist, 'mu', mu, 'cov', cov, 'bounds', []);
        samples = pfem_lhs_sample(spec, n, 'Seed', seed);

        y = pfem_yaml_load(yaml_path);
        case_type = pfem_detect_case_type(y);
        b = get_backend(y);

        qvals = NaN(n, 1);
        for k = 1:n
            ov = struct(); ov.(pname) = samples(k);
            try
                [st, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, ov);
                if st == 0
                    q = b.extract_qoi(out, case_type);
                    if q.ok, qvals(k) = q.value; end
                end
            catch ME
                % Store nothing, count as fail
            end
        end

        n_ok = sum(~isnan(qvals));
        total_ok = total_ok + n_ok;
        total_n  = total_n + n;

        [~, stem] = fileparts(yaml_rel);
        qrange = '(none)';
        if n_ok > 0
            qrange = sprintf('[%.4g, %.4g]', min(qvals(~isnan(qvals))), max(qvals(~isnan(qvals))));
        end
        pdstring = sprintf('%s ~ %s', pname, dist);
        status = sprintf('%2d / %d  %s', n_ok, n, qrange);
        fprintf('  %-42s  %-24s  %s\n', stem, pdstring, status);

        if n_ok == 0, failed{end+1} = stem; end %#ok<AGROW>
    end

    fprintf('  ---\n  TOTAL: %d / %d samples across %d cases in %.1f s\n', ...
        total_ok, total_n, size(checks, 1), toc(t_start));
    if ~isempty(failed)
        fprintf('  FAILED cases (0 OK samples): %s\n', strjoin(failed, ', '));
    end
    fprintf('==========================================================\n');
    ok = isempty(failed);
    if ~ok, error('test_all_cases_stochastic: %d cases had zero successful samples', numel(failed)); end
end
