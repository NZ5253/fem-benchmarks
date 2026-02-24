function pfem_studio(yaml_path, pfem_root)
% PFEM_STUDIO  Unified PFEM study environment — replaces NZ.m
%
% Usage:
%   pfem_studio()                             % file picker opens
%   pfem_studio('benchmarks/pfem5/chap06/p61.yaml')
%   pfem_studio(yaml_path, pfem_root)
%
% Layout:
%   Left  (53%): Undeformed mesh (from YAML, updates after each run)
%   Right top   : Deformed mesh + displacement colour map
%   Right bottom: Results summary
%   Right strip : Parameter editor + Run button
%
% Sweep mode:
%   Type comma-separated values in any edit field  (e.g.  50, 100, 200, 500)
%   Press Run → studio runs PFEM for each value and opens a sweep summary figure
%
% Good test case:  benchmarks/pfem5/chap06/p61.yaml
%   Try:  yield_stress  =  50, 100, 200, 500
%         youngs_modulus_E  =  5e4, 1e5, 2e5

    repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
    if nargin < 2 || isempty(pfem_root)
        pfem_root = fullfile(getenv('HOME'), 'Downloads', 'pfem5', '5th_ed');
    end

    % ---- YAML selection ----
    if nargin < 1 || isempty(yaml_path)
        start_dir = fullfile(repo_root, 'benchmarks', 'pfem5');
        [fname, fpath] = uigetfile('*.yaml', 'Select PFEM YAML', start_dir);
        if isequal(fname, 0), return; end
        yaml_path = fullfile(fpath, fname);
    end

    addpath(genpath(fullfile(repo_root, 'matlab')));

    if startsWith(yaml_path, '~')
        yaml_path = [getenv('HOME') yaml_path(2:end)];
    end
    if ~isabspath(yaml_path)
        yaml_path = fullfile(repo_root, yaml_path);
    end
    if ~exist(yaml_path, 'file')
        error('YAML not found: %s', yaml_path);
    end

    yaml = pfem_yaml_load(yaml_path);

    % ---- Figure ----
    fig = figure('Name', sprintf('PFEM Studio — %s', yaml.title), ...
                 'Position', [30 30 1550 820], ...
                 'Color', [0.12 0.12 0.15], 'NumberTitle', 'off');

    % Top bar: case info + Load button
    uicontrol('Parent', fig, 'Style', 'text', ...
              'String', yaml.title, ...
              'Units', 'normalized', 'Position', [0.01 0.965 0.44 0.028], ...
              'HorizontalAlignment', 'left', 'FontSize', 9, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.12 0.12 0.15], 'ForegroundColor', [0.80 0.85 0.90]);

    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
              'String', 'Load YAML...', ...
              'Units', 'normalized', 'Position', [0.46 0.963 0.08 0.030], ...
              'FontSize', 8, ...
              'BackgroundColor', [0.25 0.30 0.35], 'ForegroundColor', [0.9 0.9 0.9], ...
              'Callback', @(~,~) reload_yaml(fig, repo_root, pfem_root));

    % ========== LEFT: undeformed mesh ==========
    ax_mesh = axes('Parent', fig, ...
                   'Position', [0.01 0.05 0.52 0.91], ...
                   'Color', [0.08 0.08 0.10]);
    axis(ax_mesh, 'equal'); axis(ax_mesh, 'off');

    % ========== RIGHT TOP: deformed mesh ==========
    ax_def = axes('Parent', fig, ...
                  'Position', [0.555 0.42 0.415 0.545], ...
                  'Color', [0.08 0.08 0.10]);
    axis(ax_def, 'off');
    text(ax_def, 0.5, 0.5, sprintf('Press  Run Simulation\nto see deformed mesh'), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
         'FontSize', 12, 'Color', [0.38 0.38 0.38], 'Units', 'normalized');

    % ========== RIGHT BOTTOM: stats ==========
    stats_pan = uipanel('Parent', fig, ...
                        'Title', 'Results Summary', ...
                        'FontSize', 9, 'FontWeight', 'bold', ...
                        'Position', [0.555 0.02 0.415 0.37], ...
                        'BackgroundColor', [0.10 0.10 0.13], ...
                        'ForegroundColor', [0.65 0.65 0.65]);
    stats_txt = uicontrol('Parent', stats_pan, 'Style', 'text', ...
                          'String', 'No results yet.', ...
                          'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.94], ...
                          'HorizontalAlignment', 'left', 'FontSize', 8, ...
                          'FontName', 'Monospaced', ...
                          'BackgroundColor', [0.10 0.10 0.13], ...
                          'ForegroundColor', [0.68 0.90 0.68]);

    % ========== RIGHT STRIP: param panel ==========
    param_pan = uipanel('Parent', fig, ...
                        'Title', 'Tunable Parameters', ...
                        'FontSize', 9, 'FontWeight', 'bold', ...
                        'Position', [0.545 0.02 0.45 0.96], ...
                        'BackgroundColor', [0.15 0.15 0.20], ...
                        'ForegroundColor', [0.85 0.85 0.85]);

    % ---- Draw initial undeformed mesh ----
    draw_undeformed(ax_mesh, yaml_path, yaml);

    % ---- Build parameter editor ----
    [edit_handles, param_names] = ...
        build_param_ui(param_pan, ax_mesh, ax_def, stats_txt, ...
                       yaml, yaml_path, pfem_root, repo_root);

    % Store everything in figure for reload callback
    setappdata(fig, 'yaml_path',    yaml_path);
    setappdata(fig, 'pfem_root',    pfem_root);
    setappdata(fig, 'repo_root',    repo_root);
    setappdata(fig, 'edit_handles', edit_handles);
    setappdata(fig, 'param_names',  param_names);
    setappdata(fig, 'ax_mesh',      ax_mesh);
    setappdata(fig, 'ax_def',       ax_def);
    setappdata(fig, 'stats_txt',    stats_txt);
    setappdata(fig, 'param_pan',    param_pan);
