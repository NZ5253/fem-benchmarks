function [nodes, elem_conn, meta] = pfem_extract_coords(yaml_or_out)
% PFEM_EXTRACT_COORDS  Extract node coordinates from YAML tokens
%
% Usage:
%   [nodes, elem_conn, meta] = pfem_extract_coords(yaml_path)
%   [nodes, elem_conn, meta] = pfem_extract_coords(out_struct)
%
% Returns:
%   nodes     - [nn x ndim] node coordinates
%   elem_conn - [nels x nod] element connectivity (if available)
%   meta      - struct with mesh info (nn, nels, nod, program, etc.)
%
% Supports all PFEM chapters (4-11):
%   - Structured 2D: p51, p55, p61-p68, p72-p73, p84-p89, p91-p96, p102-p104, p112-p118
%   - Structured 3D: p53, p56, p57
%   - Explicit mesh: p42, p44, p45, p54, p74, p75, p88, p610
%   - 1D elements:   p41, p43, p46, p71, p81-p83, p93, p101, p111

    nodes = [];
    elem_conn = [];
    meta = struct();

    % Get YAML path from input
    if isstruct(yaml_or_out)
        if isfield(yaml_or_out, 'yaml_path')
            yaml_path = yaml_or_out.yaml_path;
        elseif isfield(yaml_or_out, 'yaml')
            yaml_path = yaml_or_out.yaml;
        else
            return;
        end
    else
        yaml_path = yaml_or_out;
    end

    % Load YAML
    if ~exist(yaml_path, 'file')
        return;
    end

    yaml = pfem_yaml_load(yaml_path);

    % Get tokens
    if ~isfield(yaml, 'inputs') || ~isfield(yaml.inputs, 'all_tokens')
        return;
    end

    tokens = yaml.inputs.all_tokens;
    vals = tokens_to_values(tokens);

    % Determine program type from source file
    program = '';
    chapter = 0;
    if isfield(yaml, 'code') && isfield(yaml.code, 'source_file')
        src = yaml.code.source_file;
        [~, prog_name, ~] = fileparts(src);
        program = prog_name;
        % Extract chapter number
        ch_match = regexp(src, 'chap(\d+)', 'tokens');
        if ~isempty(ch_match)
            chapter = str2double(ch_match{1}{1});
        end
    end

    meta.program = program;
    meta.chapter = chapter;

    % Detect format from io_reads and parse accordingly
    if has_g_coord_read(yaml)
        % Explicit mesh (p42, p44, p45, p54, p74, p75, p88, p610)
        [nodes, elem_conn, meta] = parse_explicit_mesh(vals, yaml, meta);
    elseif has_ell_read(yaml)
        % 1D mesh (p41, p43, p46, p71, p81-p83, p93, p101, p111)
        [nodes, elem_conn, meta] = parse_1d_mesh(vals, yaml, meta);
    elseif has_x_y_coords_read(yaml)
        % Structured mesh (most programs)
        [nodes, elem_conn, meta] = parse_structured_mesh_generic(vals, yaml, meta);
    end
end


function [nodes, elem_conn, meta] = parse_structured_mesh_generic(vals, yaml, meta)
% Parse structured mesh by detecting header format from io_reads
    nodes = [];
    elem_conn = [];

    program = meta.program;
    chapter = meta.chapter;

    % Get first READ statement to determine header format
    first_read = get_first_read(yaml);

    % Detect header type and extract parameters
    [nxe, nye, nze, nod, dir, np_types, header_tokens] = detect_header_format(first_read, vals, program, chapter);

    if isempty(nxe) || isempty(nye)
        return;
    end

    meta.nxe = nxe;
    meta.nye = nye;
    meta.nod = nod;
    meta.dir = dir;
    meta.ndim = 2;

    if ~isempty(nze) && nze > 0
        meta.nze = nze;
        meta.ndim = 3;
    end

    % Determine prop count based on program/chapter
    nprops = get_nprops(program, chapter);
    prop_count = nprops * np_types;

    % Coordinate start position (1-based)
    coord_start = header_tokens + prop_count + 1;

    % Check for etype (conditional read)
    if np_types > 1
        % etype uses nels tokens (nxe*nye for 2D)
        nels = nxe * nye;
        if meta.ndim == 3
            nels = nxe * nye * nze;
        end
        coord_start = coord_start + nels;
    end

    % Extract coordinates
    if meta.ndim == 2
        [nodes, meta] = generate_2d_nodes(vals, coord_start, nxe, nye, nod, dir, meta);
    else
        [nodes, meta] = generate_3d_nodes(vals, coord_start, nxe, nye, nze, nod, meta);
    end
