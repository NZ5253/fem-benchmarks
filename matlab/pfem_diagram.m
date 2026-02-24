function pfem_diagram(yaml_path, varargin)
% PFEM_DIAGRAM  Textbook-style FEM mesh diagram with interactive parameters
%
% Usage:
%   pfem_diagram(yaml_path)
%   pfem_diagram(yaml_path, 'node_numbers', true)
%   pfem_diagram(yaml_path, 'axes', ax)   % draw on existing axes (no new figure/panel)
%   pfem_diagram(yaml_path, 'overrides', struct('youngs_modulus_E', 2e5))
%
% The 'axes' option is used by pfem_studio to embed the diagram.

    p = inputParser;
    addParameter(p, 'node_numbers', false);
    addParameter(p, 'elem_numbers', true);
    addParameter(p, 'axes',      []);        % external axes handle
    addParameter(p, 'overrides', struct());  % parameter overrides
    parse(p, varargin{:});
    opts.node_numbers = p.Results.node_numbers;
    opts.elem_numbers = p.Results.elem_numbers;
    ext_ax   = p.Results.axes;
    overrides = p.Results.overrides;

    % Expand ~ in path
    if startsWith(yaml_path, '~')
        yaml_path = [getenv('HOME') yaml_path(2:end)];
    end

    if ~exist(yaml_path, 'file')
        error('YAML not found: %s', yaml_path);
    end

    % ---- Load mesh data ----
    [nodes, elem_conn, meta, yaml] = load_mesh_data(yaml_path);
    if isempty(nodes)
        error('Could not extract mesh data from %s', yaml_path);
    end

    % ---- Apply overrides to token list ----
    tokens = yaml.inputs.all_tokens;
    if ~isempty(fieldnames(overrides)) && isfield(yaml, 'tunable_parameters')
        for k = 1:numel(yaml.tunable_parameters)
            fn = yaml.tunable_parameters{k}.name;
            if isfield(overrides, fn)
                tokens{yaml.tunable_parameters{k}.global_token_index} = overrides.(fn);
            end
        end
    end

    % ---- Parse BCs and loads ----
    vals  = tokens_to_vals(tokens);
    bcs   = parse_bcs(vals, meta, yaml);
    loads = parse_loads(vals, meta, yaml, bcs);

    % ---- Build prop display (overrides take precedence) ----
    [prop_names, prop_values] = build_prop_display(yaml.tunable_parameters, overrides);

    title_str = yaml.title;
    if ~isempty(fieldnames(overrides))
        fns = fieldnames(overrides);
        parts = {};
        for i = 1:numel(fns)
            lbl = format_prop_label(fns{i});
            plain = regexprep(lbl, '\\(\w+)', '$1');
            parts{end+1} = sprintf('%s=%.4g', plain, overrides.(fns{i})); %#ok<AGROW>
        end
        title_str = [title_str '  (' strjoin(parts, ',  ') ')'];
    end

    mesh = struct('nodes', nodes, 'elem_conn', elem_conn, 'meta', meta, ...
                  'bcs', bcs, 'loads', loads, ...
                  'prop_names', {prop_names}, 'prop_values', prop_values, ...
                  'title', title_str, 'opts', opts);

    % ---- Embedded mode: draw on provided axes, no figure/panel ----
    if ~isempty(ext_ax)
        draw_diagram(ext_ax, mesh);
        title(ext_ax, title_str, 'FontSize', 10, 'FontWeight', 'bold', ...
              'Interpreter', 'none');
        return;
    end

    % ---- Standalone mode: create figure + interactive panel ----
    fig = figure('Name', sprintf('PFEM Diagram — %s', mesh.title), ...
                 'Position', [60 60 1100 650], ...
                 'Color', [0.97 0.97 0.97]);

    ax = axes('Parent', fig, 'Position', [0.03 0.06 0.64 0.88]);
    axis(ax, 'equal'); axis(ax, 'off'); hold(ax, 'on');

    draw_diagram(ax, mesh);
    create_param_panel(fig, yaml_path, ax, opts);

    title(ax, mesh.title, 'FontSize', 11, 'FontWeight', 'bold', ...
          'Interpreter', 'none');
end


% =========================================================================
function draw_diagram(ax, mesh)
% Draw the complete textbook-style FEM diagram
    cla(ax);
    hold(ax, 'on');

    nodes     = mesh.nodes;
    elem_conn = mesh.elem_conn;
    meta      = mesh.meta;
    bcs       = mesh.bcs;
    loads     = mesh.loads;
    opts      = mesh.opts;

    % Domain bounds (with some padding)
    x_all = nodes(:,1);
    y_all = nodes(:,2);
    xmin = min(x_all); xmax = max(x_all);
    ymin = min(y_all); ymax = max(y_all);
    W = xmax - xmin; H = ymax - ymin;
    pad = 0.18 * max(W, H);

    % ---- Draw load arrows first (elements + nodes drawn on top) ----
    draw_loads_arrows(ax, nodes, loads, W, H);

    % ---- Draw boundary conditions ----
    draw_bcs(ax, nodes, bcs, xmin, xmax, ymin, ymax, W, H);

    % ---- Draw element outlines (on top of arrows so numbers are readable) ----
    draw_elements(ax, nodes, elem_conn, meta, opts);

    % ---- Draw node dots ----
    plot(ax, nodes(:,1), nodes(:,2), 'k.', 'MarkerSize', 8);

    % ---- Node numbers (optional) ----
    if opts.node_numbers
        for n = 1:size(nodes,1)
            text(ax, nodes(n,1), nodes(n,2), sprintf(' %d', n), ...
                 'FontSize', 7, 'Color', [0.3 0.3 0.8]);
        end
    end

    % ---- Dimension annotations ----
    annotate_dimensions(ax, xmin, xmax, ymin, ymax, W, H, pad);

    % ---- Material properties box ----
    annotate_props(ax, mesh, xmax, ymax, W, H, pad);

    axis(ax, 'equal');
    axis(ax, 'off');
    margin = pad * 0.9;
    axis(ax, [xmin - margin, xmax + margin*3.5, ymin - margin, ymax + margin*1.2]);
    hold(ax, 'off');
