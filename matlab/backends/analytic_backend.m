function b = analytic_backend()
% ANALYTIC_BACKEND  Closed-form oracle backend.
%
% Selects a small library of analytic solutions used as independent
% references against PFEM. Which formula runs is chosen by y.runner.model
% (also read from y.runner.type='analytic' via get_backend).
%
% Supported models  (case type -> model name):
%
%   plasticity_load  prandtl_bearing    P_lim = (2 + pi) * yield_stress
%                                       Tresca / undrained strip footing
%   plasticity_load  prandtl_terzaghi   q_ult = c*Nc + 0.5*gamma*B*Ng
%                                       Mohr-Coulomb surface footing (Vesic)
%   elastic_static   bar_elongation     u = P*L/(A*E)
%   eigenvalue       ss_beam_eigen      omega^2 = (pi/L)^4 * EI/(rhoA)
%                                       first mode of a simply-supported
%                                       Euler-Bernoulli beam
%   dynamic_transient sdof_step         u_peak = 2 * F / k
%                                       undamped SDOF, suddenly applied force
%   consolidation    terzaghi_1d        Uav(Tv) = 1 - sum (2/M^2) exp(-M^2*Tv)
%                                       series truncated at 100 terms
%   thermal          slab_heat_gen      T_max = T_s + qgen * L^2 / (8*k)
%                                       symmetric slab with internal heat gen
%   seepage_steady   strip_seepage      h_max = h0 + N*L^2 / (8*k)
%                                       1-D strip aquifer with uniform recharge
%   slope_srf        infinite_slope     FS = c/(gamma*H*sin(b)*cos(b))
%                                            + tan(phi)/tan(b)
%                                       infinite planar slope, drained
%
% Each formula is a canonical closed-form solution for a simplified
% geometry; do not expect these to match arbitrary PFEM cases quantitatively,
% but each is exact for its own problem and correct in physical scaling.
%
% out.qoi carries the computed QoI struct; b.extract_qoi passes it through
% so callers see the same {value, label, unit, ok} shape as
% pfem_extract_qoi. If ctx.repo_root is set the run writes a small
% results.mat + run_info.txt into runs/analytic/<case>/<param_key>/ so the
% GUI's Results table populates and downstream tools can find the outputs.

    b.name           = 'analytic';
    b.run            = @analytic_run;
    b.extract_qoi    = @(out, ~) out.qoi;
    b.non_sampleable = @(y) {};   % nothing off-limits for closed-form models
end


function [status, out] = analytic_run(ctx, y, overrides)
    if nargin < 3 || isempty(overrides), overrides = struct(); end

    model = '';
    if isfield(y, 'runner') && isstruct(y.runner) && isfield(y.runner, 'model')
        model = lower(strtrim(char(y.runner.model)));
    end
    if isempty(model)
        error('analytic_backend: y.runner.model is required (e.g. "prandtl_bearing")');
    end

    q = eval_model(model, y, overrides);

    out.qoi       = q;
    out.model     = model;
    out.case      = model;
    out.files     = {};
    out.run_dir   = '';
    if isfield(ctx, 'yaml_path'), out.yaml_path = ctx.yaml_path; end
    out.overrides = overrides;

    % Persist to disk if we know where the repo is (GUI + sweep runners
    % pass this via ctx). Absent for pure programmatic calls in tests.
    if isfield(ctx, 'repo_root') && ~isempty(ctx.repo_root)
        [~, yaml_stem] = fileparts_or_default(ctx, model);
        run_dir = fullfile(ctx.repo_root, 'runs', 'analytic', yaml_stem, ...
                           param_key(overrides));
        if ~exist(run_dir, 'dir'), mkdir(run_dir); end
        save(fullfile(run_dir, 'results.mat'), 'q', 'overrides', 'model');
        write_run_info(run_dir, model, q, overrides);
        out.run_dir = run_dir;
        out.case    = yaml_stem;
        out.files   = {fullfile(run_dir, 'results.mat')};
    end

    status = 0;
end