end


function [nxe, nye, nze, nod, dir, np_types, header_tokens] = detect_header_format(first_read, vals, program, chapter)
% Detect header format from first READ statement
    nxe = []; nye = []; nze = []; nod = []; dir = 'x'; np_types = 1;
    header_tokens = 0;

    if isempty(first_read)
        return;
    end

    % Count variables in first READ (approximate token count)
    % Different header patterns:

    if contains(first_read, 'type_2d') && contains(first_read, 'element') && contains(first_read, 'nod')
        % Type A (p51, p55): type_2d, element, nod, dir, nxe, nye, nip, np_types
        nod = to_num(vals{3});
        dir = vals{4};
        nxe = to_num(vals{5});
        nye = to_num(vals{6});
        np_types = to_num(vals{8});
        header_tokens = 8;

    elseif contains(first_read, 'type_2d') && contains(first_read, 'dir') && ~contains(first_read, 'element')
        % Type B (p72, p84, etc.): type_2d, dir, nxe, nye, np_types
        dir = vals{2};
        nxe = to_num(vals{3});
        nye = to_num(vals{4});
        np_types = to_num(vals{5});
        nod = 4;  % Implicit for flow/transient problems
        header_tokens = 5;

    elseif contains(first_read, 'nxe') && contains(first_read, 'nye') && contains(first_read, 'nod') && contains(first_read, 'np_types')
        % Type D (p102, p112, etc.): nxe, nye, nod, np_types
        nxe = to_num(vals{1});
        nye = to_num(vals{2});
        nod = to_num(vals{3});
        np_types = to_num(vals{4});
        dir = 'x';
        header_tokens = 4;

    elseif contains(first_read, 'nxe') && contains(first_read, 'nye') && contains(first_read, 'np_types') && ~contains(first_read, 'nod')
        % Type C (p61, etc.): nxe, nye, np_types
        nxe = to_num(vals{1});
        nye = to_num(vals{2});
        np_types = to_num(vals{3});
        nod = 8;  % Default for nonlinear
        dir = 'y';
        header_tokens = 3;

    elseif contains(first_read, 'nod') && contains(first_read, 'nxe') && contains(first_read, 'nye') && contains(first_read, 'nze')
        % Type E (p53, p56, p57): nod, nxe, nye, nze, nip, np_types
        nod = to_num(vals{1});
        nxe = to_num(vals{2});
        nye = to_num(vals{3});
        nze = to_num(vals{4});
        np_types = to_num(vals{6});
        dir = 'x';
        header_tokens = 6;

    elseif contains(first_read, 'nxe') && contains(first_read, 'nye')
        % Generic fallback: look for nxe, nye pattern
        % Try to find numeric values that look like mesh dimensions
        for i = 1:min(6, numel(vals))
            v = to_num(vals{i});
            if isempty(nxe) && v > 0 && v < 100 && mod(v, 1) == 0
                nxe = v;
            elseif ~isempty(nxe) && isempty(nye) && v > 0 && v < 100 && mod(v, 1) == 0
                nye = v;
                break;
            end
        end
        nod = 4;
        dir = 'x';
        np_types = 1;
        header_tokens = 4;
    end
end


function nprops = get_nprops(program, chapter)
% Get number of material properties based on program
    % Default property counts by chapter/program type
    if chapter == 4
        nprops = 1;  % 1D: just E or k
    elseif chapter == 5
        if startsWith(program, 'p53') || startsWith(program, 'p56') || startsWith(program, 'p57')
            nprops = 2;  % 3D: E, nu (per row)
        else
            nprops = 2;  % 2D elasticity: E, nu
        end
    elseif chapter == 6
        nprops = 7;  % Plasticity: E, nu, gamma, sy, de, npri, nsrf or similar
    elseif chapter == 7
        nprops = 1;  % Flow: k
    elseif chapter == 8
        nprops = 1;  % Transient: k or c
    elseif chapter == 9
        nprops = 2;  % Coupled: multiple properties
    elseif chapter == 10
        nprops = 2;  % Eigen: E, rho
    elseif chapter == 11
        nprops = 2;  % Parallel: E, rho
    else
        nprops = 2;  % Default
    end
