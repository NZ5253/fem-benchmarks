function pfem_batch_figs(chapter_or_yaml, pfem_root)
% PFEM_BATCH_FIGS  Auto-generate sweep comparison figures for benchmark cases
%
% For each YAML case, automatically selects the primary tunable parameter,
% runs 4 sweep values, draws deformed mesh comparison, and saves PNG figures.
%
% Usage:
%   pfem_batch_figs('chap06')          % all cases in chap06
%   pfem_batch_figs('chap06/p61.yaml') % single case
%   pfem_batch_figs('all')             % all chapters 4-11
%
% Prerequisites:
%   PFEM binaries must be compiled (scripts/pfem_build_chapter.sh).
%   Works for structural cases (chap04-06, 08, 11) where .res has nodal
%   displacements.  Flow/eigenvalue/coupled cases are skipped gracefully.
%
% Output:
%   Figures saved to figures/<chap>/<case>_<param>.png
%
% Note:
%   For interactive single-case exploration use pfem_studio instead.

    repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
    if nargin < 2 || isempty(pfem_root)
        pfem_root = fullfile(repo_root, 'pfem');
    end
    if nargin < 1 || isempty(chapter_or_yaml)
        chapter_or_yaml = 'all';
    end

    addpath(genpath(fullfile(repo_root, 'matlab')));
    bench_root = fullfile(repo_root, 'benchmarks', 'pfem5');

    % ----- Collect YAML files -----
    if endsWith(chapter_or_yaml, '.yaml') || endsWith(chapter_or_yaml, '.yml')
        % Single YAML path (absolute or relative to repo root)
        p = chapter_or_yaml;
        if ~isabspath(p)
            p = fullfile(repo_root, p);
        end
        process_case(p, repo_root, pfem_root);
        return;
    end

    if strcmp(chapter_or_yaml, 'all')
        chap_dirs = dir(fullfile(bench_root, 'chap*'));
        chapters  = {chap_dirs([chap_dirs.isdir]).name};
    else
        chapters = {chapter_or_yaml};
    end

    total_saved = 0;
    for ci = 1:numel(chapters)
        chap = chapters{ci};
        yaml_files = dir(fullfile(bench_root, chap, '*.yaml'));
        fprintf('\n=== %s  (%d cases) ===\n', chap, numel(yaml_files));
        for fi = 1:numel(yaml_files)
            p = fullfile(yaml_files(fi).folder, yaml_files(fi).name);
            saved = process_case(p, repo_root, pfem_root);
            total_saved = total_saved + saved;
        end
    end

    fprintf('\nDone. %d figure(s) saved to figures/\n', total_saved);
end


% --------------------------------------------------------------------------
function saved = process_case(yaml_path, repo_root, pfem_root)
    saved = 0;

    try
        yaml = pfem_yaml_load(yaml_path);
    catch ME
        fprintf('  [SKIP] Cannot load YAML %s: %s\n', yaml_path, ME.message);
        return;
    end

    case_name  = yaml.inputs.basename;
    chap_num   = yaml.authors.source.chapter;
    chap_str   = sprintf('chap%02d', chap_num);

    % --- Pick primary sweep parameter ---
    [sweep_param, sweep_type, sweep_range] = pick_sweep_param(yaml);
    if isempty(sweep_param)
        fprintf('  [skip] %-12s — no sweep-able parameter\n', case_name);
        return;
    end

    % --- Generate 4 sweep values ---
    sweep_values = make_sweep_values(sweep_range, sweep_type, 4);
    fprintf('  [run]  %-12s sweep %-28s [%.3g … %.3g]\n', ...
            case_name, sweep_param, sweep_values(1), sweep_values(end));

    % --- Run sweep ---
    results = run_sweep(yaml_path, repo_root, pfem_root, sweep_param, sweep_values);

    n_ok = sum([results.status] == 0 & ~cellfun(@isempty, {results.nodes}));
    if n_ok == 0
        fprintf('  [skip] %-12s — no mesh output (binary missing or non-structural)\n', case_name);
        return;
    end

    % --- Generate figure ---
    fig = build_sweep_figure(results, sweep_param, case_name, yaml.title, yaml_path);

    % --- Save figure ---
    fig_dir  = fullfile(repo_root, 'figures', chap_str);
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
    fig_path = fullfile(fig_dir, sprintf('%s_%s.png', case_name, sweep_param));

    try
        print(fig, fig_path, '-dpng', '-r120');
        fprintf('  [saved] %s\n', strrep(fig_path, repo_root, ''));
        saved = 1;
    catch ME
        fprintf('  [warn]  Could not save figure: %s\n', ME.message);
    end
    close(fig);
end


