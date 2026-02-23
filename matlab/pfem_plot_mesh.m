function pfem_plot_mesh(out, varargin)
% PFEM_PLOT_MESH  Visualize mesh and deformed shape
%
% Usage:
%   pfem_plot_mesh(out)                    % Plot mesh from run output
%   pfem_plot_mesh(out, 'scale', 1000)     % Scale deformation
%   pfem_plot_mesh(results_array)          % Compare meshes from sweep
%
% Options:
%   'scale'  - Deformation scale factor (default: auto)
%   'title'  - Custom title

    p = inputParser;
    addParameter(p, 'scale', []);
    addParameter(p, 'title', '');
    parse(p, varargin{:});
    scale_factor = p.Results.scale;
    custom_title = p.Results.title;

    % Handle array of results (compare meshes)
    if numel(out) > 1
        plot_mesh_comparison(out, scale_factor);
        return;
    end

    % Single mesh visualization
    [nodes, disp, elem_centers, stresses, ndim] = parse_mesh_data(out);

    if isempty(nodes)
        fprintf('Could not extract mesh data.\n');
        return;
    end

    % Auto-scale deformation
    if isempty(scale_factor)
        max_disp = max(abs(disp(:)));
        if ndim == 1
            mesh_size = range(nodes(:,1));
        elseif ndim >= 2
            mesh_size = max(range(nodes(:,1)), range(nodes(:,2)));
        end
        if max_disp > 0
            scale_factor = 0.1 * mesh_size / max_disp;
        else
            scale_factor = 1;
        end
    end

    % Handle 1D case
    if ndim == 1
        plot_1d_mesh(nodes, disp, scale_factor, out, custom_title);
        return;
    end

    % Create figure
    figure('Name', 'PFEM Mesh Visualization', 'Position', [100 100 1200 500]);

    % Get parameter info
    param_str = '';
    if isfield(out, 'overrides') && ~isempty(out.overrides) && ~isempty(fieldnames(out.overrides))
        fnames = fieldnames(out.overrides);
        parts = {};
        for i = 1:numel(fnames)
            parts{end+1} = sprintf('%s=%.4g', fnames{i}, out.overrides.(fnames{i}));
        end
        param_str = strjoin(parts, ', ');
    end

    case_name = '';
    if isfield(out, 'case')
        case_name = out.case;
    end

    % Subplot 1: Original vs Deformed mesh
    subplot(1, 2, 1);
    hold on;

    % Plot original nodes
    plot(nodes(:,1), nodes(:,2), 'bo', 'MarkerSize', 6, 'MarkerFaceColor', 'b');

    % Plot deformed nodes
    deformed = nodes + scale_factor * disp;
    plot(deformed(:,1), deformed(:,2), 'rs', 'MarkerSize', 6, 'MarkerFaceColor', 'r');

    % Draw lines connecting original to deformed (shows displacement vectors)
    for i = 1:size(nodes, 1)
        plot([nodes(i,1), deformed(i,1)], [nodes(i,2), deformed(i,2)], 'k-', 'LineWidth', 0.5);
    end

    % Plot element centers
    if ~isempty(elem_centers)
        plot(elem_centers(:,1), elem_centers(:,2), 'g^', 'MarkerSize', 8, 'MarkerFaceColor', 'g');
    end

    hold off;
    axis equal;
    grid on;
    xlabel('X (m)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Y (m)', 'FontSize', 11, 'FontWeight', 'bold');
    title(sprintf('Mesh & Deformation (scale: %.0fx)', scale_factor), 'FontSize', 12, 'FontWeight', 'bold');
    legend({'Original Nodes', 'Deformed Nodes', '', 'Element Centers'}, 'Location', 'best');

    % Subplot 2: Displacement magnitude contour
    subplot(1, 2, 2);

    disp_mag = sqrt(disp(:,1).^2 + disp(:,2).^2);
    scatter(nodes(:,1), nodes(:,2), 100, disp_mag, 'filled');
    colorbar;
    colormap(jet);
    axis equal;
    grid on;
    xlabel('X (m)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Y (m)', 'FontSize', 11, 'FontWeight', 'bold');
    title('Displacement Magnitude (m)', 'FontSize', 12, 'FontWeight', 'bold');

    % Main title
    if ~isempty(custom_title)
        sgtitle(custom_title, 'FontSize', 14, 'FontWeight', 'bold');
    else
        sgtitle(sprintf('PFEM Mesh: %s\n%s', case_name, param_str), 'FontSize', 14, 'FontWeight', 'bold');
    end
end