end


% ==========================================================================
function reload_yaml(fig, repo_root, pfem_root)
% Load a new YAML into the same figure window

    start_dir = fullfile(repo_root, 'benchmarks', 'pfem5');
    [fname, fpath] = uigetfile('*.yaml', 'Select PFEM YAML', start_dir);
    if isequal(fname, 0), return; end
    yaml_path = fullfile(fpath, fname);

    % Clear axes and rebuild
    ax_mesh = getappdata(fig, 'ax_mesh');
    ax_def  = getappdata(fig, 'ax_def');
    stats_txt = getappdata(fig, 'stats_txt');
    param_pan = getappdata(fig, 'param_pan');

    yaml = pfem_yaml_load(yaml_path);

    % Update title bar
    set(fig, 'Name', sprintf('PFEM Studio — %s', yaml.title));
    title_ctrl = findobj(fig, 'Style', 'text', '-and', 'FontSize', 9);
    if ~isempty(title_ctrl), set(title_ctrl(end), 'String', yaml.title); end

    % Reset axes
    cla(ax_def); axis(ax_def,'off');
    text(ax_def, 0.5, 0.5, sprintf('Press  Run Simulation\nto see deformed mesh'), ...
         'HorizontalAlignment','center','VerticalAlignment','middle', ...
         'FontSize', 12, 'Color', [0.38 0.38 0.38], 'Units','normalized');
    set(stats_txt, 'String', 'No results yet.');

    % Rebuild param panel
    delete(get(param_pan, 'Children'));
    set(param_pan, 'Title', 'Tunable Parameters');

    draw_undeformed(ax_mesh, yaml_path, yaml);

    [edit_handles, param_names] = ...
        build_param_ui(param_pan, ax_mesh, ax_def, stats_txt, ...
                       yaml, yaml_path, pfem_root, repo_root);

    setappdata(fig, 'yaml_path',    yaml_path);
    setappdata(fig, 'edit_handles', edit_handles);
    setappdata(fig, 'param_names',  param_names);