% --------------------------------------------------------------------------
function [param_name, param_type, param_range] = pick_sweep_param(yaml)
    param_name = ''; param_type = 'real'; param_range = [];
    if ~isfield(yaml, 'tunable_parameters'), return; end

    tparams = yaml.tunable_parameters;
    if ~iscell(tparams)
        tparams = num2cell(tparams);
    end

    for k = 1:numel(tparams)
        tp = tparams{k};
        if ~isstruct(tp),              continue; end
        if ~isfield(tp,'suggested_range'), continue; end
        % Skip topology parameters (changing them breaks coordinate arrays)
        if isfield(tp,'note') && contains(tp.note, 'WARNING'), continue; end
        param_name  = tp.name;
        param_type  = tp.type;
        param_range = tp.suggested_range;
        return;
    end
end


% --------------------------------------------------------------------------
function vals = make_sweep_values(range_arr, param_type, n)
    lo = range_arr(1);
    hi = range_arr(2);

    if strcmp(param_type, 'int')
        lo_i = max(round(lo), 1);
        hi_i = min(round(hi), lo_i * 20);
        vals = unique(round(linspace(lo_i, hi_i, n)));
    elseif lo > 0
        vals = 10.^linspace(log10(lo), log10(hi), n);
    else
        vals = linspace(lo, hi, n);
    end
    vals = vals(:)';   % row vector
end


% --------------------------------------------------------------------------
function results = run_sweep(yaml_path, repo_root, pfem_root, sweep_param, sweep_values)
    n       = numel(sweep_values);
    results = repmat(struct('value',0,'status',-1,'out',[],...
                            'nodes',[],'disp_mat',[],'elem_conn',[],...
                            'meta',struct(),'max_u',NaN), 1, n);

    for i = 1:n
        v = sweep_values(i);
        overrides = struct();
        overrides.(sweep_param) = v;

        try
            [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
        catch ME
            fprintf('    (%d/%d) Error: %s\n', i, n, ME.message);
            status = -1;
            out    = struct('files',{{}},'param_key','');
        end

        results(i).value  = v;
        results(i).status = status;
        results(i).out    = out;

        if status == 0
            [nd, dm, ec, mt] = extract_mesh_and_displacements(out, yaml_path, overrides);
            results(i).nodes     = nd;
            results(i).disp_mat  = dm;
            results(i).elem_conn = ec;
            results(i).meta      = mt;
            if ~isempty(dm)
                nc = min(2, size(dm, 2));
                results(i).max_u = max(sqrt(sum(dm(:,1:nc).^2, 2)));
            end
        end
    end
end


% --------------------------------------------------------------------------
function fig = build_sweep_figure(results, sweep_param, case_name, case_title, yaml_path)
    n           = numel(results);
    vals        = [results.value];
    maxu        = [results.max_u];
    sweep_label = strrep(sweep_param, '_', ' ');

    cols = min(n, 4);
    rows = ceil(n / cols);

    fig = figure('Name', sprintf('Batch sweep: %s — %s', sweep_label, case_name), ...
                 'Position', [80 80 340*cols 280*(rows+1)], ...
                 'Color', [0.11 0.11 0.14], 'Visible', 'off');

    % Top strip: parameter vs max|u|
    ax_c = subplot(rows+1, 1, 1, 'Parent', fig);
    set(ax_c, 'Color', [0.08 0.08 0.10], ...
              'XColor', [0.70 0.70 0.70], 'YColor', [0.70 0.70 0.70], ...
              'GridColor', [0.30 0.30 0.30], 'GridAlpha', 0.5);
    hold(ax_c, 'on'); grid(ax_c, 'on');

    ok = [results.status] == 0 & ~isnan(maxu);
    if any(ok)
        plot(ax_c, vals(ok), maxu(ok), 'o-', ...
             'Color', [0.40 0.75 0.40], 'MarkerFaceColor', [0.40 0.75 0.40], ...
             'LineWidth', 2, 'MarkerSize', 8);
    end
    if any(~ok)
        plot(ax_c, vals(~ok), zeros(1,sum(~ok)), 'rx', 'MarkerSize', 12, 'LineWidth', 2);
    end
    xlabel(ax_c, sweep_label,  'Color', [0.75 0.75 0.75], 'FontSize', 9);
    ylabel(ax_c, 'max|u|',    'Color', [0.75 0.75 0.75], 'FontSize', 9);
    title(ax_c, sprintf('%s — sweep of %s', case_title, sweep_label), ...
          'Color', [0.88 0.88 0.88], 'FontSize', 10, 'Interpreter', 'none');
    hold(ax_c, 'off');

    % Tiled deformed meshes
    for i = 1:n
        ax = subplot(rows+1, cols, cols + i, 'Parent', fig);
        set(ax, 'Color', [0.08 0.08 0.10]);
        r  = results(i);

        if r.status == 0 && ~isempty(r.nodes) && ~isempty(r.disp_mat)
            draw_deformed_panel(ax, r.nodes, r.disp_mat, r.elem_conn, r.meta);
            if isnan(r.max_u)
                lbl = sprintf('%s = %.4g', sweep_label, r.value);
            else
                lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, r.value, r.max_u);
            end
        else
            axis(ax, 'off');
            text(ax, 0.5, 0.5, sprintf('%s = %.4g\nN/A', sweep_label, r.value), ...
                 'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5], ...
                 'FontSize', 9, 'Units', 'normalized');
            lbl = sprintf('%s = %.4g  [N/A]', sweep_label, r.value);
        end
        title(ax, lbl, 'FontSize', 8, 'Color', [0.80 0.80 0.80], 'Interpreter', 'none');
    end
