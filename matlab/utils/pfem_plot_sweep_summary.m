function fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path, varargin)
% PFEM_PLOT_SWEEP_SUMMARY  Deformed mesh comparison figure from sweep results
%
% Generates a dark-themed figure with:
%   - Top row:    parameter vs max|u| curve
%   - Bottom row: tiled deformed mesh panels for each sweep value
%
% Usage:
%   fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path)
%   fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path, 'Save', '/path/fig.png')
%   fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path, 'Show', false)
%
% Inputs:
%   results     - struct array with fields:
%                   .value  (sweep value)
%                   .status (0 = success)
%                   .out    (from pfem_run_from_yaml — must have .files cell array)
%   sweep_param - name of swept parameter (string, used for axis labels)
%   yaml_path   - path to the benchmark YAML (for node coordinate extraction)
%
% Name-value options:
%   'Title'  - super-title string (default: basename of yaml_path)
%   'Save'   - file path to save PNG; directory is created automatically
%   'Show'   - true/false (default: true) — make figure visible

    p = inputParser;
    addParameter(p, 'Title', '');
    addParameter(p, 'Save',  '');
    addParameter(p, 'Show',  true);
    parse(p, varargin{:});

    case_title  = p.Results.Title;
    save_path   = p.Results.Save;
    do_show     = p.Results.Show;

    if isempty(case_title)
        [~, bn] = fileparts(yaml_path);
        case_title = strrep(bn, '_', ' ');
    end

    sweep_label = strrep(sweep_param, '_', ' ');
    n    = numel(results);
    vals = arrayfun(@(r) r.value, results);

    % Parse displacement results for each run.
    % parse_run returns either per-node displacements (Format A: elastic/structural)
    % or a [load, max_disp] table (Format B: load-step nonlinear, e.g. p61 von Mises).
    nodes_arr     = cell(n,1);
    disp_arr      = cell(n,1);
    ec_arr        = cell(n,1);
    load_disp_arr = cell(n,1);
    maxu_vec      = NaN(n,1);

    for i = 1:n
        if results(i).status ~= 0, continue; end
        ov = struct();
        ov.(sweep_param) = results(i).value;
        [nd, dm, ec, ld] = parse_run(results(i).out, yaml_path, ov);
        nodes_arr{i}     = nd;
        disp_arr{i}      = dm;
        ec_arr{i}        = ec;
        load_disp_arr{i} = ld;
        if ~isempty(dm)
            % Format A: per-node displacements
            nc = min(2, size(dm, 2));
            maxu_vec(i) = max(sqrt(sum(dm(:,1:nc).^2, 2)));
        elseif ~isempty(ld)
            % Format B: load-step table — use max|disp| at final step
            maxu_vec(i) = max(abs(ld(:, 2)));
        end
    end

    % Figure layout
    cols = min(n, 4);
    rows = ceil(n / cols);
    vis  = 'off';
    if do_show, vis = 'on'; end

    fig = figure('Name', sprintf('Sweep: %s — %s', sweep_label, case_title), ...
                 'Position', [80 80 340*cols 280*(rows+1)], ...
                 'Color', [0.11 0.11 0.14], 'Visible', vis);

    % ---- Top strip: parameter vs max|u| ----
    ax_c = subplot(rows+1, 1, 1, 'Parent', fig);
    set(ax_c, 'Color', [0.08 0.08 0.10], ...
              'XColor', [0.70 0.70 0.70], 'YColor', [0.70 0.70 0.70], ...
              'GridColor', [0.30 0.30 0.30], 'GridAlpha', 0.5);
    hold(ax_c, 'on'); grid(ax_c, 'on');

    ok = [results.status] == 0 & ~isnan(maxu_vec');
    if any(ok)
        plot(ax_c, vals(ok), maxu_vec(ok)', 'o-', ...
             'Color', [0.40 0.75 0.40], 'MarkerFaceColor', [0.40 0.75 0.40], ...
             'LineWidth', 2, 'MarkerSize', 8);
    end
    if any(~ok)
        plot(ax_c, vals(~ok), zeros(1,sum(~ok)), 'rx', 'MarkerSize', 12, 'LineWidth', 2);
    end
    has_ld = any(cellfun(@(x) ~isempty(x), load_disp_arr));
    ylbl = 'max|u|';
    if has_ld && ~any(cellfun(@(x) ~isempty(x), disp_arr))
        ylbl = 'max displacement at final step';
    end
    xlabel(ax_c, sweep_label, 'Color', [0.75 0.75 0.75], 'FontSize', 9);
    ylabel(ax_c, ylbl,        'Color', [0.75 0.75 0.75], 'FontSize', 9);
    title(ax_c, sprintf('%s  —  sweep of  %s', case_title, sweep_label), ...
          'Color', [0.88 0.88 0.88], 'FontSize', 10, 'Interpreter', 'none');
    hold(ax_c, 'off');

    % ---- Tiled panels: deformed mesh (Format A) or load-disp curve (Format B) ----
    for i = 1:n
        ax  = subplot(rows+1, cols, cols+i, 'Parent', fig);
        set(ax, 'Color', [0.08 0.08 0.10]);
        nd = nodes_arr{i};
        dm = disp_arr{i};
        ec = ec_arr{i};
        ld = load_disp_arr{i};

        if results(i).status == 0 && ~isempty(nd) && ~isempty(dm)
            % Format A: draw deformed mesh
            draw_deformed(ax, nd, dm, ec);
            if isnan(maxu_vec(i))
                lbl = sprintf('%s = %.4g', sweep_label, vals(i));
            else
                lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, vals(i), maxu_vec(i));
            end
        elseif results(i).status == 0 && ~isempty(ld)
            % Format B: draw load-displacement curve
            draw_load_disp(ax, ld, sweep_label, vals(i));
            lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, vals(i), maxu_vec(i));
        else
            axis(ax, 'off');
            text(ax, 0.5, 0.5, sprintf('%s = %.4g\nN/A', sweep_label, vals(i)), ...
                 'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5], ...
                 'FontSize', 9, 'Units', 'normalized');
            lbl = sprintf('%s = %.4g  [N/A]', sweep_label, vals(i));
        end
        title(ax, lbl, 'FontSize', 8, 'Color', [0.80 0.80 0.80], 'Interpreter', 'none');
    end

    % ---- Save ----
    if ~isempty(save_path)
        d = fileparts(save_path);
        if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
        print(fig, save_path, '-dpng', '-r120');
    end