end


% =========================================================================
function draw_elements(ax, nodes, elem_conn, meta, opts)
% Draw element outlines and (optionally) circled element numbers

    nod  = meta.nod;
    nels = meta.nels;

    if ~isempty(elem_conn)
        % Explicit connectivity — draw element perimeter
        % Corner node indices in local ordering depend on element type
        for e = 1:nels
            conn = elem_conn(e, :);
            % Perimeter nodes (exclude centre for quad9)
            if nod == 9
                perim = conn([1 2 3 4 5 6 7 8 1]);   % 8 perimeter nodes
            elseif nod == 8
                perim = conn([1 2 3 4 5 6 7 8 1]);
            elseif nod == 4
                perim = conn([1 2 3 4 1]);
            elseif nod == 3
                perim = conn([1 2 3 1]);
            elseif nod == 6
                perim = conn([1 2 3 4 5 6 1]);
            else
                perim = [conn conn(1)];
            end
            px = nodes(perim, 1);
            py = nodes(perim, 2);
            plot(ax, px, py, 'k-', 'LineWidth', 1.0);

            if opts.elem_numbers
                corners = conn(1:min(4, nod));
                if nod >= 8
                    corners = conn([1 3 5 7]);
                end
                cx = mean(nodes(corners, 1));
                cy = mean(nodes(corners, 2));
                % Estimate element size from corner spread
                elem_sz = max(max(nodes(corners,1))-min(nodes(corners,1)), ...
                              max(nodes(corners,2))-min(nodes(corners,2)));
                draw_circled_number(ax, cx, cy, e, meta, elem_sz);
            end
        end

    elseif isfield(meta, 'x_coords') && isfield(meta, 'y_coords')
        % Structured mesh — draw from coordinate arrays
        xc = meta.x_coords;
        yc = meta.y_coords;
        nxe = meta.nxe;
        nye = meta.nye;

        for je = 1:nye
            for ie = 1:nxe
                x1 = xc(ie);  x2 = xc(ie+1);
                y1 = yc(je);  y2 = yc(je+1);
                plot(ax, [x1 x2 x2 x1 x1], [y1 y1 y2 y2 y1], ...
                     'k-', 'LineWidth', 1.0);

                if opts.elem_numbers
                    e_num = (je-1)*nxe + ie;
                    cx = (x1+x2)/2;
                    cy = (y1+y2)/2;
                    elem_sz = min(x2-x1, abs(y2-y1));
                    draw_circled_number(ax, cx, cy, e_num, meta, elem_sz);
                end
            end
        end
    end
end


% =========================================================================
function draw_circled_number(ax, cx, cy, num, meta, elem_size)
% Draw a circled element number at (cx, cy)
% elem_size: approximate element side length (optional)
    if nargin < 6 || isempty(elem_size)
        if isfield(meta, 'x_coords') && isfield(meta, 'nxe')
            W = max(meta.x_coords) - min(meta.x_coords);
            H = max(meta.y_coords) - min(meta.y_coords);
            elem_size = min(W/meta.nxe, H/meta.nye);
        elseif isfield(meta, 'nels')
            % Rough estimate from domain and element count
            elem_size = 0.5;  % placeholder; overridden below
        else
            elem_size = 0.5;
        end
    end
    r = 0.28 * elem_size;
    r = max(r, 0.01);

    theta = linspace(0, 2*pi, 40);
    fill(ax, cx + r*cos(theta), cy + r*sin(theta), 'w', ...
         'EdgeColor', 'k', 'LineWidth', 0.8);
    text(ax, cx, cy, num2str(num), 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'middle', 'FontSize', 8, 'FontWeight', 'bold');
end