end


% ==========================================================================
function draw_undeformed(ax, yaml_path, yaml)
% Draw undeformed mesh from YAML-derived coordinates

    cla(ax); hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');
    set(ax, 'Color', [0.08 0.08 0.10]);

    [nodes, elem_conn, meta] = pfem_extract_coords(yaml_path);

    if isempty(nodes)
        text(ax, 0.5, 0.5, 'Could not extract mesh coordinates', ...
             'HorizontalAlignment', 'center', 'Color', [0.6 0.4 0.4], ...
             'FontSize', 11, 'Units', 'normalized');
        hold(ax,'off'); return;
    end

    ndim = size(nodes, 2);

    if ndim == 1
        plot(ax, nodes(:,1), zeros(size(nodes,1),1), 'o-', ...
             'Color', [0.50 0.72 0.90], 'MarkerFaceColor', [0.50 0.72 0.90], ...
             'MarkerSize', 7, 'LineWidth', 1.5);
    elseif ~isempty(elem_conn)
        draw_elem_edges(ax, nodes, elem_conn, [0.38 0.50 0.62], 0.9);
        scatter(ax, nodes(:,1), nodes(:,2), 16, [0.65 0.80 0.95], ...
                'filled', 'MarkerEdgeColor', 'none');
    elseif isfield(meta, 'x_coords') && isfield(meta, 'y_coords')
        draw_grid(ax, meta.x_coords, meta.y_coords, [0.36 0.48 0.60], 1.0);
        scatter(ax, nodes(:,1), nodes(:,2), 14, [0.60 0.76 0.92], ...
                'filled', 'MarkerEdgeColor', 'none');
    else
        scatter(ax, nodes(:,1), nodes(:,2), 18, [0.60 0.76 0.92], ...
                'filled', 'MarkerEdgeColor', 'none');
    end

    nn_str   = '';  if isfield(meta,'nn'),      nn_str   = sprintf('%d nodes', meta.nn);  end
    prog_str = '';  if isfield(meta,'program'), prog_str = meta.program;                   end
    nod_str  = '';  if isfield(meta,'nod'),     nod_str  = sprintf('nod=%d', meta.nod);   end
    parts = {prog_str, nod_str, nn_str};
    parts = parts(~cellfun(@isempty, parts));
    info  = strtrim(strjoin(parts, '  '));

    title(ax, yaml.title, 'FontSize', 10, 'Color', [0.85 0.85 0.85], ...
          'Interpreter', 'none', 'FontWeight', 'bold');
    xlabel(ax, info, 'FontSize', 8, 'Color', [0.48 0.48 0.48], 'Interpreter', 'none');
    hold(ax, 'off');
end


% ==========================================================================
function draw_grid(ax, x_coords, y_coords, col, lw)
    for j = 1:numel(y_coords)
        plot(ax, x_coords([1 end]), [y_coords(j) y_coords(j)], '-', 'Color', col, 'LineWidth', lw);
    end
    for i = 1:numel(x_coords)
        plot(ax, [x_coords(i) x_coords(i)], y_coords([1 end]), '-', 'Color', col, 'LineWidth', lw);
    end
end

function draw_elem_edges(ax, nodes, elem_conn, col, lw)
    nod = size(elem_conn, 2);
    if nod>=8, order=[1 2 3 4 5 6 7 8 1]; elseif nod==4, order=[1 2 3 4 1];
    elseif nod==3, order=[1 2 3 1];        else, order=[1 2]; end
    for e = 1:size(elem_conn,1)
        c = elem_conn(e,:);
        o = order(order <= nod);
        plot(ax, nodes(c(o),1), nodes(c(o),2), '-', 'Color', col, 'LineWidth', lw);
    end
end


