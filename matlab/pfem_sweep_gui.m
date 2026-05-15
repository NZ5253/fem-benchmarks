function pfem_sweep_gui()
% PFEM_SWEEP_GUI  Multi-case parametric sweep studio with graphical interface.
%
% Features:
%   - Load any number of YAML benchmark cases via file picker
%   - Tunable parameters auto-populated from all loaded YAMLs (union)
%   - Enable/disable individual parameters; enter sweep values manually
%   - Suggested ranges shown; fill with N log-spaced values ([-][N][+] counter)
%   - Sweep modes: Lockstep (arrays vary together) or Grid (Cartesian product)
%   - Preview scenario list before running
%   - Run all cases x scenarios; live log output; stop button
%   - Results table with max|u|; open saved figures; compare runs in GUI log
%
% Usage:
%   pfem_sweep_gui()
%
% Requires MATLAB R2019b or later (uifigure, uigridlayout).

%s = settings;
%s.matlab.desktop.Zoom.PersonalValue = 200

    % close all handles regular figures; delete(findall) also catches uifigures
    close all;
    delete(findall(0, 'Type', 'figure'));

    repo_root  = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
    pfem_root  = fullfile(repo_root, 'pfem');
    bench_root = fullfile(repo_root, 'benchmarks', 'pfem5');
    addpath(genpath(fullfile(repo_root, 'matlab')));

    %% ── Figure ──────────────────────────────────────────────────────────────
    fig = uifigure('Name', 'PFEM Sweep Studio', ...
                   'Position', [40 40 1340 870], ...
                   'Color', [0.13 0.13 0.16]);

    st = struct( ...
        'repo_root',       repo_root, ...
        'pfem_root',       pfem_root, ...
        'bench_root',      bench_root, ...
        'yaml_paths',      {{}}, ...
        'case_result_map', {{}}, ...
        'stop_flag',       false, ...
        'corr_pairs',      []);  % Nx3 [name_i, name_j, rho] cell array — see cb_correlations
    setappdata(fig, 'state', st);

    %% ── Outer grid: 3 rows ──────────────────────────────────────────────────
    gl = uigridlayout(fig, [3, 1]);
    gl.RowHeight        = {'1x', 215, 205};
    gl.ColumnWidth      = {'1x'};
    gl.Padding          = [8 8 8 8];
    gl.RowSpacing       = 5;
    gl.BackgroundColor  = [0.13 0.13 0.16];

    %% ── ROW 1: Cases (left) | Parameters (right) ───────────────────────────
    r1 = uigridlayout(gl, [1, 2]);
    r1.Layout.Row      = 1;
    r1.ColumnWidth     = {240, '1x'};
    r1.RowHeight       = {'1x'};
    r1.Padding         = [0 0 0 0];
    r1.ColumnSpacing   = 5;
    r1.BackgroundColor = [0.13 0.13 0.16];

    % Cases panel
    cp = spanel(r1, 'Cases', 1, 1);
    cg = uigridlayout(cp, [3, 1]);
    cg.RowHeight = {'1x', 28, 28};  cg.ColumnWidth = {'1x'};
    cg.Padding = [4 4 4 4];  cg.RowSpacing = 3;
    cg.BackgroundColor = [0.10 0.10 0.12];

    case_lb = uilistbox(cg, 'Items', {}, 'Multiselect', 'on', ...
        'BackgroundColor', [0.07 0.07 0.09], ...
        'FontColor', [0.84 0.84 0.84], 'FontSize', 10);
    case_lb.Layout.Row = 1;  case_lb.Layout.Column = 1;

    btn_add = sbtn(cg, '+ Add YAML(s)', [0.16 0.32 0.54], 2, 1);
    btn_rem = sbtn(cg, '- Remove Selected', [0.40 0.12 0.12], 3, 1);

    % Parameters panel
    pp = spanel(r1, 'Tunable Parameters — enable, enter values, see suggested ranges', 1, 2);
    pg = uigridlayout(pp, [2, 1]);
    pg.RowHeight = {'1x', 30};  pg.ColumnWidth = {'1x'};
    pg.Padding = [4 4 4 4];  pg.RowSpacing = 3;
    pg.BackgroundColor = [0.10 0.10 0.12];

    param_tbl = uitable(pg, ...
        'ColumnName',     {'', 'Parameter', 'Values  (comma-separated)', 'Suggested Range', 'Chapters'}, ...
        'ColumnFormat',   {'logical', 'char', 'char', 'char', 'char'}, ...
        'ColumnEditable', [true, false, true, false, false], ...
        'ColumnWidth',    {28, 205, 245, 175, 100}, ...
        'Data',           {}, ...
        'FontSize',       11);
    param_tbl.Layout.Row = 1;  param_tbl.Layout.Column = 1;

    % Sweep mode toolbar
    sw = uigridlayout(pg, [1, 10]);
    sw.Layout.Row = 2;  sw.Layout.Column = 1;
    sw.ColumnWidth = {'fit', 210, 'fit', 28, 34, 28, 'fit', 'fit', 'fit', '1x'};
    sw.RowHeight = {'1x'};  sw.Padding = [0 2 0 2];  sw.ColumnSpacing = 4;
    sw.BackgroundColor = [0.10 0.10 0.12];

    lbl_mode = uilabel(sw, 'Text', 'Mode:', ...
        'FontColor', [0.65 0.65 0.65], 'FontSize', 11);
    lbl_mode.Layout.Row = 1;  lbl_mode.Layout.Column = 1; %#ok<NASGU>

    sweep_dd = uidropdown(sw, ...
        'Items', {'Lockstep  (same-length arrays)', 'Grid  (Cartesian product)', 'Stochastic  (distributions)', 'Sensitivity  (tornado)'}, ...
        'Value', 'Lockstep  (same-length arrays)', ...
        'BackgroundColor', [0.15 0.15 0.18], ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 11, ...
        'Tooltip', sprintf(['Lockstep: parameters vary together — E=[1e4,2e4], nu=[0.2,0.3] → 2 scenarios\n' ...
                            'Grid: all combinations — E=[1e4,2e4], nu=[0.2,0.3] → 4 scenarios (max 500)\n' ...
                            'Stochastic: sample from distributions — enter lognormal(60,0.3) or normal(0.3,0.1)\n' ...
                            'Sensitivity: OAT analysis at mu and mu+/-sigma per param; produces a tornado plot (2k+1 PFEM runs)']));
    sweep_dd.Layout.Row = 1;  sweep_dd.Layout.Column = 2;

    btn_fill = sbtn(sw, 'Fill Ranges', [0.22 0.22 0.10], 1, 3);

    btn_minus = uibutton(sw, 'Text', '−', ...
        'BackgroundColor', [0.20 0.20 0.26], ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 14, 'FontWeight', 'bold');
    btn_minus.Layout.Row = 1;  btn_minus.Layout.Column = 4;

    count_lbl = uilabel(sw, 'Text', '4', 'HorizontalAlignment', 'center', ...
        'FontColor', [0.95 0.80 0.30], 'FontSize', 13, 'FontWeight', 'bold', ...
        'Tooltip', 'Number of values generated by Fill Ranges (1–20)');
    count_lbl.Layout.Row = 1;  count_lbl.Layout.Column = 5;

    btn_plus = uibutton(sw, 'Text', '+', ...
        'BackgroundColor', [0.20 0.20 0.26], ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 14, 'FontWeight', 'bold');
    btn_plus.Layout.Row = 1;  btn_plus.Layout.Column = 6;

    lhs_cb = uicheckbox(sw, ...
        'Text', 'LHS', ...
        'Value', true, ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 11, ...
        'Tooltip', 'Stochastic mode only: use Latin Hypercube Sampling instead of plain Monte Carlo. Reduces estimator variance ~6-14x for the same sample count.', ...
        'Enable', 'off');
    lhs_cb.Layout.Row = 1;  lhs_cb.Layout.Column = 7;

    btn_corr = uibutton(sw, ...
        'Text', 'Corr...', ...
        'BackgroundColor', [0.20 0.20 0.26], ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 11, ...
        'Tooltip', 'Stochastic mode: enter pairwise correlations between sampled parameters (Iman-Conover, preserves LHS marginals)', ...
        'Enable', 'off');
    btn_corr.Layout.Row = 1;  btn_corr.Layout.Column = 8;

    btn_preview = sbtn(sw, 'Preview Scenarios', [0.16 0.28 0.16], 1, 9);

    %% ── ROW 2: Run (left) | Log (right) ────────────────────────────────────
    r2 = uigridlayout(gl, [1, 2]);
    r2.Layout.Row      = 2;
    r2.ColumnWidth     = {240, '1x'};
    r2.RowHeight       = {'1x'};
    r2.Padding         = [0 0 0 0];
    r2.ColumnSpacing   = 5;
    r2.BackgroundColor = [0.13 0.13 0.16];

    run_pan = spanel(r2, 'Run', 1, 1);
    rg = uigridlayout(run_pan, [4, 1]);
    rg.RowHeight = {38, 28, 20, '1x'};  rg.ColumnWidth = {'1x'};
    rg.Padding = [6 6 6 6];  rg.RowSpacing = 4;
    rg.BackgroundColor = [0.10 0.10 0.12];

    btn_run = uibutton(rg, 'Text', 'Run All', ...
        'BackgroundColor', [0.13 0.42 0.16], ...
        'FontColor', [0.96 0.96 0.96], ...
        'FontSize', 14, 'FontWeight', 'bold');
    btn_run.Layout.Row = 1;  btn_run.Layout.Column = 1;

    btn_stop = sbtn(rg, 'Stop', [0.44 0.13 0.13], 2, 1);
    btn_stop.FontSize = 12;

    prog_lbl = uilabel(rg, 'Text', 'Ready', ...
        'HorizontalAlignment', 'center', ...
        'FontColor', [0.50 0.50 0.50], 'FontSize', 9);
    prog_lbl.Layout.Row = 3;  prog_lbl.Layout.Column = 1;

    log_pan = spanel(r2, 'Log', 1, 2);
    lg = uigridlayout(log_pan, [1, 1]);
    lg.Padding = [4 4 4 4];  lg.BackgroundColor = [0.10 0.10 0.12];

    log_ta = uitextarea(lg, ...
        'Value', {'PFEM Sweep Studio — ready.', ...
                  'Step 1: Add YAML cases.  Step 2: Configure parameters.  Step 3: Run All.'}, ...
        'BackgroundColor', [0.05 0.05 0.07], ...
        'FontColor',       [0.72 0.90 0.72], ...
        'FontSize', 9, 'FontName', 'Monospace', ...
        'Editable', 'off');
    log_ta.Layout.Row = 1;  log_ta.Layout.Column = 1;

    %% ── ROW 3: Results ──────────────────────────────────────────────────────
    res_pan = spanel(gl, 'Results', 3, 1);
    rsg = uigridlayout(res_pan, [1, 2]);
    rsg.ColumnWidth = {'1x', 170};  rsg.RowHeight = {'1x'};
    rsg.Padding = [4 4 4 4];  rsg.ColumnSpacing = 5;
    rsg.BackgroundColor = [0.10 0.10 0.12];

    res_tbl = uitable(rsg, ...
        'ColumnName',     {'', 'Case', 'Scenario', 'Status', 'max|u|', 'Time (s)', 'Run Directory'}, ...
        'ColumnFormat',   {'logical', 'char', 'char', 'char', 'char', 'char', 'char'}, ...
        'ColumnEditable', [true, false, false, false, false, false, false], ...
        'ColumnWidth',    {24, 70, 205, 52, 100, 62, 310}, ...
        'Data',           {}, ...
        'FontSize',       10);
    res_tbl.Layout.Row = 1;  res_tbl.Layout.Column = 1;

    ag = uigridlayout(rsg, [4, 1]);
    ag.Layout.Row = 1;  ag.Layout.Column = 2;
    ag.RowHeight = {28, 28, 28, '1x'};  ag.ColumnWidth = {'1x'};
    ag.Padding = [0 0 0 0];  ag.RowSpacing = 4;
    ag.BackgroundColor = [0.10 0.10 0.12];

    btn_figs = sbtn(ag, 'Open Figures',      [0.17 0.27 0.42], 1, 1);
    btn_figs.Tooltip = 'Tick checkboxes on rows first. Each case opens its own figure.';
    btn_cmp  = sbtn(ag, 'Show Comparison',   [0.17 0.27 0.42], 2, 1);
    btn_cmp.Tooltip  = 'Tick 2+ row checkboxes to compare scenarios in the log.';
    btn_clr  = sbtn(ag, 'Clear Results',     [0.35 0.13 0.13], 3, 1);

    %% ── Wire callbacks ──────────────────────────────────────────────────────
    btn_add.ButtonPushedFcn     = @(~,~) cb_add_cases(fig, case_lb, param_tbl);
    btn_rem.ButtonPushedFcn     = @(~,~) cb_remove_cases(fig, case_lb, param_tbl);
    sweep_dd.ValueChangedFcn    = @(~,~) on_mode_change(sweep_dd, count_lbl, lhs_cb, btn_corr);
    btn_fill.ButtonPushedFcn    = @(~,~) cb_fill_ranges(fig, param_tbl, count_lbl, sweep_dd);
    btn_minus.ButtonPushedFcn   = @(~,~) adj_count(count_lbl, -1, sweep_dd);
    btn_plus.ButtonPushedFcn    = @(~,~) adj_count(count_lbl, +1, sweep_dd);
    btn_corr.ButtonPushedFcn    = @(~,~) cb_correlations(fig, param_tbl);
    btn_preview.ButtonPushedFcn = @(~,~) cb_preview(param_tbl, sweep_dd, log_ta);
    btn_run.ButtonPushedFcn     = @(~,~) cb_run(fig, param_tbl, sweep_dd, log_ta, prog_lbl, res_tbl, count_lbl, lhs_cb);
    btn_stop.ButtonPushedFcn    = @(~,~) cb_stop(fig);
    btn_figs.ButtonPushedFcn    = @(~,~) cb_open_figs(fig, res_tbl);
    btn_cmp.ButtonPushedFcn     = @(~,~) cb_print_compare(fig, log_ta, res_tbl);
    btn_clr.ButtonPushedFcn     = @(~,~) set(res_tbl, 'Data', {});
