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

    close all;   % close any open figures / previous GUI instances

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
        'stop_flag',       false);
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
    sw = uigridlayout(pg, [1, 8]);
    sw.Layout.Row = 2;  sw.Layout.Column = 1;
    sw.ColumnWidth = {'fit', 210, 'fit', 28, 34, 28, 'fit', '1x'};
    sw.RowHeight = {'1x'};  sw.Padding = [0 2 0 2];  sw.ColumnSpacing = 4;
    sw.BackgroundColor = [0.10 0.10 0.12];

    lbl_mode = uilabel(sw, 'Text', 'Mode:', ...
        'FontColor', [0.65 0.65 0.65], 'FontSize', 11);
    lbl_mode.Layout.Row = 1;  lbl_mode.Layout.Column = 1; %#ok<NASGU>

    sweep_dd = uidropdown(sw, ...
        'Items', {'Lockstep  (same-length arrays)', 'Grid  (Cartesian product)'}, ...
        'Value', 'Lockstep  (same-length arrays)', ...
        'BackgroundColor', [0.15 0.15 0.18], ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 11, ...
        'Tooltip', sprintf(['Lockstep: parameters vary together — E=[1e4,2e4], nu=[0.2,0.3] → 2 scenarios\n' ...
                            'Grid: all combinations — E=[1e4,2e4], nu=[0.2,0.3] → 4 scenarios (max 500)']));
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

    btn_preview = sbtn(sw, 'Preview Scenarios', [0.16 0.28 0.16], 1, 7);

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
        'ColumnName',     {'', 'Case', 'Scenario', 'Status', 'max|u|', 'Run Directory'}, ...
        'ColumnFormat',   {'logical', 'char', 'char', 'char', 'char', 'char'}, ...
        'ColumnEditable', [true, false, false, false, false, false], ...
        'ColumnWidth',    {24, 70, 205, 52, 100, 350}, ...
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
    btn_fill.ButtonPushedFcn    = @(~,~) cb_fill_ranges(fig, param_tbl, count_lbl);
    btn_minus.ButtonPushedFcn   = @(~,~) adj_count(count_lbl, -1);
    btn_plus.ButtonPushedFcn    = @(~,~) adj_count(count_lbl, +1);
    btn_preview.ButtonPushedFcn = @(~,~) cb_preview(param_tbl, sweep_dd, log_ta);
    btn_run.ButtonPushedFcn     = @(~,~) cb_run(fig, param_tbl, sweep_dd, log_ta, prog_lbl, res_tbl);
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


function cb_fill_ranges(~, param_tbl, count_lbl)
% Populate Values column with N log-spaced values within each suggested range.
% N is controlled by the [-][N][+] counter next to this button.
    n = max(1, min(20, round(str2double(count_lbl.Text))));
    data = param_tbl.Data;
    if isempty(data), return; end
    for i = 1:size(data, 1)
        if ~data{i,1}, continue; end         % skip disabled rows
        rng_str = strtrim(data{i,4});
        if isempty(rng_str), continue; end
        rng = str2num(rng_str);              %#ok<ST2NM>
        if numel(rng) < 2, continue; end
        lo = rng(1);  hi = rng(end);
        if lo <= 0, lo = max(hi / 1e3, 1e-12); end
        if lo <= 0 || hi <= 0 || lo >= hi, continue; end
        if n == 1
            vals = sqrt(lo * hi);            % geometric mean — single representative value
        else
            vals = round_sig4(logspace(log10(lo), log10(hi), n));
        end
        data{i,3} = num2str(vals, '%.4g  ');
    end
    param_tbl.Data = data;
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


function cb_run(fig, param_tbl, sweep_dd, log_ta, prog_lbl, res_tbl)
    st = getappdata(fig, 'state');
    if isempty(st.yaml_paths)
        uialert(fig, 'Add at least one YAML case first.', 'No cases'); return;
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
            if status == 0
                append_log(log_ta, sprintf('    OK  — %d file(s)   max|u| = %s', out.num_files, max_u));
            else
                append_log(log_ta, sprintf('    FAILED (exit %d)', status));
                max_u = '-';
            end

            % Append row to results table (col1 = checkbox)
            n = size(row_data, 1) + 1;
            row_data{n,1} = false;
            row_data{n,2} = case_name;
            row_data{n,3} = label;
            row_data{n,4} = ifelse(status==0, 'OK', 'FAIL');
            row_data{n,5} = max_u;
            row_data{n,6} = out.run_dir;
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
        fig_prefix = fullfile(runs_dir, sprintf('%s_sweep', cn));
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
                    if isfield(p, 'suggested_range') && ~isempty(p.suggested_range)
                        rng = p.suggested_range;
                        if iscell(rng), rng = cellfun(@to_dbl, rng); end
                        if numel(rng) >= 2
                            e.range = sprintf('[%s, %s]', cnum(rng(1)), cnum(rng(end)));
                        end
                    end
                    if isfield(p, 'description'), e.desc = p.description; end
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
        if isKey(old_vals, nm)
            data{i,3} = old_vals(nm);
        else
            data{i,3} = '';
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

        % Format B: load-step table
        for i = 1:numel(lines)
            if contains(lines{i},'step') && contains(lines{i},'load') && contains(lines{i},'disp')
                last_u = nan;
                for j = i+1:numel(lines)
                    ln = strtrim(lines{j});
                    if isempty(ln), break; end
                    v = sscanf(ln, '%f');
                    if numel(v) >= 3, last_u = v(3); end
                end
                if ~isnan(last_u), s = sprintf('%.3e', abs(last_u)); end
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


function adj_count(count_lbl, delta)
% Increment or decrement the Fill Ranges count (clamped to 1–20).
    n = str2double(count_lbl.Text) + delta;
    count_lbl.Text = num2str(max(1, min(20, n)));
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
