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

    % ---- LaTeX rendering defaults (crisp vector-quality text) ----
    set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
    set(groot, 'defaultAxesFontSize', 16);

    p = inputParser;
    addParameter(p, 'Title', '');
    addParameter(p, 'Save',  '');
    addParameter(p, 'Show',  true);
    addParameter(p, 'Split', false);
    parse(p, varargin{:});

    case_title  = p.Results.Title;
    save_arg    = p.Results.Save;
    do_show     = p.Results.Show;
    do_split    = p.Results.Split;

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

        % Allow r.out to be a plain directory path string (e.g. from replot scripts)
        r_out = results(i).out;
        if ischar(r_out) || isstring(r_out)
            r_out = pfem_out_from_dir(char(r_out));
        end

        % Parse .res — use the actual run overrides for coord extraction so
        % multi-param scenarios supply all changed values, not just one.
        if isfield(r_out, 'overrides') && ~isempty(fieldnames(r_out.overrides))
            ov = r_out.overrides;
        elseif isfield(results(i), 'overrides') && ~isempty(fieldnames(results(i).overrides))
            ov = results(i).overrides;
        else
            ov = struct();
        end
        [nd, dm, ec, ld, ld_fmt] = parse_res(r_out, yaml_path, ov);
        nodes_arr{i}     = nd;
        disp_arr{i}      = dm;
        ec_arr{i}        = ec;
        load_disp_arr{i} = ld;
        if ~isempty(ld_fmt), ld_fmt_arr{i} = ld_fmt; end

        if ~isempty(dm)
            nc = min(2, size(dm,2));
            maxu_vec(i) = max(sqrt(sum(dm(:,1:nc).^2, 2)));
        elseif ~isempty(ld)
            % For SRF format col2=displacement, for B format col2=disp too
            maxu_vec(i) = max(abs(ld(:,2)));
        end

        % Locate PostScript output files
        out_files = {};
        if isfield(r_out, 'files')
            out_files = r_out.files;
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
                [en_nodes, en_conn, en_displ, en_srf, en_matid] = parse_pfem_ensi(ensi_f{1});
                % Pull SRF values from .res load_disp table if available
                % (ensi time values are just step indices 1,2,3,…)
                ld_srf = en_srf;
                if ~isempty(load_disp_arr{i})
                    ld_srf = load_disp_arr{i}(:,1);  % actual srf from .res
                end
                ensi_arr{i} = struct('nodes',en_nodes, 'conn',en_conn, ...
                    'displ',{en_displ}, 'srf',ld_srf, 'matid',en_matid);
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
    has_ensi_matid = has_ensi && any(cellfun(@(e) ~isempty(e) && ...
        isfield(e,'matid') && ~isempty(e.matid), ensi_arr));

    vis  = 'off';
    if do_show, vis = 'on'; end
    figs = struct('res',[],'msh',[],'dis',[],'vec',[],'ensi',[],'ensi_prog',[],'ensi_zones',[]);

    % Distinct color per scenario — used consistently across every figure type
    scenario_colors = scenario_color_map(n);

    % ====================================================================
    % Figure 1 — Load / Displacement  (.res)
    % ====================================================================
    % Detect dominant format for axis labels
    is_seepage = any(strcmp(ld_fmt_arr, 'C'));
    is_srf_fmt = any(strcmp(ld_fmt_arr, 'S'));
    if is_seepage
        ov_xlabel = 'Time';  ov_ylabel = 'Uav';
        sum_ylabel = 'final Uav';
    elseif is_srf_fmt
        ov_xlabel = 'SRF';   ov_ylabel = '\delta_{max}';
        sum_ylabel = 'max disp';
    else
        ov_xlabel = 'max|u|'; ov_ylabel = 'Load';
        sum_ylabel = 'max|u|';
    end

    if has_res
        [nr_p, nc_p] = panel_layout(n);
        n_rows_total = nr_p + 2;
        fig1_title = sprintf('%s — %s sweep', case_title, sweep_label);
        if is_seepage, fig1_title = ['Consolidation — ' fig1_title]; end
        if is_srf_fmt,  fig1_title = ['SRF Analysis — ' fig1_title]; end
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
                    'MarkerSize',14, 'LineWidth',2.5);
                leg_labels{i}  = [panel_labels{i} '  [FAIL]'];
            elseif ~isempty(load_disp_arr{i})
                ld = load_disp_arr{i};
                if is_seepage
                    xd = ld(:,1); yd = ld(:,2);
                elseif strcmp(ld_fmt_arr{i},'S')
                    xd = ld(:,1); yd = ld(:,2);   % SRF, disp
                else
                    xd = abs(ld(:,2)); yd = ld(:,1);
                end
                leg_handles(i) = plot(ax_ov, xd, yd, 's-', ...
                    'Color',col, 'MarkerFaceColor',col, ...
                    'LineWidth',2.5, 'MarkerSize',9);
                leg_labels{i}  = panel_labels{i};
            elseif ~isempty(disp_arr{i})
                dm  = disp_arr{i};
                nc2 = min(2, size(dm,2));
                mag = sqrt(sum(dm(:,1:nc2).^2, 2));
                leg_handles(i) = plot(ax_ov, 1:numel(mag), mag, '-', ...
                    'Color',col, 'LineWidth',2.5);
                leg_labels{i}  = panel_labels{i};
            else
                leg_handles(i) = plot(ax_ov, NaN, NaN, '-', 'Color',col);
                leg_labels{i}  = [panel_labels{i} '  [N/A]'];
            end
        end
        if is_srf_fmt, set(ax_ov,'YDir','reverse'); end
        xlabel(ax_ov, ov_xlabel, 'Color',[0.15 0.15 0.15], 'FontSize',18);
        ylabel(ax_ov, ov_ylabel, 'Color',[0.15 0.15 0.15], 'FontSize',18);
        title(ax_ov, sprintf('Overlay --- %s  [%d scenarios]', case_title, n), ...
              'Color',[0.10 0.10 0.10], 'FontSize',18, 'FontWeight','bold', ...
              'Interpreter','none');
        lgd = legend(ax_ov, leg_handles, leg_labels, ...
                     'TextColor',[0.20 0.20 0.20], 'FontSize',16, ...
                     'Location','best', 'Interpreter','none');
        lgd.Color = [0.95 0.95 0.95];
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
                     'Color',col, 'MarkerFaceColor',col, 'MarkerSize',14);
            else
                plot(ax_c, vals(i), 0, 'x', 'Color',col, ...
                     'MarkerSize',16, 'LineWidth',2.5);
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
        xlabel(ax_c, sweep_label, 'Color',[0.15 0.15 0.15], 'FontSize',18);
        ylabel(ax_c, sum_ylabel,  'Color',[0.15 0.15 0.15], 'FontSize',18);
        title(ax_c, sprintf('Summary --- %s vs %s', sum_ylabel, sweep_label), ...
              'Color',[0.20 0.20 0.20], 'FontSize',16, 'Interpreter','none');
        hold(ax_c,'off');

        % ---- Rows 3+: Individual panels (same color as overlay) ----
        % Compute shared axis limits for fair visual comparison
        all_x = []; all_y = [];
        for i = 1:n
            if ~isempty(load_disp_arr{i})
                ld = load_disp_arr{i};
                if is_seepage || strcmp(ld_fmt_arr{i}, 'C')
                    all_x = [all_x; ld(:,1)]; all_y = [all_y; ld(:,2)]; %#ok<AGROW>
                elseif strcmp(ld_fmt_arr{i}, 'S')
                    all_x = [all_x; ld(:,1)]; all_y = [all_y; ld(:,2)]; %#ok<AGROW> % X=SRF, Y=δmax
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
                title(ax, lbl, 'FontSize',16, 'Color',col, 'Interpreter','none');

            elseif ~isempty(load_disp_arr{i})
                draw_load_disp(ax, load_disp_arr{i}, ld_fmt_arr{i}, col);
                if ~isempty(shared_xlim)
                    xlim(ax, shared_xlim); ylim(ax, shared_ylim);
                    if strcmp(ld_fmt_arr{i}, 'S')
                        set(ax, 'YDir', 'reverse');
                    end
                end
                if ~isnan(maxu_vec(i))
                    val_lbl = sprintf('%.3e', maxu_vec(i));
                    if strcmp(ld_fmt_arr{i}, 'C')
                        lbl = sprintf('%s\nfinal Uav = %s', lbl, val_lbl);
                    else
                        lbl = sprintf('%s\nmax|u| = %s', lbl, val_lbl);
                    end
                end
                title(ax, lbl, 'FontSize',16, 'Color',col, 'Interpreter','none');

            elseif ~isempty(disp_arr{i})
                dm  = disp_arr{i};
                nc2 = min(2, size(dm,2));
                mag = sqrt(sum(dm(:,1:nc2).^2, 2));
                plot(ax, 1:numel(mag), mag, '-', 'Color',col, 'LineWidth',1.5);
                xlabel(ax,'Node','Color',[0.15 0.15 0.15],'FontSize',16);
                ylabel(ax,'$|u|$','Color',[0.15 0.15 0.15],'FontSize',16,'Interpreter','latex');
                grid(ax,'on');
                lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                title(ax, lbl, 'FontSize',16, 'Color',col, 'Interpreter','none');

            else
                show_na(ax, [lbl newline 'N/A']);
            end
            panel_axes(i) = ax;
        end

        do_save(fig1, save_prefix, 'res');

        % ---- Split: standalone overlay figure for presentation ----
        if do_split && ~isempty(save_prefix)
            fig_ov_s = figure('Position', [80 80 520 380], 'Color', 'w', 'Visible', 'on');
            ax_s = axes(fig_ov_s);
            style_ax(ax_s); set(ax_s, 'FontSize', 18);
            hold(ax_s, 'on'); grid(ax_s, 'on');
            leg_h_s = gobjects(n,1);
            for i = 1:n
                col = scenario_colors(i,:);
                if results(i).status ~= 0
                    leg_h_s(i) = plot(ax_s, NaN, NaN, 'x', 'Color', col, ...
                        'MarkerSize', 18, 'LineWidth', 3);
                elseif ~isempty(load_disp_arr{i})
                    ld = load_disp_arr{i};
                    if is_seepage
                        xd = ld(:,1); yd = ld(:,2);
                    elseif strcmp(ld_fmt_arr{i}, 'S')
                        xd = ld(:,1); yd = ld(:,2);
                    else
                        xd = abs(ld(:,2)); yd = ld(:,1);
                    end
                    leg_h_s(i) = plot(ax_s, xd, yd, 's-', 'Color', col, ...
                        'MarkerFaceColor', col, 'LineWidth', 3.5, 'MarkerSize', 12);
                elseif ~isempty(disp_arr{i})
                    dm  = disp_arr{i};
                    nc2 = min(2, size(dm,2));
                    mag = sqrt(sum(dm(:,1:nc2).^2, 2));
                    leg_h_s(i) = plot(ax_s, 1:numel(mag), mag, '-', ...
                        'Color', col, 'LineWidth', 3.5);
                else
                    leg_h_s(i) = plot(ax_s, NaN, NaN, '-', 'Color', col);
                end
            end
            if is_srf_fmt, set(ax_s, 'YDir', 'reverse'); end
            xlabel(ax_s, ov_xlabel, 'FontSize', 20);
            ylabel(ax_s, ov_ylabel, 'FontSize', 20);
            title(ax_s, case_title, 'FontSize', 22, 'FontWeight', 'bold', 'Interpreter', 'none');
            lgd_s = legend(ax_s, leg_h_s, panel_labels, ...
                'FontSize', 16, 'Location', 'best', 'Interpreter', 'none');
            lgd_s.Color = [0.95 0.95 0.95];
            % FS markers for SRF format
            if is_srf_fmt
                for i = 1:n
                    if isempty(load_disp_arr{i}) || size(load_disp_arr{i},2) < 3, continue; end
                    ld = load_disp_arr{i};
                    iters = ld(:,3);
                    ilimit = max(iters(~isnan(iters)));
                    if isempty(ilimit) || ilimit < 10, continue; end
                    fs_k = find(iters < ilimit, 1, 'last');
                    if ~isempty(fs_k)
                        plot(ax_s, ld(fs_k,1), ld(fs_k,2), 'p', ...
                            'Color', scenario_colors(i,:), 'MarkerSize', 20, ...
                            'MarkerFaceColor', scenario_colors(i,:), 'LineWidth', 2, ...
                            'HandleVisibility', 'off');
                        text(ax_s, ld(fs_k,1)*1.02, ld(fs_k,2), ...
                            sprintf(' FS=%.2g', ld(fs_k,1)), ...
                            'Color', scenario_colors(i,:), 'FontSize', 18, 'FontWeight', 'bold');
                    end
                end
            end
            hold(ax_s, 'off');
            do_save(ax_s, save_prefix, 'res_overlay');
            if ~do_show, close(fig_ov_s); end
        end
    end

    % ====================================================================
    % Figure 2 — Reference Mesh  (.msh)
    % ====================================================================
    if has_msh
        [nr, nc2] = spatial_layout(n);
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
                title(ax, lbl,'FontSize',16,'Color',col,'Interpreter','none');
            elseif ~isempty(msh_arr{i})
                draw_ps_mesh(ax, msh_arr{i}, col);
                title(ax, lbl,'FontSize',16,'Color',col,'FontWeight','bold','Interpreter','none');
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
        [nr, nc2] = spatial_layout(n);
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
                title(ax, lbl,'FontSize',16,'Color',col,'Interpreter','none');
            elseif ~isempty(nodes_arr{i}) && ~isempty(disp_arr{i})
                % Use YAML coords + .res displacements with heavy amplification
                % so Poisson/material differences are clearly visible between panels
                draw_deformed(ax, nodes_arr{i}, disp_arr{i}, ec_arr{i}, 0.60);
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                    % In-plot annotation: max displacement value at top-right
                    xl = xlim(ax); yl = ylim(ax);
                    text(ax, xl(1)+0.97*(xl(2)-xl(1)), yl(1)+0.95*(yl(2)-yl(1)), ...
                         sprintf('max|u|=%.3e', maxu_vec(i)), ...
                         'Color', col, 'FontSize', 13, 'FontWeight', 'bold', ...
                         'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
                         'Interpreter', 'none');
                end
                title(ax, lbl,'FontSize',16,'Color',col,'FontWeight','bold','Interpreter','none');
            elseif ~isempty(dis_arr{i})
                % Fallback: PostScript .dis file (undeformed + deformed overlay)
                if ~isempty(msh_arr{i})
                    draw_ps_mesh(ax, msh_arr{i}, [0.30 0.35 0.42], [0.10 0.11 0.14]);
                end
                draw_ps_mesh(ax, dis_arr{i}, col, [0.16 0.19 0.24]);
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax, lbl,'FontSize',16,'Color',col,'FontWeight','bold','Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
            dis_axes(i) = ax;
        end
        % No linkaxes: each panel has its own tight zoom set by draw_deformed
        do_save(fig3, save_prefix, 'dis');

        % ---- Split: per-scenario deformed shape figures ----
        if do_split && ~isempty(save_prefix)
            for i = 1:n
                if results(i).status ~= 0, continue; end
                if isempty(nodes_arr{i}) || isempty(disp_arr{i}), continue; end
                fig_di = figure('Position', [80 80 520 380], 'Color', 'w', 'Visible', 'on');
                ax_di = axes(fig_di);
                draw_deformed(ax_di, nodes_arr{i}, disp_arr{i}, ec_arr{i}, 0.60);
                set(ax_di, 'FontSize', 18, 'TickLabelInterpreter', 'latex');
                box(ax_di, 'on');
                xlabel(ax_di, '$x$ (m)', 'FontSize', 20, 'Interpreter', 'latex');
                ylabel(ax_di, '$y$ (m)', 'FontSize', 20, 'Interpreter', 'latex');
                col = scenario_colors(i,:);
                lbl = panel_labels{i};
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax_di, lbl, 'FontSize', 20, 'Color', col, ...
                    'FontWeight', 'bold', 'Interpreter', 'none');
                do_save(ax_di, save_prefix, sprintf('dis_%d', i));
                if ~do_show, close(fig_di); end
            end
        end
    end

    % ====================================================================
    % Figure 4 — Displacement Vectors  (.vec)
    % ====================================================================
    if has_vecs
        [nr, nc2] = spatial_layout(n);
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
                title(ax, lbl,'FontSize',16,'Color',col,'Interpreter','none');
            elseif ~isempty(vec_arr{i})
                draw_ps_vecs(ax, vec_arr{i}, col);
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax, lbl,'FontSize',16,'Color',col,'FontWeight','bold','Interpreter','none');
            else
                show_na(ax, [lbl newline 'N/A']);
            end
            vec_axes(i) = ax;
        end
        % No linkaxes: each panel has its own tight zoom set by draw_ps_vecs
        do_save(fig4, save_prefix, 'vec');

        % ---- Split: per-scenario vector figures ----
        if do_split && ~isempty(save_prefix)
            for i = 1:n
                if results(i).status ~= 0 || isempty(vec_arr{i}), continue; end
                fig_vi = figure('Position', [80 80 520 380], 'Color', 'w', 'Visible', 'on');
                ax_vi = axes(fig_vi);
                draw_ps_vecs(ax_vi, vec_arr{i}, scenario_colors(i,:));
                set(ax_vi, 'FontSize', 18, 'TickLabelInterpreter', 'latex');
                box(ax_vi, 'on');
                xlabel(ax_vi, '$x$', 'FontSize', 20, 'Interpreter', 'latex');
                ylabel(ax_vi, '$y$', 'FontSize', 20, 'Interpreter', 'latex');
                lbl = panel_labels{i};
                if ~isnan(maxu_vec(i))
                    lbl = sprintf('%s\nmax|u| = %.3e', lbl, maxu_vec(i));
                end
                title(ax_vi, lbl, 'FontSize', 20, 'Color', scenario_colors(i,:), ...
                    'FontWeight', 'bold', 'Interpreter', 'none');
                do_save(ax_vi, save_prefix, sprintf('vec_%d', i));
                if ~do_show, close(fig_vi); end
            end
        end
    end

    % ====================================================================
    % Figure 5 — 3D EnSight: deformed shape panels per scenario
    %   Left column : side view  (x–y projection, z = slice near z_min)
    %   Right column: plan view  (x–z projection, y = slice near y_max)
    % Each row is one sweep scenario; color = displacement magnitude.
    % Matches book Figure 6.55 style for p612/p613 slope problems.
    % ====================================================================
    if has_ensi
        % One panel per scenario — 3D deformed mesh at failure (Figure 6.55 style)
        [nr_e, nc_e] = spatial_layout(n);
        fig5 = make_dark_figure( ...
            sprintf('Deformed Mesh at Failure (3D) — %s — %s sweep', case_title, sweep_label), ...
            nc_e, nr_e, vis);
        figs.ensi = fig5;

        % Global displacement range for consistent colourscale
        global_maxu = 0;
        for i = 1:n
            if isempty(ensi_arr{i}), continue; end
            last_s = numel(ensi_arr{i}.displ);
            while last_s > 1 && isempty(ensi_arr{i}.displ{last_s}), last_s = last_s-1; end
            if ~isempty(ensi_arr{i}.displ{last_s})
                d = ensi_arr{i}.displ{last_s};
                global_maxu = max(global_maxu, max(sqrt(sum(d.^2,2))));
            end
        end
        if global_maxu == 0, global_maxu = 1; end

        ax_e   = gobjects(n,1);
        lbl_e  = cell(n,1);
        col_e  = zeros(n,3);
        for i = 1:n
            col = scenario_colors(i,:);
            lbl = panel_labels{i};
            ax  = subplot(nr_e, nc_e, i, 'Parent', fig5);
            ax_e(i) = ax;  col_e(i,:) = col;

            if results(i).status ~= 0 || isempty(ensi_arr{i})
                show_na(ax, [lbl newline '[N/A]']);
                lbl_e{i} = [lbl newline '[N/A]'];
                continue;
            end

            en = ensi_arr{i};

            % Find last valid displacement step
            last_s = numel(en.displ);
            while last_s > 1 && isempty(en.displ{last_s}), last_s = last_s-1; end
            if isempty(en.displ{last_s})
                show_na(ax, [lbl newline 'no displ']);
                lbl_e{i} = [lbl newline 'no displ'];
                continue;
            end
            d_last = en.displ{last_s};
            mag    = sqrt(sum(d_last.^2, 2));

            % Scale factor: amplify ~18% of domain width for visibility
            domain_w = max(en.nodes(:,1)) - min(en.nodes(:,1));
            sf = 0;
            if max(mag) > 0, sf = 0.18 * domain_w / max(mag); end

            srf_lbl = '';
            if ~isempty(en.srf) && last_s <= numel(en.srf)
                srf_lbl = sprintf('SRF=%.3g', en.srf(last_s));
            end
            max_lbl = sprintf('max|u|=%.3e', max(mag));
            lbl_e{i} = sprintf('%s\n%s  %s', lbl, srf_lbl, max_lbl);

            % 3D boundary-face patch — matches book Figure 6.55
            draw_ensi_3d(ax, en.nodes, en.conn, d_last, sf, [0 global_maxu]);

            % Colorbar on last panel only
            if i == n
                cb = colorbar(ax);
                cb.Color = [0.20 0.20 0.20]; cb.FontSize = 14;
                cb.TickLabelInterpreter = 'latex';
                cb.Label.String = '$|u|$';
                cb.Label.Color  = [0.20 0.20 0.20];
                cb.Label.Interpreter = 'latex'; cb.Label.FontSize = 16;
            end
        end

        % Add panel labels using figure annotations anchored to OuterPosition —
        % axis equal vis3d repositions the inner axes unpredictably, so
        % annotations on the figure itself are the only reliable approach.
        drawnow;
        for i = 1:n
            if isempty(lbl_e{i}), continue; end
            op = ax_e(i).OuterPosition;  % [x y w h] normalised figure units
            % Place text in bottom 14% of the outer panel area
            annotation(fig5, 'textbox', ...
                [op(1)+op(3)*0.02, op(2), op(3)*0.96, op(4)*0.14], ...
                'String',           lbl_e{i}, ...
                'Color',            col_e(i,:), ...
                'EdgeColor',        'none', ...
                'BackgroundColor',  'none', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment',   'middle', ...
                'FontSize',         12, ...
                'Interpreter',      'none', ...
                'FitBoxToText',     'off');
        end

        do_save(fig5, save_prefix, 'ensi');

        % ---- Split: per-scenario 3D mesh figures ----
        if do_split && ~isempty(save_prefix)
            for i = 1:n
                if isempty(ensi_arr{i}), continue; end
                en = ensi_arr{i};
                last_s2 = numel(en.displ);
                while last_s2 > 1 && isempty(en.displ{last_s2}), last_s2 = last_s2-1; end
                if isempty(en.displ{last_s2}), continue; end
                d_last = en.displ{last_s2};
                mag_i = sqrt(sum(d_last.^2, 2));
                dw = max(en.nodes(:,1)) - min(en.nodes(:,1));
                sf_i = 0; if max(mag_i) > 0, sf_i = 0.18 * dw / max(mag_i); end

                fig_ei = figure('Position', [80 80 640 500], 'Color', 'w', 'Visible', 'on');
                ax_ei = axes(fig_ei);
                draw_ensi_3d(ax_ei, en.nodes, en.conn, d_last, sf_i, [0 global_maxu]);
                set(ax_ei, 'FontSize', 24, 'TickLabelInterpreter', 'latex', ...
                    'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
                    'Clipping', 'off');
                xlabel(ax_ei, '$x$ (m)', 'Interpreter', 'latex', 'FontSize', 16);
                ylabel(ax_ei, '$y$ (m)', 'Interpreter', 'latex', 'FontSize', 16);
                zlabel(ax_ei, '$z$ (m)', 'Interpreter', 'latex', 'FontSize', 16);
                grid(ax_ei, 'on');
                box(ax_ei, 'on');
                cb = colorbar(ax_ei); cb.FontSize = 22;
                cb.TickLabelInterpreter = 'latex';
                cb.Label.String = '$|u|$'; cb.Label.FontSize = 24;
                cb.Label.Interpreter = 'latex';
                % No title on split figures — slide frame provides context
                do_save(fig_ei, save_prefix, sprintf('ensi_%d', i));
                if ~do_show, close(fig_ei); end
            end
        end
    end

    % ====================================================================
    % Figure 6 — SRF Progression  (deformed mesh at every SRF step)
    %   Rows = scenarios, Columns = SRF steps
    %   Shows how the slope deforms progressively as SRF increases.
    % ====================================================================
    if has_ensi
        valid_e = find(~cellfun(@isempty, ensi_arr));
        n_steps_max = max(cellfun(@(e) numel(e.displ), ensi_arr(valid_e)));

        % Global displacement range across ALL scenarios × ALL steps
        g_max_all = 0;
        for i = valid_e'
            for s = 1:numel(ensi_arr{i}.displ)
                if ~isempty(ensi_arr{i}.displ{s})
                    d = ensi_arr{i}.displ{s};
                    g_max_all = max(g_max_all, max(sqrt(sum(d.^2,2))));
                end
            end
        end
        if g_max_all == 0, g_max_all = 1; end

        fig6 = figure('Name', ...
            sprintf('SRF Progression — %s — %s sweep', case_title, sweep_label), ...
            'Position', [80 80 min(260*n_steps_max, 1820) 270*n], ...
            'Color', [1.00 1.00 1.00], 'Visible', 'on');
        figs.ensi_prog = fig6;

        ax_p   = gobjects(n, n_steps_max);
        lbl_p  = cell(n, 1);
        col_p  = zeros(n, 3);

        % Pre-compute a fixed scale factor per scenario row from the LAST valid
        % displacement step, so deformation grows visibly across columns.
        sf_row = zeros(n,1);
        for i = 1:n
            if isempty(ensi_arr{i}), continue; end
            en = ensi_arr{i};
            last_s2 = numel(en.displ);
            while last_s2 > 1 && isempty(en.displ{last_s2}), last_s2 = last_s2-1; end
            if ~isempty(en.displ{last_s2})
                d2 = en.displ{last_s2};
                domain_w2 = max(en.nodes(:,1)) - min(en.nodes(:,1));
                mm = max(sqrt(sum(d2.^2,2)));
                if mm > 0, sf_row(i) = 0.18 * domain_w2 / mm; end
            end
        end

        for i = 1:n
            col = scenario_colors(i,:);
            col_p(i,:) = col;
            lbl_p{i}   = panel_labels{i};

            for s = 1:n_steps_max
                ax = subplot(n, n_steps_max, (i-1)*n_steps_max + s, 'Parent', fig6);
                ax_p(i,s) = ax;

                if isempty(ensi_arr{i}) || s > numel(ensi_arr{i}.displ) || ...
                        isempty(ensi_arr{i}.displ{s})
                    set(ax,'Color',[0.95 0.95 0.95],'XColor','none','YColor','none');
                    axis(ax,'off');
                    text(ax,0.5,0.5,'—','Units','normalized','Color',[0.70 0.70 0.70],...
                        'HorizontalAlignment','center','FontSize',14);
                    continue;
                end

                en = ensi_arr{i};
                d  = en.displ{s};
                % Use row-fixed sf so deformation amplitude grows step-to-step
                draw_ensi_3d(ax, en.nodes, en.conn, d, sf_row(i), [0 g_max_all]);
            end
        end

        % Use figure annotations for both column headers and row labels —
        % axis titles on 3D axes get clipped; drawnow first to fix layout.
        drawnow;

        % Column headers: SRF value above each column (top of figure)
        % Use the scenario with the most SRF steps (longest ref_srf) so that
        % all columns get actual SRF values, not just step indices.
        ref_srf = [];
        for i2 = 1:n
            if ~isempty(ensi_arr{i2}) && numel(ensi_arr{i2}.srf) > numel(ref_srf)
                ref_srf = ensi_arr{i2}.srf;
            end
        end
        for s = 1:n_steps_max
            op = ax_p(1,s).OuterPosition;   % top-row panel for column s
            srf_str = sprintf('SRF=%.3g', s);
            if ~isempty(ref_srf) && s <= numel(ref_srf)
                srf_str = sprintf('SRF=%.3g', ref_srf(s));
            end
            annotation(fig6, 'textbox', ...
                [op(1), op(2)+op(4)*0.86, op(3), op(4)*0.13], ...
                'String', srf_str, ...
                'Color', [0.20 0.20 0.20], ...
                'EdgeColor','none', 'BackgroundColor','none', ...
                'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
                'FontSize', 16, 'Interpreter','none', 'FitBoxToText','off');
        end

        % Row labels
        for i = 1:n
            op = ax_p(i,1).OuterPosition;
            annotation(fig6, 'textbox', ...
                [op(1), op(2), op(3)*0.98, op(4)*0.13], ...
                'String',  lbl_p{i}, ...
                'Color',   col_p(i,:), ...
                'EdgeColor','none', 'BackgroundColor','none', ...
                'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
                'FontSize', 14, 'Interpreter','none', 'FitBoxToText','off');
        end
        % Single colourbar on the last panel
        cb = colorbar(ax_p(n, n_steps_max));
        cb.Color = [0.20 0.20 0.20]; cb.FontSize = 14;
        cb.TickLabelInterpreter = 'latex';
        cb.Label.String = '$|u|$';
        cb.Label.Color  = [0.20 0.20 0.20];
        cb.Label.Interpreter = 'latex'; cb.Label.FontSize = 16;

        do_save(fig6, save_prefix, 'ensi_prog');
    end

    % ====================================================================
    % Figure 7 — Material Zones  (undeformed mesh coloured by zone ID)
    %   One panel per scenario confirms multi-zone proportional patching.
    %   Since the mesh topology is identical across scenarios, the zone
    %   geometry is the same; the labels show zone cohesion values.
    % ====================================================================
    if has_ensi_matid
        % Find first scenario that has both matid and geometry
        ref_idx = find(cellfun(@(e) ~isempty(e) && isfield(e,'matid') && ...
            ~isempty(e.matid) && ~isempty(e.conn), ensi_arr), 1);
        if ~isempty(ref_idx)
            en_ref  = ensi_arr{ref_idx};
            matid_v = en_ref.matid;
            zones   = unique(matid_v);
            n_zones = numel(zones);

            % Categorical colour for each zone (qualitative palette)
            zone_palette = lines(max(n_zones, 7));
            zone_palette = zone_palette(1:n_zones, :);

            % Boundary faces + source element for matid lookup
            [fn_z, eid_z] = get_boundary_faces(en_ref.conn);
            face_zone = matid_v(eid_z);   % zone ID for each boundary face

            % Per-face colour array
            face_rgb = zeros(size(fn_z,1), 3);
            for z = 1:n_zones
                mask = (face_zone == zones(z));
                face_rgb(mask,:) = repmat(zone_palette(z,:), sum(mask), 1);
            end

            [nr_z, nc_z] = spatial_layout(n);
            fig7 = make_dark_figure( ...
                sprintf('Material Zones — %s — %s sweep', case_title, sweep_label), ...
                nc_z, nr_z, vis);
            figs.ensi_zones = fig7;

            ax_z  = gobjects(n,1);
            lbl_z = cell(n,1);
            col_z = zeros(n,3);
            for i = 1:n
                col = scenario_colors(i,:);
                lbl = panel_labels{i};
                ax  = subplot(nr_z, nc_z, i, 'Parent', fig7);
                ax_z(i) = ax; col_z(i,:) = col;

                % All scenarios share the same zone topology; label differs
                hold(ax,'on');
                patch(ax, 'Faces', fn_z, 'Vertices', en_ref.nodes, ...
                    'FaceVertexCData', face_rgb, ...
                    'FaceColor', 'flat', ...
                    'EdgeColor', [0.70 0.70 0.70], 'LineWidth', 0.3, ...
                    'HandleVisibility', 'off');
                set(ax, 'Color',[1.00 1.00 1.00], ...
                    'XColor',[0.20 0.20 0.20], 'YColor',[0.20 0.20 0.20], ...
                    'ZColor',[0.20 0.20 0.20]);
                axis(ax,'equal','vis3d');
                view(ax, -35, 25);
                camlight(ax,'headlight'); lighting(ax,'flat');
                hold(ax,'off');

                % Zone legend on last panel
                if i == n
                    for z = 1:n_zones
                        patch(ax, 'XData',[], 'YData',[], 'ZData',[], ...
                            'FaceColor', zone_palette(z,:), ...
                            'EdgeColor', 'none', ...
                            'DisplayName', sprintf('Zone %d', zones(z)));
                    end
                    leg = legend(ax, 'Location','best');
                    leg.TextColor  = [0.15 0.15 0.15];
                    leg.Color      = [0.95 0.95 0.95];
                    leg.EdgeColor  = [0.70 0.70 0.70];
                end
                lbl_z{i} = lbl;
            end

            drawnow;
            for i = 1:n
                op = ax_z(i).OuterPosition;
                annotation(fig7, 'textbox', ...
                    [op(1)+op(3)*0.02, op(2), op(3)*0.96, op(4)*0.13], ...
                    'String',  lbl_z{i}, ...
                    'Color',   col_z(i,:), ...
                    'EdgeColor','none', 'BackgroundColor','none', ...
                    'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
                    'FontSize', 16, 'Interpreter','none', 'FitBoxToText','off');
            end
            do_save(fig7, save_prefix, 'ensi_zones');

            % ---- Split: single zone figure (same mesh for all scenarios) ----
            if do_split && ~isempty(save_prefix)
                fig_z1 = figure('Position', [80 80 640 500], 'Color', 'w', 'Visible', 'on');
                ax_z1 = axes(fig_z1);
                hold(ax_z1, 'on');
                patch(ax_z1, 'Faces', fn_z, 'Vertices', en_ref.nodes, ...
                    'FaceVertexCData', face_rgb, 'FaceColor', 'flat', ...
                    'EdgeColor', [0.70 0.70 0.70], 'LineWidth', 0.3, ...
                    'HandleVisibility', 'off');
                set(ax_z1, 'Color', 'w', ...
                    'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
                    'FontSize', 24, 'TickLabelInterpreter', 'latex', ...
                    'Clipping', 'off');
                xlabel(ax_z1, '$x$ (m)', 'Interpreter', 'latex', 'FontSize', 24);
                ylabel(ax_z1, '$y$ (m)', 'Interpreter', 'latex', 'FontSize', 24);
                zlabel(ax_z1, '$z$ (m)', 'Interpreter', 'latex', 'FontSize', 24);
                daspect(ax_z1, [1 1 1]);
                view(ax_z1, -35, 25);
                grid(ax_z1, 'on');
                camlight(ax_z1, 'headlight'); lighting(ax_z1, 'flat');
                box(ax_z1, 'on');
                for z = 1:n_zones
                    patch(ax_z1, 'XData', [], 'YData', [], 'ZData', [], ...
                        'FaceColor', zone_palette(z,:), 'EdgeColor', 'none', ...
                        'DisplayName', sprintf('Zone %d', zones(z)));
                end
                leg_z1 = legend(ax_z1, 'FontSize', 18, 'Location', 'best', ...
                    'Interpreter', 'latex');
                leg_z1.TextColor = [0.15 0.15 0.15];
                hold(ax_z1, 'off');
                do_save(fig_z1, save_prefix, 'ensi_zones_single');
                if ~do_show, close(fig_z1); end
            end
        end
    end

    % Close figures that the caller did not request to display
    if ~do_show
        fn = fieldnames(figs);
        for k = 1:numel(fn)
            f = figs.(fn{k});
            if ~isempty(f) && isvalid(f)
                close(f);
            end
        end
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
% Return n visually distinct, high-contrast colors on a light background.
    if n <= 1
        colors = [0.12 0.47 0.71];
        return;
    end
    % Use a curated palette for small n, fall back to HSV for large n
    palette = [ ...
        0.12 0.47 0.71;   % blue
        0.84 0.15 0.16;   % red
        0.17 0.63 0.17;   % green
        1.00 0.50 0.05;   % orange
        0.58 0.40 0.74;   % purple
        0.55 0.34 0.29;   % brown
        0.89 0.47 0.76;   % pink
        0.50 0.50 0.50;   % gray
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

function fig = make_dark_figure(name, ncols, nrows, ~)
    % Always create visible — setting axis properties on invisible figures
    % causes MATLAB to invalidate handles on Linux (headless renderer bug).
    % Figures are closed after saving when Show=false.
    fig = figure('Name', name, ...
                 'Position', [80 80 min(500*ncols, 2000) 420*nrows], ...
                 'Color', [1.00 1.00 1.00], ...
                 'Visible', 'on');
end


function [nr, nc] = panel_layout(n)
% Layout for res/load-disp charts — keep 1 row so overlay/summary stay wide.
    nc = min(n, 4);
    nr = ceil(n / nc);
end

function [nr, nc] = spatial_layout(n)
% Layout for spatial figures (mesh, deformed, vectors, EnSight).
% 4 scenarios → 2×2 grid so each panel is 4× larger than a 1×4 strip.
    if n <= 3
        nc = n;  nr = 1;
    elseif n == 4
        nc = 2;  nr = 2;
    else
        nc = min(n, 3);
        nr = ceil(n / nc);
    end
end


function style_ax(ax)
    set(ax, 'Color', [1.00 1.00 1.00], ...
            'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15], ...
            'GridColor',[0.80 0.80 0.80], 'GridAlpha',0.5, ...
            'FontSize', 16, 'LineWidth', 1.2, ...
            'TickLabelInterpreter', 'latex');
    box(ax, 'on');
end


function do_save(fig_or_ax, prefix, tag)
    if isempty(prefix) || ~isvalid(fig_or_ax), return; end
    out_png = [prefix '_' tag '.png'];
    out_pdf = [prefix '_' tag '.pdf'];
    d = fileparts(out_png);
    if ~isempty(d) && ~exist(d,'dir'), mkdir(d); end
    drawnow('expose');
    % Determine if caller passed an axes (tight crop) or figure
    if isa(fig_or_ax, 'matlab.graphics.axis.Axes')
        target = fig_or_ax;  % exportgraphics on axes = tight crop
        fig    = ancestor(fig_or_ax, 'figure');
    else
        target = fig_or_ax;
        fig    = fig_or_ax;
    end
    % Vector PDF — preferred for presentation (crisp at any zoom)
    try
        exportgraphics(target, out_pdf, 'ContentType', 'vector', 'BackgroundColor', 'white');
        fprintf('  Saved (vector): %s\n', out_pdf);
    catch e
        fprintf('  PDF export failed (%s), using raster only\n', e.message);
    end
    % Raster PNG
    if isa(fig_or_ax, 'matlab.graphics.axis.Axes')
        exportgraphics(target, out_png, 'Resolution', 250, 'BackgroundColor', 'white');
    else
        % Figure-level: print preserves full window including tick labels
        print(fig, out_png, '-dpng', '-r250');
    end
    fprintf('  Saved (raster): %s\n', out_png);
end


function out = pfem_out_from_dir(run_dir)
% Build a minimal out-struct from a run directory path (as returned by pfem_runner).
% Scans for .res/.msh/.dis/.vec/.ensi.case files matching the dataset name.
    out = struct('files', {{}}, 'work_dir', run_dir);
    if ~exist(run_dir, 'dir'), return; end
    d = dir(fullfile(run_dir, '*.res'));
    if isempty(d), return; end
    base  = d(1).name(1:end-4);   % strip .res extension
    exts  = {'.res', '.msh', '.dis', '.vec', '.ensi.case'};
    files = {};
    for k = 1:numel(exts)
        f = fullfile(run_dir, [base exts{k}]);
        if exist(f, 'file'), files{end+1} = f; end
    end
    out.files = files;
end


% ==========================================================================
% Drawing helpers
% ==========================================================================

function show_na(ax, lbl)
    axis(ax,'off');
    set(ax,'Color',[1.00 1.00 1.00]);
    text(ax, 0.5, 0.5, lbl, 'HorizontalAlignment','center', ...
         'Color',[0.40 0.40 0.40], 'FontSize',12, 'Units','normalized');
end


function draw_ps_mesh(ax, patches, edge_col, face_col)
% Draw PostScript polygon list (from .msh or .dis file).
    if nargin < 3 || isempty(edge_col), edge_col = [0.20 0.40 0.75]; end
    if nargin < 4 || isempty(face_col), face_col = [0.94 0.96 0.99]; end
    hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');
    set(ax,'Color',[1.00 1.00 1.00]);
    for k = 1:numel(patches)
        pts = patches{k};
        if size(pts,1) < 2, continue; end
        fill(ax, pts([1:end,1],1), pts([1:end,1],2), ...
             face_col, 'EdgeColor', edge_col, 'LineWidth', 2.0);
    end
    hold(ax,'off');
end


function draw_ps_vecs(ax, arrows, col)
% Draw displacement arrows from .vec file data.
% Auto-scales so the largest arrow = 20% of domain height (clearly visible).
    if nargin < 3, col = [0.55 0.80 0.55]; end
    hold(ax,'on');
    set(ax,'Color',[1.00 1.00 1.00]);

    dx = arrows(:,3) - arrows(:,1);
    dy = arrows(:,4) - arrows(:,2);
    mag = sqrt(dx.^2 + dy.^2);
    max_mag = max(mag);

    x0 = min(arrows(:,1));  x1 = max(arrows(:,1));
    y0 = min(arrows(:,2));  y1 = max(arrows(:,2));
    domain_w = x1 - x0;
    domain_h = y1 - y0;
    % Scale by height (not max) so vertical-dominant problems look good
    domain_ref = max(domain_h, domain_w * 0.3);
    if domain_ref == 0, domain_ref = 1; end

    sf = 1;
    if max_mag > 0, sf = 0.20 * domain_ref / max_mag; end

    quiver(ax, arrows(:,1), arrows(:,2), dx*sf, dy*sf, 0, ...
           'Color',col, 'LineWidth',2.5, 'MaxHeadSize',0.8, 'AutoScale','off');

    % Tight zoom — use actual node bounds with 25% padding
    xpad = max(0.25 * domain_w, 0.25 * domain_h);
    ypad = max(0.35 * domain_h, 0.10 * domain_w);
    xlim(ax, [x0-xpad, x1+xpad]);
    ylim(ax, [y0-ypad, y1+ypad]);

    % Allow y-axis to stretch to fill panel (improves readability of flat domains)
    axis(ax,'normal');

    % Show coordinate axes
    axis(ax,'on');
    set(ax,'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
           'GridColor',[0.80 0.80 0.80],'GridAlpha',0.4, ...
           'FontSize',16,'TickDir','out','Box','on', ...
           'TickLabelInterpreter','latex');
    grid(ax,'on');
    xlabel(ax,'$x$','FontSize',18,'Interpreter','latex');
    ylabel(ax,'$y$','FontSize',18,'Interpreter','latex');

    % Annotate max displacement magnitude
    text(ax, x0+0.97*(x1-x0+2*xpad)-xpad, y0+ypad+0.95*(y1-y0+2*ypad), ...
         sprintf('max$|u|$=%.3e', max_mag), ...
         'Color', col, 'FontSize', 16, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
         'Interpreter', 'latex');
    hold(ax,'off');
end


function draw_load_disp(ax, load_disp, fmt, col)
% Draw load-displacement or consolidation curve.
%   fmt='B': Format B load-step  — X=max|u|, Y=Load
%   fmt='S': SRF format          — X=SRF,    Y=δmax (Y inverted, iter annotated)
%   fmt='C': seepage              — X=Time,   Y=Uav
    if nargin < 3, fmt = 'B'; end
    if nargin < 4 || isempty(col)
        if strcmp(fmt,'C'), col = [0.40 0.75 0.75]; else, col = [0.40 0.75 0.40]; end
    end
    hold(ax,'on'); grid(ax,'on');
    set(ax,'Color',[1.00 1.00 1.00], ...
           'XColor',[0.15 0.15 0.15], 'YColor',[0.15 0.15 0.15], ...
           'GridColor',[0.80 0.80 0.80], 'GridAlpha',0.4);

    set(ax, 'FontSize', 16, 'TickLabelInterpreter', 'latex');
    box(ax, 'on');

    if strcmp(fmt, 'C')
        plot(ax, load_disp(:,1), load_disp(:,2), 'o-', ...
             'Color',col, 'MarkerFaceColor',col, 'LineWidth',2.5, 'MarkerSize',9);
        xlabel(ax,'Time','FontSize',18,'Interpreter','latex');
        ylabel(ax,'$U_\mathrm{av}$','FontSize',18,'Interpreter','latex');

    elseif strcmp(fmt, 'S')
        % SRF format — matches book Figure 6.54 style
        xd = load_disp(:,1);   % SRF
        yd = load_disp(:,2);   % δmax
        plot(ax, xd, yd, 's-', 'Color',col, 'MarkerFaceColor',col, ...
             'LineWidth',2.5, 'MarkerSize',10);
        set(ax,'YDir','reverse');
        xlabel(ax,'SRF','FontSize',18,'Interpreter','latex');
        ylabel(ax,'$\delta_\mathrm{max}$','FontSize',18,'Interpreter','latex');
        % Annotate iteration counts (3rd column when available)
        if size(load_disp,2) >= 3
            iters  = load_disp(:,3);
            ilimit = max(iters(~isnan(iters)));   % largest observed = likely limit
            for k = 1:numel(xd)
                it = iters(k);
                if isnan(it), continue; end
                itlbl = sprintf('%g', it);
                % Only mark '+' (hit limit) when ilimit is large enough that
                % hitting it is meaningful (avoids "2+" for well-converged runs)
                if it >= ilimit && ilimit >= 10, itlbl = [itlbl '+']; end %#ok<AGROW>
                text(ax, xd(k), yd(k), ['  ' itlbl], ...
                     'Color',[0.30 0.25 0.00], 'FontSize',14, ...
                     'VerticalAlignment','middle');
            end
            % Mark FS at last non-diverged point (iters < limit)
            fs_k = find(iters < ilimit, 1, 'last');
            if ~isempty(fs_k)
                text(ax, xd(fs_k)*1.01, yd(fs_k), ...
                     sprintf('  FS=%.2g', xd(fs_k)), ...
                     'Color',[0.65 0.30 0.00], 'FontSize',16, 'FontWeight','bold');
            end
        end

    else
        plot(ax, abs(load_disp(:,2)), load_disp(:,1), 'o-', ...
             'Color',col, 'MarkerFaceColor',col, 'LineWidth',2.5, 'MarkerSize',9);
        xlabel(ax,'max$|u|$','FontSize',18,'Interpreter','latex');
        ylabel(ax,'Load','FontSize',18,'Interpreter','latex');
    end
    hold(ax,'off');
end


function draw_deformed(ax, nodes, disp_mat, elem_conn, sf_frac)
% Draw deformed mesh from YAML node coordinates and Format A per-node displacements.
% sf_frac: scale deformation so max|u| = sf_frac * domain_size (default 0.18).
    if nargin < 5 || isempty(sf_frac), sf_frac = 0.18; end
    hold(ax,'on'); axis(ax,'equal');
    set(ax,'Color',[1.00 1.00 1.00]);

    nc       = min(2, size(disp_mat,2));
    disp_mag = sqrt(sum(disp_mat(:,1:nc).^2, 2));
    max_mag  = max(disp_mag);

    if size(nodes,2) >= 2
        W  = max(nodes(:,1)) - min(nodes(:,1));
        H  = max(nodes(:,2)) - min(nodes(:,2));
        sf = 1;
        if max_mag > 0, sf = sf_frac * max(W,H) / max_mag; end

        def      = nodes;
        def(:,1) = nodes(:,1) + sf * disp_mat(:,1);
        def(:,2) = nodes(:,2) + sf * disp_mat(:,2);

        if ~isempty(elem_conn)
            draw_edges(ax, nodes, elem_conn, [0.55 0.65 0.75], 1.5);
            draw_edges(ax, def,   elem_conn, [0.55 0.78 1.00], 2.5);
        end
        scatter(ax, def(:,1), def(:,2), 60, disp_mag, 'filled');
        colormap(ax,'turbo');

        % Tight zoom with 8% padding around both undeformed+deformed extents
        x_all = [nodes(:,1); def(:,1)];
        y_all = [nodes(:,2); def(:,2)];
        xpad  = 0.08 * max(W, 1e-9);
        ypad  = 0.08 * max(H, 1e-9);
        xlim(ax, [min(x_all)-xpad, max(x_all)+xpad]);
        ylim(ax, [min(y_all)-ypad, max(y_all)+ypad]);

        % Show axes with coordinate values
        axis(ax,'on');
        set(ax, 'XColor',[0.15 0.15 0.15], 'YColor',[0.15 0.15 0.15], ...
                'GridColor',[0.80 0.80 0.80], 'GridAlpha',0.4, ...
                'FontSize',16, 'TickDir','out', 'Box','on', ...
                'TickLabelInterpreter','latex');
        grid(ax,'on');
        xlabel(ax,'$x$ (m)','FontSize',18,'Interpreter','latex');
        ylabel(ax,'$y$ (m)','FontSize',18,'Interpreter','latex');
    else
        x = (1:size(disp_mat,1))';
        scatter(ax, x, disp_mat(:,1), 36, disp_mag, 'filled');
        colormap(ax,'turbo');
        axis(ax,'on');
        set(ax,'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
               'FontSize',16,'TickLabelInterpreter','latex');
        box(ax,'on');
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
                    if numel(v) >= 3
                        ld(end+1,:) = [v(1), v(2), v(3)]; %#ok<AGROW> [srf, max_disp, iters]
                    elseif numel(v) >= 2
                        ld(end+1,:) = [v(1), v(2), NaN];  %#ok<AGROW>
                    end
                else
                    if numel(v) >= 4
                        ld(end+1,:) = [v(2), v(3), v(4)]; %#ok<AGROW> [load, disp, iters]
                    elseif numel(v) >= 3
                        ld(end+1,:) = [v(2), v(3), NaN];  %#ok<AGROW>
                    end
                end
            end
            % 'S' = SRF format (X=srf, Y=disp inverted); 'B' = standard load-disp
            if ~isempty(ld)
                load_disp = ld;
                if is_srf, ld_fmt = 'S'; else, ld_fmt = 'B'; end
            end
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

function [face_nodes, elem_id] = get_boundary_faces(conn)
% Extract boundary (external surface) faces from hex8 corner connectivity.
% Returns Nf×4 face node index array, and optionally Nf×1 source element index.
    hf = [1 2 3 4; 5 6 7 8; 1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8];
    n_elem = size(conn,1);
    n_hf   = size(hf,1);
    total  = n_elem * n_hf;

    orig   = zeros(total,4);
    srt    = zeros(total,4);
    src_e  = zeros(total,1);
    for e = 1:n_elem
        cn = conn(e,1:8);
        for fi = 1:n_hf
            idx = (e-1)*n_hf + fi;
            fn = cn(hf(fi,:));
            orig(idx,:) = fn;
            srt(idx,:)  = sort(fn);
            src_e(idx)  = e;
        end
    end

    [~, ia, ic] = unique(srt, 'rows', 'stable');
    counts     = accumarray(ic, 1);
    bnd        = ia(counts == 1);
    face_nodes = orig(bnd, :);
    elem_id    = src_e(bnd);
end


function draw_ensi_3d(ax, nodes, conn, displ, sf, clim_range)
% Render the deformed 3D mesh as a surface patch coloured by |u|.
% Matches book Figure 6.55 style: boundary faces, gray-to-white colormap.
    if isempty(conn) || isempty(displ), return; end

    mag = sqrt(sum(displ.^2, 2));

    % Deformed node positions
    def = nodes;
    def(:,1) = nodes(:,1) + sf * displ(:,1);
    def(:,2) = nodes(:,2) + sf * displ(:,2);
    def(:,3) = nodes(:,3) + sf * displ(:,3);

    % Boundary faces only
    try
        fn = get_boundary_faces(conn);
    catch
        fn = [];
    end
    if isempty(fn), return; end

    % Draw with patch (per-vertex colour = |u|)
    hold(ax,'on');
    patch(ax, 'Faces', fn, 'Vertices', def, ...
          'FaceVertexCData', mag, ...
          'FaceColor', 'interp', ...
          'EdgeColor', [0.35 0.35 0.35], 'LineWidth', 0.4);
    colormap(ax, parula);   % high displacement = bright yellow, visible on dark bg
    clim(ax, clim_range);
    daspect(ax, [1 1 1]);
    view(ax, -35, 25);            % perspective matching Figure 6.55
    set(ax,'Color',[1.00 1.00 1.00], ...
           'XColor','k', 'YColor','k', 'ZColor','k', ...
           'FontSize', 24, 'TickLabelInterpreter', 'latex', ...
           'Clipping', 'off');
    xlabel(ax, '$x$ (m)', 'Interpreter', 'latex', 'FontSize', 24);
    ylabel(ax, '$y$ (m)', 'Interpreter', 'latex', 'FontSize', 24);
    zlabel(ax, '$z$ (m)', 'Interpreter', 'latex', 'FontSize', 24);
    grid(ax, 'on');
    box(ax, 'on');
    camlight(ax,'headlight');
    lighting(ax,'flat');
    hold(ax,'off');
end