end


%% ============================================================================
%%  CALLBACKS
%% ============================================================================

function cb_add_cases(fig, case_lb, param_tbl)
    st = getappdata(fig, 'state');
    start_dir = st.bench_root;
    if ~exist(start_dir, 'dir'), start_dir = st.repo_root; end

    [fnames, fpath] = uigetfile('*.yaml', 'Select YAML benchmark file(s)', ...
        start_dir, 'MultiSelect', 'on');
    if isequal(fnames, 0), return; end
    if ischar(fnames), fnames = {fnames}; end

    for k = 1:numel(fnames)
        fp = fullfile(fpath, fnames{k});
        if ~ismember(fp, st.yaml_paths)
            st.yaml_paths{end+1} = fp;
        end
    end
    setappdata(fig, 'state', st);
    refresh_cases(case_lb, st.yaml_paths);
    refresh_params(fig, param_tbl);
end


function cb_remove_cases(fig, case_lb, param_tbl)
    st  = getappdata(fig, 'state');
    sel = case_lb.Value;
    if isempty(sel), return; end
    keep = ~ismember(case_lb.Items, sel);
    st.yaml_paths = st.yaml_paths(keep);
    setappdata(fig, 'state', st);
    refresh_cases(case_lb, st.yaml_paths);
    refresh_params(fig, param_tbl);
end


function cb_fill_ranges(~, param_tbl, count_lbl, sweep_dd)
% Populate Values column.
% Deterministic: N log-spaced values from suggested range.
% Stochastic:    lognormal(mu, cov) using current_value as mu, COV=0.3 default.
%                The counter N sets number of samples (stored in count_lbl).
    is_stoch = nargin >= 4 && contains(sweep_dd.Value, 'Stochastic');
    n = max(1, min(500, round(str2double(count_lbl.Text))));
    data = param_tbl.Data;
    if isempty(data), return; end

    for i = 1:size(data, 1)
        if ~data{i,1}, continue; end

        pname   = data{i,2};
        rng_str = strtrim(data{i,4});

        if is_stoch
            % Already has a distribution spec — leave it alone
            cur = strtrim(data{i,3});
            if contains(cur, '('), continue; end

            % Use current value as mu, fall back to geometric mean of range
            mu = [];
            if ~isempty(cur)
                mu = str2double(cur);
            end
            if isempty(mu) || isnan(mu) || mu <= 0
                if ~isempty(rng_str)
                    rng = str2num(rng_str); %#ok<ST2NM>
                    if numel(rng) >= 2 && rng(1) > 0 && rng(end) > 0
                        mu = sqrt(rng(1) * rng(end));
                    end
                end
            end
            if isempty(mu) || isnan(mu) || mu <= 0, continue; end

            % Skip solver/mesh params entirely in stochastic mode
            if isnan(default_cov(pname)), continue; end

            % Integer/mesh params — fix value, don't sample
            if is_int_param(pname)
                data{i,3} = sprintf('%.4g', mu);
            else
                cov = default_cov(pname);
                data{i,3} = sprintf('lognormal(%.4g, %.2f)', mu, cov);
            end
        else
            % Deterministic: log-spaced values
            if isempty(rng_str), continue; end
            rng = str2num(rng_str); %#ok<ST2NM>
            if numel(rng) < 2, continue; end
            lo = rng(1);  hi = rng(end);
            if lo <= 0, lo = max(hi / 1e3, 1e-12); end
            if lo <= 0 || hi <= 0 || lo >= hi, continue; end
            if n == 1
                vals = sqrt(lo * hi);
            else
                vals = round_sig4(logspace(log10(lo), log10(hi), n));
            end
            if is_int_param(pname)
                vals = unique(round(vals), 'stable');
            end
            data{i,3} = num2str(vals, '%.4g  ');
        end
    end
    param_tbl.Data = data;
end


function cov = default_cov(pname)
% Return sensible default COV for material properties.
% Returns NaN for solver/mesh settings — these should NOT be sampled.
    SOLVER_PARAMS = {'convergence_tolerance','local_yield_tolerance_ltol', ...
                     'cg_tolerance','iteration_limit','cg_iteration_limit', ...
                     'load_increments','prescribed_increment','nels_or_nxe', ...
                     'np_types_or_nye','time_step_dtim','number_of_steps', ...
                     'theta_integration','mass_damping_factor','stiffness_damping_factor', ...
                     'damping_ratio','newmark_beta','newmark_gamma','natural_frequency', ...
                     'number_of_modes','num_eigenvalues','krylov_subspace_size', ...
                     'max_arnoldi_iterations','earth_pressure_coeff_k0', ...
                     'initial_effective_stress','bulk_modulus_ke'};
    if any(strcmp(pname, SOLVER_PARAMS))
        cov = NaN;   % solver/mesh setting — skip in stochastic fill
    elseif any(strcmp(pname, {'cohesion_c','cohesion_fill','cohesion_embankment','yield_stress'}))
        cov = 0.40;  % strength: high uncertainty
    elseif any(strcmp(pname, {'friction_angle_phi','friction_angle_fill','friction_angle_embankment', ...
                              'dilation_angle_psi'}))
        cov = 0.10;  % angles: lower uncertainty
    elseif any(strcmp(pname, {'youngs_modulus_E','youngs_modulus_fill','youngs_modulus_embankment', ...
                              'stiffness_E_or_EI','axial_stiffness_EA'}))
        cov = 0.30;  % stiffness: moderate
    elseif any(strcmp(pname, {'poisson_ratio_nu','poisson_ratio_fill','poisson_ratio_embankment'}))
        cov = 0.10;  % Poisson: low
    elseif any(strcmp(pname, {'unit_weight_gamma','unit_weight_fill','unit_weight_embankment','density_rho'}))
        cov = 0.05;  % unit weight: very low
    elseif any(strcmp(pname, {'permeability_k_or_cv','permeability_kx','permeability_ky'}))
        cov = 0.50;  % permeability: very high uncertainty
    else
        cov = 0.20;  % generic material property
    end