% ==========================================================================
function [edit_handles, param_names] = ...
         build_param_ui(pan, ax_mesh, ax_def, stats_txt, ...
                        yaml, yaml_path, pfem_root, repo_root)

    edit_handles = {};  param_names = {};

    if ~isfield(yaml, 'tunable_parameters')
        uicontrol('Parent', pan, 'Style', 'text', ...
                  'String', 'No tunable parameters found.', ...
                  'Units', 'normalized', 'Position', [0.04 0.86 0.92 0.08], ...
                  'ForegroundColor', [0.55 0.55 0.55], ...
                  'BackgroundColor', [0.15 0.15 0.20], 'FontSize', 9);
        return;
    end

    tparams = yaml.tunable_parameters;
    np      = numel(tparams);

    row_h  = min(0.064, 0.68 / np);
    top    = 0.97;
    lbl_w  = 0.55;  edit_w = 0.37;
    x_lbl  = 0.02;  x_edit = 0.61;

    for k = 1:np
        tp      = tparams{k};
        row_top = top - (k-1) * row_h;
        is_topo = isfield(tp,'note') && ~isempty(tp.note);
        lbl_col = [0.88 0.88 0.88];
        if is_topo, lbl_col = [1.00 0.74 0.38]; end

        uicontrol('Parent', pan, 'Style', 'text', ...
                  'String', format_label(tp), ...
                  'Units', 'normalized', ...
                  'Position', [x_lbl, row_top-row_h, lbl_w, row_h*0.82], ...
                  'HorizontalAlignment', 'left', 'FontSize', 8, ...
                  'ForegroundColor', lbl_col, 'BackgroundColor', [0.15 0.15 0.20]);

        cur = tp.current_value;
        if isnumeric(cur), val_str = num2str(cur, '%g');
        else,              val_str = strtrim(char(cur));
        end

        eh = uicontrol('Parent', pan, 'Style', 'edit', ...
                       'String', val_str, 'Tag', tp.name, ...
                       'Units', 'normalized', ...
                       'Position', [x_edit, row_top-row_h, edit_w, row_h*0.72], ...
                       'FontSize', 8, ...
                       'BackgroundColor', [0.20 0.20 0.27], ...
                       'ForegroundColor', [1 1 1]);
        edit_handles{end+1} = eh;
        param_names{end+1}  = tp.name;
    end

    sep_y = top - np*row_h - 0.010;

    % Hint for sweep mode
    uicontrol('Parent', pan, 'Style', 'text', ...
              'String', ['Tip: enter comma-separated values (e.g. 50,100,200) for a sweep' newline ...
                         '* orange = mesh-topology param'], ...
              'Units', 'normalized', ...
              'Position', [x_lbl, sep_y-0.055, 0.95, 0.048], ...
              'HorizontalAlignment', 'left', 'FontSize', 6.5, ...
              'ForegroundColor', [0.70 0.75 0.60], 'BackgroundColor', [0.15 0.15 0.20]);

    run_cb = @(~,~) run_simulation( ...
        yaml_path, pfem_root, repo_root, yaml, tparams, ...
        edit_handles, param_names, ax_mesh, ax_def, stats_txt);

    uicontrol('Parent', pan, 'Style', 'pushbutton', ...
              'String', 'Run Simulation', ...
              'Units', 'normalized', ...
              'Position', [0.05, sep_y-0.108, 0.90, 0.068], ...
              'FontSize', 10, 'FontWeight', 'bold', ...
              'BackgroundColor', [0.14 0.44 0.14], ...
              'ForegroundColor', [1 1 1], ...
              'Callback', run_cb);

    for k = 1:numel(edit_handles)
        set(edit_handles{k}, 'Callback', run_cb);
    end
end


% ==========================================================================
function run_simulation(yaml_path, pfem_root, repo_root, yaml, tparams, ...
                        edit_handles, param_names, ax_mesh, ax_def, stats_txt)
