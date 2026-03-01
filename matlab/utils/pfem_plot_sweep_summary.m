function figs = pfem_plot_sweep_summary(results, sweep_param, yaml_path, varargin)
% PFEM_PLOT_SWEEP_SUMMARY  Separate comparison figures per PFEM output type.
%
% Creates one figure window per available output type:
%   figs.res  – Load/Displacement (.res): sweep-summary curve + per-case curves
%   figs.msh  – Reference Mesh    (.msh): undeformed mesh panels
%   figs.dis  – Deformed Shape    (.dis): deformed mesh panels
%   figs.vec  – Vectors           (.vec): displacement vector panels
%
% Only creates figures for output types present in at least one result.
%
% Usage:
%   figs = pfem_plot_sweep_summary(results, sweep_param, yaml_path)
%   figs = pfem_plot_sweep_summary(..., 'Save', '/dir/prefix')   % or .png path
%   figs = pfem_plot_sweep_summary(..., 'Show', false)
%
% When Save ends in .png the extension is stripped and used as a path prefix.
% Four files may be written: {prefix}_res.png, {prefix}_msh.png,
%                            {prefix}_dis.png, {prefix}_vec.png

    p = inputParser;
    addParameter(p, 'Title', '');
    addParameter(p, 'Save',  '');
    addParameter(p, 'Show',  true);
    parse(p, varargin{:});

    case_title  = p.Results.Title;
    save_arg    = p.Results.Save;
    do_show     = p.Results.Show;

    if isempty(case_title)
        [~, bn] = fileparts(yaml_path);
        case_title = strrep(bn, '_', ' ');
    end

    % Derive save prefix (strip .png if caller passed a full file path)
    save_prefix = save_arg;
    if ~isempty(save_prefix) && strcmpi(save_prefix(end-3:min(end,end)), '.png')
        save_prefix = save_prefix(1:end-4);
    end

    sweep_label = strrep(sweep_param, '_', ' ');
    n    = numel(results);
    vals = arrayfun(@(r) r.value, results);

    % Per-result display labels (scenario label if present, else param=val)
    has_labels = all(arrayfun(@(r) isfield(r,'label') && ~isempty(r.label), results));
    if has_labels
        panel_labels = {results.label};
    else
        panel_labels = arrayfun(@(r) sprintf('%s = %.4g', sweep_label, r.value), ...
                                results, 'UniformOutput', false);
    end

    % ---- Collect all result data ----------------------------------------
    load_disp_arr = cell(n,1);   % Format B: [load, max_disp] per step
    nodes_arr     = cell(n,1);   % Format A: node coordinates
    disp_arr      = cell(n,1);   % Format A: per-node displacements
    ec_arr        = cell(n,1);   % Format A: element connectivity
    msh_arr       = cell(n,1);   % PS .msh polygons (undeformed)
    dis_arr       = cell(n,1);   % PS .dis polygons (deformed)
    vec_arr       = cell(n,1);   % PS .vec arrows
    maxu_vec      = NaN(n,1);

    for i = 1:n
        if results(i).status ~= 0, continue; end

        % Parse .res — use the actual run overrides for coord extraction so
        % multi-param scenarios supply all changed values, not just one.
        if isfield(results(i).out, 'overrides') && ~isempty(fieldnames(results(i).out.overrides))
            ov = results(i).out.overrides;
        elseif isfield(results(i), 'overrides') && ~isempty(fieldnames(results(i).overrides))
            ov = results(i).overrides;
        else
            ov = struct();
        end
        [nd, dm, ec, ld] = parse_res(results(i).out, yaml_path, ov);
        nodes_arr{i}     = nd;
        disp_arr{i}      = dm;
        ec_arr{i}        = ec;
        load_disp_arr{i} = ld;

        if ~isempty(dm)
            nc = min(2, size(dm,2));
            maxu_vec(i) = max(sqrt(sum(dm(:,1:nc).^2, 2)));
        elseif ~isempty(ld)
            maxu_vec(i) = max(abs(ld(:,2)));
        end

        % Locate PostScript output files
        out_files = {};
        if isfield(results(i).out, 'files')
            out_files = results(i).out.files;
        elseif isfield(results(i), 'files')
            out_files = results(i).files;
        end
        if ~iscell(out_files), out_files = {}; end

        msh_f = out_files(cellfun(@(f) endsWith(f,'.msh'), out_files));
        if ~isempty(msh_f) && exist(msh_f{1},'file')
            msh_arr{i} = parse_pfem_msh(msh_f{1});
        end

        dis_f = out_files(cellfun(@(f) endsWith(f,'.dis'), out_files));
        if ~isempty(dis_f) && exist(dis_f{1},'file')
            dis_arr{i} = parse_pfem_msh(dis_f{1});   % same PS polygon format
        end

        vec_f = out_files(cellfun(@(f) endsWith(f,'.vec'), out_files));
        if ~isempty(vec_f) && exist(vec_f{1},'file')
            vec_arr{i} = parse_pfem_vec(vec_f{1});
        end
    end

    has_res  = any(~cellfun(@isempty, load_disp_arr)) || any(~cellfun(@isempty, disp_arr));
    has_msh  = any(~cellfun(@isempty, msh_arr));
    has_dis  = any(~cellfun(@isempty, dis_arr));
    has_vecs = any(~cellfun(@isempty, vec_arr));

    vis  = 'off';
    if do_show, vis = 'on'; end
    figs = struct('res',[],'msh',[],'dis',[],'vec',[]);

    % ====================================================================
    % Figure 1 — Load / Displacement  (.res)
    % ====================================================================
    if has_res
        [nr_p, nc_p] = panel_layout(n);
        n_rows_total = nr_p + 1;   % row 1 = summary curve; rows 2..end = panels
        fig1 = make_dark_figure( ...
            sprintf('Load–Disp — %s — %s sweep', case_title, sweep_label), ...
            nc_p, n_rows_total, vis);
        figs.res = fig1;

        % Top row: parameter-vs-max|u| sweep curve (spans all columns)
        ax_c = subplot(n_rows_total, nc_p, 1:nc_p, 'Parent', fig1);
        style_ax(ax_c);
        hold(ax_c,'on'); grid(ax_c,'on');

        ok = ([results.status]==0) & ~isnan(maxu_vec');
        if any(ok)
            plot(ax_c, vals(ok), maxu_vec(ok)', 'o-', ...
                 'Color',[0.40 0.75 0.40], 'MarkerFaceColor',[0.40 0.75 0.40], ...
                 'LineWidth',2, 'MarkerSize',8);
        end
        if any(~ok)
            plot(ax_c, vals(~ok), zeros(1,sum(~ok)), 'rx', ...
                 'MarkerSize',12, 'LineWidth',2);
        end
        % When x-axis carries scenario indices, label each tick with the scenario text
        if has_labels
            set(ax_c, 'XTick', vals, 'XTickLabel', panel_labels, ...
                      'XTickLabelRotation', 20, 'TickLabelInterpreter', 'none');
        end
        xlabel(ax_c, sweep_label, 'Color',[0.75 0.75 0.75], 'FontSize',9);
        ylabel(ax_c, 'max|u|',    'Color',[0.75 0.75 0.75], 'FontSize',9);
        title(ax_c, sprintf('%s — sweep of  %s', case_title, sweep_label), ...
              'Color',[0.88 0.88 0.88], 'FontSize',10, 'Interpreter','none');
        hold(ax_c,'off');

        % Remaining rows: one panel per scenario (layout handles n > 4)
        for i = 1:n
            ax  = subplot(n_rows_total, nc_p, nc_p + i, 'Parent', fig1);
            style_ax(ax);
            lbl = panel_labels{i};

            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);

            elseif ~isempty(load_disp_arr{i})
                draw_load_disp(ax, load_disp_arr{i});
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax, lbl, 'FontSize',8,'Color',[0.80 0.80 0.80],'Interpreter','none');

            elseif ~isempty(disp_arr{i})
                dm  = disp_arr{i};
                nc  = min(2, size(dm,2));
                mag = sqrt(sum(dm(:,1:nc).^2, 2));
                plot(ax, 1:numel(mag), mag, '-', ...
                     'Color',[0.40 0.75 0.40], 'LineWidth',1.5);
                xlabel(ax,'Node','Color',[0.70 0.70 0.70],'FontSize',8);
                ylabel(ax,'|u|', 'Color',[0.70 0.70 0.70],'FontSize',8);
                grid(ax,'on');
                lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                title(ax, lbl, 'FontSize',8,'Color',[0.80 0.80 0.80],'Interpreter','none');

            else
                show_na(ax, [lbl newline 'N/A']);
            end
        end

        do_save(fig1, save_prefix, 'res');
    end

    % ====================================================================
    % Figure 2 — Reference Mesh  (.msh)
    % ====================================================================
    if has_msh
        [nr, nc2] = panel_layout(n);
        fig2 = make_dark_figure( ...
            sprintf('Reference Mesh — %s — %s sweep', case_title, sweep_label), ...
            nc2, nr, vis);
        figs.msh = fig2;

        for i = 1:n
            ax  = subplot(nr, nc2, i, 'Parent', fig2);
            lbl = panel_labels{i};
            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
            elseif ~isempty(msh_arr{i})
                draw_ps_mesh(ax, msh_arr{i}, [0.72 0.78 0.84]);
                title(ax, lbl,'FontSize',8,'Color',[0.80 0.80 0.80],'Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
        end

        do_save(fig2, save_prefix, 'msh');
    end

    % ====================================================================
    % Figure 3 — Deformed Shape  (.dis)
    % ====================================================================
    if has_dis
        [nr, nc2] = panel_layout(n);
        fig3 = make_dark_figure( ...
            sprintf('Deformed Shape — %s — %s sweep', case_title, sweep_label), ...
            nc2, nr, vis);
        figs.dis = fig3;

        for i = 1:n
            ax  = subplot(nr, nc2, i, 'Parent', fig3);
            lbl = panel_labels{i};
            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
            elseif ~isempty(dis_arr{i})
                draw_ps_mesh(ax, dis_arr{i}, [0.70 0.85 0.70]);
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax, lbl,'FontSize',8,'Color',[0.80 0.80 0.80],'Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
        end

        do_save(fig3, save_prefix, 'dis');
    end

    % ====================================================================
    % Figure 4 — Displacement Vectors  (.vec)
    % ====================================================================
    if has_vecs
        [nr, nc2] = panel_layout(n);
        fig4 = make_dark_figure( ...
            sprintf('Displacement Vectors — %s — %s sweep', case_title, sweep_label), ...
            nc2, nr, vis);
        figs.vec = fig4;

        for i = 1:n
            ax  = subplot(nr, nc2, i, 'Parent', fig4);
            lbl = panel_labels{i};
            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
            elseif ~isempty(vec_arr{i})
                draw_ps_vecs(ax, vec_arr{i});
                title(ax, lbl,'FontSize',8,'Color',[0.80 0.80 0.80],'Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
        end

        do_save(fig4, save_prefix, 'vec');
    end
end


% ==========================================================================
% Layout helpers
% ==========================================================================

function fig = make_dark_figure(name, ncols, nrows, vis)
    fig = figure('Name', name, ...
                 'Position', [80 80 min(340*ncols, 1400) 280*nrows], ...
                 'Color', [0.11 0.11 0.14], ...
                 'Visible', vis);
end


function [nr, nc] = panel_layout(n)
% Choose rows/cols so panels fit in at most 4 columns.
    nc = min(n, 4);
    nr = ceil(n / nc);
end


function style_ax(ax)
    set(ax, 'Color', [0.08 0.08 0.10], ...
            'XColor', [0.70 0.70 0.70], 'YColor', [0.70 0.70 0.70], ...
            'GridColor',[0.30 0.30 0.30], 'GridAlpha',0.5);
end


function do_save(fig, prefix, tag)
    if isempty(prefix), return; end
    out_path = [prefix '_' tag '.png'];
    d = fileparts(out_path);
    if ~isempty(d) && ~exist(d,'dir'), mkdir(d); end
    print(fig, out_path, '-dpng', '-r120');
end


% ==========================================================================
% Drawing helpers
% ==========================================================================

function show_na(ax, lbl)
    axis(ax,'off');
    set(ax,'Color',[0.08 0.08 0.10]);
    text(ax, 0.5, 0.5, lbl, 'HorizontalAlignment','center', ...
         'Color',[0.5 0.5 0.5], 'FontSize',9, 'Units','normalized');
end


function draw_ps_mesh(ax, patches, edge_col)
% Draw PostScript polygon list (from .msh or .dis file).
    if nargin < 3, edge_col = [0.72 0.78 0.84]; end
    hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');
    set(ax,'Color',[0.08 0.08 0.10]);
    face_col = [0.12 0.14 0.17];
    for k = 1:numel(patches)
        pts = patches{k};
        if size(pts,1) < 2, continue; end
        fill(ax, pts([1:end,1],1), pts([1:end,1],2), ...
             face_col, 'EdgeColor', edge_col, 'LineWidth', 0.7);
    end
    hold(ax,'off');
end


function draw_ps_vecs(ax, arrows)
% Draw displacement arrows from .vec file data.
    hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');
    set(ax,'Color',[0.08 0.08 0.10]);
    col = [0.55 0.80 0.55];
    for k = 1:size(arrows,1)
        x1 = arrows(k,1); y1 = arrows(k,2);
        x2 = arrows(k,3); y2 = arrows(k,4);
        quiver(ax, x1, y1, x2-x1, y2-y1, 0, ...
               'Color',col, 'LineWidth',0.8, 'MaxHeadSize',0.6);
    end
    hold(ax,'off');
end


function draw_load_disp(ax, load_disp)
% Draw load vs displacement curve (Format B .res data).
    hold(ax,'on'); grid(ax,'on');
    set(ax,'Color',[0.08 0.08 0.10], ...
           'XColor',[0.70 0.70 0.70], 'YColor',[0.70 0.70 0.70], ...
           'GridColor',[0.30 0.30 0.30], 'GridAlpha',0.4);
    plot(ax, abs(load_disp(:,2)), load_disp(:,1), 'o-', ...
         'Color',[0.40 0.75 0.40], 'MarkerFaceColor',[0.40 0.75 0.40], ...
         'LineWidth',1.5, 'MarkerSize',4);
    xlabel(ax,'max|u|','Color',[0.70 0.70 0.70],'FontSize',8);
    ylabel(ax,'Load',  'Color',[0.70 0.70 0.70],'FontSize',8);
    hold(ax,'off');
end


function draw_deformed(ax, nodes, disp_mat, elem_conn)
% Draw deformed mesh from YAML node coordinates and Format A per-node displacements.
    hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');

    nc       = min(2, size(disp_mat,2));
    disp_mag = sqrt(sum(disp_mat(:,1:nc).^2, 2));
    max_mag  = max(disp_mag);

    if size(nodes,2) >= 2
        W  = max(nodes(:,1)) - min(nodes(:,1));
        H  = max(nodes(:,2)) - min(nodes(:,2));
        sf = 1;
        if max_mag > 0, sf = 0.08 * max(W,H) / max_mag; end

        def      = nodes;
        def(:,1) = nodes(:,1) + sf * disp_mat(:,1);
        def(:,2) = nodes(:,2) + sf * disp_mat(:,2);

        if ~isempty(elem_conn)
            draw_edges(ax, nodes, elem_conn, [0.22 0.28 0.34], 0.5);
            draw_edges(ax, def,   elem_conn, [0.48 0.60 0.72], 0.9);
        end
        scatter(ax, def(:,1), def(:,2), 18, disp_mag, 'filled');
        colormap(ax,'turbo');
    else
        x = (1:size(disp_mat,1))';
        scatter(ax, x, disp_mat(:,1), 18, disp_mag, 'filled');
        colormap(ax,'turbo');
    end
    hold(ax,'off');
end


function draw_edges(ax, nodes, conn, col, lw)
    for e = 1:size(conn,1)
        nids = conn(e,:);
        nids = nids(nids >= 1 & nids <= size(nodes,1));
        if numel(nids) < 2, continue; end
        nids(end+1) = nids(1); %#ok<AGROW>
        plot(ax, nodes(nids,1), nodes(nids,2), '-', 'Color',col, 'LineWidth',lw);
    end
end


% ==========================================================================
% File parsers
% ==========================================================================

function patches = parse_pfem_msh(msh_path)
% Parse a PFEM PostScript mesh file (.msh or .dis) into polygon vertex arrays.
    patches = {};
    try
        fid = fopen(msh_path,'r');
        if fid == -1, return; end
        raw = textscan(fid,'%s','Delimiter','\n','Whitespace','');
        fclose(fid);
        lines = raw{1};

        NUM   = '([+-]?\d+\.?\d*(?:[eE][+-]?\d+)?)';
        pat_m = ['^' NUM '\s+' NUM '\s+m\s*$'];
        pat_l = ['^' NUM '\s+' NUM '\s+l\s*$'];

        current = [];
        for k = 1:numel(lines)
            ln  = strtrim(lines{k});
            tok = regexp(ln, pat_m, 'tokens');
            if ~isempty(tok)
                current = [str2double(tok{1}{1}), str2double(tok{1}{2})];
                continue;
            end
            tok = regexp(ln, pat_l, 'tokens');
            if ~isempty(tok)
                current(end+1,:) = [str2double(tok{1}{1}), str2double(tok{1}{2})]; %#ok<AGROW>
                continue;
            end
            if strcmp(ln,'c s') && size(current,1) >= 3
                patches{end+1} = current; %#ok<AGROW>
                current = [];
            end
        end
    catch
    end
end


function arrows = parse_pfem_vec(vec_path)
% Parse a PFEM .vec PostScript file into [from_x from_y to_x to_y] rows.
    arrows = [];
    try
        fid = fopen(vec_path,'r');
        if fid == -1, return; end
        raw = textscan(fid,'%s','Delimiter','\n','Whitespace','');
        fclose(fid);
        lines = raw{1};

        NUM = '([+-]?\d+\.?\d*(?:[eE][+-]?\d+)?)';
        pat = ['^' NUM '\s+' NUM '\s+' NUM '\s+' NUM '\s+arrow\s*$'];

        for k = 1:numel(lines)
            ln  = strtrim(lines{k});
            tok = regexp(ln, pat, 'tokens');
            if ~isempty(tok)
                arrows(end+1,:) = cellfun(@str2double, tok{1}); %#ok<AGROW>
            end
        end
    catch
    end
end


function [nodes, disp_mat, elem_conn, load_disp] = parse_res(out, yaml_path, overrides)
% Parse a PFEM .res file.
%
% Format A (elastic/structural): per-node displacement table.
%   Returns: nodes (Nx2), disp_mat (Nx2+), elem_conn, load_disp=[]
% Format B (nonlinear load-step): "step load disp iters" table.
%   Returns: nodes=[], disp_mat=[], elem_conn=[], load_disp (Nx2 [load, max_disp])
    nodes = []; disp_mat = []; elem_conn = []; load_disp = [];

    if ~isfield(out,'files') || isempty(out.files), return; end
    res_files = out.files(cellfun(@(f) endsWith(f,'.res'), out.files));
    if isempty(res_files), return; end
    res_path = res_files{1};
    if ~exist(res_path,'file'), return; end

    fid = fopen(res_path,'r');
    if fid == -1, return; end
    raw   = textscan(fid,'%s','Delimiter','\n','Whitespace','');
    fclose(fid);
    lines = raw{1};

    % --- Try Format A: per-node displacement header ---
    disp_start = 0;
    disp_cols  = 2;
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if contains(ln,'Node') && contains(ln,'disp')
            disp_start = i + 1;
            if     contains(ln,'z-disp'),  disp_cols = 3;
            elseif ~contains(ln,'y-disp'), disp_cols = 1;
            end
            break;
        end
    end

    if disp_start > 0
        dd = [];
        for i = disp_start:numel(lines)
            ln = strtrim(lines{i});
            if isempty(ln) || contains(ln,'integration') || contains(ln,'Element'), break; end
            v = sscanf(ln,'%f');
            if numel(v) >= 1 + disp_cols
                dd(end+1,:) = v(2:(1+disp_cols))'; %#ok<AGROW>
            end
        end
        if ~isempty(dd)
            disp_mat = dd;
            n_nodes  = size(dd,1);
            try
                [ny, ec, ~] = pfem_extract_coords(yaml_path, overrides);
                if ~isempty(ny) && size(ny,1) == n_nodes
                    nodes     = ny;
                    elem_conn = ec;
                else
                    nodes = [(1:n_nodes)', zeros(n_nodes,1)];
                end
            catch
                nodes = [(1:n_nodes)', zeros(n_nodes,1)];
            end
        end
        return;
    end

    % --- Try Format B: "step load disp iters" header ---
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if contains(ln,'step') && contains(ln,'load') && contains(ln,'disp')
            ld = [];
            for j = i+1:numel(lines)
                ln2 = strtrim(lines{j});
                if isempty(ln2), break; end
                v = sscanf(ln2,'%f');
                if numel(v) >= 3
                    ld(end+1,:) = [v(2), v(3)]; %#ok<AGROW>
                end
            end
            if ~isempty(ld), load_disp = ld; end
            return;
        end
    end

    % --- Try Format C: seepage/consolidation "Time  Uav  Pressure" header ---
    % Returns [time, Uav] so the existing load-disp plot shows consolidation
    % degree (Uav) vs time.
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if contains(ln,'Time') && contains(ln,'Uav')
            ld = [];
            for j = i+1:numel(lines)
                ln2 = strtrim(lines{j});
                if isempty(ln2) || contains(ln2,'Depth'), break; end
                v = sscanf(ln2,'%f');
                if numel(v) >= 2
                    ld(end+1,:) = [v(1), v(2)]; %#ok<AGROW>  [time, Uav]
                end
            end
            if ~isempty(ld), load_disp = ld; end
            return;
        end
    end
end