function q = eval_model(model, y, overrides)
    q = struct('value', NaN, 'label', 'QoI', 'unit', '', 'raw', [], 'ok', false);

    switch model
    case 'prandtl_bearing'
        sigma_y = fetch_param(y, overrides, 'yield_stress');
        q.value = (2 + pi) * sigma_y;
        q.label = 'P_lim';
        q.unit  = fetch_unit(y, 'yield_stress', 'kPa');
        q.ok    = true;

    case 'prandtl_terzaghi'
        c      = fetch_param(y, overrides, 'cohesion_c');
        phi_d  = fetch_param(y, overrides, 'friction_angle_phi');
        gamma  = fetch_param(y, overrides, 'unit_weight_gamma');
        B      = fetch_param(y, overrides, 'footing_width_B');
        phi    = phi_d * pi / 180;
        Nq     = exp(pi * tan(phi)) * tan(pi/4 + phi/2)^2;
        Nc     = (Nq - 1) * cot_safe(phi);
        Ng     = 2 * (Nq + 1) * tan(phi);
        q.value = c * Nc + 0.5 * gamma * B * Ng;
        q.label = 'q_ult';
        q.unit  = 'kPa';
        q.ok    = true;

    case 'bar_elongation'
        P = fetch_param(y, overrides, 'force_P');
        L = fetch_param(y, overrides, 'length_L');
        A = fetch_param(y, overrides, 'area_A');
        E = fetch_param(y, overrides, 'youngs_modulus_E');
        q.value = P * L / (A * E);
        q.label = 'u_max';
        q.unit  = 'm';
        q.ok    = true;

    case 'ss_beam_eigen'
        L    = fetch_param(y, overrides, 'length_L');
        EI   = fetch_param(y, overrides, 'stiffness_E_or_EI');
        rhoA = fetch_param(y, overrides, 'mass_per_length_rhoA');
        q.value = (pi/L)^4 * EI / rhoA;
        q.label = 'omega^2';
        q.unit  = 'rad^2/s^2';
        q.ok    = true;

    case 'sdof_step'
        F = fetch_param(y, overrides, 'force_F');
        k = fetch_param(y, overrides, 'stiffness_k');
        q.value = 2 * F / k;   % undamped SDOF dynamic load factor = 2
        q.label = 'u_peak';
        q.unit  = 'm';
        q.ok    = true;

    case 'terzaghi_1d'
        % Time factor Tv is dimensionless; Uav depends only on Tv.
        Tv = fetch_param(y, overrides, 'time_factor_Tv');
        Uav = 1;
        for m = 0:100
            M = (2*m + 1) * pi / 2;
            Uav = Uav - (2 / M^2) * exp(-M^2 * Tv);
        end
        q.value = Uav;
        q.label = 'Uav_end';
        q.unit  = '';   % dimensionless
        q.ok    = true;

    case 'slab_heat_gen'
        Ts   = fetch_param(y, overrides, 'surface_temp_Ts');
        qgen = fetch_param(y, overrides, 'heat_generation_qgen');
        L    = fetch_param(y, overrides, 'length_L');
        k    = fetch_param(y, overrides, 'conductivity_k');
        q.value = Ts + qgen * L^2 / (8 * k);
        q.label = 'T_max';
        q.unit  = 'K';
        q.ok    = true;

    case 'strip_seepage'
        h0 = fetch_param(y, overrides, 'boundary_head_h0');
        N  = fetch_param(y, overrides, 'recharge_N');
        L  = fetch_param(y, overrides, 'length_L');
        k  = fetch_param(y, overrides, 'permeability_k_or_cv');
        q.value = h0 + N * L^2 / (8 * k);
        q.label = 'h_max';
        q.unit  = 'm';
        q.ok    = true;

    case 'infinite_slope'
        c     = fetch_param(y, overrides, 'cohesion_c');
        phi_d = fetch_param(y, overrides, 'friction_angle_phi');
        gamma = fetch_param(y, overrides, 'unit_weight_gamma');
        H     = fetch_param(y, overrides, 'height_H');
        b_d   = fetch_param(y, overrides, 'slope_angle_beta_deg');
        phi = phi_d * pi / 180;
        b   = b_d   * pi / 180;
        q.value = c / (gamma * H * sin(b) * cos(b)) + tan(phi) / tan(b);
        q.label = 'FS';
        q.unit  = '';
        q.ok    = true;

    otherwise
        error('analytic_backend: unknown model "%s"', model);
    end