% Detect sweep vs single run, then dispatch

    % ---- Parse all edit fields ----
    scalar_overrides = struct();   % values with a single number
    sweep_param  = '';
    sweep_values = [];

    for k = 1:numel(edit_handles)
        str = strtrim(get(edit_handles{k}, 'String'));
        % str2num handles space- or comma-separated lists
        vals = str2num(str); %#ok<ST2NM>
        if isempty(vals), continue; end

        if numel(vals) > 1 && isempty(sweep_param)
            % First multi-value field → sweep parameter
            sweep_param  = param_names{k};
            sweep_values = vals;
        elseif numel(vals) == 1
            scalar_overrides.(param_names{k}) = vals;
        end
    end

    if ~isempty(sweep_param)
        % ---- SWEEP MODE ----
        run_sweep(yaml_path, pfem_root, repo_root, yaml, tparams, ...
                  sweep_param, sweep_values, scalar_overrides, ...
                  ax_mesh, ax_def, stats_txt);
    else
        % ---- SINGLE RUN ----
        run_single(yaml_path, pfem_root, repo_root, yaml, tparams, ...
                   scalar_overrides, ax_mesh, ax_def, stats_txt);
    end
end


% ==========================================================================
function run_single(yaml_path, pfem_root, repo_root, yaml, tparams, ...
                    overrides, ax_mesh, ax_def, stats_txt)