end


function cb_correlations(fig, param_tbl)
% Modal dialog for editing pairwise parameter correlations.
% Stores corr_pairs as an Nx3 cell array {name_i, name_j, rho} on the
% main figure's app state. Used by cb_run_stochastic to build the
% correlation matrix passed to pfem_lhs_sample.

    st = getappdata(fig, 'state');
    if ~isfield(st, 'corr_pairs') || isempty(st.corr_pairs)
        existing = cell(0, 3);
    else
        existing = st.corr_pairs;
    end

    % Collect names of currently-checked stochastic params (for the user's reference).
    data = param_tbl.Data;
    enabled_names = {};
    for i = 1:size(data, 1)
        if data{i, 1} && ~isempty(strtrim(data{i, 3}))
            enabled_names{end+1} = data{i, 2}; %#ok<AGROW>
        end
    end

    dlg = uifigure('Name', 'Parameter Correlations', ...
        'Position', [200 200 640 360], ...
        'Color', [0.10 0.10 0.12], ...
        'WindowStyle', 'modal');
    dlg_gl = uigridlayout(dlg, [4, 1]);
    dlg_gl.RowHeight = {'fit', '1x', '1x', 'fit'};
    dlg_gl.BackgroundColor = [0.10 0.10 0.12];

    if isempty(enabled_names)
        info_text = 'No stochastic parameters detected. Enable parameters and enter distributions first.';
    else
        info_text = sprintf('Checked stochastic params: %s', strjoin(enabled_names, ', '));
    end
    info = uilabel(dlg_gl, 'Text', info_text, ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 11, 'WordWrap', 'on'); %#ok<NASGU>

    note = uilabel(dlg_gl, 'Text', ...
        sprintf(['Enter pairwise correlations as rows: parameter 1, parameter 2, rho in [-1, 1].\n' ...
                 'Names must match parameters in the main table. Iman-Conover preserves LHS marginals.']), ...
        'FontColor', [0.65 0.65 0.65], 'FontSize', 10, 'WordWrap', 'on'); %#ok<NASGU>

    if isempty(existing)
        starter = cell(3, 3);
        starter(:) = {''};
    else
        starter = existing;
        % Pad to at least 3 rows
        if size(starter, 1) < 3
            extra = cell(3 - size(starter, 1), 3);
            extra(:) = {''};
            starter = [starter; extra];
        end
    end

    tbl = uitable(dlg_gl, ...
        'Data', starter, ...
        'ColumnName', {'parameter 1', 'parameter 2', 'rho'}, ...
        'ColumnEditable', [true, true, true], ...
        'RowName', {}, ...
        'BackgroundColor', [0.16 0.16 0.20; 0.13 0.13 0.16], ...
        'ForegroundColor', [0.92 0.92 0.92], ...
        'ColumnWidth', {220, 220, 80});

    btn_row = uigridlayout(dlg_gl, [1, 4]);
    btn_row.ColumnWidth = {'1x', 'fit', 'fit', 'fit'};
    btn_row.BackgroundColor = [0.10 0.10 0.12];

    spacer = uilabel(btn_row, 'Text', ''); spacer.Layout.Column = 1; %#ok<NASGU>

    btn_clear = uibutton(btn_row, 'Text', 'Clear All', ...
        'BackgroundColor', [0.30 0.20 0.20], 'FontColor', [0.92 0.92 0.92]);
    btn_clear.Layout.Column = 2;
    btn_clear.ButtonPushedFcn = @(~,~) clear_table(tbl);

    btn_cancel = uibutton(btn_row, 'Text', 'Cancel', ...
        'BackgroundColor', [0.20 0.20 0.26], 'FontColor', [0.92 0.92 0.92]);
    btn_cancel.Layout.Column = 3;
    btn_cancel.ButtonPushedFcn = @(~,~) close(dlg);

    btn_ok = uibutton(btn_row, 'Text', 'OK', ...
        'BackgroundColor', [0.16 0.40 0.20], 'FontColor', [1 1 1]);
    btn_ok.Layout.Column = 4;
    btn_ok.ButtonPushedFcn = @(~,~) save_and_close(fig, dlg, tbl);
end


function clear_table(tbl)
    blank = cell(size(tbl.Data));
    blank(:) = {''};
    tbl.Data = blank;
end


function save_and_close(fig, dlg, tbl)
    raw = tbl.Data;
    pairs = cell(0, 3);
    for i = 1:size(raw, 1)
        a = strtrim(char_or_empty(raw{i, 1}));
        b = strtrim(char_or_empty(raw{i, 2}));
        rho_cell = raw{i, 3};
        if isempty(a) || isempty(b) || isempty(rho_cell)
            continue;
        end
        if ischar(rho_cell)
            rho = str2double(strtrim(rho_cell));
        else
            rho = double(rho_cell);
        end
        if isnan(rho) || abs(rho) > 1
            uialert(dlg, sprintf('Row %d: rho must be a number in [-1, 1] (got "%s")', i, num2str(rho_cell)), ...
                'Bad correlation value');
            return;
        end
        pairs(end+1, :) = {a, b, rho}; %#ok<AGROW>
    end
    st = getappdata(fig, 'state');
    st.corr_pairs = pairs;
    setappdata(fig, 'state', st);
    close(dlg);
end


function s = char_or_empty(v)
    if isempty(v),       s = '';        return;  end
    if ischar(v),        s = v;         return;  end
    if isstring(v),      s = char(v);   return;  end
    s = '';
end


function cb_preview(param_tbl, sweep_dd, log_ta)
    [scenarios, err] = build_scenarios(param_tbl, sweep_dd);
    if ~isempty(err)
        append_log(log_ta, sprintf('[Preview] %s', err)); return;
    end
    append_log(log_ta, sprintf('--- Scenario Preview: %d scenario(s) ---', numel(scenarios)));
    for i = 1:min(numel(scenarios), 25)
        sc   = scenarios(i);
        fns  = fieldnames(rmfield(sc, 'label'));
        parts = cellfun(@(f) sprintf('%s=%s', f, cnum(sc.(f))), fns, 'UniformOutput', false);
        append_log(log_ta, sprintf('  sc%d  (%s):  %s', i, sc.label, strjoin(parts, '  ')));
    end
    if numel(scenarios) > 25
        append_log(log_ta, sprintf('  ... (%d more)', numel(scenarios) - 25));
    end
end


function cb_run(fig, param_tbl, sweep_dd, log_ta, prog_lbl, res_tbl, count_lbl, lhs_cb)
    st = getappdata(fig, 'state');
    if isempty(st.yaml_paths)
        uialert(fig, 'Add at least one YAML case first.', 'No cases'); return;
    end

    % ---- Stochastic mode: delegate to inline stochastic runner ----
    if contains(sweep_dd.Value, 'Stochastic')
        n_samples = max(10, min(500, round(str2double(count_lbl.Text))));
        use_lhs = nargin >= 8 && isvalid(lhs_cb) && lhs_cb.Value;
        cb_run_stochastic(fig, param_tbl, log_ta, prog_lbl, res_tbl, n_samples, use_lhs);
        return;
    end

    % ---- Sensitivity mode: OAT analysis with tornado plot per case ----
    if contains(sweep_dd.Value, 'Sensitivity')
        cb_run_sensitivity(fig, param_tbl, log_ta, prog_lbl, res_tbl);
        return;
    end

    [scenarios, err] = build_scenarios(param_tbl, sweep_dd);
    if ~isempty(err)
        uialert(fig, err, 'Scenario error'); return;
    end
    if isempty(scenarios)
        uialert(fig, 'No enabled parameters with values entered.', 'Nothing to run'); return;
    end

    st.stop_flag = false;
    setappdata(fig, 'state', st);

    n_cases   = numel(st.yaml_paths);
    n_sc      = numel(scenarios);
    total     = n_cases * n_sc;
    done      = 0;

    sc_fields = fieldnames(rmfield(scenarios(1), 'label'));
    sweep_display = ifelse(numel(sc_fields) == 1, sc_fields{1}, 'Scenario');

    append_log(log_ta, sprintf('=== Run start: %d case(s) x %d scenario(s) = %d total ===', ...
        n_cases, n_sc, total));

    row_data = res_tbl.Data;

    for ci = 1:n_cases
        yaml_path = st.yaml_paths{ci};
        [yaml_dir, case_name, ~] = fileparts(yaml_path);
        [~, chap_str] = fileparts(yaml_dir);

        append_log(log_ta, sprintf('--- Case: %s  (%s) ---', case_name, chap_str));

        % Load YAML for program/chapter info
        try
            y_tmp   = pfem_yaml_load(yaml_path);
            program = y_tmp.authors.source.program;
            chap    = sprintf('chap%02d', y_tmp.authors.source.chapter);
        catch ex
            append_log(log_ta, sprintf('  YAML error: %s — skipping.', ex.message));
            continue;
        end

        % Build binary if needed
        prog_lbl.Text = sprintf('Building %s...', program);  drawnow;
        if ~pfem_ensure_built(st.repo_root, st.pfem_root, program, chap)
            append_log(log_ta, sprintf('  Build failed for %s — skipping.', program));
            continue;
        end

        case_results = struct('label',{}, 'value',{}, 'status',{}, ...
                              'run_dir',{}, 'files',{}, 'out',{});

        for si = 1:n_sc
            st2 = getappdata(fig, 'state');
            if st2.stop_flag
                append_log(log_ta, 'Stopped by user.');
                prog_lbl.Text = 'Stopped';
                return;
            end

            sc    = scenarios(si);
            label = sc.label;
            ovr   = rmfield(sc, 'label');

            done = done + 1;
            prog_lbl.Text = sprintf('%d / %d  (%s | %s)', done, total, case_name, label);
            append_log(log_ta, sprintf('  [%d/%d]  %s | %s', done, total, case_name, label));
            drawnow;

            try
                [status, out] = pfem_run_from_yaml(st.repo_root, st.pfem_root, yaml_path, ovr);
            catch ex
                append_log(log_ta, sprintf('    ERROR: %s', ex.message));
                status = -1;
                out = struct('files', {{}}, 'num_files', 0, 'run_dir', '', 'overrides', ovr);
            end

            sc_val = ifelse(numel(sc_fields) == 1, ovr.(sc_fields{1}), si);

            case_results(si).label   = label;
            case_results(si).value   = sc_val;
            case_results(si).status  = status;
            case_results(si).run_dir = out.run_dir;
            case_results(si).files   = out.files;
            case_results(si).out     = out;

            max_u = get_max_u_str(out);
            if isfield(out, 'elapsed_sec')
                t_str = sprintf('%.2f', out.elapsed_sec);
            else
                t_str = '-';
            end
            if status == 0
                append_log(log_ta, sprintf('    OK  — %d file(s)   max|u| = %s   t = %s s', out.num_files, max_u, t_str));
            else
                append_log(log_ta, sprintf('    FAILED (exit %d)', status));
                max_u = '-';
                t_str = '-';
            end

            % Append row to results table (col1 = checkbox)
            n = size(row_data, 1) + 1;
            row_data{n,1} = false;
            row_data{n,2} = case_name;
            row_data{n,3} = label;
            row_data{n,4} = ifelse(status==0, 'OK', 'FAIL');
            row_data{n,5} = max_u;
            row_data{n,6} = t_str;
            row_data{n,7} = out.run_dir;
            res_tbl.Data  = row_data;
            drawnow;
        end

        % Store this case's results for later figure/compare use
        st = getappdata(fig, 'state');
        entry = struct('case_name', case_name, 'chap_str', chap_str, ...
                       'yaml_path', yaml_path, 'sweep_display', sweep_display, ...
                       'case_results', case_results);
        st.case_result_map{end+1} = entry;
        setappdata(fig, 'state', st);

    end

    if isempty(row_data)
        n_ok = 0;
    else
        n_ok = sum(strcmp(row_data(:,4), 'OK'));
    end
    prog_lbl.Text = sprintf('Done  (%d / %d OK)', n_ok, total);
    append_log(log_ta, '=== Run complete ===');
end


function cb_stop(fig)
    st = getappdata(fig, 'state');
    st.stop_flag = true;
    setappdata(fig, 'state', st);
end


function cb_run_stochastic(fig, param_tbl, log_ta, prog_lbl, res_tbl, n_samples, use_lhs)
% Run stochastic sweep inline — updates GUI log/progress after each run.
% Values column accepts distribution specs: lognormal(60, 0.3), normal(0.3, 0.1), etc.
% Or a single number to fix that parameter.
% n_samples comes from the counter; seed is fixed at 42 for reproducibility.
% use_lhs (default true): use Latin Hypercube Sampling (variance-reduced)
% instead of plain Monte Carlo with independent draws per parameter.

    if nargin < 7, use_lhs = true; end

    st = getappdata(fig, 'state');
    data = param_tbl.Data;

    param_defs  = [];
    fixed       = struct();
    n_stoch     = 0;

    for i = 1:size(data, 1)
        if ~data{i,1}, continue; end
        pname = data{i,2};
        vs    = strtrim(data{i,3});
        if isempty(vs), continue; end

        tok = regexp(vs, '^\s*(\w+)\s*\(\s*(.+)\s*\)\s*$', 'tokens');
        if ~isempty(tok)
            dist_type = lower(tok{1}{1});
            args = str2num(tok{1}{2}); %#ok<ST2NM>
            if isempty(args) || numel(args) < 2
                uialert(fig, sprintf('Bad distribution for "%s": %s\nExpected: type(mu, cov) or type(mu, cov, lo, hi)', pname, vs), 'Parse error');
                return;
            end
            pd = struct('name', pname, 'dist', dist_type, ...
                        'mu', args(1), 'cov', args(2), 'bounds', []);
            if numel(args) >= 4
                pd.bounds = [args(3), args(4)];
            elseif strcmp(dist_type, 'uniform')
                pd.bounds = [args(1), args(2)];
                pd.mu = 0; pd.cov = 0;
            end
            n_stoch = n_stoch + 1;
            if isempty(param_defs)
                param_defs = pd;
            else
                param_defs(end+1) = pd; %#ok<AGROW>
            end
        else
            % Solver/mesh params must not be overridden — use YAML defaults
            if isnan(default_cov(pname)), continue; end
            v = str2num(vs); %#ok<ST2NM>
            if isempty(v) || numel(v) ~= 1
                uialert(fig, sprintf('For stochastic mode, "%s" must be a distribution spec or a single fixed value.\nGot: %s\n\nExamples:\n  lognormal(60, 0.3)\n  normal(0.3, 0.1)\n  20  (fixed)', pname, vs), 'Parse error');
                return;
            end
            fixed.(pname) = v;
        end
    end

    if n_stoch == 0
        uialert(fig, sprintf('No distribution specs found.\n\nEnter distributions like:\n  lognormal(60, 0.3)\n  normal(0.3, 0.1)\n  truncnormal(0.3, 0.1, 0, 0.499)'), ...
            'No distributions');
        return;
    end

    seed = 42;   % fixed seed for reproducibility

    n_params    = numel(param_defs);
    param_names = cell(n_params, 1);
    for k = 1:n_params
        param_names{k} = param_defs(k).name;
    end

    % ---- Resolve correlation pairs (set via the Corr... dialog) ----
    rho_numeric = [];
    rho_pairs_used = {};
    rho_pairs_skipped = {};
    if isfield(st, 'corr_pairs') && ~isempty(st.corr_pairs)
        for r = 1:size(st.corr_pairs, 1)
            a = st.corr_pairs{r, 1};
            b = st.corr_pairs{r, 2};
            ia = find(strcmp(param_names, a), 1);
            ib = find(strcmp(param_names, b), 1);
            if isempty(ia) || isempty(ib) || ia == ib
                rho_pairs_skipped{end+1} = sprintf('(%s, %s)', a, b); %#ok<AGROW>
                continue;
            end
            rho_numeric(end+1, :) = [ia, ib, st.corr_pairs{r, 3}]; %#ok<AGROW>
            rho_pairs_used{end+1} = sprintf('%s-%s rho=%+.2f', a, b, st.corr_pairs{r, 3}); %#ok<AGROW>
        end
    end

    % ---- Generate all samples upfront ----
    if use_lhs
        % Latin Hypercube Sampling: stratified joint draw across all params.
        % Build a clean spec struct array (assign .bounds explicitly so it's
        % always present, even when the user did not specify bounds).
        lhs_specs = struct('dist', {}, 'mu', {}, 'cov', {}, 'bounds', {});
        for k = 1:n_params
            pd = param_defs(k);
            if ~isempty(pd.bounds), b = pd.bounds; else, b = []; end
            lhs_specs(k) = struct('dist', pd.dist, 'mu', pd.mu, 'cov', pd.cov, 'bounds', b); %#ok<AGROW>
        end
        if isempty(rho_numeric)
            all_samples = pfem_lhs_sample(lhs_specs, n_samples, 'Seed', seed);
        else
            all_samples = pfem_lhs_sample(lhs_specs, n_samples, 'Seed', seed, ...
                'Correlation', rho_numeric);
        end
    else
        % Plain Monte Carlo with independent draws per parameter.
        all_samples = zeros(n_samples, n_params);
        for k = 1:n_params
            pd = param_defs(k);
            bargs = {};
            if ~isempty(pd.bounds), bargs = {'Bounds', pd.bounds}; end
            all_samples(:, k) = pfem_sample_distribution(pd.dist, pd.mu, pd.cov, n_samples, ...
                bargs{:}, 'Seed', seed + k - 1);
        end
    end

    % ---- Run each case ----
    for ci = 1:numel(st.yaml_paths)
        yaml_path = st.yaml_paths{ci};
        [~, case_name] = fileparts(yaml_path);

        if use_lhs, sample_method = 'LHS'; else, sample_method = 'IID Monte Carlo'; end
        if isempty(rho_numeric)
            corr_tag = '';
        else
            corr_tag = sprintf(', correlated [%s]', strjoin(rho_pairs_used, '; '));
        end
        append_log(log_ta, sprintf('=== Stochastic sweep: %s, %d samples (%s%s) ===', case_name, n_samples, sample_method, corr_tag));
        if ~isempty(rho_pairs_skipped)
            append_log(log_ta, sprintf('  [warn] correlation pairs skipped (param not enabled in this case): %s', ...
                strjoin(rho_pairs_skipped, ', ')));
        end
        for k = 1:n_params
            pd = param_defs(k);
            append_log(log_ta, sprintf('  %s: %s(mu=%.4g, COV=%.2g)', pd.name, pd.dist, pd.mu, pd.cov));
        end
        fn = fieldnames(fixed);
        for k = 1:numel(fn)
            append_log(log_ta, sprintf('  %s: %.4g (fixed)', fn{k}, fixed.(fn{k})));
        end

        % Build binary
        try
            y_tmp     = pfem_yaml_load(yaml_path);
            program   = y_tmp.authors.source.program;
            chap      = sprintf('chap%02d', y_tmp.authors.source.chapter);
            case_type = pfem_detect_case_type(y_tmp);
        catch ex
            append_log(log_ta, sprintf('  YAML error: %s', ex.message));
            continue;
        end
        prog_lbl.Text = sprintf('Building %s...', program); drawnow;
        if ~pfem_ensure_built(st.repo_root, st.pfem_root, program, chap)
            append_log(log_ta, sprintf('  Build failed for %s', program));
            continue;
        end
        append_log(log_ta, sprintf('  case type: %s', case_type));

        qoi_vec      = NaN(n_samples, 1);
        qoi_label    = 'QoI';
        qoi_unit     = '';
        status_vec   = -ones(n_samples, 1);
        row_data     = res_tbl.Data;
        t_start      = tic;

        for si = 1:n_samples
            % Check stop
            st2 = getappdata(fig, 'state');
            if st2.stop_flag
                append_log(log_ta, 'Stopped by user.');
                prog_lbl.Text = 'Stopped';
                return;
            end

            % Build overrides
            overrides = fixed;
            parts = {};
            for k = 1:n_params
                overrides.(param_names{k}) = all_samples(si, k);
                parts{end+1} = sprintf('%s=%.4g', param_names{k}(1:min(end,6)), all_samples(si,k)); %#ok<AGROW>
            end
            label = strjoin(parts, ' ');

            prog_lbl.Text = sprintf('Stochastic: %s (%d/%d)', case_name, si, n_samples);
            append_log(log_ta, sprintf('  [%d/%d] %s', si, n_samples, label));
            drawnow;

            try
                [status, out] = pfem_run_from_yaml(st.repo_root, st.pfem_root, yaml_path, overrides);
                status_vec(si) = status;

                if status == 0
                    q = pfem_extract_qoi(out, case_type);
                    qoi_vec(si) = q.value;
                    if q.ok
                        qoi_label = q.label;
                        qoi_unit  = q.unit;
                    end
                    if isempty(qoi_unit)
                        append_log(log_ta, sprintf('    OK  %s=%.4g  t=%.1fs', ...
                            qoi_label, q.value, out.elapsed_sec));
                    else
                        append_log(log_ta, sprintf('    OK  %s=%.4g %s  t=%.1fs', ...
                            qoi_label, q.value, qoi_unit, out.elapsed_sec));
                    end
                else
                    append_log(log_ta, sprintf('    FAILED (exit %d)', status));
                end
            catch ex
                append_log(log_ta, sprintf('    ERROR: %s', ex.message));
                status_vec(si) = -1;
            end

            % Add row to results table
            nr = size(row_data, 1) + 1;
            row_data{nr,1} = false;
            row_data{nr,2} = case_name;
            row_data{nr,3} = label;
            row_data{nr,4} = ifelse(status_vec(si)==0, 'OK', 'FAIL');
            row_data{nr,5} = ifelse(~isnan(qoi_vec(si)), sprintf('%s=%.4g', qoi_label, qoi_vec(si)), '-');
            row_data{nr,6} = ifelse(status_vec(si)==0, sprintf('%.1f', out.elapsed_sec), '-');
            row_data{nr,7} = ifelse(isfield(out,'run_dir'), out.run_dir, '-');
            res_tbl.Data = row_data;
            drawnow;
        end
        elapsed = toc(t_start);

        % ---- Statistics ----
        valid    = status_vec == 0 & ~isnan(qoi_vec);
        q_valid  = qoi_vec(valid);
        if isempty(q_valid)
            append_log(log_ta, '  WARNING: no successful runs.');
            continue;
        end
        mu_q    = mean(q_valid);
        sigma_q = std(q_valid);
        % Reliability metrics only apply when QoI naturally compares to 1.0
        % (i.e. Factor of Safety from slope_srf cases)
        if strcmp(case_type, 'slope_srf')
            pf = sum(q_valid < 1.0) / numel(q_valid);
            if pf > 0 && pf < 1
                beta_rel = -sqrt(2) * erfinv(2*pf - 1);
            elseif pf == 0
                beta_rel = Inf;
            else
                beta_rel = -Inf;
            end
        else
            pf       = NaN;
            beta_rel = NaN;
        end

        unit_str = '';
        if ~isempty(qoi_unit), unit_str = [' ', qoi_unit]; end
        append_log(log_ta, sprintf('  --- Results (%d/%d OK, %.1f s) ---', sum(valid), n_samples, elapsed));
        append_log(log_ta, sprintf('  %s: mean=%.4g%s  std=%.4g  COV=%.1f%%', ...
            qoi_label, mu_q, unit_str, sigma_q, sigma_q/abs(mu_q)*100));
        if ~isnan(pf)
            append_log(log_ta, sprintf('  P(failure) = %.2f%%,  beta = %.2f', pf*100, beta_rel));
        end
        append_log(log_ta, sprintf('  %s range: [%.4g, %.4g]%s', qoi_label, min(q_valid), max(q_valid), unit_str));

        % ---- Generate figures ----
        ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
        save_prefix = fullfile(st.repo_root, 'runs', chap, case_name, ...
            sprintf('%s_stochastic_%s', case_name, ts));
        ttl = sprintf('%s Stochastic', case_name);

        plot_stochastic_gui(q_valid, all_samples(valid,:), param_names, ...
            mu_q, sigma_q, pf, beta_rel, ttl, save_prefix, qoi_label, qoi_unit);

        append_log(log_ta, sprintf('  Figures saved: %s_*', save_prefix));

        % Add summary row
        nr = size(row_data, 1) + 1;
        row_data{nr,1} = false;
        row_data{nr,2} = case_name;
        row_data{nr,3} = sprintf('--- SUMMARY n=%d ---', n_samples);
        row_data{nr,4} = sprintf('%d/%d', sum(valid), n_samples);
        row_data{nr,5} = sprintf('%s=%.4g +/- %.4g%s', qoi_label, mu_q, sigma_q, unit_str);
        row_data{nr,6} = sprintf('%.1f', elapsed);
        row_data{nr,7} = fileparts(save_prefix);
        res_tbl.Data = row_data;
        drawnow;
    end

    prog_lbl.Text = 'Done (stochastic)';
    append_log(log_ta, '=== Stochastic sweep complete ===');
end


function cb_run_sensitivity(fig, param_tbl, log_ta, prog_lbl, res_tbl)
% Sensitivity (one-at-a-time) mode: each enabled stochastic parameter is
% perturbed by +/- 1 sigma (geometric for lognormal) while the others stay
% at their means. Produces a tornado plot per case.

    st = getappdata(fig, 'state');
    data = param_tbl.Data;

    % Collect enabled parameters with distribution specs.
    specs = struct('name', {}, 'dist', {}, 'mu', {}, 'cov', {}, 'bounds', {});
    fixed = struct();
    for i = 1:size(data, 1)
        if ~data{i, 1}, continue; end
        pname = data{i, 2};
        vs    = strtrim(data{i, 3});
        if isempty(vs), continue; end

        tok = regexp(vs, '^\s*(\w+)\s*\(\s*(.+)\s*\)\s*$', 'tokens');
        if ~isempty(tok)
            dist_type = lower(tok{1}{1});
            args = str2num(tok{1}{2}); %#ok<ST2NM>
            if isempty(args) || numel(args) < 2
                uialert(fig, sprintf('Bad distribution for "%s": %s', pname, vs), 'Parse error');
                return;
            end
            spec = struct('name', pname, 'dist', dist_type, ...
                'mu', args(1), 'cov', args(2), 'bounds', []);
            if numel(args) >= 4
                spec.bounds = [args(3), args(4)];
            elseif strcmp(dist_type, 'uniform')
                spec.bounds = [args(1), args(2)];
                spec.mu = (args(1) + args(2)) / 2;
                spec.cov = 0;
            end
            specs(end+1) = spec; %#ok<AGROW>
        else
            % Solver/mesh params skipped, fixed values respected.
            if isnan(default_cov(pname)), continue; end
            v = str2num(vs); %#ok<ST2NM>
            if isempty(v) || numel(v) ~= 1, continue; end
            fixed.(pname) = v;
        end
    end

    if isempty(specs)
        uialert(fig, sprintf(['No distribution specs found.\n\n' ...
            'Sensitivity needs at least one parameter entered as a distribution\n' ...
            '(e.g. lognormal(60, 0.40)). Switch to Stochastic mode and use\n' ...
            'Fill Ranges to populate, then switch back to Sensitivity.']), ...
            'No specs');
        return;
    end

    n_cases = numel(st.yaml_paths);
    if n_cases == 0
        uialert(fig, 'Add at least one YAML case first.', 'No cases'); return;
    end

    append_log(log_ta, sprintf('=== Sensitivity (tornado), %d case(s) x (%d params, %d runs each) ===', ...
        n_cases, numel(specs), 2 * numel(specs) + 1));
    fn = fieldnames(fixed);
    for k = 1:numel(fn)
        append_log(log_ta, sprintf('  fixed: %s = %.4g', fn{k}, fixed.(fn{k})));
    end

    row_data = res_tbl.Data;
    for ci = 1:n_cases
        yaml_path = st.yaml_paths{ci};
        [~, case_name] = fileparts(yaml_path);

        try
            y_tmp   = pfem_yaml_load(yaml_path);
            program = y_tmp.authors.source.program;
            chap    = sprintf('chap%02d', y_tmp.authors.source.chapter);
        catch ex
            append_log(log_ta, sprintf('  YAML error: %s', ex.message));
            continue;
        end

        prog_lbl.Text = sprintf('Building %s...', program); drawnow;
        if ~pfem_ensure_built(st.repo_root, st.pfem_root, program, chap)
            append_log(log_ta, sprintf('  Build failed for %s', program));
            continue;
        end

        prog_lbl.Text = sprintf('Sensitivity: %s (1/%d)', case_name, 2 * numel(specs) + 1);
        drawnow;

        append_log(log_ta, sprintf('--- Case: %s (%s) ---', case_name, chap));
        try
            result = pfem_sensitivity_oat(st.repo_root, st.pfem_root, yaml_path, specs, ...
                'Fixed', fixed, 'Verbose', false);
        catch ex
            append_log(log_ta, sprintf('  ERROR: %s', ex.message));
            continue;
        end

        if isnan(result.qoi_baseline)
            append_log(log_ta, '  Baseline run failed; skipping case.');
            continue;
        end

        append_log(log_ta, sprintf('  baseline %s = %.4g', result.qoi_label, result.qoi_baseline));
        append_log(log_ta, '  parameter ranking by absolute sensitivity:');
        for ii = 1:numel(result.order)
            j = result.order(ii);
            if isnan(result.qoi_low(j)) || isnan(result.qoi_high(j))
                append_log(log_ta, sprintf('    %d. %-22s (run failed)', ii, result.param_names{j}));
            else
                append_log(log_ta, sprintf('    %d. %-22s %s: %.4g -> %.4g  (spread %.4g)', ...
                    ii, result.param_names{j}, result.qoi_label, ...
                    result.qoi_low(j), result.qoi_high(j), result.qoi_high(j) - result.qoi_low(j)));
            end
        end

        ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
        save_prefix = fullfile(st.repo_root, 'runs', chap, case_name, ...
            sprintf('%s_tornado_%s', case_name, ts));
        try
            pfem_plot_tornado(result, ...
                'Title', sprintf('%s sensitivity (mu, mu+/-sigma)', case_name), ...
                'Save', save_prefix);
            append_log(log_ta, sprintf('  tornado saved: %s_*', save_prefix));
        catch ex
            append_log(log_ta, sprintf('  tornado plot ERROR: %s', ex.message));
        end

        % Add summary row to results table.
        nr = size(row_data, 1) + 1;
        row_data{nr, 1} = false;
        row_data{nr, 2} = case_name;
        row_data{nr, 3} = sprintf('--- TORNADO k=%d ---', numel(specs));
        row_data{nr, 4} = sprintf('%s base=%.3g', result.qoi_label, result.qoi_baseline);
        if ~isempty(result.order)
            j_top = result.order(1);
            row_data{nr, 5} = sprintf('top: %s spread=%.3g', result.param_names{j_top}, ...
                result.qoi_high(j_top) - result.qoi_low(j_top));
        else
            row_data{nr, 5} = '-';
        end
        row_data{nr, 6} = '-';
        row_data{nr, 7} = fileparts(save_prefix);
        res_tbl.Data = row_data;
        drawnow;
    end

    prog_lbl.Text = 'Done (sensitivity)';
    append_log(log_ta, '=== Sensitivity sweep complete ===');
end


function plot_stochastic_gui(qvals, samples, param_names, mu_q, sigma_q, pf, beta_rel, ttl, save_prefix, qoi_label, qoi_unit)
% Generate and save stochastic result figures for any QoI (FS, P_lim, u_max, ...)
    if nargin < 10 || isempty(qoi_label), qoi_label = 'QoI'; end
    if nargin < 11, qoi_unit = ''; end

    set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
    set(groot, 'defaultAxesFontSize', 16);

    d = fileparts(save_prefix);
    if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end

    qoi_tex = strrep(qoi_label, '_', '\_');
    if isempty(qoi_unit)
        xlab = sprintf('%s', qoi_tex);
    else
        xlab = sprintf('%s [%s]', qoi_tex, qoi_unit);
    end
    is_fs = strcmpi(qoi_label, 'FS');

    % ---- Histogram ----
    fig1 = figure('Position', [80 80 560 420], 'Color', 'w');
    ax1 = axes(fig1);
    histogram(ax1, qvals, 'Normalization', 'pdf', 'FaceColor', [0.2 0.5 0.8], ...
        'EdgeColor', 'w', 'FaceAlpha', 0.85);
    hold(ax1, 'on');
    if numel(qvals) > 5
        pos = qvals(qvals > 0);
        if numel(pos) > 5
            mu_ln = mean(log(pos)); sig_ln = std(log(pos));
            if sig_ln > 0
                xp = linspace(min(pos)*0.9, max(pos)*1.1, 200);
                yp = (1./(xp*sig_ln*sqrt(2*pi))) .* exp(-(log(xp)-mu_ln).^2/(2*sig_ln^2));
                plot(ax1, xp, yp, 'r-', 'LineWidth', 2.5);
            end
        end
    end
    if is_fs
        yl = ylim(ax1);
        plot(ax1, [1 1], yl, 'k--', 'LineWidth', 2);
    end
    xlabel(ax1, xlab, 'Interpreter', 'latex', 'FontSize', 18);
    ylabel(ax1, 'Probability Density', 'Interpreter', 'latex', 'FontSize', 18);
    title(ax1, sprintf('%s --- %s distribution ($n=%d$)', ttl, qoi_tex, numel(qvals)), ...
        'Interpreter', 'latex', 'FontSize', 14);
    if is_fs && ~isnan(pf)
        annotation(fig1, 'textbox', [0.58 0.68 0.38 0.22], ...
            'String', sprintf('$\\mu = %.3f$\n$\\sigma = %.3f$\n$P_f = %.2f\\%%$\n$\\beta = %.2f$', ...
                mu_q, sigma_q, pf*100, beta_rel), ...
            'Interpreter', 'latex', 'FontSize', 16, ...
            'EdgeColor', [0.5 0.5 0.5], 'BackgroundColor', [1 1 1 0.9], 'FitBoxToText', 'on');
    else
        annotation(fig1, 'textbox', [0.58 0.72 0.38 0.18], ...
            'String', sprintf('$\\mu = %.4g$\n$\\sigma = %.4g$\n$\\mathrm{COV} = %.1f\\%%$', ...
                mu_q, sigma_q, sigma_q/abs(mu_q)*100), ...
            'Interpreter', 'latex', 'FontSize', 16, ...
            'EdgeColor', [0.5 0.5 0.5], 'BackgroundColor', [1 1 1 0.9], 'FitBoxToText', 'on');
    end
    box(ax1, 'on'); grid(ax1, 'on');
    safe_label = safe_for_filename(qoi_label);
    try exportgraphics(fig1, sprintf('%s_%s_hist.pdf', save_prefix, safe_label), 'ContentType','vector','BackgroundColor','white'); catch, end
    print(fig1, sprintf('%s_%s_hist.png', save_prefix, safe_label), '-dpng', '-r250');

    % ---- CDF ----
    fig2 = figure('Position', [80 80 560 420], 'Color', 'w');
    ax2 = axes(fig2);
    qs = sort(qvals); cdf_v = (1:numel(qs))'/numel(qs);
    plot(ax2, qs, cdf_v, 'b-', 'LineWidth', 2.5);
    hold(ax2, 'on');
    if is_fs
        plot(ax2, [1 1], [0 1], 'k--', 'LineWidth', 2);
        if ~isnan(pf) && pf > 0 && pf < 1
            plot(ax2, 1, pf, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
        end
    end
    xlabel(ax2, xlab, 'Interpreter', 'latex', 'FontSize', 18);
    ylabel(ax2, sprintf('$P(%s \\leq x)$', qoi_tex), 'Interpreter', 'latex', 'FontSize', 18);
    title(ax2, sprintf('%s --- CDF', ttl), 'Interpreter', 'latex', 'FontSize', 14);
    box(ax2, 'on'); grid(ax2, 'on');
    try exportgraphics(fig2, sprintf('%s_%s_cdf.pdf', save_prefix, safe_label), 'ContentType','vector','BackgroundColor','white'); catch, end
    print(fig2, sprintf('%s_%s_cdf.png', save_prefix, safe_label), '-dpng', '-r250');

    % ---- Scatter per parameter ----
    for k = 1:size(samples, 2)
        fig_k = figure('Position', [80 80 560 420], 'Color', 'w');
        ax_k = axes(fig_k);
        scatter(ax_k, samples(:,k), qvals, 40, [0.2 0.5 0.8], 'filled', 'MarkerFaceAlpha', 0.6);
        if is_fs
            hold(ax_k, 'on');
            plot(ax_k, xlim(ax_k), [1 1], 'k--', 'LineWidth', 2);
        end
        xlabel(ax_k, strrep(param_names{k},'_','\_'), 'Interpreter', 'latex', 'FontSize', 18);
        ylabel(ax_k, xlab, 'Interpreter', 'latex', 'FontSize', 18);
        title(ax_k, sprintf('%s --- %s vs %s', ttl, strrep(param_names{k},'_','\_'), qoi_tex), ...
            'Interpreter', 'latex', 'FontSize', 14);
        box(ax_k, 'on'); grid(ax_k, 'on');
        try exportgraphics(fig_k, sprintf('%s_%s_scatter_%s.pdf', save_prefix, safe_label, param_names{k}), ...
                'ContentType','vector','BackgroundColor','white'); catch, end
        print(fig_k, sprintf('%s_%s_scatter_%s.png', save_prefix, safe_label, param_names{k}), '-dpng', '-r250');
    end
end


function s = safe_for_filename(s)
    s = regexprep(s, '[^A-Za-z0-9_-]', '_');
    if isempty(s), s = 'qoi'; end
end


function cb_open_figs(fig, res_tbl)
% Open sweep figures for checked rows.
% All checked scenarios for the SAME case are combined into ONE figure
% (side-by-side comparison, exactly like NZ.m). Each unique case gets its
% own independent figure window.
    st = getappdata(fig, 'state');
    row_data = res_tbl.Data;
    if isempty(st.case_result_map) || isempty(row_data)
        uialert(fig, 'No results yet. Run a sweep first.', 'No results'); return;
    end

    % Collect checked (case_name, label) pairs
    want_cn  = {};
    want_lbl = {};
    for r = 1:size(row_data, 1)
        if isequal(row_data{r,1}, true)
            want_cn{end+1}  = row_data{r,2};  %#ok<AGROW>
            want_lbl{end+1} = row_data{r,3};  %#ok<AGROW>
        end
    end
    if isempty(want_cn)
        uialert(fig, 'Tick the checkbox on one or more rows first.', 'Nothing checked'); return;
    end

    % Process each unique case independently — one figure window per case
    opened     = 0;
    done_cases = {};
    for k = 1:numel(st.case_result_map)
        m  = st.case_result_map{k};
        cn = m.case_name;
        if ~any(strcmp(want_cn, cn)), continue; end          % nothing checked for this case
        if any(strcmp(done_cases, cn)),        continue; end  % already processed

        % Gather ALL checked scenarios for this case across every map entry
        % (handles results from multiple separate Run calls)
        cn_labels  = want_lbl(strcmp(want_cn, cn));
        yaml_path  = m.yaml_path;
        chap_str   = m.chap_str;
        sweep_disp = m.sweep_display;

        % Collect matching scenarios into a cell array first — avoids
        % "dissimilar structures" error from struct([]) initialisation.
        sc_cells = {};
        for k2 = 1:numel(st.case_result_map)
            m2 = st.case_result_map{k2};
            if ~strcmp(m2.case_name, cn), continue; end
            for si = 1:numel(m2.case_results)
                if any(strcmp(cn_labels, m2.case_results(si).label))
                    sc_cells{end+1} = m2.case_results(si); %#ok<AGROW>
                end
            end
        end
        done_cases{end+1} = cn; %#ok<AGROW>

        if isempty(sc_cells), continue; end

        % Convert cell array → struct array (safe: all elements share same fields)
        all_sc = sc_cells{1};
        for ii = 2:numel(sc_cells)
            all_sc(ii) = sc_cells{ii}; %#ok<AGROW>
        end

        % If mixed single/multi-param runs, x-axis label falls back to 'Scenario'
        if numel(all_sc) > 1
            sweep_disp = 'Scenario';
        end

        runs_dir   = fullfile(st.repo_root, 'runs', chap_str, cn);
        if ~exist(runs_dir, 'dir'), mkdir(runs_dir); end
        ts         = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
        fig_prefix = fullfile(runs_dir, sprintf('%s_sweep_%s', cn, ts));
        try
            figs_out = pfem_plot_sweep_summary(all_sc, sweep_disp, yaml_path, ...
                'Title', sprintf('PFEM %s  [%d scenario(s)]', cn, numel(all_sc)), ...
                'Save', fig_prefix, 'Show', true);
            % Raise each created figure above the uifigure window
            for fn = fieldnames(figs_out)'
                f = figs_out.(fn{1});
                if ~isempty(f) && ishandle(f)
                    figure(f);
                end
            end
            drawnow;
            opened = opened + 1;
        catch ex
            uialert(fig, ex.message, sprintf('Figure error: %s', cn));
        end
    end
    if opened == 0
        uialert(fig, 'No results matched the checked rows.', 'Nothing opened');
    end
end


function cb_print_compare(fig, log_ta, res_tbl)
% Show text comparison in the GUI log.
% Requires 2+ rows selected (Ctrl/Shift). Single-row selection makes no
% sense for a comparative sweep — alert the user instead.
    st = getappdata(fig, 'state');
    if isempty(st.case_result_map)
        uialert(fig, 'No results yet. Run a sweep first.', 'No results'); return;
    end

    row_data = res_tbl.Data;
    want_cn  = {};
    want_lbl = {};
    for r = 1:size(row_data, 1)
        if isequal(row_data{r,1}, true)
            want_cn{end+1}  = row_data{r,2};  %#ok<AGROW>
            want_lbl{end+1} = row_data{r,3};  %#ok<AGROW>
        end
    end
    if isempty(want_cn)
        uialert(fig, 'Tick the checkbox on one or more rows first.', 'Nothing checked'); return;
    end
    if numel(want_cn) < 2
        uialert(fig, sprintf('Tick 2 or more rows to compare scenarios.\nA single run has nothing to compare against.'), ...
                'Need 2+ rows'); return;
    end

    append_log(log_ta, '══════════════════════════════════════════════════════');
    append_log(log_ta, sprintf('  Comparison: %d checked scenario(s) vs original', numel(want_cn)));
    append_log(log_ta, '══════════════════════════════════════════════════════');

    found = 0;
    for k = 1:numel(st.case_result_map)
        m = st.case_result_map{k};
        for si = 1:numel(m.case_results)
            r = m.case_results(si);
            % Check if this scenario is in the selection
            match = false;
            for ri = 1:numel(want_cn)
                if strcmp(want_cn{ri}, m.case_name) && strcmp(want_lbl{ri}, r.label)
                    match = true; break;
                end
            end
            if ~match || r.status ~= 0, continue; end
            found = found + 1;
            append_log(log_ta, sprintf('─── %s  |  %s ───', m.case_name, r.label));
            try
                txt = evalc('pfem_compare_results(r.out, ''plot'', false, ''text'', true)');
                lns = strsplit(txt, newline);
                for li = 1:numel(lns)
                    ln = strtrim(lns{li});
                    if ~isempty(ln)
                        append_log(log_ta, ['  ' ln]);
                    end
                end
            catch ex
                append_log(log_ta, sprintf('  [compare error] %s', ex.message));
            end
        end
    end

    if found == 0
        append_log(log_ta, '  (no successful runs matched the selection)');
    end
    append_log(log_ta, '══════════════════════════════════════════════════════');
end


%% ============================================================================
%%  HELPER FUNCTIONS
%% ============================================================================

function refresh_cases(case_lb, yaml_paths)
    if isempty(yaml_paths)
        case_lb.Items = {};  case_lb.Value = {};  return;
    end
    case_lb.Items = cellfun(@short_path, yaml_paths, 'UniformOutput', false);
    case_lb.Value = {};
end


function refresh_params(fig, param_tbl)
% Reload union of tunable parameters from all loaded YAMLs and rebuild table.
    st = getappdata(fig, 'state');
    if isempty(st.yaml_paths)
        param_tbl.Data = {};  return;
    end

    % Build union map: name → {chaps[], range, desc}
    all_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for k = 1:numel(st.yaml_paths)
        try
            y    = pfem_yaml_load(st.yaml_paths{k});
            chap = num2str(y.authors.source.chapter);
            tp   = y.tunable_parameters;
            for ti = 1:numel(tp)
                p  = tp{ti};
                nm = p.name;
                if isKey(all_map, nm)
                    e = all_map(nm);
                    if ~ismember(chap, e.chaps), e.chaps{end+1} = chap; end
                else
                    e       = struct();
                    e.chaps = {chap};
                    e.range = '';
                    e.desc  = '';
                    e.defval = '';
                    if isfield(p, 'suggested_range') && ~isempty(p.suggested_range)
                        rng = p.suggested_range;
                        if iscell(rng), rng = cellfun(@to_dbl, rng); end
                        if numel(rng) >= 2
                            e.range = sprintf('[%s, %s]', cnum(rng(1)), cnum(rng(end)));
                        end
                    end
                    if isfield(p, 'description'), e.desc = p.description; end
                    if isfield(p, 'current_value') && ~isempty(p.current_value)
                        cv = p.current_value;
                        if isnumeric(cv)
                            e.defval = num2str(cv, '%g');
                        elseif ischar(cv) || isstring(cv)
                            e.defval = strtrim(char(cv));
                        end
                    end
                end
                all_map(nm) = e;
            end
        catch
        end
    end

    % Preserve user-entered values
    old_data = param_tbl.Data;
    old_vals = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for r = 1:size(old_data, 1)
        if size(old_data, 2) >= 3 && ~isempty(old_data{r,2})
            old_vals(old_data{r,2}) = old_data{r,3};
        end
    end

    % Build new table data (sorted by name)
    names = sort(keys(all_map));
    data  = cell(numel(names), 5);
    for i = 1:numel(names)
        nm = names{i};
        e  = all_map(nm);
        data{i,1} = true;
        data{i,2} = nm;
        if isKey(old_vals, nm) && ~isempty(old_vals(nm))
            data{i,3} = old_vals(nm);
        else
            data{i,3} = e.defval;   % YAML current_value as default
        end
        data{i,4} = e.range;
        data{i,5} = strjoin(e.chaps, ', ');
    end
    param_tbl.Data = data;
end


function [scenarios, err] = build_scenarios(param_tbl, sweep_dd)
% Parse enabled table rows and build scenario struct array.
    scenarios = struct([]);
    err       = '';

    data = param_tbl.Data;
    if isempty(data), err = 'No parameters loaded.'; return; end

    param_names = {};
    param_vals  = {};
    for i = 1:size(data, 1)
        if ~data{i,1}, continue; end           % disabled
        vs = strtrim(data{i,3});
        if isempty(vs), continue; end          % no values entered
        v = str2num(vs);                       %#ok<ST2NM>
        if isempty(v)
            err = sprintf('Cannot parse values for "%s": "%s"', data{i,2}, vs);
            return;
        end
        param_names{end+1} = data{i,2};       %#ok<AGROW>
        param_vals{end+1}  = v(:)';           %#ok<AGROW>
    end

    if isempty(param_names), err = 'No enabled parameters have values entered.'; return; end

    is_grid = contains(sweep_dd.Value, 'Grid');

    if is_grid
        % Cartesian product via ndgrid
        n_total = prod(cellfun(@numel, param_vals));
        if n_total > 500
            err = sprintf('Grid would produce %d scenarios (max 500). Reduce values or use Lockstep.', n_total);
            return;
        end
        idx_cells = cellfun(@(v) 1:numel(v), param_vals, 'UniformOutput', false);
        grids     = cell(1, numel(param_vals));
        [grids{:}] = ndgrid(idx_cells{:});
        sc_list   = cell(1, n_total);
        for si = 1:n_total
            sc    = struct();
            parts = {};
            for k = 1:numel(param_names)
                idx        = grids{k}(si);
                val        = param_vals{k}(idx);
                sc.(param_names{k}) = val;
                parts{end+1} = sprintf('%s=%s', abbrev(param_names{k}), cnum(val)); %#ok<AGROW>
            end
            sc.label    = strjoin(parts, ' ');
            sc_list{si} = sc;
        end
        scenarios = [sc_list{:}];
    else
        % Lockstep — delegate to pfem_make_scenarios
        n_vals = cellfun(@numel, param_vals);
        if ~all(n_vals == n_vals(1))
            err = sprintf('Lockstep requires equal-length value arrays. Got lengths: %s', ...
                          mat2str(n_vals));
            return;
        end
        args = reshape([param_names; param_vals], 1, []);
        scenarios = pfem_make_scenarios(args{:});
    end
end


function s = get_max_u_str(out)
% Return compact max|u| string from run output struct.
    s = '-';
    if ~isfield(out,'files') || isempty(out.files), return; end
    res_f = out.files(cellfun(@(f) endsWith(f,'.res'), out.files));
    if isempty(res_f), return; end
    try
        fid = fopen(res_f{1}, 'r');
        if fid == -1, return; end
        raw   = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
        fclose(fid);
        lines = raw{1};

        % Format A: per-node displacement header
        for i = 1:numel(lines)
            if contains(lines{i},'Node') && contains(lines{i},'disp')
                dd = [];
                for j = i+1:min(i+2000, numel(lines))
                    ln = strtrim(lines{j});
                    if isempty(ln) || contains(ln,'Element') || contains(ln,'integration'), break; end
                    v = sscanf(ln, '%f');
                    if numel(v) >= 2, dd(end+1,:) = v(2:end)'; end %#ok<AGROW>
                end
                if ~isempty(dd), s = sprintf('%.3e', max(abs(dd(:)))); return; end
            end
        end

        % Format B: load-step table ("step load disp iters" or "srf max disp iters")
        for i = 1:numel(lines)
            hdr = lines{i};
            is_srf = contains(hdr,'srf') && contains(hdr,'disp');
            is_std = contains(hdr,'step') && contains(hdr,'load') && contains(hdr,'disp');
            if is_srf || is_std
                last_u = nan;
                disp_col = 3; if is_srf, disp_col = 2; end
                for j = i+1:numel(lines)
                    ln = strtrim(lines{j});
                    if isempty(ln), break; end
                    v = sscanf(ln, '%f');
                    if numel(v) >= disp_col, last_u = v(disp_col); end
                end
                if ~isnan(last_u), s = sprintf('%.3e', abs(last_u)); end
                return;
            end
        end

        % Format C: seepage/consolidation — show max Uav (consolidation degree)
        for i = 1:numel(lines)
            if contains(lines{i},'Time') && contains(lines{i},'Uav')
                last_uav = nan;
                for j = i+1:numel(lines)
                    ln = strtrim(lines{j});
                    if isempty(ln) || contains(ln,'Depth'), break; end
                    v = sscanf(ln, '%f');
                    if numel(v) >= 2, last_uav = v(2); end
                end
                if ~isnan(last_uav), s = sprintf('%.3f Uav', abs(last_uav)); end
                return;
            end
        end
    catch
    end
end


function append_log(log_ta, msg)
    cur = log_ta.Value;
    if ischar(cur), cur = {cur}; end
    log_ta.Value = [cur; {msg}];
    scroll(log_ta, 'bottom');
    drawnow;
end


function on_mode_change(sweep_dd, count_lbl, lhs_cb, btn_corr)
% Update counter label when user switches mode; enable LHS toggle and Corr button only in stochastic mode.
    is_stoch = contains(sweep_dd.Value, 'Stochastic');
    is_sens  = contains(sweep_dd.Value, 'Sensitivity');
    if is_stoch
        count_lbl.Text = '50';
        count_lbl.Tooltip = 'Number of Monte Carlo samples — use +/- to adjust (10–500)';
    elseif is_sens
        count_lbl.Text = '-';
        count_lbl.Tooltip = 'Sensitivity mode runs 2k+1 simulations (k = enabled stochastic params) — counter not used';
    else
        count_lbl.Text = '4';
        count_lbl.Tooltip = 'Number of values generated by Fill Ranges (1–20)';
    end
    if nargin >= 3 && isvalid(lhs_cb)
        if is_stoch, lhs_cb.Enable = 'on'; else, lhs_cb.Enable = 'off'; end
    end
    if nargin >= 4 && isvalid(btn_corr)
        if is_stoch, btn_corr.Enable = 'on'; else, btn_corr.Enable = 'off'; end
    end
end


function adj_count(count_lbl, delta, sweep_dd)
% Increment/decrement counter. In stochastic mode: samples (1–500). Otherwise: values (1–20).
    is_stoch = nargin >= 3 && contains(sweep_dd.Value, 'Stochastic');
    n = str2double(count_lbl.Text) + delta;
    if is_stoch
        % Larger steps for sample counts: 10 at a time
        n = str2double(count_lbl.Text) + delta * 10;
        count_lbl.Text = num2str(max(10, min(500, n)));
        count_lbl.Tooltip = 'Number of Monte Carlo samples (10–500)';
    else
        count_lbl.Text = num2str(max(1, min(20, n)));
        count_lbl.Tooltip = 'Number of values generated by Fill Ranges (1–20)';
    end
end


%% ── UI factory helpers ───────────────────────────────────────────────────────

function h = spanel(parent, title_str, row, col)
% Styled dark panel.
    h = uipanel(parent, 'Title', title_str, ...
        'BackgroundColor', [0.10 0.10 0.12], ...
        'ForegroundColor', [0.72 0.72 0.72], ...
        'BorderType', 'line');
    h.Layout.Row    = row;
    h.Layout.Column = col;
end


function h = sbtn(parent, label, bg, row, col)
% Styled dark button.
    h = uibutton(parent, 'Text', label, ...
        'BackgroundColor', bg, ...
        'FontColor', [0.90 0.90 0.90], ...
        'FontSize', 11);
    h.Layout.Row    = row;
    h.Layout.Column = col;
end


%% ── Numeric helpers ──────────────────────────────────────────────────────────

function s = cnum(v)
% Compact number string for labels and display.
    if v == 0
        s = '0';
    elseif abs(v) >= 1e4 || (abs(v) < 0.01 && v ~= 0)
        s = regexprep(sprintf('%.3g', v), 'e[+]?0*(\d)', 'e$1');
        s = regexprep(s, 'e-0*(\d)', 'e-$1');
    else
        s = sprintf('%g', v);
    end
end


function out = round_sig4(v)
% Round to 4 significant figures.
    out = zeros(size(v));
    for i = 1:numel(v)
        if v(i) == 0, out(i) = 0; continue; end
        mag     = floor(log10(abs(v(i)))) - 3;
        out(i)  = round(v(i) / 10^mag) * 10^mag;
    end
end


function d = to_dbl(x)
    if isnumeric(x), d = double(x);
    elseif ischar(x), d = str2double(x);
    else, d = 0;
    end
end


function s = ifelse(cond, a, b)
    if cond, s = a; else, s = b; end
end


function tf = is_int_param(name)
% Returns true for PFEM parameters that Fortran reads as INTEGER.
% Passing floats (e.g. 7.937) for these causes "Bad integer" runtime errors.
    INT_PARAMS = { ...
        'load_increments', 'iteration_limit', 'number_of_steps', ...
        'nels_or_nxe', 'np_types_or_nye', 'number_of_modes', ...
        'num_eigenvalues', 'krylov_subspace_size', 'max_arnoldi_iterations', ...
        'cg_iteration_limit' };
    tf = any(strcmp(name, INT_PARAMS));
end


function s = short_path(p)
% 'chap06/p61' style short label for listbox.
    [d, fn, ~] = fileparts(p);
    [~, chap]  = fileparts(d);
    s = [chap '/' fn];
end


function s = abbrev(pname)
% Short abbreviation for parameter names (Grid mode scenario labels).
    map = struct( ...
        'youngs_modulus_E',          'E',     'poisson_ratio_nu',          'nu',    ...
        'yield_stress',              'sy',    'density_rho',               'rho',   ...
        'mass_per_length_rhoA',      'rhoA',  'stiffness_E_or_EI',         'EI',    ...
        'axial_stiffness_EA',        'EA',    'heat_capacity_rhoc',        'rhoc',  ...
        'unit_weight_gamma',         'UW',    'unit_weight_fill',          'UW_f',  ...
        'unit_weight_embankment',    'UW_e',  'friction_angle_phi',        'phi',   ...
        'friction_angle_fill',       'phi_f', 'friction_angle_embankment', 'phi_e', ...
        'cohesion_c',                'c',     'cohesion_fill',             'c_f',   ...
        'cohesion_embankment',       'c_e',   'dilation_angle_psi',        'psi',   ...
        'dilation_angle_fill',       'psi_f', 'dilation_angle_embankment', 'psi_e', ...
        'earth_pressure_coeff_k0',   'k0',    'permeability_k_or_cv',      'k',     ...
        'permeability_kx',           'kx',    'permeability_ky',           'ky',    ...
        'conductivity_kx',           'kx',    'conductivity_ky',           'ky',    ...
        'bulk_modulus_ke',           'ke',    'initial_effective_stress',  'cons',  ...
        'dynamic_viscosity',         'visc',  'convergence_tolerance',     'tol',   ...
        'iteration_limit',           'lim',   'load_increments',           'incs',  ...
        'cg_tolerance',              'cg_t',  'cg_iteration_limit',        'cg_l',  ...
        'local_yield_tolerance_ltol','ltol',  'prescribed_increment',      'presc', ...
        'time_step_dtim',            'dt',    'number_of_steps',           'nstep', ...
        'theta_integration',         'theta', 'mass_damping_factor',       'fm',    ...
        'stiffness_damping_factor',  'fk',    'damping_ratio',             'dr',    ...
        'newmark_beta',              'beta',  'newmark_gamma',             'gam',   ...
        'natural_frequency',         'omega', 'number_of_modes',           'nmodes',...
        'num_eigenvalues',           'nev',   'krylov_subspace_size',      'ncv',   ...
        'max_arnoldi_iterations',    'maxitr','nels_or_nxe',               'nxe',   ...
        'np_types_or_nye',           'nye',   'youngs_modulus_fill',       'E_f',   ...
        'youngs_modulus_embankment', 'E_e',   'poisson_ratio_fill',        'nu_f',  ...
        'poisson_ratio_embankment',  'nu_e'   ...
    );
    if isfield(map, pname)
        s = map.(pname);
    else
        s = pname(1:min(6, end));
    end
end