% =========================================================================
function draw_bcs(ax, nodes, bcs, xmin, xmax, ymin, ymax, W, H)
% Draw BC indicators

    arrow_len = 0.14 * max(W, H);
    hatch_len = arrow_len * 0.55;
    hatch_sep = arrow_len * 0.28;

    % ----- Draw roller arrows -----
    % x-roller nodes (x displacement fixed): arrows pointing inward in x
    draw_roller_arrows(ax, nodes, bcs.x_roller_nodes, 'x', ...
                       xmin, xmax, ymin, ymax, arrow_len);

    % y-roller nodes: arrows pointing inward in y
    draw_roller_arrows(ax, nodes, bcs.y_roller_nodes, 'y', ...
                       xmin, xmax, ymin, ymax, arrow_len);

    % ----- Draw fixed (clamped) hatching -----
    % Group fully-fixed nodes by which boundary they lie on
    fixed = bcs.fixed_nodes;
    if ~isempty(fixed)
        fx = nodes(fixed, 1);  fy = nodes(fixed, 2);
        tol = 1e-6 * max(W, H);

        sides = {'bottom', ymin, 'y';
                 'top',    ymax, 'y';
                 'left',   xmin, 'x';
                 'right',  xmax, 'x'};

        for s = 1:size(sides, 1)
            side_name = sides{s,1};
            coord_val = sides{s,2};
            coord_dir = sides{s,3};

            if strcmp(coord_dir, 'y')
                on_side = abs(fy - coord_val) < tol;
            else
                on_side = abs(fx - coord_val) < tol;
            end

            if sum(on_side) < 1, continue; end

            if strcmp(coord_dir, 'y')
                pts = sort(fx(on_side));
            else
                pts = sort(fy(on_side));
            end

            draw_hatching(ax, side_name, coord_val, pts, ...
                          hatch_len, hatch_sep);
        end
    end
end


% =========================================================================
function draw_roller_arrows(ax, nodes, roller_nodes, direction, ...
                             xmin, xmax, ymin, ymax, arrow_len)
% Draw roller arrows for given nodes
    if isempty(roller_nodes), return; end

    W = xmax - xmin; H = ymax - ymin;
    tol = 1e-6 * max(W, H);
    ahd = arrow_len * 0.35;   % arrowhead size

    for ni = roller_nodes(:)'
        nx = nodes(ni, 1);  ny = nodes(ni, 2);

        if strcmp(direction, 'x')
            % Arrow perpendicular to x: points inward in x
            if abs(nx - xmin) < tol
                % Left boundary: arrow points right
                x0 = nx - arrow_len;  x1 = nx;
                y0 = ny;              y1 = ny;
                plot(ax, [x0 x1], [y0 y1], 'k-', 'LineWidth', 1.2);
                fill(ax, [x1, x1-ahd, x1-ahd], ...
                         [y1, y1+ahd*0.5, y1-ahd*0.5], 'k');
            elseif abs(nx - xmax) < tol
                % Right boundary: arrow points left
                x0 = nx + arrow_len;  x1 = nx;
                y0 = ny;              y1 = ny;
                plot(ax, [x0 x1], [y0 y1], 'k-', 'LineWidth', 1.2);
                fill(ax, [x1, x1+ahd, x1+ahd], ...
                         [y1, y1+ahd*0.5, y1-ahd*0.5], 'k');
            end

        else  % 'y'
            if abs(ny - ymax) < tol
                % Top boundary: arrow points down
                x0 = nx;  x1 = nx;
                y0 = ny + arrow_len;  y1 = ny;
                plot(ax, [x0 x1], [y0 y1], 'k-', 'LineWidth', 1.2);
                fill(ax, [x1, x1+ahd*0.5, x1-ahd*0.5], ...
                         [y1, y1+ahd, y1+ahd], 'k');
            elseif abs(ny - ymin) < tol
                % Bottom boundary: arrow points up
                x0 = nx;  x1 = nx;
                y0 = ny - arrow_len;  y1 = ny;
                plot(ax, [x0 x1], [y0 y1], 'k-', 'LineWidth', 1.2);
                fill(ax, [x1, x1+ahd*0.5, x1-ahd*0.5], ...
                         [y1, y1-ahd, y1-ahd], 'k');
            end
        end
    end
end


% =========================================================================
function draw_hatching(ax, side, coord_val, pts, hatch_len, hatch_sep)
% Draw engineering hatching for a fixed (clamped) boundary edge

    if numel(pts) < 2, return; end
    p0 = pts(1);  p1 = pts(end);
    num_lines = max(3, round((p1 - p0) / hatch_sep));
    tick_pts   = linspace(p0, p1, num_lines);

    switch side
        case 'bottom'
            % horizontal baseline, hatch goes down
            plot(ax, [p0 p1], [coord_val coord_val], 'k-', 'LineWidth', 1.5);
            for t = tick_pts
                plot(ax, [t, t-hatch_len], [coord_val, coord_val-hatch_len], ...
                     'k-', 'LineWidth', 1.0);
            end
        case 'top'
            plot(ax, [p0 p1], [coord_val coord_val], 'k-', 'LineWidth', 1.5);
            for t = tick_pts
                plot(ax, [t, t+hatch_len], [coord_val, coord_val+hatch_len], ...
                     'k-', 'LineWidth', 1.0);
            end
        case 'left'
            plot(ax, [coord_val coord_val], [p0 p1], 'k-', 'LineWidth', 1.5);
            for t = tick_pts
                plot(ax, [coord_val, coord_val-hatch_len], [t, t-hatch_len], ...
                     'k-', 'LineWidth', 1.0);
            end
        case 'right'
            plot(ax, [coord_val coord_val], [p0 p1], 'k-', 'LineWidth', 1.5);
            for t = tick_pts
                plot(ax, [coord_val, coord_val+hatch_len], [t, t+hatch_len], ...
                     'k-', 'LineWidth', 1.0);
            end
    end