end


% --------------------------------------------------------------------------
function draw_deformed_panel(ax, nodes, disp_mat, elem_conn, ~)
% Draw deformed mesh on axes ax, coloured by displacement magnitude.
    hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');

    nc       = min(2, size(disp_mat, 2));
    disp_mag = sqrt(sum(disp_mat(:, 1:nc).^2, 2));
    max_mag  = max(disp_mag);

    if size(nodes, 2) >= 2
        W  = max(nodes(:,1)) - min(nodes(:,1));
        H  = max(nodes(:,2)) - min(nodes(:,2));
        sf = 1;
        if max_mag > 0, sf = 0.08 * max(W, H) / max_mag; end

        def      = nodes;
        def(:,1) = nodes(:,1) + sf * disp_mat(:,1);
        def(:,2) = nodes(:,2) + sf * disp_mat(:,2);

        % Undeformed mesh (faint)
        if ~isempty(elem_conn)
            draw_elem_edges(ax, nodes, elem_conn, [0.22 0.28 0.34], 0.5);
        end
        % Deformed mesh outline
        if ~isempty(elem_conn)
            draw_elem_edges(ax, def, elem_conn, [0.48 0.60 0.72], 0.9);
        end
        % Nodes coloured by |u|
        scatter(ax, def(:,1), def(:,2), 18, disp_mag, 'filled');
        colormap(ax, 'turbo');
    else
        % 1D case — plot displacement profile
        x = (1:size(disp_mat,1))';
        scatter(ax, x, disp_mat(:,1), 18, disp_mag, 'filled');
        colormap(ax, 'turbo');
    end
    hold(ax, 'off');
end


% --------------------------------------------------------------------------
function draw_elem_edges(ax, nodes, conn, col, lw)
% Draw one line per element edge using the connectivity matrix.
    n_e = size(conn, 1);
    n_c = size(conn, 2);
    for e = 1:n_e
        nids = conn(e, :);
        nids = nids(nids >= 1 & nids <= size(nodes, 1));
        if numel(nids) < 2, continue; end
        nids(end+1) = nids(1);  %#ok<AGROW>  close element loop
        plot(ax, nodes(nids,1), nodes(nids,2), '-', ...
             'Color', col, 'LineWidth', lw);
    end
end


% --------------------------------------------------------------------------
function [nodes, disp_mat, elem_conn, meta] = extract_mesh_and_displacements(out, yaml_path, overrides)
% Parse nodal displacements from .res and coordinates from YAML.
    nodes = []; disp_mat = []; elem_conn = []; meta = struct();

    if ~isfield(out, 'files') || isempty(out.files), return; end
    res_files = out.files(cellfun(@(f) endsWith(f,'.res'), out.files));
    if isempty(res_files), return; end
    res_path = res_files{1};
    if ~exist(res_path, 'file'), return; end

    fid = fopen(res_path, 'r');
    if fid == -1, return; end
    raw   = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    % Locate displacement block header
    disp_start = 0;
    disp_cols  = 2;
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if contains(ln, 'Node') && contains(ln, 'disp')
            disp_start = i + 1;
            if     contains(ln, 'z-disp'),   disp_cols = 3;
            elseif ~contains(ln, 'y-disp'),  disp_cols = 1;
            end
            break;
        end
    end
    if disp_start == 0, return; end   % no per-node displacements (load table / eigenvalue)

    disp_data = [];
    for i = disp_start:numel(lines)
        ln = strtrim(lines{i});
        if isempty(ln) || contains(ln, 'integration') || contains(ln, 'Element'), break; end
        v = sscanf(ln, '%f');
        if numel(v) >= 1 + disp_cols
            disp_data(end+1, :) = v(2:(1+disp_cols))'; %#ok<AGROW>
        end
    end
    if isempty(disp_data), return; end
    disp_mat = disp_data;

    % Node coordinates + element connectivity from YAML
    n_nodes = size(disp_mat, 1);
    try
        [ny, ec, mt] = pfem_extract_coords(yaml_path, overrides);
        if ~isempty(ny) && size(ny, 1) == n_nodes
            nodes     = ny;
            elem_conn = ec;
            meta      = mt;
        else
            % Mismatch — use simple 1-D index coordinates as fallback
            nodes = [(1:n_nodes)', zeros(n_nodes, 1)];
        end
    catch
        nodes = [(1:n_nodes)', zeros(n_nodes, 1)];
    end
end
