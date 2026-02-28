function fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path, varargin)
% PFEM_PLOT_SWEEP_SUMMARY  Deformed mesh comparison figure from sweep results
%
% Generates a dark-themed figure with:
%   - Top strip:     parameter vs max|u| (or max displacement) curve
%   - Mesh row:      deformed mesh panels (from YAML coords + .res, or from .msh PostScript)
%   - Vector row:    displacement vector panels (from .vec PostScript, if present)
%
% Supported .res formats:
%   Format A (elastic/structural): per-node x-disp/y-disp table
%   Format B (nonlinear load-step): "step load disp iters" table — draws from .msh/.vec
%
% Usage:
%   fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path)
%   fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path, 'Save', '/path/fig.png')
%   fig = pfem_plot_sweep_summary(results, sweep_param, yaml_path, 'Show', false)

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

    % ---- Collect all result data ----
    nodes_arr     = cell(n,1);   % Format A: undeformed node coords
    disp_arr      = cell(n,1);   % Format A: per-node displacement matrix
    ec_arr        = cell(n,1);   % Format A: element connectivity
    load_disp_arr = cell(n,1);   % Format B: [load, max_disp] table
    msh_arr       = cell(n,1);   % PS .msh: cell of polygon vertex matrices
    vec_arr       = cell(n,1);   % PS .vec: [from_x from_y to_x to_y] matrix
    maxu_vec      = NaN(n,1);

    for i = 1:n
        if results(i).status ~= 0, continue; end

        % Parse .res file (Format A or B)
        ov = struct();
        ov.(sweep_param) = results(i).value;
        [nd, dm, ec, ld] = parse_res(results(i).out, yaml_path, ov);
        nodes_arr{i}     = nd;
        disp_arr{i}      = dm;
        ec_arr{i}        = ec;
        load_disp_arr{i} = ld;

        if ~isempty(dm)
            nc = min(2, size(dm, 2));
            maxu_vec(i) = max(sqrt(sum(dm(:,1:nc).^2, 2)));
        elseif ~isempty(ld)
            maxu_vec(i) = max(abs(ld(:, 2)));
        end

        % Parse PostScript files if present
        out_files = {};
        if isfield(results(i).out, 'files')
            out_files = results(i).out.files;
        elseif isfield(results(i), 'files')
            out_files = results(i).files;
        end
        if ~iscell(out_files), out_files = {}; end

        msh_files = out_files(cellfun(@(f) endsWith(f, '.msh'), out_files));
        if ~isempty(msh_files) && exist(msh_files{1}, 'file')
            msh_arr{i} = parse_pfem_msh(msh_files{1});
        end

        vec_files = out_files(cellfun(@(f) endsWith(f, '.vec'), out_files));
        if ~isempty(vec_files) && exist(vec_files{1}, 'file')
            vec_arr{i} = parse_pfem_vec(vec_files{1});
        end
    end

    has_disp_mesh = any(~cellfun(@isempty, disp_arr));
    has_ps_mesh   = any(~cellfun(@isempty, msh_arr));
    has_ps_vecs   = any(~cellfun(@isempty, vec_arr));

    % ---- Figure layout ----
    cols = min(n, 4);
    rows = ceil(n / cols);
    % Extra panel row for vectors (only when PS vector data available)
    vec_row = has_ps_vecs;
    total_rows = rows + 1 + double(vec_row);   % +1 for top strip

    vis = 'off';
    if do_show, vis = 'on'; end

    fig = figure('Name', sprintf('Sweep: %s — %s', sweep_label, case_title), ...
                 'Position', [80 80 340*cols 260*total_rows], ...
                 'Color', [0.11 0.11 0.14], 'Visible', vis);

    % ---- Top strip: parameter vs max|u| ----
    ax_c = subplot(total_rows, 1, 1, 'Parent', fig);
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

    ylbl = 'max|u|';
    if ~has_disp_mesh && has_ps_mesh
        ylbl = 'max displacement at final step';
    end
    xlabel(ax_c, sweep_label, 'Color', [0.75 0.75 0.75], 'FontSize', 9);
    ylabel(ax_c, ylbl,        'Color', [0.75 0.75 0.75], 'FontSize', 9);
    title(ax_c, sprintf('%s  —  sweep of  %s', case_title, sweep_label), ...
          'Color', [0.88 0.88 0.88], 'FontSize', 10, 'Interpreter', 'none');
    hold(ax_c, 'off');

    % ---- Mesh panels (row 2) ----
    for i = 1:n
        ax = subplot(total_rows, cols, cols + i, 'Parent', fig);
        set(ax, 'Color', [0.08 0.08 0.10]);

        nd  = nodes_arr{i};
        dm  = disp_arr{i};
        ec  = ec_arr{i};
        ld  = load_disp_arr{i};
        msh = msh_arr{i};

        if results(i).status ~= 0
            lbl = sprintf('%s = %.4g  [FAIL]', sweep_label, vals(i));
            show_na(ax, lbl);
        elseif ~isempty(nd) && ~isempty(dm)
            % Format A: draw deformed mesh from YAML coords + .res displacements
            draw_deformed(ax, nd, dm, ec);
            if isnan(maxu_vec(i))
                lbl = sprintf('%s = %.4g', sweep_label, vals(i));
            else
                lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, vals(i), maxu_vec(i));
            end
        elseif ~isempty(msh)
            % Format B: draw deformed mesh from .msh PostScript
            draw_ps_mesh(ax, msh);
            if isnan(maxu_vec(i))
                lbl = sprintf('%s = %.4g', sweep_label, vals(i));
            else
                lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, vals(i), maxu_vec(i));
            end
        elseif ~isempty(ld)
            % Fallback: no PS mesh — draw load-displacement curve
            draw_load_disp(ax, ld);
            lbl = sprintf('%s = %.4g\nmax|u| = %.3e', sweep_label, vals(i), maxu_vec(i));
        else
            lbl = sprintf('%s = %.4g\nN/A', sweep_label, vals(i));
            show_na(ax, lbl);
        end
        title(ax, lbl, 'FontSize', 8, 'Color', [0.80 0.80 0.80], 'Interpreter', 'none');
    end

    % ---- Vector panels (row 3, only when .vec data present) ----
    if vec_row
        for i = 1:n
            ax = subplot(total_rows, cols, 2*cols + i, 'Parent', fig);
            set(ax, 'Color', [0.08 0.08 0.10]);
            vec = vec_arr{i};
            if results(i).status == 0 && ~isempty(vec)
                draw_ps_vecs(ax, vec);
                lbl = sprintf('%s = %.4g\nvectors', sweep_label, vals(i));
            else
                lbl = sprintf('%s = %.4g\n[no vectors]', sweep_label, vals(i));
                show_na(ax, lbl);
            end
            title(ax, lbl, 'FontSize', 8, 'Color', [0.80 0.80 0.80], 'Interpreter', 'none');
        end
    end

    % ---- Save ----
    if ~isempty(save_path)
        d = fileparts(save_path);
        if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
        print(fig, save_path, '-dpng', '-r120');
    end