end


% =========================================================================
function draw_loads_arrows(ax, nodes, loads, W, H)
% Draw applied load arrows (proportional to magnitude)

    if isempty(loads.nodes), return; end

    max_f  = max(max(abs(loads.fx)), max(abs(loads.fy)));
    if max_f == 0, return; end
    scale  = 0.18 * max(W, H) / max_f;

    for i = 1:numel(loads.nodes)
        ni = loads.nodes(i);
        nx = nodes(ni, 1);
        ny = nodes(ni, 2);
        fx = loads.fx(i);
        fy = loads.fy(i);

        if abs(fx) > 0
            draw_force_arrow(ax, nx, ny, fx*scale, 0, [0.8 0 0]);
        end
        if abs(fy) > 0
            draw_force_arrow(ax, nx, ny, 0, fy*scale, [0.8 0 0]);
        end
    end

    % Label: place load magnitude beside the largest arrow
    [max_fy_val, max_fy_idx] = max(abs(loads.fy));
    [max_fx_val, max_fx_idx] = max(abs(loads.fx));
    if max_fy_val > 0
        ni  = loads.nodes(max_fy_idx);
        lx  = nodes(ni,1) + 0.025*W;
        ly  = nodes(ni,2);   % arrow starts here and goes down
        text(ax, lx, ly, sprintf('  %.4g', max_fy_val), ...
             'FontSize', 8, 'Color', [0.7 0 0], ...
             'VerticalAlignment', 'middle');
    elseif max_fx_val > 0
        ni  = loads.nodes(max_fx_idx);
        lx  = nodes(ni,1);
        ly  = nodes(ni,2) + 0.025*H;
        text(ax, lx, ly, sprintf('%.4g', max_fx_val), ...
             'FontSize', 8, 'Color', [0.7 0 0], ...
             'HorizontalAlignment', 'center');
    end
end


% =========================================================================
function draw_force_arrow(ax, x, y, dx, dy, color)
% Draw a single force arrow from (x,y) in direction (dx,dy)
    mag = sqrt(dx^2 + dy^2);
    if mag < eps, return; end

    x1 = x + dx;  y1 = y + dy;
    plot(ax, [x x1], [y y1], '-', 'Color', color, 'LineWidth', 1.5);

    % Arrowhead
    ahd = mag * 0.28;
    ux = dx/mag;  uy = dy/mag;
    px = -uy;     py = ux;   % perpendicular
    fill(ax, [x1, x1 - ahd*ux + ahd*0.4*px, x1 - ahd*ux - ahd*0.4*px], ...
             [y1, y1 - ahd*uy + ahd*0.4*py, y1 - ahd*uy - ahd*0.4*py], ...
             color, 'EdgeColor', 'none');
end


% =========================================================================
function annotate_dimensions(ax, xmin, xmax, ymin, ymax, W, H, pad)
% Draw dimension annotations outside the mesh

    offset_x = pad * 0.45;
    offset_y = pad * 0.45;
    tick     = pad * 0.12;

    % Width dimension (below)
    y_dim = ymin - offset_y;
    plot(ax, [xmin xmax], [y_dim y_dim], 'k-', 'LineWidth', 1.0);
    plot(ax, [xmin xmin], [y_dim - tick, y_dim + tick], 'k-', 'LineWidth', 1.0);
    plot(ax, [xmax xmax], [y_dim - tick, y_dim + tick], 'k-', 'LineWidth', 1.0);
    % Arrows
    ahd = pad * 0.07;
    fill(ax, [xmin, xmin+ahd, xmin+ahd], [y_dim, y_dim+ahd*0.4, y_dim-ahd*0.4], 'k');
    fill(ax, [xmax, xmax-ahd, xmax-ahd], [y_dim, y_dim+ahd*0.4, y_dim-ahd*0.4], 'k');
    text(ax, (xmin+xmax)/2, y_dim - tick*1.5, sprintf('%.4g m', W), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
         'FontSize', 10, 'FontWeight', 'bold');

    % Height dimension (right side)
    x_dim = xmax + offset_x;
    plot(ax, [x_dim x_dim], [ymin ymax], 'k-', 'LineWidth', 1.0);
    plot(ax, [x_dim - tick, x_dim + tick], [ymin ymin], 'k-', 'LineWidth', 1.0);
    plot(ax, [x_dim - tick, x_dim + tick], [ymax ymax], 'k-', 'LineWidth', 1.0);
    fill(ax, [x_dim, x_dim+ahd*0.4, x_dim-ahd*0.4], [ymax, ymax-ahd, ymax-ahd], 'k');
    fill(ax, [x_dim, x_dim+ahd*0.4, x_dim-ahd*0.4], [ymin, ymin+ahd, ymin+ahd], 'k');
    text(ax, x_dim + tick*1.5, (ymin+ymax)/2, sprintf('%.4g m', abs(H)), ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
         'FontSize', 10, 'FontWeight', 'bold', 'Rotation', 90);
end


