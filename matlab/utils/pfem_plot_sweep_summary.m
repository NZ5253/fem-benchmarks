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
        panel_labels = cellfun(@wrap_label, {results.label}, 'UniformOutput', false);
    else
        panel_labels = arrayfun(@(r) sprintf('%s = %.4g', sweep_label, r.value), ...
                                results, 'UniformOutput', false);
    end

    % ---- Collect all result data ----------------------------------------
    load_disp_arr = cell(n,1);   % Format B/C: [col1, col2] per step
    ld_fmt_arr    = repmat({'B'}, n, 1);  % 'B'=load-step, 'C'=seepage
    nodes_arr     = cell(n,1);   % Format A: node coordinates
    disp_arr      = cell(n,1);   % Format A: per-node displacements
    ec_arr        = cell(n,1);   % Format A: element connectivity
    msh_arr       = cell(n,1);   % PS .msh polygons (undeformed)
    dis_arr       = cell(n,1);   % PS .dis polygons (deformed)
    vec_arr       = cell(n,1);   % PS .vec arrows
    ensi_arr      = cell(n,1);   % EnSight Gold: {nodes, conn, displ_steps, srf_vals, ld_srf}
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
        [nd, dm, ec, ld, ld_fmt] = parse_res(results(i).out, yaml_path, ov);
        nodes_arr{i}     = nd;
        disp_arr{i}      = dm;
        ec_arr{i}        = ec;
        load_disp_arr{i} = ld;
        if ~isempty(ld_fmt), ld_fmt_arr{i} = ld_fmt; end

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

        % EnSight Gold (.ensi.case) — 3D programs (p612, p613, p57, …)
        ensi_f = out_files(cellfun(@(f) endsWith(f,'.ensi.case'), out_files));
        if ~isempty(ensi_f) && exist(ensi_f{1},'file')
            try
                [en_nodes, en_conn, en_displ, en_srf] = parse_pfem_ensi(ensi_f{1});
                % Pull SRF values from .res load_disp table if available
                % (ensi time values are just step indices 1,2,3,…)
                ld_srf = en_srf;
                if ~isempty(load_disp_arr{i})
                    ld_srf = load_disp_arr{i}(:,1);  % actual srf from .res
                end
                ensi_arr{i} = struct('nodes',en_nodes, 'conn',en_conn, ...
                    'displ',{en_displ}, 'srf',ld_srf);
                % Update maxu_vec from EnSight last step if not already set
                if isnan(maxu_vec(i)) && ~isempty(en_displ) && ~isempty(en_displ{end})
                    d = en_displ{end};
                    maxu_vec(i) = max(sqrt(sum(d.^2, 2)));
                end
            catch
            end
        end
    end

    has_res  = any(~cellfun(@isempty, load_disp_arr)) || any(~cellfun(@isempty, disp_arr));
    has_msh  = any(~cellfun(@isempty, msh_arr));
    has_dis  = any(~cellfun(@isempty, dis_arr));
    has_vecs = any(~cellfun(@isempty, vec_arr));
    has_ensi = any(~cellfun(@isempty, ensi_arr));

    vis  = 'off';
    if do_show, vis = 'on'; end
    figs = struct('res',[],'msh',[],'dis',[],'vec',[],'ensi',[]);

    % Distinct color per scenario — used consistently across every figure type
    scenario_colors = scenario_color_map(n);

    % ====================================================================
    % Figure 1 — Load / Displacement  (.res)
    % ====================================================================
    % Detect dominant format for axis labels (C = seepage if any scenario is C)
    is_seepage = any(strcmp(ld_fmt_arr, 'C'));
    if is_seepage
        ov_xlabel = 'Time';  ov_ylabel = 'Uav';
        sum_ylabel = 'final Uav';
    else
        ov_xlabel = 'max|u|'; ov_ylabel = 'Load';
        sum_ylabel = 'max|u|';
    end

    if has_res
        [nr_p, nc_p] = panel_layout(n);
        % Layout: row 1 = overlay (full width)
        %         row 2 = summary sweep curve (full width)
        %         rows 3+ = individual panels
        n_rows_total = nr_p + 2;
        fig1_title = sprintf('%s — %s sweep', case_title, sweep_label);
        if is_seepage, fig1_title = ['Consolidation — ' fig1_title]; end
        fig1 = make_dark_figure(fig1_title, nc_p, n_rows_total, vis);
        figs.res = fig1;

        % ---- Row 1: Overlay — all curves on one axis, distinct colors ----
        ax_ov = subplot(n_rows_total, nc_p, 1:nc_p, 'Parent', fig1);
        style_ax(ax_ov);
        hold(ax_ov,'on'); grid(ax_ov,'on');
        leg_handles = gobjects(n,1);
        leg_labels  = cell(n,1);
        for i = 1:n
            col = scenario_colors(i,:);
            if results(i).status ~= 0
                leg_handles(i) = plot(ax_ov, NaN, NaN, 'x', 'Color',col, ...
                    'MarkerSize',10, 'LineWidth',2);
                leg_labels{i}  = [panel_labels{i} '  [FAIL]'];
            elseif ~isempty(load_disp_arr{i})
                ld = load_disp_arr{i};
                if is_seepage
                    xd = ld(:,1); yd = ld(:,2);
                else
                    xd = abs(ld(:,2)); yd = ld(:,1);
                end
                leg_handles(i) = plot(ax_ov, xd, yd, 'o-', ...
                    'Color',col, 'MarkerFaceColor',col, ...
                    'LineWidth',2, 'MarkerSize',5);
                leg_labels{i}  = panel_labels{i};
            elseif ~isempty(disp_arr{i})
                dm  = disp_arr{i};
                nc2 = min(2, size(dm,2));
                mag = sqrt(sum(dm(:,1:nc2).^2, 2));
                leg_handles(i) = plot(ax_ov, 1:numel(mag), mag, '-', ...
                    'Color',col, 'LineWidth',2);
                leg_labels{i}  = panel_labels{i};
            else
                leg_handles(i) = plot(ax_ov, NaN, NaN, '-', 'Color',col);
                leg_labels{i}  = [panel_labels{i} '  [N/A]'];
            end
        end
        xlabel(ax_ov, ov_xlabel, 'Color',[0.75 0.75 0.75], 'FontSize',9);
        ylabel(ax_ov, ov_ylabel, 'Color',[0.75 0.75 0.75], 'FontSize',9);
        title(ax_ov, sprintf('Overlay — %s  [%d scenarios]', case_title, n), ...
              'Color',[0.95 0.95 0.95], 'FontSize',11, 'FontWeight','bold', ...
              'Interpreter','none');
        lgd = legend(ax_ov, leg_handles, leg_labels, ...
                     'TextColor',[0.88 0.88 0.88], 'FontSize',8, ...
                     'Location','best', 'Interpreter','none');
        lgd.Color = [0.10 0.10 0.13];
        hold(ax_ov,'off');

        % ---- Row 2: Summary — sweep parameter vs max|u| ----
        ax_c = subplot(n_rows_total, nc_p, (nc_p+1):(2*nc_p), 'Parent', fig1);
        style_ax(ax_c);
        hold(ax_c,'on'); grid(ax_c,'on');
        ok = ([results.status]==0) & ~isnan(maxu_vec');
        for i = 1:n
            col = scenario_colors(i,:);
            if ok(i)
                plot(ax_c, vals(i), maxu_vec(i), 'o', ...
                     'Color',col, 'MarkerFaceColor',col, 'MarkerSize',10);
            else
                plot(ax_c, vals(i), 0, 'x', 'Color',col, ...
                     'MarkerSize',12, 'LineWidth',2);
            end
        end
        if sum(ok) > 1
            plot(ax_c, vals(ok), maxu_vec(ok)', '--', ...
                 'Color',[0.55 0.55 0.55], 'LineWidth',1);
        end
        if has_labels
            set(ax_c, 'XTick', vals, 'XTickLabel', panel_labels, ...
                      'XTickLabelRotation', 20, 'TickLabelInterpreter', 'none');
        end
        xlabel(ax_c, sweep_label, 'Color',[0.75 0.75 0.75], 'FontSize',9);
        ylabel(ax_c, sum_ylabel,  'Color',[0.75 0.75 0.75], 'FontSize',9);
        title(ax_c, sprintf('Summary — %s vs %s', sum_ylabel, sweep_label), ...
              'Color',[0.88 0.88 0.88], 'FontSize',9, 'Interpreter','none');
        hold(ax_c,'off');

        % ---- Rows 3+: Individual panels (same color as overlay) ----
        % Compute shared axis limits for fair visual comparison
        all_x = []; all_y = [];
        for i = 1:n
            if ~isempty(load_disp_arr{i})
                ld = load_disp_arr{i};
                if is_seepage
                    all_x = [all_x; ld(:,1)]; all_y = [all_y; ld(:,2)]; %#ok<AGROW>
                else
                    all_x = [all_x; abs(ld(:,2))]; all_y = [all_y; ld(:,1)]; %#ok<AGROW>
                end
            end
        end
        shared_xlim = []; shared_ylim = [];
        if ~isempty(all_x)
            shared_xlim = [min(all_x)*0.95, max(all_x)*1.05];
            shared_ylim = [min(all_y)*0.95, max(all_y)*1.05];
            % Avoid degenerate limits
            if shared_xlim(1) == shared_xlim(2), shared_xlim = shared_xlim + [-1 1]; end
            if shared_ylim(1) == shared_ylim(2), shared_ylim = shared_ylim + [-1 1]; end
        end

        panel_axes = gobjects(n,1);
        for i = 1:n
            ax  = subplot(n_rows_total, nc_p, 2*nc_p + i, 'Parent', fig1);
            style_ax(ax);
            col = scenario_colors(i,:);
            lbl = panel_labels{i};

            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
                % Colored title bar to indicate failure
                title(ax, lbl, 'FontSize',10, 'Color',col, 'Interpreter','none');

            elseif ~isempty(load_disp_arr{i})
                draw_load_disp(ax, load_disp_arr{i}, ld_fmt_arr{i}, col);
                if ~isempty(shared_xlim)
                    xlim(ax, shared_xlim); ylim(ax, shared_ylim);
                end
                if ~isnan(maxu_vec(i))
                    val_lbl = sprintf('%.3e', maxu_vec(i));
                    if strcmp(ld_fmt_arr{i}, 'C')
                        lbl = sprintf('%s\nfinal Uav = %s', lbl, val_lbl);
                    else
                        lbl = sprintf('%s\nmax|u| = %s', lbl, val_lbl);
                    end
                end
                title(ax, lbl, 'FontSize',10, 'Color',col, 'Interpreter','none');

            elseif ~isempty(disp_arr{i})
                dm  = disp_arr{i};
                nc2 = min(2, size(dm,2));
                mag = sqrt(sum(dm(:,1:nc2).^2, 2));
                plot(ax, 1:numel(mag), mag, '-', 'Color',col, 'LineWidth',1.5);
                xlabel(ax,'Node','Color',[0.70 0.70 0.70],'FontSize',8);
                ylabel(ax,'|u|', 'Color',[0.70 0.70 0.70],'FontSize',8);
                grid(ax,'on');
                lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                title(ax, lbl, 'FontSize',10, 'Color',col, 'Interpreter','none');

            else
                show_na(ax, [lbl newline 'N/A']);
            end
            panel_axes(i) = ax;
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
        mesh_axes = gobjects(n,1);
        for i = 1:n
            ax  = subplot(nr, nc2, i, 'Parent', fig2);
            col = scenario_colors(i,:);
            lbl = panel_labels{i};
            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
                title(ax, lbl,'FontSize',8,'Color',col,'Interpreter','none');
            elseif ~isempty(msh_arr{i})
                draw_ps_mesh(ax, msh_arr{i}, col);
                title(ax, lbl,'FontSize',11,'Color',col,'FontWeight','bold','Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
            mesh_axes(i) = ax;
        end
        linkaxes(mesh_axes, 'xy');   % same scale across panels
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
        dis_axes = gobjects(n,1);
        for i = 1:n
            ax  = subplot(nr, nc2, i, 'Parent', fig3);
            col = scenario_colors(i,:);
            lbl = panel_labels{i};
            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
                title(ax, lbl,'FontSize',8,'Color',col,'Interpreter','none');
            elseif ~isempty(dis_arr{i})
                draw_ps_mesh(ax, dis_arr{i}, col);
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax, lbl,'FontSize',11,'Color',col,'FontWeight','bold','Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
            dis_axes(i) = ax;
        end
        linkaxes(dis_axes, 'xy');    % same spatial scale across panels
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
        vec_axes = gobjects(n,1);
        for i = 1:n
            ax  = subplot(nr, nc2, i, 'Parent', fig4);
            col = scenario_colors(i,:);
            lbl = panel_labels{i};
            if results(i).status ~= 0
                show_na(ax, [lbl newline '[FAIL]']);
                title(ax, lbl,'FontSize',8,'Color',col,'Interpreter','none');
            elseif ~isempty(vec_arr{i})
                draw_ps_vecs(ax, vec_arr{i}, col);
                title(ax, lbl,'FontSize',11,'Color',col,'FontWeight','bold','Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
            vec_axes(i) = ax;
        end
        linkaxes(vec_axes, 'xy');
        do_save(fig4, save_prefix, 'vec');
    end

    % ====================================================================
    % Figure 5 — 3D EnSight: deformed shape panels per scenario
    %   Left column : side view  (x–y projection, z = slice near z_min)
    %   Right column: plan view  (x–z projection, y = slice near y_max)
    % Each row is one sweep scenario; color = displacement magnitude.
    % Matches book Figure 6.55 style for p612/p613 slope problems.
    % ====================================================================
    if has_ensi
        % Determine subplot layout: 2 view columns × n scenario rows
        n_rows_e = n;
        fig5 = make_dark_figure( ...
            sprintf('Deformed Shape (3D) — %s — %s sweep', case_title, sweep_label), ...
            2, n_rows_e, vis);
        figs.ensi = fig5;

        % Global color limits: max displacement across all scenarios + steps
        global_maxu = 0;
        for i = 1:n
            if isempty(ensi_arr{i}), continue; end
            for s = 1:numel(ensi_arr{i}.displ)
                if isempty(ensi_arr{i}.displ{s}), continue; end
                d = ensi_arr{i}.displ{s};
                global_maxu = max(global_maxu, max(sqrt(sum(d.^2,2))));
            end
        end
        if global_maxu == 0, global_maxu = 1; end

        for i = 1:n
            col = scenario_colors(i,:);
            lbl = panel_labels{i};

            ax_side = subplot(n_rows_e, 2, (i-1)*2+1, 'Parent', fig5);
            ax_plan = subplot(n_rows_e, 2, (i-1)*2+2, 'Parent', fig5);
            style_ax(ax_side); style_ax(ax_plan);

            if results(i).status ~= 0 || isempty(ensi_arr{i})
                show_na(ax_side, [lbl newline '[N/A]']);
                show_na(ax_plan, [lbl newline '[N/A]']);
                title(ax_side, lbl,'Color',col,'FontSize',9,'Interpreter','none');
                title(ax_plan, '(plan)','Color',col,'FontSize',9,'Interpreter','none');
                continue;
            end

            en    = ensi_arr{i};
            nodes = en.nodes;     % N×3
            srf_v = en.srf;

            % Use last displacement step (failure / highest SRF)
            last_s = numel(en.displ);
            while last_s > 1 && isempty(en.displ{last_s})
                last_s = last_s - 1;
            end
            if isempty(en.displ{last_s})
                show_na(ax_side, [lbl newline 'no displ']);
                show_na(ax_plan, [lbl newline 'no displ']);
                continue;
            end
            d_last = en.displ{last_s};          % N×3 displacement at last SRF
            mag    = sqrt(sum(d_last.^2, 2));   % N×1 magnitude

            % Scale factor: amplify displ so it is ~8% of domain width
            domain_w = max(nodes(:,1)) - min(nodes(:,1));
            sf = 0;
            if max(mag) > 0, sf = 0.08 * domain_w / max(mag); end

            % Deformed node positions
            xd = nodes(:,1) + sf * d_last(:,1);
            yd = nodes(:,2) + sf * d_last(:,2);
            zd = nodes(:,3) + sf * d_last(:,3);

            srf_lbl = '';
            if ~isempty(srf_v) && last_s <= numel(srf_v)
                srf_lbl = sprintf('  SRF=%.3g', srf_v(last_s));
            end
            max_lbl = sprintf('  max|u|=%.3e', max(mag));

            % ── Side view: x–y (deformed, colored by |u|) ──────────────
            draw_ensi_scatter(ax_side, xd, yd, mag, [0 global_maxu], col);
            draw_ensi_edges(ax_side, xd, yd, en.conn, [0.25 0.28 0.32]);
            xlabel(ax_side,'x','Color',[0.7 0.7 0.7],'FontSize',8);
            ylabel(ax_side,'y','Color',[0.7 0.7 0.7],'FontSize',8);
            title(ax_side, [lbl newline 'Side view (x-y)' srf_lbl max_lbl], ...
                'Color',col,'FontSize',9,'FontWeight','bold','Interpreter','none');

            % ── Plan view: x–z (deformed, colored by |u|) ──────────────
            draw_ensi_scatter(ax_plan, xd, zd, mag, [0 global_maxu], col);
            draw_ensi_edges(ax_plan, xd, zd, en.conn, [0.25 0.28 0.32]);
            xlabel(ax_plan,'x','Color',[0.7 0.7 0.7],'FontSize',8);
            ylabel(ax_plan,'z','Color',[0.7 0.7 0.7],'FontSize',8);
            title(ax_plan, 'Plan view (x-z)', ...
                'Color',[0.7 0.7 0.7],'FontSize',9,'Interpreter','none');

            % Colorbar on plan axis
            cb = colorbar(ax_plan);
            cb.Color = [0.7 0.7 0.7];
            cb.Label.String = '|u|';
            cb.Label.Color  = [0.7 0.7 0.7];
            clim(ax_plan, [0 global_maxu]);
        end

        do_save(fig5, save_prefix, 'ensi');
    end
end


function lbl = wrap_label(lbl, max_per_line)
% Wrap a space-separated "key=val key=val ..." label every max_per_line tokens.
    if nargin < 2, max_per_line = 3; end
    parts = strsplit(strtrim(lbl), ' ');
    parts = parts(~cellfun(@isempty, parts));
    lines = {};
    for k = 1:max_per_line:numel(parts)
        chunk = parts(k : min(k+max_per_line-1, numel(parts)));
        lines{end+1} = strjoin(chunk, '  '); %#ok<AGROW>
    end
    lbl = strjoin(lines, newline);
end


function colors = scenario_color_map(n)
% Return n visually distinct, high-contrast colors on a dark background.
    if n <= 1
        colors = [0.40 0.85 0.50];
        return;
    end
    % Use a curated palette for small n, fall back to HSV for large n
    palette = [ ...
        0.29 0.78 0.35;   % green
        0.98 0.55 0.24;   % orange
        0.38 0.70 0.98;   % blue
        0.95 0.33 0.33;   % red
        0.75 0.45 0.95;   % purple
        0.98 0.88 0.22;   % yellow
        0.35 0.93 0.88;   % teal
        0.98 0.55 0.75;   % pink
    ];
    if n <= size(palette,1)
        colors = palette(1:n,:);
    else
        colors = hsv(n);
    end
end


% ==========================================================================
% Layout helpers
% ==========================================================================

function fig = make_dark_figure(name, ncols, nrows, vis)
    fig = figure('Name', name, ...
                 'Position', [80 80 min(380*ncols, 1520) 340*nrows], ...
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


function draw_ps_vecs(ax, arrows, col)
% Draw displacement arrows from .vec file data.
    if nargin < 3, col = [0.55 0.80 0.55]; end
    hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');
    set(ax,'Color',[0.08 0.08 0.10]);
    for k = 1:size(arrows,1)
        x1 = arrows(k,1); y1 = arrows(k,2);
        x2 = arrows(k,3); y2 = arrows(k,4);
        quiver(ax, x1, y1, x2-x1, y2-y1, 0, ...
               'Color',col, 'LineWidth',0.8, 'MaxHeadSize',0.6);
    end
    hold(ax,'off');
end


function draw_load_disp(ax, load_disp, fmt, col)
% Draw load-displacement or consolidation curve.
%   fmt='B' (default): Format B load-step — X=max|u|, Y=Load
%   fmt='C':           Format C seepage   — X=Time,   Y=Uav
%   col: RGB line color (default green/teal)
    if nargin < 3, fmt = 'B'; end
    if nargin < 4 || isempty(col)
        if strcmp(fmt,'C'), col = [0.40 0.75 0.75]; else, col = [0.40 0.75 0.40]; end
    end
    hold(ax,'on'); grid(ax,'on');
    set(ax,'Color',[0.08 0.08 0.10], ...
           'XColor',[0.70 0.70 0.70], 'YColor',[0.70 0.70 0.70], ...
           'GridColor',[0.30 0.30 0.30], 'GridAlpha',0.4);
    if strcmp(fmt, 'C')
        plot(ax, load_disp(:,1), load_disp(:,2), 'o-', ...
             'Color',col, 'MarkerFaceColor',col, 'LineWidth',2, 'MarkerSize',5);
        xlabel(ax,'Time', 'Color',[0.70 0.70 0.70],'FontSize',8);
        ylabel(ax,'Uav',  'Color',[0.70 0.70 0.70],'FontSize',8);
    else
        plot(ax, abs(load_disp(:,2)), load_disp(:,1), 'o-', ...
             'Color',col, 'MarkerFaceColor',col, 'LineWidth',2, 'MarkerSize',5);
        xlabel(ax,'max|u|','Color',[0.70 0.70 0.70],'FontSize',8);
        ylabel(ax,'Load',  'Color',[0.70 0.70 0.70],'FontSize',8);
    end
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


function [nodes, disp_mat, elem_conn, load_disp, ld_fmt] = parse_res(out, yaml_path, overrides)
% Parse a PFEM .res file.
%
% Format A (elastic/structural): per-node displacement table.
%   Returns: nodes (Nx2), disp_mat (Nx2+), elem_conn, load_disp=[], ld_fmt=''
% Format B (nonlinear load-step): "step load disp iters" table.
%   Returns: nodes=[], disp_mat=[], elem_conn=[], load_disp (Nx2 [load, max_disp]), ld_fmt='B'
% Format C (seepage/consolidation): "Time  Uav  Pressure" table.
%   Returns: nodes=[], disp_mat=[], elem_conn=[], load_disp (Nx2 [time, Uav]), ld_fmt='C'
    nodes = []; disp_mat = []; elem_conn = []; load_disp = []; ld_fmt = '';

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

    % --- Try Format B: "step load disp iters" OR "srf max disp iters" header ---
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        is_srf = contains(ln,'srf') && contains(ln,'disp');
        is_std = contains(ln,'step') && contains(ln,'load') && contains(ln,'disp');
        if is_srf || is_std
            ld = [];
            for j = i+1:numel(lines)
                ln2 = strtrim(lines{j});
                if isempty(ln2), break; end
                v = sscanf(ln2,'%f');
                if is_srf
                    if numel(v) >= 2
                        ld(end+1,:) = [v(1), v(2)]; %#ok<AGROW>  [srf, max_disp]
                    end
                else
                    if numel(v) >= 3
                        ld(end+1,:) = [v(2), v(3)]; %#ok<AGROW>  [load, disp]
                    end
                end
            end
            if ~isempty(ld), load_disp = ld; ld_fmt = 'B'; end
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
            if ~isempty(ld), load_disp = ld; ld_fmt = 'C'; end
            return;
        end
    end
end


% ==========================================================================
% EnSight drawing helpers
% ==========================================================================

function draw_ensi_scatter(ax, px, py, mag, clim_range, ~)
% Scatter plot of projected node positions, colored by displacement magnitude.
    hold(ax,'on'); axis(ax,'equal');
    set(ax,'Color',[0.06 0.06 0.08]);
    scatter(ax, px, py, 4, mag, 'filled');
    colormap(ax, 'turbo');
    clim(ax, clim_range);
    hold(ax,'off');
end


function draw_ensi_edges(ax, px, py, conn, edge_col)
% Draw element edge outlines projected to the (px,py) plane.
% Uses only the 8 corner nodes of each hexa20 element.
% Faces drawn: bottom quad (nodes 1-2-3-4) and top quad (5-6-7-8).
    if isempty(conn), return; end
    if nargin < 5, edge_col = [0.30 0.33 0.38]; end

    % Corner face index sets for a standard hex8: bottom, top, 4 sides
    hex_faces = {[1 2 3 4]; [5 6 7 8]; [1 2 6 5]; [2 3 7 6]; [3 4 8 7]; [4 1 5 8]};

    hold(ax,'on');
    for e = 1:size(conn,1)
        nids = conn(e,:);
        nids = nids(nids >= 1 & nids <= numel(px));
        if numel(nids) < 4, continue; end
        for fi = 1:numel(hex_faces)
            f = hex_faces{fi};
            f = f(f <= numel(nids));
            if numel(f) < 3, continue; end
            ns = nids(f);
            xf = px(ns([1:end 1]));
            yf = py(ns([1:end 1]));
            plot(ax, xf, yf, '-', 'Color', edge_col, 'LineWidth', 0.4);
        end
    end
    hold(ax,'off');
end