end


% ==========================================================================
function draw_load_disp(ax, load_disp, sweep_label, sweep_val)
% Draw a load-displacement curve for Format B .res files (nonlinear load-step output).
    hold(ax, 'on'); grid(ax, 'on');
    set(ax, 'Color', [0.08 0.08 0.10], ...
            'XColor', [0.70 0.70 0.70], 'YColor', [0.70 0.70 0.70], ...
            'GridColor', [0.30 0.30 0.30], 'GridAlpha', 0.4);
    u = abs(load_disp(:, 2));   % max |displacement| at each step
    p = load_disp(:, 1);         % applied load at each step
    plot(ax, u, p, 'o-', ...
         'Color', [0.40 0.75 0.40], 'MarkerFaceColor', [0.40 0.75 0.40], ...
         'LineWidth', 1.5, 'MarkerSize', 4);
    xlabel(ax, 'max|u|', 'Color', [0.70 0.70 0.70], 'FontSize', 8);
    ylabel(ax, 'Load',   'Color', [0.70 0.70 0.70], 'FontSize', 8);
    hold(ax, 'off');
end


% ==========================================================================
function draw_deformed(ax, nodes, disp_mat, elem_conn)
    hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');

    nc       = min(2, size(disp_mat, 2));
    disp_mag = sqrt(sum(disp_mat(:,1:nc).^2, 2));
    max_mag  = max(disp_mag);

    if size(nodes, 2) >= 2
        W  = max(nodes(:,1)) - min(nodes(:,1));
        H  = max(nodes(:,2)) - min(nodes(:,2));
        sf = 1;
        if max_mag > 0, sf = 0.08 * max(W,H) / max_mag; end

        def      = nodes;
        def(:,1) = nodes(:,1) + sf * disp_mat(:,1);
        def(:,2) = nodes(:,2) + sf * disp_mat(:,2);

        if ~isempty(elem_conn)
            draw_edges(ax, nodes, elem_conn, [0.22 0.28 0.34], 0.5);   % undeformed
            draw_edges(ax, def,   elem_conn, [0.48 0.60 0.72], 0.9);   % deformed
        end
        scatter(ax, def(:,1), def(:,2), 18, disp_mag, 'filled');
        colormap(ax, 'turbo');
    else
        % 1D: displacement profile
        x = (1:size(disp_mat,1))';
        scatter(ax, x, disp_mat(:,1), 18, disp_mag, 'filled');
        colormap(ax, 'turbo');
    end
    hold(ax, 'off');