% =========================================================================
function annotate_props(ax, mesh, xmax, ymax, W, H, pad)
% Material properties annotation box (top-right)

    lines = {};
    for k = 1:numel(mesh.prop_names)
        n = mesh.prop_names{k};
        v = mesh.prop_values(k);
        lines{end+1} = sprintf('%s = %.4g', n, v); %#ok<AGROW>
    end
    if isempty(lines), return; end

    txt = strjoin(lines, newline);
    bx  = xmax + pad * 0.55;
    by  = ymax;
    text(ax, bx, by, txt, ...
         'FontSize', 9, 'VerticalAlignment', 'top', ...
         'BackgroundColor', [1 1 0.85], ...
         'EdgeColor', [0.6 0.6 0.3], ...
         'Margin', 4, 'LineWidth', 0.8);
end


% =========================================================================
function create_param_panel(fig, yaml_path, ax_main, opts)
% Create interactive right panel with tunable parameter edit fields

    yaml = pfem_yaml_load(yaml_path);
    if ~isfield(yaml, 'tunable_parameters')
        return;
    end
    tparams = yaml.tunable_parameters;

    % Panel
    pan = uipanel('Parent', fig, ...
                  'Title', 'Tunable Parameters', ...
                  'FontSize', 10, 'FontWeight', 'bold', ...
                  'Position', [0.69 0.06 0.30 0.88], ...
                  'BackgroundColor', [0.95 0.95 0.95]);

    np = numel(tparams);
    row_h  = 0.085;
    top    = 0.95;
    lbl_w  = 0.60;
    edit_w = 0.35;
    x_lbl  = 0.03;
    x_edit = 0.63;

    edit_handles = {};
    param_names  = {};

    for k = 1:np
        tp = tparams{k};
        row_top = top - (k-1) * row_h;

        % Label
        uicontrol('Parent', pan, 'Style', 'text', ...
                  'String', format_param_label(tp), ...
                  'Units', 'normalized', ...
                  'Position', [x_lbl, row_top - row_h, lbl_w, row_h*0.75], ...
                  'HorizontalAlignment', 'left', ...
                  'FontSize', 8, ...
                  'BackgroundColor', [0.95 0.95 0.95]);

        % Edit field
        cur_val = tp.current_value;
        if isnumeric(cur_val)
            val_str = num2str(cur_val, '%g');
        else
            val_str = strtrim(char(cur_val));
        end

        eh = uicontrol('Parent', pan, 'Style', 'edit', ...
                       'String', val_str, ...
                       'Tag', tp.name, ...
                       'Units', 'normalized', ...
                       'Position', [x_edit, row_top - row_h, edit_w, row_h*0.72], ...
                       'FontSize', 8, ...
                       'BackgroundColor', 'white');

        edit_handles{end+1} = eh;
        param_names{end+1}  = tp.name;
    end

    % Mesh-change warning label
    warn_y = top - np * row_h - 0.02;
    uicontrol('Parent', pan, 'Style', 'text', ...
              'String', '* Mesh-changing params require re-running YAML generator', ...
              'Units', 'normalized', ...
              'Position', [x_lbl, warn_y - 0.07, 0.94, 0.07], ...
              'HorizontalAlignment', 'left', ...
              'FontSize', 7, 'ForegroundColor', [0.5 0.3 0], ...
              'BackgroundColor', [0.95 0.95 0.95]);

    % Apply button
    btn_y = warn_y - 0.14;
    uicontrol('Parent', pan, 'Style', 'pushbutton', ...
              'String', 'Apply', ...
              'Units', 'normalized', ...
              'Position', [0.15, btn_y, 0.70, 0.08], ...
              'FontSize', 9, 'FontWeight', 'bold', ...
              'Callback', @(~,~) apply_params(yaml_path, tparams, ...
                                              edit_handles, param_names, ...
                                              ax_main, opts));

    % Note about Enter key
    uicontrol('Parent', pan, 'Style', 'text', ...
              'String', 'Press Enter in any field to apply', ...
              'Units', 'normalized', ...
              'Position', [x_lbl, btn_y - 0.06, 0.94, 0.05], ...
              'HorizontalAlignment', 'center', ...
              'FontSize', 7, 'ForegroundColor', [0.4 0.4 0.4], ...
              'BackgroundColor', [0.95 0.95 0.95]);

    % Attach Enter callback to each edit field
    for k = 1:numel(edit_handles)
        set(edit_handles{k}, 'Callback', ...
            @(~,~) apply_params(yaml_path, tparams, edit_handles, param_names, ...
                                ax_main, opts));
    end
end