end


% ==========================================================================
function show_na(ax, lbl)
    axis(ax, 'off');
    text(ax, 0.5, 0.5, lbl, 'HorizontalAlignment', 'center', ...
         'Color', [0.5 0.5 0.5], 'FontSize', 9, 'Units', 'normalized');
end


% ==========================================================================
function draw_ps_mesh(ax, patches)
% Draw deformed mesh polygons parsed from a PFEM .msh PostScript file.
    hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');
    set(ax, 'Color', [0.08 0.08 0.10]);
    col = [0.72 0.78 0.84];
    for k = 1:numel(patches)
        pts = patches{k};
        if size(pts, 1) < 2, continue; end
        fill(ax, pts([1:end,1], 1), pts([1:end,1], 2), ...
             [0.12 0.14 0.17], 'EdgeColor', col, 'LineWidth', 0.7);
    end
    hold(ax, 'off');
end


% ==========================================================================
function draw_ps_vecs(ax, arrows)
% Draw displacement vectors parsed from a PFEM .vec PostScript file.
    hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');
    set(ax, 'Color', [0.08 0.08 0.10]);
    col = [0.55 0.80 0.55];
    for k = 1:size(arrows, 1)
        x1 = arrows(k,1); y1 = arrows(k,2);
        x2 = arrows(k,3); y2 = arrows(k,4);
        quiver(ax, x1, y1, x2-x1, y2-y1, 0, ...
               'Color', col, 'LineWidth', 0.8, 'MaxHeadSize', 0.6);
    end
    hold(ax, 'off');
end