% Run PFEM once and display result

    % Find what changed
    changed = struct();
    fns = fieldnames(overrides);
    for k = 1:numel(fns)
        fn = fns{k};
        tp_idx = find(strcmp(cellfun(@(t) t.name, tparams, 'uni',0), fn), 1);
        if isempty(tp_idx), continue; end
        orig = tparams{tp_idx}.current_value;
        if ~isnumeric(orig), orig = str2double(orig); end
        if abs(overrides.(fn) - orig) > 1e-10 * max(abs(overrides.(fn)),1)
            changed.(fn) = overrides.(fn);
        end
    end

    % Running indicator
    cla(ax_def); axis(ax_def,'off');
    text(ax_def, 0.5, 0.5, 'Running simulation...', ...
         'HorizontalAlignment','center','VerticalAlignment','middle', ...
         'FontSize',12,'Color',[1.0 0.78 0.28],'Units','normalized');
    set(stats_txt,'String','Running...'); drawnow;

    try
        [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    catch ME
        show_error(ax_def, stats_txt, ME.message); return;
    end
    if status ~= 0
        show_error(ax_def, stats_txt, 'Simulation returned non-zero status.'); return;
    end

    draw_undeformed(ax_mesh, yaml_path, yaml);

    [nodes, disp_mat, elem_conn, meta] = parse_pfem_results(out, yaml_path);
    [~, stresses] = parse_stresses(out);

    if ~isempty(nodes) && ~isempty(disp_mat)
        plot_deformed(ax_def, nodes, disp_mat, elem_conn, meta, overrides);
    else
        cla(ax_def); axis(ax_def,'off');
        text(ax_def, 0.5,0.5,'No mesh data in output', ...
             'HorizontalAlignment','center','Color',[0.5 0.5 0.5],'FontSize',11,'Units','normalized');
    end

    set(stats_txt, 'String', build_stats(disp_mat, stresses, changed, out));
end


% ==========================================================================
function run_sweep(yaml_path, pfem_root, repo_root, yaml, tparams, ...
                   sweep_param, sweep_values, base_overrides, ...
                   ax_mesh, ax_def, stats_txt)
% Run PFEM for each value in sweep_values, then open a sweep summary figure

    n  = numel(sweep_values);
    results = struct('value',{}, 'status',{}, 'out',{}, ...
                     'nodes',{}, 'disp_mat',{}, 'elem_conn',{}, 'meta',{}, ...
                     'max_u',{});

    for i = 1:n
        v = sweep_values(i);
        overrides = base_overrides;
        overrides.(sweep_param) = v;

        % Progress in deformed axes
        cla(ax_def); axis(ax_def,'off');
        text(ax_def, 0.5, 0.5, sprintf('Sweep %d/%d  (%s = %.4g)', i, n, sweep_param, v), ...
             'HorizontalAlignment','center','VerticalAlignment','middle', ...
             'FontSize',11,'Color',[1.0 0.78 0.28],'Units','normalized');
        set(stats_txt,'String', sprintf('Running %d/%d: %s = %.4g', i, n, sweep_param, v));
        drawnow;

        try
            [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
        catch ME
            status = -1; out = struct('files',{{}},'run_name',''); %#ok<AGROW>
            fprintf('[Sweep %d/%d] Error: %s\n', i, n, ME.message);
        end

        results(i).value  = v;
        results(i).status = status;
        results(i).out    = out;

        if status == 0
            [nd, dm, ec, mt] = parse_pfem_results(out, yaml_path);
            results(i).nodes     = nd;
            results(i).disp_mat  = dm;
            results(i).elem_conn = ec;
            results(i).meta      = mt;
            if ~isempty(dm)
                results(i).max_u = max(sqrt(sum(dm(:,1:min(2,end)).^2, 2)));
            else
                results(i).max_u = NaN;
            end
        else
            results(i).nodes = []; results(i).disp_mat = []; results(i).max_u = NaN;
        end
    end

    % Update left panel with default mesh
    draw_undeformed(ax_mesh, yaml_path, yaml);

    % Show last successful result on the deformed axis
    last_ok = find([results.status]==0, 1, 'last');
    if ~isempty(last_ok) && ~isempty(results(last_ok).nodes)
        plot_deformed(ax_def, results(last_ok).nodes, results(last_ok).disp_mat, ...
                      results(last_ok).elem_conn, results(last_ok).meta, ...
                      struct(sweep_param, results(last_ok).value));
    end

    n_ok = sum([results.status]==0);
    sweep_label = strrep(sweep_param,'_',' ');
    set(stats_txt,'String', sprintf('Sweep done: %d/%d OK\nSee sweep figure for comparison.', n_ok, n));

    % ---- Open sweep summary figure ----
    plot_sweep_summary(results, sweep_param, sweep_label, yaml.title, yaml_path);
end


% ==========================================================================
function plot_sweep_summary(results, sweep_param, sweep_label, case_title, yaml_path)
% Show parameter-vs-max_u curve + tiled deformed meshes for each sweep value

    n    = numel(results);
    vals = [results.value];
    maxu = [results.max_u];

    % Layout: top row = parameter vs max|u|  (full width)
    %         bottom rows = tiled deformed meshes
    cols = min(n, 4);
    rows = ceil(n / cols);

    sfig = figure('Name', sprintf('Sweep: %s — %s', sweep_label, case_title), ...
                  'Position', [80 80 340*cols 280*(rows+1)], ...
                  'Color', [0.11 0.11 0.14]);

    % ---- Top: parameter vs max|u| ----
    ax_curve = subplot(rows+1, 1, 1, 'Parent', sfig);
    set(ax_curve, 'Color', [0.08 0.08 0.10], ...
                  'XColor',[0.7 0.7 0.7], 'YColor',[0.7 0.7 0.7], ...
                  'GridColor',[0.3 0.3 0.3], 'GridAlpha', 0.5);
    hold(ax_curve, 'on'); grid(ax_curve, 'on');

    ok = [results.status] == 0;
    plot(ax_curve, vals(ok), maxu(ok), 'o-', ...
         'Color', [0.40 0.75 0.40], 'MarkerFaceColor', [0.40 0.75 0.40], ...
         'LineWidth', 2, 'MarkerSize', 8);
    if any(~ok)
        plot(ax_curve, vals(~ok), zeros(sum(~ok),1), 'rx', 'MarkerSize', 12, 'LineWidth', 2);
    end
    xlabel(ax_curve, sweep_label, 'Color', [0.75 0.75 0.75], 'FontSize', 9);
    ylabel(ax_curve, 'max|u|', 'Color', [0.75 0.75 0.75], 'FontSize', 9);
    title(ax_curve, sprintf('%s — sweep of %s', case_title, sweep_label), ...
          'Color', [0.88 0.88 0.88], 'FontSize', 10, 'Interpreter', 'none');
    hold(ax_curve, 'off');

    % ---- Bottom: one mesh per sweep value ----
    for i = 1:n
        ax = subplot(rows+1, cols, cols + i, 'Parent', sfig);
        set(ax, 'Color', [0.08 0.08 0.10]);

        r = results(i);
        if r.status == 0 && ~isempty(r.nodes) && ~isempty(r.disp_mat)
            plot_deformed(ax, r.nodes, r.disp_mat, r.elem_conn, r.meta, struct());
            lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, r.value, r.max_u);
        else
            axis(ax, 'off');
            text(ax, 0.5, 0.5, sprintf('%s = %.4g\nFailed', sweep_label, r.value), ...
                 'HorizontalAlignment','center','Color',[1 0.4 0.4], ...
                 'FontSize',9,'Units','normalized');
            lbl = sprintf('%s = %.4g  [failed]', sweep_label, r.value);
        end
        title(ax, lbl, 'FontSize', 8, 'Color', [0.80 0.80 0.80], 'Interpreter', 'none');
    end
end


% ==========================================================================
function plot_deformed(ax, nodes, disp_mat, elem_conn, meta, overrides)

    cla(ax); hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');
    set(ax,'Color',[0.08 0.08 0.10]);

    if size(nodes,2) < 2, hold(ax,'off'); return; end

    nc = min(2, size(disp_mat,2));
    disp_mag = sqrt(sum(disp_mat(:,1:nc).^2, 2));
    max_mag  = max(disp_mag);

    W = max(nodes(:,1)) - min(nodes(:,1));
    H = max(nodes(:,2)) - min(nodes(:,2));
    sf = 1;
    if max_mag > 0, sf = 0.08 * max(W,H) / max_mag; end

    def = nodes;
    def(:,1) = nodes(:,1) + sf * disp_mat(:,1);
    def(:,2) = nodes(:,2) + sf * disp_mat(:,2);

    % Undeformed (faint)
    if ~isempty(elem_conn)
        draw_elem_edges(ax, nodes, elem_conn, [0.22 0.28 0.34], 0.5);
    elseif isfield(meta,'x_coords') && isfield(meta,'y_coords')
        draw_grid(ax, meta.x_coords, meta.y_coords, [0.20 0.26 0.32], 0.5);
    end

    % Deformed outline
    if ~isempty(elem_conn)
        draw_elem_edges(ax, def, elem_conn, [0.48 0.60 0.72], 0.9);
    end

    % Colour by |u|
    scatter(ax, def(:,1), def(:,2), 20, disp_mag, 'filled');
    colormap(ax, 'turbo');
    cb = colorbar(ax);
    cb.Color = [0.65 0.65 0.65];
    cb.Label.String = '|u|';  cb.Label.Color = [0.65 0.65 0.65];

    title(ax, sprintf('scale \x00D7%.0f', sf), ...
          'FontSize', 8, 'Color', [0.78 0.78 0.78]);
    hold(ax,'off');
end


% ==========================================================================
function [nodes, disp_mat, elem_conn, meta] = parse_pfem_results(out, yaml_path)
    nodes=[]; disp_mat=[]; elem_conn=[]; meta=struct();
    if ~isfield(out,'files') || isempty(out.files), return; end
    is_res    = cellfun(@(f) endsWith(f,'.res'), out.files);
    res_files = out.files(is_res);
    if isempty(res_files), return; end
    res_path = res_files{1};
    if ~exist(res_path,'file'), return; end

    lines = read_lines(res_path);
    disp_start=0; disp_cols=2;
    for i=1:numel(lines)
        ln=strtrim(lines{i});
        if contains(ln,'Node') && contains(ln,'disp')
            disp_start=i+1;
            if contains(ln,'z-disp'), disp_cols=3;
            elseif ~contains(ln,'y-disp'), disp_cols=1; end
            break;
        end
    end
    if disp_start==0, return; end

    disp_data=[];
    for i=disp_start:numel(lines)
        ln=strtrim(lines{i});
        if isempty(ln)||contains(ln,'integration')||contains(ln,'Element'), break; end
        v=sscanf(ln,'%f');
        if numel(v)>=1+disp_cols
            disp_data(end+1,:)=v(2:(1+disp_cols))'; %#ok<AGROW>
        end
    end
    if isempty(disp_data), return; end
    disp_mat=disp_data;

    n_nodes=size(disp_mat,1);
    [ny, ec, mt] = pfem_extract_coords(yaml_path);
    if ~isempty(ny) && size(ny,1)==n_nodes
        nodes=ny; elem_conn=ec; meta=mt;
    else
        nodes=[(1:n_nodes)' zeros(n_nodes,1)];
    end
end


function [stress_start, stresses] = parse_stresses(out)
    stresses=[]; stress_start=0;
    if ~isfield(out,'files')||isempty(out.files), return; end
    is_res=cellfun(@(f) endsWith(f,'.res'), out.files);
    res_files=out.files(is_res);
    if isempty(res_files), return; end
    res_path=res_files{1};
    if ~exist(res_path,'file'), return; end
    lines=read_lines(res_path);
    for i=1:numel(lines)
        if contains(strtrim(lines{i}),'Element') && contains(lines{i},'sig')
            stress_start=i+1; break;
        end
    end
    if stress_start==0, return; end
    for i=stress_start:numel(lines)
        ln=strtrim(lines{i}); if isempty(ln), break; end
        v=sscanf(ln,'%f');
        if numel(v)>=4, stresses(end+1,:)=v(4:end)'; end %#ok<AGROW>
    end
end


function txt = build_stats(disp_mat, stresses, changed, out)
    lines={};
    if ~isempty(fieldnames(changed))
        lines{end+1}='--- Changed ---';
        fns=fieldnames(changed);
        for i=1:numel(fns), lines{end+1}=sprintf('  %-20s %.4g',fns{i},changed.(fns{i})); end
        lines{end+1}='';
    end
    if ~isempty(disp_mat)
        lines{end+1}='--- Displacements ---';
        dof_lbl={'ux','uy','uz'};
        for d=1:size(disp_mat,2)
            [mx,ni]=max(abs(disp_mat(:,d)));
            lines{end+1}=sprintf('  max|%s| = %+.4e  (node %d)',dof_lbl{d},mx,ni);
        end
        mag=sqrt(sum(disp_mat.^2,2)); [mx,ni]=max(mag);
        lines{end+1}=sprintf('  max|u|  = %+.4e  (node %d)',mx,ni);
    end
    if ~isempty(stresses)
        lines{end+1}=''; lines{end+1}='--- Stresses ---';
        slbl={'sxx','syy','txy','szz','p'};
        for d=1:min(size(stresses,2),numel(slbl))
            lines{end+1}=sprintf('  max|%s| = %+.4e',slbl{d},max(abs(stresses(:,d))));
        end
    end
    if isfield(out,'run_name')&&~isempty(out.run_name)
        lines{end+1}=''; lines{end+1}=['  run: ' out.run_name];
    end
    txt=strjoin(lines,newline);
end

function show_error(ax, stats_txt, msg)
    cla(ax); axis(ax,'off');
    text(ax,0.5,0.5,{'Run failed:',msg},'HorizontalAlignment','center', ...
         'Color',[1 0.38 0.38],'FontSize',10,'Units','normalized');
    set(stats_txt,'String',['Error: ' msg]);
end

function lines = read_lines(path)
    fid=fopen(path,'r'); raw=textscan(fid,'%s','Delimiter','\n','Whitespace','');
    fclose(fid); lines=raw{1};
end

function lbl = format_label(tp)
    if isfield(tp,'description')&&~isempty(tp.description), desc=tp.description;
    else, desc=strrep(tp.name,'_',' '); end
    if isfield(tp,'note')&&~isempty(tp.note), lbl=[desc ' *']; else, lbl=desc; end
end

function tf = isabspath(p)
    tf=~isempty(p)&&(p(1)=='/'||p(1)=='~'||(numel(p)>=2&&p(2)==':'));
end