% =========================================================================
function apply_params(yaml_path, tparams, edit_handles, param_names, ax_main, opts)
% Called when user edits a param and presses Enter or Apply

    % Build overrides from ALL edit fields (for token patching)
    % and track only CHANGED params (for title display)
    yaml = pfem_yaml_load(yaml_path);
    overrides = struct();
    changed   = struct();

    for k = 1:numel(edit_handles)
        str = strtrim(get(edit_handles{k}, 'String'));
        v   = str2double(str);
        if isnan(v), continue; end

        overrides.(param_names{k}) = v;

        % Compare to original value
        tp_orig = tparams{k};
        if isnumeric(tp_orig.current_value)
            orig = tp_orig.current_value;
        else
            orig = str2double(tp_orig.current_value);
        end
        if isnan(orig) || abs(v - orig) > 1e-10 * max(abs(v), 1)
            changed.(param_names{k}) = v;
        end
    end

    % Patch tokens
    tokens = yaml.inputs.all_tokens;
    for k = 1:numel(tparams)
        fn = tparams{k}.name;
        if isfield(overrides, fn)
            tokens{tparams{k}.global_token_index} = overrides.(fn);
        end
    end

    % Rebuild mesh (geometry unchanged for material param edits)
    [nodes, elem_conn, meta] = pfem_extract_coords(yaml_path);

    % Re-parse bcs/loads with updated tokens
    vals  = tokens_to_vals(tokens);
    bcs   = parse_bcs(vals, meta, yaml);
    loads = parse_loads(vals, meta, yaml, bcs);

    % Build prop display from overrides + originals
    [prop_names, prop_values] = build_prop_display(tparams, overrides);

    % Title: base title + only the changed parameters
    title_str = yaml.title;
    if ~isempty(fieldnames(changed))
        parts = {};
        fns = fieldnames(changed);
        for i = 1:numel(fns)
            lbl = format_prop_label(fns{i});
            plain_lbl = regexprep(lbl, '\\(\w+)', '$1');   % \nu→nu, \rho→rho
        parts{end+1} = sprintf('%s=%.4g', plain_lbl, changed.(fns{i})); %#ok<AGROW>
        end
        title_str = [title_str '  (' strjoin(parts, ',  ') ')'];
    end

    mesh = struct('nodes', nodes, 'elem_conn', elem_conn, 'meta', meta, ...
                  'bcs', bcs, 'loads', loads, ...
                  'prop_names', {prop_names}, 'prop_values', prop_values, ...
                  'title', title_str, 'opts', opts);

    draw_diagram(ax_main, mesh);
    title(ax_main, title_str, 'FontSize', 11, 'FontWeight', 'bold', ...
          'Interpreter', 'none');
end


% =========================================================================
% DATA LOADING AND PARSING
% =========================================================================

function [nodes, elem_conn, meta, yaml] = load_mesh_data(yaml_path)
    yaml = pfem_yaml_load(yaml_path);
    [nodes, elem_conn, meta] = pfem_extract_coords(yaml_path);
end


function mesh = build_mesh(nodes, elem_conn, meta, bcs, loads, yaml, opts)
% Build mesh display struct

    % Collect display properties from tunable_parameters
    [prop_names, prop_values] = build_prop_display(yaml.tunable_parameters, struct());

    title_str = '';
    if isfield(yaml, 'title')
        title_str = yaml.title;
    end

    mesh = struct('nodes', nodes, 'elem_conn', elem_conn, 'meta', meta, ...
                  'bcs', bcs, 'loads', loads, ...
                  'prop_names', {prop_names}, 'prop_values', prop_values, ...
                  'title', title_str, 'opts', opts);
end


function [names, values] = build_prop_display(tparams, overrides)
% Build list of material property names/values for display

    % Which params to show (material properties, not mesh topology)
    skip_patterns = {'nels', 'nxe', 'nye', 'nze', 'np_types', 'nod', 'nn', 'nip'};

    names  = {};
    values = [];

    for k = 1:numel(tparams)
        tp  = tparams{k};
        nm  = tp.name;

        % Skip mesh topology parameters
        skip = false;
        for s = skip_patterns
            if contains(nm, s{1}), skip = true; break; end
        end
        if skip, continue; end

        % Get value (override if provided)
        if isfield(overrides, nm)
            v = overrides.(nm);
        elseif isnumeric(tp.current_value)
            v = tp.current_value;
        else
            v = str2double(tp.current_value);
        end
        if isnan(v), continue; end

        % Build nice label
        lbl = format_prop_label(nm);
        names{end+1}  = lbl; %#ok<AGROW>
        values(end+1) = v;   %#ok<AGROW>
    end
end


function lbl = format_prop_label(nm)
% Convert parameter name to display label
    replacements = { ...
        'youngs_modulus_E',  'E'; ...
        'poisson_ratio_nu',  '\nu'; ...
        'density_rho',       '\rho'; ...
        'dtim',              '\Deltat'; ...
        'nstep',             'nstep'; ...
        'theta',             '\theta'; ...
        'tol',               'tol'; ...
        'limit',             'limit'; ...
    };
    for r = 1:size(replacements,1)
        if strcmp(nm, replacements{r,1})
            lbl = replacements{r,2};
            return;
        end
    end
    lbl = strrep(nm, '_', ' ');
end


function lbl = format_param_label(tp)
% Format parameter label for the UI panel
    nm = tp.name;
    if isfield(tp, 'description') && ~isempty(tp.description)
        desc = tp.description;
    else
        desc = strrep(nm, '_', ' ');
    end
    if isfield(tp, 'note') && ~isempty(tp.note)
        lbl = sprintf('%s *', desc);
    else
        lbl = desc;
    end
end


% =========================================================================
% BC PARSING
% =========================================================================