function plot_mesh_comparison(results, scale_factor)
% Compare meshes from multiple runs (e.g., mesh refinement study)
    n_runs = numel(results);

    % Determine grid layout
    if n_runs <= 2
        rows = 1; cols = 2;
    elseif n_runs <= 4
        rows = 2; cols = 2;
    else
        rows = 2; cols = ceil(n_runs/2);
    end

    figure('Name', 'PFEM Mesh Comparison', 'Position', [50 50 400*cols 350*rows]);

    for k = 1:n_runs
        if results(k).status ~= 0
            continue;
        end

        out = results(k).out;
        [nodes, disp, ~, ~] = parse_mesh_data(out);

        if isempty(nodes)
            continue;
        end

        % Auto-scale if not provided
        if isempty(scale_factor)
            max_disp = max(abs(disp(:)));
            mesh_size = max(range(nodes(:,1)), range(nodes(:,2)));
            if max_disp > 0
                sf = 0.1 * mesh_size / max_disp;
            else
                sf = 1;
            end
        else
            sf = scale_factor;
        end

        subplot(rows, cols, k);
        hold on;

        % Plot original mesh
        plot(nodes(:,1), nodes(:,2), 'b.', 'MarkerSize', 8);

        % Plot deformed
        deformed = nodes + sf * disp;
        plot(deformed(:,1), deformed(:,2), 'r.', 'MarkerSize', 8);

        hold off;
        axis equal;
        grid on;

        % Get parameter info for title
        param_str = sprintf('Value=%.4g', results(k).value);
        if isfield(out, 'overrides') && ~isempty(out.overrides)
            fnames = fieldnames(out.overrides);
            if ~isempty(fnames)
                param_str = sprintf('%s=%.4g', fnames{1}, out.overrides.(fnames{1}));
            end
        end

        title(sprintf('%s (%d nodes)', param_str, size(nodes,1)), 'FontSize', 11);
        xlabel('X'); ylabel('Y');
    end

    sgtitle('Mesh Comparison Across Parameter Values', 'FontSize', 14, 'FontWeight', 'bold');
end


function [nodes, disp, elem_centers, stresses, ndim] = parse_mesh_data(out)
% Parse mesh data from .res file and YAML
    nodes = [];
    disp = [];
    elem_centers = [];
    stresses = [];
    ndim = 2;  % Default to 2D

    % Find .res file
    res_files = out.files(endsWith(out.files, '.res'));
    if isempty(res_files)
        return;
    end
    res_path = res_files{1};

    if ~exist(res_path, 'file')
        return;
    end

    % Read file
    fid = fopen(res_path, 'r');
    if fid == -1
        return;
    end

    content = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = content{1};

    % Detect displacement format and parse
    disp_start = 0;
    stress_start = 0;
    disp_cols = 2;  % Default number of displacement columns

    for i = 1:numel(lines)
        line = strtrim(lines{i});
        if contains(line, 'Node') && contains(line, 'disp')
            disp_start = i + 1;
            % Detect number of displacement columns from header
            if contains(line, 'z-disp')
                disp_cols = 3;
                ndim = 3;
            elseif ~contains(line, 'y-disp')
                disp_cols = 1;
                ndim = 1;
            end
        elseif contains(line, 'Element') && contains(line, 'sig')
            stress_start = i + 1;
        end
    end

    % Parse displacements
    disp_data = [];
    if disp_start > 0
        for i = disp_start:numel(lines)
            line = strtrim(lines{i});
            if isempty(line) || contains(line, 'integration') || contains(line, 'Element')
                break;
            end
            vals = sscanf(line, '%f');
            if numel(vals) >= 1 + disp_cols
                disp_data(end+1, :) = vals(2:(1+disp_cols))';
            end
        end
    end

    if isempty(disp_data)
        return;
    end

    disp = disp_data;
    n_nodes = size(disp, 1);

    % Parse stresses (includes element center coordinates)
    if stress_start > 0
        for i = stress_start:numel(lines)
            line = strtrim(lines{i});
            if isempty(line)
                break;
            end
            vals = sscanf(line, '%f');
            if numel(vals) >= 5
                elem_centers(end+1, :) = vals(2:3)';  % x-coord, y-coord
                stresses(end+1, :) = vals(4:end)';
            end
        end
    end

    % Try to get exact coordinates from YAML
    [nodes, yaml_ndim] = extract_coords_from_yaml(out, n_nodes);

    % Update ndim if YAML provided it
    if ~isempty(yaml_ndim)
        ndim = yaml_ndim;
    end

    % Fallback to approximation if YAML extraction failed
    if isempty(nodes)
        nodes = generate_approx_nodes(n_nodes, out, elem_centers);
    end
end


function [nodes, ndim] = extract_coords_from_yaml(out, n_nodes)
% Extract exact node coordinates from YAML tokens
    nodes = [];
    ndim = [];

    % Check for YAML path in output struct
    yaml_path = '';
    if isfield(out, 'yaml_path')
        yaml_path = out.yaml_path;
    elseif isfield(out, 'yaml')
        yaml_path = out.yaml;
    end

    if isempty(yaml_path) || ~exist(yaml_path, 'file')
        return;
    end

    try
        [yaml_nodes, ~, meta] = pfem_extract_coords(yaml_path);

        % Verify node count matches
        if ~isempty(yaml_nodes) && size(yaml_nodes, 1) == n_nodes
            nodes = yaml_nodes;
            ndim = size(yaml_nodes, 2);
            fprintf('  [Mesh] Using exact coordinates from YAML (%s, %d nodes, %dD)\n', ...
                    meta.program, n_nodes, ndim);
        elseif ~isempty(yaml_nodes)
            fprintf('  [Mesh] Node count mismatch: YAML=%d, res=%d. Using approximation.\n', ...
                    size(yaml_nodes, 1), n_nodes);
        end
    catch ME
        % Silently fall back to approximation
        fprintf('  [Mesh] YAML extraction failed: %s\n', ME.message);
    end