end


% ==========================================================================
function draw_edges(ax, nodes, conn, col, lw)
    for e = 1:size(conn, 1)
        nids = conn(e,:);
        nids = nids(nids >= 1 & nids <= size(nodes, 1));
        if numel(nids) < 2, continue; end
        nids(end+1) = nids(1); %#ok<AGROW>
        plot(ax, nodes(nids,1), nodes(nids,2), '-', 'Color', col, 'LineWidth', lw);
    end
end


% ==========================================================================
function [nodes, disp_mat, elem_conn, load_disp] = parse_run(out, yaml_path, overrides)
% Parse results from a PFEM .res file.
%
% Format A (structural/elastic): per-node displacements table.
%   Returns: nodes (coords), disp_mat (Nx2+ displacements), elem_conn, load_disp=[]
%
% Format B (nonlinear load-step, e.g. p61 von Mises):
%   "step  load  disp  iters" table.
%   Returns: nodes=[], disp_mat=[], elem_conn=[], load_disp (Nx2 [load, max_disp])
    nodes = []; disp_mat = []; elem_conn = []; load_disp = [];

    if ~isfield(out, 'files') || isempty(out.files), return; end
    res_files = out.files(cellfun(@(f) endsWith(f, '.res'), out.files));
    if isempty(res_files), return; end
    res_path = res_files{1};
    if ~exist(res_path, 'file'), return; end

    fid = fopen(res_path, 'r');
    if fid == -1, return; end
    raw   = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

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
    if disp_start == 0
        % Format A not found — check for Format B: "step  load  disp  iters" table
        ld_start = 0;
        for i = 1:numel(lines)
            ln = strtrim(lines{i});
            if contains(ln, 'step') && contains(ln, 'load') && contains(ln, 'disp')
                ld_start = i + 1;
                break;
            end
        end
        if ld_start > 0
            ld = [];
            for i = ld_start:numel(lines)
                ln = strtrim(lines{i});
                if isempty(ln), break; end
                v = sscanf(ln, '%f');
                if numel(v) >= 3   % step, load, disp [, iters]
                    ld(end+1, :) = [v(2), v(3)]; %#ok<AGROW>  [load, max_disp]
                end
            end
            if ~isempty(ld)
                load_disp = ld;
            end
        end
        return;   % no per-node data (load-step or eigenvalue output)
    end

    dd = [];
    for i = disp_start:numel(lines)
        ln = strtrim(lines{i});
        if isempty(ln) || contains(ln, 'integration') || contains(ln, 'Element'), break; end
        v = sscanf(ln, '%f');
        if numel(v) >= 1 + disp_cols
            dd(end+1, :) = v(2:(1+disp_cols))'; %#ok<AGROW>
        end
    end
    if isempty(dd), return; end
    disp_mat = dd;

    n_nodes = size(dd, 1);
    try
        [ny, ec, ~] = pfem_extract_coords(yaml_path, overrides);
        if ~isempty(ny) && size(ny, 1) == n_nodes
            nodes     = ny;
            elem_conn = ec;
        else
            nodes = [(1:n_nodes)', zeros(n_nodes, 1)];
        end
    catch
        nodes = [(1:n_nodes)', zeros(n_nodes, 1)];
    end
end