function bcs = parse_bcs(vals, meta, yaml)
% Parse boundary condition data from token values

    bcs.x_roller_nodes = [];
    bcs.y_roller_nodes = [];
    bcs.fixed_nodes    = [];

    bc_start = find_bc_start(meta, yaml);
    if bc_start < 1 || bc_start > numel(vals)
        return;
    end

    nr_val = to_num(vals{bc_start});
    if isnan(nr_val) || nr_val < 1
        return;
    end
    nr = round(nr_val);

    % nodof: degrees of freedom per node
    nodof = 2;
    try
        nodof_field = yaml.fem.dof.per_node;
        if isnumeric(nodof_field) && nodof_field > 0
            nodof = nodof_field;
        end
    catch, end

    idx = bc_start + 1;
    for i = 1:nr
        if idx + nodof > numel(vals), break; end
        node_num = round(to_num(vals{idx}));
        idx = idx + 1;
        nf = zeros(1, nodof);
        for d = 1:nodof
            nf(d) = to_num(vals{idx});
            idx = idx + 1;
        end

        % nf(d)==0 means DOF d is fixed
        fixed_dofs = (nf == 0);
        if all(fixed_dofs)
            bcs.fixed_nodes(end+1) = node_num;
        elseif fixed_dofs(1) && ~fixed_dofs(2)
            bcs.x_roller_nodes(end+1) = node_num;
        elseif ~fixed_dofs(1) && fixed_dofs(2)
            bcs.y_roller_nodes(end+1) = node_num;
        end
    end
end


function bc_start = find_bc_start(meta, yaml)
% Find 1-based token index where the BC (nr) section begins

    bc_start = -1;

    if isfield(meta, 'bc_token_start')
        bc_start = meta.bc_token_start;
        return;
    end

    % Determine from mesh type
    first_read = get_first_read(yaml);

    if has_g_coord_read(yaml)
        % Explicit mesh: header + prop + g_coord + g_num
        nod   = meta.nod;
        nels  = meta.nels;
        nn    = meta.nn;
        ndim  = meta.ndim;

        % Header size
        if contains(first_read, 'nels') && contains(first_read, 'nn')
            header_n = 9;  % p54 style
        else
            header_n = 9;
        end

        nprops   = get_nprops_yaml(yaml);
        np_types = get_np_types(yaml);
        prop_n   = nprops * np_types;

        etype_n  = 0;
        if np_types > 1
            etype_n = nels;
        end

        g_coord_n = nn * ndim;
        g_num_n   = nels * nod;

        bc_start = 1 + header_n + prop_n + etype_n + g_coord_n + g_num_n;

    elseif has_x_y_coords_read(yaml)
        % Structured mesh: header + prop + x_coords + y_coords
        [nxe, nye, ~, ~, header_n] = get_structured_header(yaml, meta);
        nprops   = get_nprops_yaml(yaml);
        np_types = get_np_types(yaml);
        prop_n   = nprops * np_types;

        etype_n  = 0;
        if np_types > 1
            etype_n = nxe * nye;
        end

        % 3D case
        if isfield(meta, 'nze') && meta.nze > 0
            nze = meta.nze;
            coord_n = (nxe+1) + (nye+1) + (nze+1);
        else
            coord_n = (nxe+1) + (nye+1);
        end

        bc_start = 1 + header_n + prop_n + etype_n + coord_n;

    elseif has_ell_read(yaml)
        % 1D mesh: header + prop + ell
        nels    = meta.nels;
        nprops  = get_nprops_yaml(yaml);
        np_types = get_np_types(yaml);
        prop_n  = nprops * np_types;
        etype_n = 0;
        if np_types > 1, etype_n = nels; end
        bc_start = 1 + 2 + prop_n + etype_n + nels;
    end
end


function nprops = get_nprops_yaml(yaml)
% Infer nprops from tunable_parameters and program context
    nprops = 2;  % default
    if ~isfield(yaml, 'tunable_parameters'), return; end
    tp = yaml.tunable_parameters;

    % Count how many prop-related parameters there are
    prop_count = 0;
    prop_kw = {'youngs', 'modulus', 'poisson', 'density', 'conductiv', ...
               'sigma_y', 'yield', 'viscosity', '_rho', 'heat_cap', ...
               'thermal', 'kx', 'ky', 'kz', 'EI', 'rhoA'};
    for k = 1:numel(tp)
        nm = tp{k}.name;
        is_prop = false;
        for kw = prop_kw
            if contains(nm, kw{1}), is_prop = true; break; end
        end
        if is_prop, prop_count = prop_count + 1; end
    end
    if prop_count > 0
        nprops = prop_count;
    else
        % Fall back to chapter-based default
        chapter = 0;
        if isfield(yaml, 'authors') && isfield(yaml.authors, 'source') && ...
           isfield(yaml.authors.source, 'chapter')
            chapter = yaml.authors.source.chapter;
        end
        nprops = chapter_default_nprops(chapter);
    end
end


function n = chapter_default_nprops(ch)
    switch ch
        case 4,  n = 1;
        case 5,  n = 3;   % E, nu, rho typically (p54 has 3)
        case 6,  n = 3;
        case 7,  n = 1;
        case 8,  n = 1;
        case 9,  n = 4;
        case 10, n = 3;
        case 11, n = 4;
        otherwise, n = 2;
    end
end