end


function nodes = generate_approx_nodes(n_nodes, out, elem_centers)
% Generate approximate node coordinates using element centers
% Element centers from .res give us actual problem dimensions

    nodes = [];

    % Get domain bounds from element centers
    if ~isempty(elem_centers)
        x_min = min(elem_centers(:,1));
        x_max = max(elem_centers(:,1));
        y_min = min(elem_centers(:,2));
        y_max = max(elem_centers(:,2));

        % Element centers are at midpoints, so extend bounds
        dx = (x_max - x_min) / max(1, size(elem_centers,1)-1);
        dy = (y_max - y_min) / max(1, size(elem_centers,1)-1);

        x_min = x_min - dx;
        x_max = x_max + dx;
        y_min = y_min - dy;
        y_max = y_max + dy;
    else
        % Default normalized domain
        x_min = 0; x_max = 1;
        y_min = -1; y_max = 0;
    end

    % Estimate grid layout from node count
    % For 8-node quads: n_nodes = (2*nxe+1)*(2*nye+1)
    % For 4-node quads: n_nodes = (nxe+1)*(nye+1)

    found = false;
    for nxe = 1:20
        for nye = 1:20
            % 8-node elements
            if (2*nxe+1)*(2*nye+1) == n_nodes
                nx = 2*nxe + 1;
                ny = 2*nye + 1;
                found = true;
                break;
            end
            % 4-node elements
            if (nxe+1)*(nye+1) == n_nodes
                nx = nxe + 1;
                ny = nye + 1;
                found = true;
                break;
            end
        end
        if found
            break;
        end
    end

    if ~found
        % Fallback: assume roughly square
        nx = ceil(sqrt(n_nodes));
        ny = ceil(n_nodes / nx);
    end

    % Generate grid coordinates with actual dimensions
    [X, Y] = meshgrid(linspace(x_min, x_max, nx), linspace(y_max, y_min, ny));

    % Flatten and take first n_nodes
    x_flat = X(:);
    y_flat = Y(:);

    if length(x_flat) >= n_nodes
        nodes = [x_flat(1:n_nodes), y_flat(1:n_nodes)];
    else
        nodes = [x_flat, y_flat];
        while size(nodes, 1) < n_nodes
            nodes(end+1, :) = nodes(end, :);
        end
    end
end


function plot_1d_mesh(nodes, disp, scale_factor, out, custom_title)
% Plot 1D mesh visualization
    figure('Name', 'PFEM 1D Mesh Visualization', 'Position', [100 100 1000 400]);

    % Get parameter info
    param_str = '';
    if isfield(out, 'overrides') && ~isempty(out.overrides) && ~isempty(fieldnames(out.overrides))
        fnames = fieldnames(out.overrides);
        parts = {};
        for i = 1:numel(fnames)
            parts{end+1} = sprintf('%s=%.4g', fnames{i}, out.overrides.(fnames{i}));
        end
        param_str = strjoin(parts, ', ');
    end

    case_name = '';
    if isfield(out, 'case')
        case_name = out.case;
    end

    % Subplot 1: Original vs Deformed
    subplot(1, 2, 1);
    hold on;

    y_orig = zeros(size(nodes));
    y_def = scale_factor * disp;

    % Plot original
    plot(nodes, y_orig, 'bo-', 'MarkerSize', 8, 'MarkerFaceColor', 'b', 'LineWidth', 2);

    % Plot deformed
    plot(nodes, y_def, 'rs-', 'MarkerSize', 8, 'MarkerFaceColor', 'r', 'LineWidth', 2);

    % Connect original to deformed
    for i = 1:length(nodes)
        plot([nodes(i), nodes(i)], [y_orig(i), y_def(i)], 'k-', 'LineWidth', 0.5);
    end

    hold off;
    grid on;
    xlabel('Position (m)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Displacement (scaled)', 'FontSize', 11, 'FontWeight', 'bold');
    title(sprintf('1D Mesh (scale: %.0fx)', scale_factor), 'FontSize', 12, 'FontWeight', 'bold');
    legend({'Original', 'Deformed'}, 'Location', 'best');

    % Subplot 2: Displacement along length
    subplot(1, 2, 2);
    bar(nodes, disp, 0.6, 'FaceColor', [0.3 0.6 0.9]);
    grid on;
    xlabel('Position (m)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Displacement (m)', 'FontSize', 11, 'FontWeight', 'bold');
    title('Nodal Displacements', 'FontSize', 12, 'FontWeight', 'bold');

    % Main title
    if ~isempty(custom_title)
        sgtitle(custom_title, 'FontSize', 14, 'FontWeight', 'bold');
    else
        sgtitle(sprintf('PFEM 1D: %s\n%s', case_name, param_str), 'FontSize', 14, 'FontWeight', 'bold');
    end
end
