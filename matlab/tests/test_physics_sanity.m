function ok = test_physics_sanity()
% TEST_PHYSICS_SANITY  Per-case-type physical-scaling assertions.
%
% For every case type in the framework we know some qualitative
% relationships that must hold: yield_stress up -> P_lim up, EI up ->
% omega^2 up, k up -> Uav_end up (faster consolidation), c up -> FS up,
% etc. This test bumps one parameter at a time on the analytic YAMLs
% and asserts the QoI moves in the correct direction.
%
% These are cheap (one analytic evaluation each) but very effective at
% catching sign flips, off-by-one bugs and formula transcription errors.

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    fprintf('\n=== Physics sanity (monotonicity) matrix ================\n');

    % Each row: yaml, base_overrides, param_to_bump, factor, direction
    % 'up' means Q(bumped) > Q(base); 'down' means Q(bumped) < Q(base).
    checks = { ...
      % --- plasticity_load (Tresca) ---
      'prandtl_bearing.yaml',   'yield_stress',           2.0,   'up';
      % --- plasticity_load (MC) ---
      'prandtl_terzaghi.yaml',  'cohesion_c',             2.0,   'up';
      'prandtl_terzaghi.yaml',  'friction_angle_phi',     1.5,   'up';
      'prandtl_terzaghi.yaml',  'footing_width_B',        2.0,   'up';
      % --- elastic_static ---
      'bar_elongation.yaml',    'force_P',                2.0,   'up';
      'bar_elongation.yaml',    'youngs_modulus_E',       2.0,   'down';
      'bar_elongation.yaml',    'area_A',                 2.0,   'down';
      % --- eigenvalue ---
      'ss_beam_eigen.yaml',     'stiffness_E_or_EI',      2.0,   'up';
      'ss_beam_eigen.yaml',     'mass_per_length_rhoA',   2.0,   'down';
      'ss_beam_eigen.yaml',     'length_L',               2.0,   'down';
      % --- dynamic_transient ---
      'sdof_step.yaml',         'force_F',                2.0,   'up';
      'sdof_step.yaml',         'stiffness_k',            2.0,   'down';
      % --- consolidation ---
      'terzaghi_1d.yaml',       'time_factor_Tv',         2.0,   'up';
      % --- thermal ---
      'slab_heat_gen.yaml',     'heat_generation_qgen',   2.0,   'up';
      'slab_heat_gen.yaml',     'conductivity_k',         2.0,   'down';
      % --- seepage_steady ---
      'strip_seepage.yaml',     'recharge_N',             2.0,   'up';
      'strip_seepage.yaml',     'permeability_k_or_cv',   2.0,   'down';
      % --- slope_srf (infinite slope) ---
      'infinite_slope.yaml',    'cohesion_c',             2.0,   'up';
      'infinite_slope.yaml',    'friction_angle_phi',     1.5,   'up';
      'infinite_slope.yaml',    'slope_angle_beta_deg',   1.5,   'down';
    };

    n_pass = 0; n_fail = 0;
    fprintf('  %-25s  %-22s  factor  direction  status\n', 'yaml', 'param bumped');
    fprintf('  %-25s  %-22s  ------  ---------  ------\n', '----', '------------');

    for i = 1:size(checks, 1)
        [yaml_rel, param, factor, direction] = deal(checks{i, :});
        yaml_path = fullfile(repo_root, 'benchmarks/analytic', yaml_rel);
        y = pfem_yaml_load(yaml_path);
        b = get_backend(y);
        ctx = struct('repo_root', repo_root, 'pfem_root', pfem_root, ...
                     'yaml_path', yaml_path);

        % Baseline
        [~, out0] = b.run(ctx, y, struct());
        q0 = b.extract_qoi(out0, '');

        % Bumped: fresh struct each iteration so earlier overrides don't leak
        base = fetch_default(y, param);
        ov = struct();
        ov.(param) = base * factor;
        [~, out1] = b.run(ctx, y, ov);
        q1 = b.extract_qoi(out1, '');

        moved_up   = q1.value > q0.value * (1 + 1e-9);
        moved_down = q1.value < q0.value * (1 - 1e-9);
        expected_up = strcmp(direction, 'up');
        actually_ok = (expected_up && moved_up) || (~expected_up && moved_down);

        [~, stem, ~] = fileparts(yaml_rel);
        status = 'OK';
        if ~actually_ok
            status = sprintf('FAIL (%.4g -> %.4g)', q0.value, q1.value);
            n_fail = n_fail + 1;
        else
            n_pass = n_pass + 1;
        end
        fprintf('  %-25s  %-22s  %5.2fx  %-9s  %s\n', stem, param, factor, direction, status);
    end

    fprintf('----------------------------------------------------------\n');
    fprintf('  %d / %d monotonicity checks pass\n', n_pass, n_pass + n_fail);
    fprintf('==========================================================\n');
    ok = (n_fail == 0);
    if ~ok, error('test_physics_sanity: %d monotonicity failures', n_fail); end
end


function v = fetch_default(y, name)
% Read current_value from the tunable_parameters entry.
    v = NaN;
    if ~isfield(y, 'tunable_parameters'), return; end
    tps = y.tunable_parameters;
    for i = 1:numel(tps)
        if iscell(tps), t = tps{i}; else, t = tps(i); end
        if isfield(t, 'name') && strcmp(t.name, name)
            cv = t.current_value;
            if isnumeric(cv), v = double(cv);
            else, v = str2double(char(cv));
            end
            return;
        end
    end
    error('test_physics_sanity: parameter "%s" not in %s', name, y.id);
end