function np = get_np_types(yaml)
% Extract np_types from tokens
    np = 1;
    tokens = yaml.inputs.all_tokens;
    first_read = get_first_read(yaml);
    if contains(first_read, 'np_types')
        % Find position of np_types in variable list
        vars = split_vars(first_read);
        pos = find(strcmp(vars, 'np_types'));
        if ~isempty(pos) && pos <= numel(tokens)
            v = to_num_tok(tokens{pos});
            if v >= 1, np = v; end
        end
    end
end


function [nxe, nye, nze, nod, header_n] = get_structured_header(yaml, meta)
    nxe = 1; nye = 1; nze = 0; nod = 8; header_n = 8;
    if isfield(meta, 'nxe'), nxe = meta.nxe; end
    if isfield(meta, 'nye'), nye = meta.nye; end
    if isfield(meta, 'nze'), nze = meta.nze; end
    if isfield(meta, 'nod'), nod = meta.nod; end

    first_read = get_first_read(yaml);
    if contains(first_read, 'type_2d') && contains(first_read, 'element')
        header_n = 8;
    elseif contains(first_read, 'type_2d') && contains(first_read, 'dir')
        header_n = 5;
    elseif contains(first_read, 'nxe') && contains(first_read, 'nod') && ...
           contains(first_read, 'np_types')
        header_n = 4;
    elseif contains(first_read, 'nxe') && contains(first_read, 'np_types')
        header_n = 3;
    elseif contains(first_read, 'nod') && contains(first_read, 'nze')
        header_n = 6;
    else
        header_n = 8;
    end
end


% =========================================================================
% LOADS PARSING
% =========================================================================

function loads = parse_loads(vals, meta, yaml, bcs)
% Parse applied loads from token values

    loads.nodes = [];
    loads.fx    = [];
    loads.fy    = [];

    bc_start = find_bc_start(meta, yaml);
    if bc_start < 1, return; end

    nr_val = to_num(vals{bc_start});
    if isnan(nr_val), return; end
    nr = round(nr_val);

    nodof = 2;
    if isfield(meta, 'nodof'), nodof = meta.nodof; end

    % Skip past nr section
    loaded_start = bc_start + 1 + nr * (1 + nodof);

    if loaded_start > numel(vals), return; end

    loaded_nodes_count = round(to_num(vals{loaded_start}));
    if isnan(loaded_nodes_count) || loaded_nodes_count < 1, return; end

    % For each loaded node: node_num, then nodof load values
    idx = loaded_start + 1;
    for i = 1:loaded_nodes_count
        if idx > numel(vals), break; end
        node_num = round(to_num(vals{idx}));
        idx = idx + 1;

        f = zeros(1, nodof);
        for d = 1:nodof
            if idx <= numel(vals)
                f(d) = to_num(vals{idx});
                idx = idx + 1;
            end
        end

        loads.nodes(end+1) = node_num;
        loads.fx(end+1)    = f(1);
        if nodof >= 2
            loads.fy(end+1) = f(2);
        else
            loads.fy(end+1) = 0;
        end
    end
end


% =========================================================================
% SMALL UTILITY FUNCTIONS (copied/adapted from pfem_extract_coords)
% =========================================================================

function vals = tokens_to_vals(tokens)
    vals = cell(size(tokens));
    for i = 1:numel(tokens)
        t = tokens{i};
        if isnumeric(t)
            vals{i} = t;
        elseif ischar(t)
            vals{i} = strrep(t, '''', '');
        else
            vals{i} = t;
        end
    end
end

function v = to_num(x)
    if isnumeric(x), v = x;
    elseif ischar(x), v = str2double(x);
        if isnan(v), v = NaN; end
    else, v = NaN;
    end
end

function v = to_num_tok(x)
    if isnumeric(x), v = x;
    elseif ischar(x)
        s = strrep(x, '''', '');
        v = str2double(s);
        if isnan(v), v = NaN; end
    else, v = NaN;
    end
end

function first_read = get_first_read(yaml)
    first_read = '';
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        reads = yaml.code.io_reads_from_unit10;
        if numel(reads) > 0 && isfield(reads{1}, 'stmt')
            first_read = reads{1}.stmt;
        end
    end
end

function has = has_g_coord_read(yaml)
    has = false;
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        for i = 1:numel(yaml.code.io_reads_from_unit10)
            if contains(yaml.code.io_reads_from_unit10{i}.stmt, 'g_coord')
                has = true; return;
            end
        end
    end
end

function has = has_x_y_coords_read(yaml)
    has = false;
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        for i = 1:numel(yaml.code.io_reads_from_unit10)
            stmt = yaml.code.io_reads_from_unit10{i}.stmt;
            if contains(stmt, 'x_coords') || contains(stmt, 'y_coords')
                has = true; return;
            end
        end
    end
end

function has = has_ell_read(yaml)
    has = false;
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        for i = 1:numel(yaml.code.io_reads_from_unit10)
            if contains(yaml.code.io_reads_from_unit10{i}.stmt, 'ell')
                has = true; return;
            end
        end
    end
end

function vars = split_vars(stmt)
% Extract variable names from READ statement
    m = regexp(stmt, 'READ\s*\([^)]+\)\s*(.+)', 'tokens');
    if isempty(m), vars = {}; return; end
    parts = strsplit(strtrim(m{1}{1}), ',');
    vars = strtrim(parts);
end