end


function c = cot_safe(x)
% cot() with a small guard to avoid /0 for phi==0 (pure cohesive soil).
    if abs(x) < 1e-12, c = 1e12; else, c = cos(x)/sin(x); end
end


% =========================================================================
function v = fetch_param(y, overrides, name)
    if isfield(overrides, name) && ~isempty(overrides.(name))
        v = double(overrides.(name));
        return;
    end
    tp = find_tunable(y, name);
    if isempty(tp)
        error('analytic_backend: parameter "%s" not in overrides or tunables', name);
    end
    if isfield(tp, 'current_value')
        v = to_num(tp.current_value);
    else
        error('analytic_backend: tunable "%s" has no current_value', name);
    end
end


function u = fetch_unit(y, name, default_unit)
    tp = find_tunable(y, name);
    if ~isempty(tp) && isfield(tp, 'unit') && ~isempty(tp.unit)
        u = char(tp.unit);
    else
        u = default_unit;
    end
end


function tp = find_tunable(y, name)
    tp = [];
    if ~isfield(y, 'tunable_parameters') || isempty(y.tunable_parameters)
        return;
    end
    tps = y.tunable_parameters;
    if iscell(tps)
        for i = 1:numel(tps)
            if isfield(tps{i}, 'name') && strcmp(tps{i}.name, name)
                tp = tps{i}; return;
            end
        end
    elseif isstruct(tps)
        for i = 1:numel(tps)
            if isfield(tps(i), 'name') && strcmp(tps(i).name, name)
                tp = tps(i); return;
            end
        end
    end
end


function v = to_num(x)
    if isnumeric(x), v = double(x); return; end
    if ischar(x) || isstring(x)
        v = str2double(char(x));
        if isnan(v)
            error('analytic_backend: cannot parse numeric value from "%s"', char(x));
        end
        return;
    end
    error('analytic_backend: unexpected numeric type %s', class(x));
end


function [d, s] = fileparts_or_default(ctx, model)
% If ctx.yaml_path is present return its (dir, stem). Else fall back to the
% model name so run_dir is still meaningful.
    if isfield(ctx, 'yaml_path') && ~isempty(ctx.yaml_path)
        [d, s] = fileparts(ctx.yaml_path);
    else
        d = ''; s = model;
    end
end


function key = param_key(overrides)
% Short param_key stem from overrides. Empty struct -> 'default'.
    if isempty(fieldnames(overrides)), key = 'default'; return; end
    fn = fieldnames(overrides);
    parts = cell(numel(fn), 1);
    for i = 1:numel(fn)
        v = overrides.(fn{i});
        if isnumeric(v), s = sprintf('%.4g', v); else, s = char(v); end
        parts{i} = [fn{i} '_' regexprep(s, '[^a-zA-Z0-9._-]', '_')];
    end
    key = strjoin(parts, '_');
    if length(key) > 60, key = key(1:60); end
end


function write_run_info(run_dir, model, q, overrides)
    fid = fopen(fullfile(run_dir, 'run_info.txt'), 'w');
    if fid < 0, return; end
    fprintf(fid, 'Analytic Backend Run\n');
    fprintf(fid, '====================\n');
    fprintf(fid, 'Date  : %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Model : %s\n', model);
    fprintf(fid, 'QoI   : %s = %.6g %s   ok=%d\n\n', q.label, q.value, q.unit, q.ok);
    if ~isempty(fieldnames(overrides))
        fprintf(fid, 'Overrides:\n');
        fn = fieldnames(overrides);
        for i = 1:numel(fn)
            v = overrides.(fn{i});
            if isnumeric(v)
                fprintf(fid, '  %-30s = %g\n', fn{i}, v);
            else
                fprintf(fid, '  %-30s = %s\n', fn{i}, char(v));
            end
        end
    end
    fclose(fid);
end