% ==========================================================================
function draw_load_disp(ax, load_disp)
% Draw a load-displacement curve (fallback when no .msh PostScript available).
    hold(ax, 'on'); grid(ax, 'on');
    set(ax, 'Color', [0.08 0.08 0.10], ...
            'XColor', [0.70 0.70 0.70], 'YColor', [0.70 0.70 0.70], ...
            'GridColor', [0.30 0.30 0.30], 'GridAlpha', 0.4);
    plot(ax, abs(load_disp(:,2)), load_disp(:,1), 'o-', ...
         'Color', [0.40 0.75 0.40], 'MarkerFaceColor', [0.40 0.75 0.40], ...
         'LineWidth', 1.5, 'MarkerSize', 4);
    xlabel(ax, 'max|u|', 'Color', [0.70 0.70 0.70], 'FontSize', 8);
    ylabel(ax, 'Load',   'Color', [0.70 0.70 0.70], 'FontSize', 8);
    hold(ax, 'off');
end


% ==========================================================================
function draw_deformed(ax, nodes, disp_mat, elem_conn)
% Draw deformed mesh from YAML node coordinates and .res per-node displacements.
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
function patches = parse_pfem_msh(msh_path)
% Parse a PFEM .msh PostScript file into element polygon vertex arrays.
% Each polygon is stored as an Nx2 matrix of [x, y] coordinates.
    patches = {};
    try
        fid = fopen(msh_path, 'r');
        if fid == -1, return; end
        raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
        fclose(fid);
        lines = raw{1};

        NUM = '([+-]?\d+\.?\d*(?:[eE][+-]?\d+)?)';
        pat_m = ['^' NUM '\s+' NUM '\s+m\s*$'];
        pat_l = ['^' NUM '\s+' NUM '\s+l\s*$'];

        current = [];
        for k = 1:numel(lines)
            ln = strtrim(lines{k});
            tok = regexp(ln, pat_m, 'tokens');
            if ~isempty(tok)
                current = [str2double(tok{1}{1}), str2double(tok{1}{2})];
                continue;
            end
            tok = regexp(ln, pat_l, 'tokens');
            if ~isempty(tok)
                current(end+1, :) = [str2double(tok{1}{1}), str2double(tok{1}{2})]; %#ok<AGROW>
                continue;
            end
            if strcmp(ln, 'c s') && size(current, 1) >= 3
                patches{end+1} = current; %#ok<AGROW>
                current = [];
            end
        end
    catch
    end
end


% ==========================================================================
function arrows = parse_pfem_vec(vec_path)
% Parse a PFEM .vec PostScript file into [from_x from_y to_x to_y] rows.
    arrows = [];
    try
        fid = fopen(vec_path, 'r');
        if fid == -1, return; end
        raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
        fclose(fid);
        lines = raw{1};

        NUM = '([+-]?\d+\.?\d*(?:[eE][+-]?\d+)?)';
        pat = ['^' NUM '\s+' NUM '\s+' NUM '\s+' NUM '\s+arrow\s*$'];

        for k = 1:numel(lines)
            ln = strtrim(lines{k});
            tok = regexp(ln, pat, 'tokens');
            if ~isempty(tok)
                arrows(end+1, :) = cellfun(@str2double, tok{1}); %#ok<AGROW>
            end
        end
    catch
    end
end


% ==========================================================================
function [nodes, disp_mat, elem_conn, load_disp] = parse_res(out, yaml_path, overrides)
% Parse results from a PFEM .res file.
%
% Format A (structural/elastic): per-node displacement table.
%   Returns: nodes, disp_mat (Nx2+), elem_conn, load_disp=[]
% Format B (nonlinear load-step): "step load disp iters" table.
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

    % --- Try Format A first ---
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

    if disp_start > 0
        dd = [];
        for i = disp_start:numel(lines)
            ln = strtrim(lines{i});
            if isempty(ln) || contains(ln, 'integration') || contains(ln, 'Element'), break; end
            v = sscanf(ln, '%f');
            if numel(v) >= 1 + disp_cols
                dd(end+1, :) = v(2:(1+disp_cols))'; %#ok<AGROW>
            end
        end
        if ~isempty(dd)
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
        return;
    end

    % --- Try Format B: "step load disp iters" table ---
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if contains(ln, 'step') && contains(ln, 'load') && contains(ln, 'disp')
            ld = [];
            for j = i+1:numel(lines)
                ln2 = strtrim(lines{j});
                if isempty(ln2), break; end
                v = sscanf(ln2, '%f');
                if numel(v) >= 3
                    ld(end+1, :) = [v(2), v(3)]; %#ok<AGROW>  [load, max_disp]
                end
            end
            if ~isempty(ld), load_disp = ld; end
            return;
        end
    end
end