end


function [nodes, meta] = generate_2d_nodes(vals, coord_start, nxe, nye, nod, dir, meta)
% Generate 2D node coordinates
    nodes = [];

    % Extract x_coords (nxe+1 values)
    x_coords = zeros(1, nxe + 1);
    for i = 1:(nxe + 1)
        idx = coord_start + i - 1;
        if idx <= numel(vals)
            x_coords(i) = to_num(vals{idx});
        end
    end

    % Extract y_coords (nye+1 values)
    y_coords = zeros(1, nye + 1);
    y_start = coord_start + nxe + 1;
    for i = 1:(nye + 1)
        idx = y_start + i - 1;
        if idx <= numel(vals)
            y_coords(i) = to_num(vals{idx});
        end
    end

    meta.x_coords = x_coords;
    meta.y_coords = y_coords;

    % Calculate node count using PFEM mesh_size formula
    if nod == 4
        meta.nn = (nxe + 1) * (nye + 1);
    elseif nod == 8
        meta.nn = (2*nxe + 1) * (nye + 1) + (nxe + 1) * nye;
    elseif nod == 9
        meta.nn = (2*nxe + 1) * (2*nye + 1);
    else
        meta.nn = (nxe + 1) * (nye + 1);
    end
    meta.nels = nxe * nye;

    % Generate fine grid positions
    x_fine = zeros(1, 2*nxe + 1);
    for i = 1:nxe
        x_fine(2*i - 1) = x_coords(i);
        x_fine(2*i) = (x_coords(i) + x_coords(i+1)) / 2;
    end
    x_fine(2*nxe + 1) = x_coords(nxe + 1);

    y_fine = zeros(1, 2*nye + 1);
    for i = 1:nye
        y_fine(2*i - 1) = y_coords(i);
        y_fine(2*i) = (y_coords(i) + y_coords(i+1)) / 2;
    end
    y_fine(2*nye + 1) = y_coords(nye + 1);

    % Generate nodes based on element type and direction
    nodes = zeros(meta.nn, 2);
    node_idx = 1;
    dir_clean = lower(strrep(char(dir), '''', ''));

    if nod == 4
        if dir_clean == 'x'
            for j = 1:(nye+1)
                for i = 1:(nxe+1)
                    nodes(node_idx, :) = [x_coords(i), y_coords(j)];
                    node_idx = node_idx + 1;
                end
            end
        else
            for i = 1:(nxe+1)
                for j = 1:(nye+1)
                    nodes(node_idx, :) = [x_coords(i), y_coords(j)];
                    node_idx = node_idx + 1;
                end
            end
        end

    elseif nod == 8
        if dir_clean == 'x'
            for j = 1:(2*nye+1)
                if mod(j, 2) == 1
                    for i = 1:(2*nxe+1)
                        nodes(node_idx, :) = [x_fine(i), y_fine(j)];
                        node_idx = node_idx + 1;
                    end
                else
                    for i = 1:(nxe+1)
                        nodes(node_idx, :) = [x_coords(i), y_fine(j)];
                        node_idx = node_idx + 1;
                    end
                end
            end
        else
            for i = 1:(2*nxe+1)
                if mod(i, 2) == 1
                    for j = 1:(2*nye+1)
                        nodes(node_idx, :) = [x_fine(i), y_fine(j)];
                        node_idx = node_idx + 1;
                    end
                else
                    for j = 1:(nye+1)
                        nodes(node_idx, :) = [x_fine(i), y_coords(j)];
                        node_idx = node_idx + 1;
                    end
                end
            end
        end

    elseif nod == 9
        if dir_clean == 'x'
            for j = 1:(2*nye+1)
                for i = 1:(2*nxe+1)
                    nodes(node_idx, :) = [x_fine(i), y_fine(j)];
                    node_idx = node_idx + 1;
                end
            end
        else
            for i = 1:(2*nxe+1)
                for j = 1:(2*nye+1)
                    nodes(node_idx, :) = [x_fine(i), y_fine(j)];
                    node_idx = node_idx + 1;
                end
            end
        end
    end
end


function [nodes, meta] = generate_3d_nodes(vals, coord_start, nxe, nye, nze, nod, meta)
% Generate 3D node coordinates
    nodes = [];

    % For 3D, coordinates may be ordered differently
    % p53: z_coords, x_coords, y_coords (from the dat file)
    % Each has size based on nze+1, nxe+1, nye+1

    z_coords = zeros(1, nze + 1);
    x_coords = zeros(1, nxe + 1);
    y_coords = zeros(1, nye + 1);

    idx = coord_start;

    % Read z_coords first
    for i = 1:(nze + 1)
        if idx <= numel(vals)
            z_coords(i) = to_num(vals{idx});
            idx = idx + 1;
        end
    end

    % Read x_coords
    for i = 1:(nxe + 1)
        if idx <= numel(vals)
            x_coords(i) = to_num(vals{idx});
            idx = idx + 1;
        end
    end

    % Read y_coords
    for i = 1:(nye + 1)
        if idx <= numel(vals)
            y_coords(i) = to_num(vals{idx});
            idx = idx + 1;
        end
    end

    meta.x_coords = x_coords;
    meta.y_coords = y_coords;
    meta.z_coords = z_coords;

    % Calculate 3D node count (simplified - assumes 8-node hex or 20-node hex)
    if nod == 8
        meta.nn = (nxe + 1) * (nye + 1) * (nze + 1);
    elseif nod == 20
        meta.nn = ((2*nxe+1)*(nze+1)+(nxe+1)*nze)*(nye+1) + (nxe+1)*(nze+1)*nye;
    else
        meta.nn = (nxe + 1) * (nye + 1) * (nze + 1);
    end
    meta.nels = nxe * nye * nze;

    % Generate 3D coordinates
    nodes = zeros(meta.nn, 3);
    node_idx = 1;

    if nod == 8
        for k = 1:(nze + 1)
            for j = 1:(nye + 1)
                for i = 1:(nxe + 1)
                    nodes(node_idx, :) = [x_coords(i), y_coords(j), z_coords(k)];
                    node_idx = node_idx + 1;
                end
            end
        end
    else
        % For other element types, generate basic grid
        for k = 1:(nze + 1)
            for j = 1:(nye + 1)
                for i = 1:(nxe + 1)
                    if node_idx <= meta.nn
                        nodes(node_idx, :) = [x_coords(i), y_coords(j), z_coords(k)];
                        node_idx = node_idx + 1;
                    end
                end
            end
        end
    end
end


function [nodes, elem_conn, meta] = parse_explicit_mesh(vals, yaml, meta)
% Parse explicit mesh (p54, p42, p44, p45, p74, p75, p88, p610)
    nodes = [];
    elem_conn = [];

    first_read = get_first_read(yaml);
    if isempty(first_read)
        return;
    end

    % Detect header format for explicit mesh
    if contains(first_read, 'nels') && contains(first_read, 'nn')
        % p54 style: element, nod, nels, nn, nip, nodof, nst, ndim, np_types
        nod = to_num(vals{2});
        nels = to_num(vals{3});
        nn = to_num(vals{4});
        ndim = to_num(vals{8});
        np_types = to_num(vals{9});
        header_tokens = 9;
        nprops = 3;
    elseif contains(first_read, 'nod') && contains(first_read, 'nxe')
        % Explicit with nxe format (varies)
        nod = to_num(vals{1});
        nels = to_num(vals{2});  % nxe actually
        nn = to_num(vals{3});
        ndim = 2;
        np_types = to_num(vals{5});
        header_tokens = 5;
        nprops = 2;
    else
        % Try generic parsing
        nod = to_num(vals{2});
        nels = to_num(vals{3});
        nn = to_num(vals{4});
        ndim = 2;
        np_types = 1;
        header_tokens = 9;
        nprops = 3;
    end

    meta.nod = nod;
    meta.nels = nels;
    meta.nn = nn;
    meta.ndim = ndim;

    prop_count = nprops * np_types;
    g_coord_start = header_tokens + prop_count + 1;

    % Read g_coord: nn * ndim values
    nodes = zeros(nn, ndim);
    for i = 1:nn
        for d = 1:ndim
            idx = g_coord_start + (i - 1) * ndim + (d - 1);
            if idx <= numel(vals)
                nodes(i, d) = to_num(vals{idx});
            end
        end
    end

    % Read g_num
    g_num_start = g_coord_start + nn * ndim;
    elem_conn = zeros(nels, nod);
    for e = 1:nels
        for n = 1:nod
            idx = g_num_start + (e - 1) * nod + (n - 1);
            if idx <= numel(vals)
                elem_conn(e, n) = to_num(vals{idx});
            end
        end
    end
end


function [nodes, elem_conn, meta] = parse_1d_mesh(vals, yaml, meta)
% Parse 1D mesh using element lengths
    nodes = [];
    elem_conn = [];

    first_read = get_first_read(yaml);
    if isempty(first_read)
        return;
    end

    % 1D format: nels, np_types; prop; etype (optional); ell
    nels = to_num(vals{1});
    np_types = to_num(vals{2});
    nn = nels + 1;

    meta.nels = nels;
    meta.nn = nn;
    meta.nod = 2;
    meta.ndim = 1;

    nprops = 1;
    prop_count = nprops * np_types;

    % ell starts after header + prop + possible etype
    ell_start = 3 + prop_count;
    if np_types > 1
        ell_start = ell_start + nels;  % etype array
    end

    % Extract element lengths
    ell = zeros(1, nels);
    for i = 1:nels
        idx = ell_start + i - 1;
        if idx <= numel(vals)
            ell(i) = to_num(vals{idx});
        end
    end

    % Generate node positions (cumulative lengths)
    nodes = zeros(nn, 1);
    nodes(1) = 0;
    for i = 1:nels
        nodes(i + 1) = nodes(i) + ell(i);
    end

    meta.ell = ell;

    % Generate simple connectivity
    elem_conn = zeros(nels, 2);
    for e = 1:nels
        elem_conn(e, :) = [e, e + 1];
    end
end


% ==================== HELPER FUNCTIONS ====================

function first_read = get_first_read(yaml)
% Get first READ statement from YAML
    first_read = '';
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        reads = yaml.code.io_reads_from_unit10;
        if numel(reads) > 0 && isfield(reads{1}, 'stmt')
            first_read = reads{1}.stmt;
        end
    end
end


function vals = tokens_to_values(tokens)
% Convert cell array of tokens to cell array preserving types
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
% Convert to number
    if isnumeric(x)
        v = x;
    elseif ischar(x)
        v = str2double(x);
        if isnan(v)
            v = 0;
        end
    else
        v = 0;
    end
end


function has = has_g_coord_read(yaml)
% Check if YAML has g_coord READ statement
    has = false;
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        reads = yaml.code.io_reads_from_unit10;
        for i = 1:numel(reads)
            if isfield(reads{i}, 'stmt') && contains(reads{i}.stmt, 'g_coord')
                has = true;
                return;
            end
        end
    end
end


function has = has_x_y_coords_read(yaml)
% Check if YAML has x_coords/y_coords READ statement
    has = false;
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        reads = yaml.code.io_reads_from_unit10;
        for i = 1:numel(reads)
            if isfield(reads{i}, 'stmt')
                if contains(reads{i}.stmt, 'x_coords') || contains(reads{i}.stmt, 'y_coords')
                    has = true;
                    return;
                end
            end
        end
    end
end


function has = has_ell_read(yaml)
% Check if YAML has ell READ statement (1D element lengths)
    has = false;
    if isfield(yaml, 'code') && isfield(yaml.code, 'io_reads_from_unit10')
        reads = yaml.code.io_reads_from_unit10;
        for i = 1:numel(reads)
            if isfield(reads{i}, 'stmt') && contains(reads{i}.stmt, 'ell')
                has = true;
                return;
            end
        end
    end
end
