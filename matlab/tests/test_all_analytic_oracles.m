function ok = test_all_analytic_oracles()
% TEST_ALL_ANALYTIC_ORACLES  Verify each analytic oracle YAML at its default
% parameters against an independent hand-derived closed-form value.
%
% One row per case type in the framework. Failure of any row means the
% analytic backend disagrees with the physics it claims to encode.

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    fprintf('\n=== Analytic oracle matrix (case type -> closed form) ====\n');

    rows = {
        %  case_type          yaml                                    expected            label
        'plasticity_load',   'benchmarks/analytic/prandtl_bearing.yaml',   (2 + pi) * 100,        'P_lim';
        'plasticity_load',   'benchmarks/analytic/prandtl_terzaghi.yaml',  mc_prandtl(10, 30, 20, 1), 'q_ult';
        'elastic_static',    'benchmarks/analytic/bar_elongation.yaml',    2e4 * 1 / (1e-4 * 2e11),  'u_max';
        'eigenvalue',        'benchmarks/analytic/ss_beam_eigen.yaml',     (pi/4)^4 * 0.08333 / 1,   'omega^2';
        'dynamic_transient', 'benchmarks/analytic/sdof_step.yaml',         2 * 1000 / 1e5,           'u_peak';
        'consolidation',     'benchmarks/analytic/terzaghi_1d.yaml',       terzaghi_uav(0.2),        'Uav_end';
        'thermal',           'benchmarks/analytic/slab_heat_gen.yaml',     300 + 1e5 * 0.1^2 / (8 * 10), 'T_max';
        'seepage_steady',    'benchmarks/analytic/strip_seepage.yaml',     10 + 1e-6 * 1000^2 / (8 * 1e-3), 'h_max';
        'slope_srf',         'benchmarks/analytic/infinite_slope.yaml',    infslope_fs(5, 25, 20, 5, 20), 'FS';
    };

    n_pass = 0; failures = 0;
    fprintf('  %-20s %-35s %-14s %-14s %s\n', 'case_type', 'model', 'expected', 'observed', 'label');
    fprintf('  %-20s %-35s %-14s %-14s %s\n', '---------', '-----', '--------', '--------', '-----');
    for i = 1:size(rows, 1)
        case_type = rows{i, 1};
        yaml_path = fullfile(repo_root, rows{i, 2});
        expected  = rows{i, 3};
        exp_label = rows{i, 4};

        y = pfem_yaml_load(yaml_path);
        b = get_backend(y);
        assert(strcmp(b.name, 'analytic'), 'yaml %s did not route to analytic', yaml_path);
        ctx = struct('repo_root', repo_root, 'pfem_root', pfem_root, 'yaml_path', yaml_path);
        [st, out] = b.run(ctx, y, struct());
        assert(st == 0);
        q = b.extract_qoi(out, case_type);

        rel = abs(q.value - expected) / max(abs(expected), realmin);
        fprintf('  %-20s %-35s %-14.6g %-14.6g %s', case_type, y.runner.model, ...
            expected, q.value, q.label);
        if rel < 1e-6 && strcmp(q.label, exp_label)
            fprintf('  OK\n');
            n_pass = n_pass + 1;
        else
            fprintf('  FAIL (rel=%.2e, label=%s vs %s)\n', rel, q.label, exp_label);
            failures = failures + 1;
        end
    end

    fprintf('----------------------------------------------------------\n');
    fprintf('  %d / %d oracles agree with hand-derived formula\n', ...
        n_pass, size(rows, 1));
    fprintf('==========================================================\n');
    ok = (failures == 0);
    if ~ok, error('test_all_analytic_oracles: %d oracle mismatches', failures); end
end


function q = mc_prandtl(c, phi_deg, gamma, B)
    phi = phi_deg * pi / 180;
    Nq = exp(pi * tan(phi)) * tan(pi/4 + phi/2)^2;
    Nc = (Nq - 1) * (cos(phi)/sin(phi));
    Ng = 2 * (Nq + 1) * tan(phi);
    q = c * Nc + 0.5 * gamma * B * Ng;
end


function Uav = terzaghi_uav(Tv)
    Uav = 1;
    for m = 0:100
        M = (2*m + 1) * pi / 2;
        Uav = Uav - (2/M^2) * exp(-M^2 * Tv);
    end
end


function FS = infslope_fs(c, phi_deg, gamma, H, beta_deg)
    phi = phi_deg * pi / 180; b = beta_deg * pi / 180;
    FS = c / (gamma * H * sin(b) * cos(b)) + tan(phi) / tan(b);
end
