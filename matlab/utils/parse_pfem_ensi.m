function [nodes, conn, displ_steps, srf_vals, matid] = parse_pfem_ensi(case_path)
% PARSE_PFEM_ENSI  Parse EnSight Gold output from PFEM 3D programs.
%
% Reads the .ensi.case manifest and the referenced geometry / displacement
% files produced by PFEM programs such as p612 and p613.
%
% Returns:
%   nodes       — (n_nodes × 3)  node coordinates  [x, y, z]
%   conn        — (n_elem  × 8)  corner-node connectivity (hexa20→8 corners)
%   displ_steps — cell(n_steps,1), each entry (n_nodes × 3) [ux, uy, uz]
%   srf_vals    — (n_steps × 1)  time/SRF values from .case file
%   matid       — (n_elem  × 1)  integer material zone ID per element ([] if absent)
%
% Usage:
%   [nodes, conn, displ, srfs, matid] = parse_pfem_ensi('path/to/p612.ensi.case');

    nodes = []; conn = []; displ_steps = {}; srf_vals = []; matid = [];
    if ~exist(case_path, 'file'), return; end

    case_dir = fileparts(case_path);

    % ── Read .case manifest ───────────────────────────────────────────────
    fid = fopen(case_path, 'r');
    if fid == -1, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    geo_file      = '';
    displ_pattern = '';
    matid_file    = '';
    n_steps       = 0;

    for i = 1:numel(lines)
        ln = strtrim(lines{i});

        % geometry file: "model: 1  p612.ensi.geo"
        tok = regexp(ln, '^model:\s+\d+\s+(\S+)', 'tokens');
        if ~isempty(tok)
            geo_file = fullfile(case_dir, tok{1}{1});
            continue;
        end

        % displacement pattern: "vector per node:  displacement  p612.ensi.displ-*****"
        tok = regexp(ln, 'displacement\s+(\S+)', 'tokens');
        if ~isempty(tok)
            displ_pattern = tok{1}{1};
            continue;
        end

        % material ID: "scalar per element:  material  p612.ensi.matid"
        tok = regexp(ln, 'scalar per element:.*material\s+(\S+)', 'tokens');
        if ~isempty(tok)
            matid_file = fullfile(case_dir, tok{1}{1});
            continue;
        end

        % step count
        tok = regexp(ln, '^number of steps:\s*(\d+)', 'tokens');
        if ~isempty(tok)
            n_steps = str2double(tok{1}{1});
            continue;
        end

        % time values (one or more lines after "time values:")
        if strcmp(ln, 'time values:')
            vals = [];
            for j = i+1 : numel(lines)
                ln2 = strtrim(lines{j});
                if isempty(ln2), break; end
                v = sscanf(ln2, '%f');
                if isempty(v), break; end
                vals = [vals; v(:)]; %#ok<AGROW>
            end
            srf_vals = vals;
        end
    end

    if isempty(geo_file) || ~exist(geo_file, 'file'), return; end
    if n_steps == 0 && ~isempty(srf_vals), n_steps = numel(srf_vals); end

    % ── Parse geometry ────────────────────────────────────────────────────
    [nodes, conn] = parse_geo(geo_file);
    if isempty(nodes), return; end
    n_nodes = size(nodes, 1);
    n_elem  = size(conn,  1);

    % ── Parse displacement files ──────────────────────────────────────────
    displ_steps = cell(n_steps, 1);
    for s = 1:n_steps
        fname = strrep(displ_pattern, '*****', sprintf('%05d', s));
        fpath = fullfile(case_dir, fname);
        if exist(fpath, 'file')
            displ_steps{s} = parse_displ(fpath, n_nodes);
        end
    end

    % ── Parse material ID (per-element scalar) ────────────────────────────
    if ~isempty(matid_file) && exist(matid_file, 'file') && n_elem > 0
        matid = parse_scalar_elem(matid_file, n_elem);
    end
end


% ============================================================
function [nodes, conn] = parse_geo(geo_path)
% Parse EnSight Gold geometry file.
% PFEM stores all x-coords, then all y-coords, then all z-coords (column order).
% Elements: hexa20 with 20 nodes per line; only first 8 (corner nodes) kept.

    nodes = []; conn = [];

    fid = fopen(geo_path, 'r');
    if fid == -1, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    % Locate "coordinates" keyword
    coord_line = 0;
    for i = 1:numel(lines)
        if strcmp(strtrim(lines{i}), 'coordinates')
            coord_line = i; break;
        end
    end
    if coord_line == 0, return; end

    n_nodes = str2double(strtrim(lines{coord_line + 1}));
    base    = coord_line + 2;                              % first x-coord line

    % Coordinates stored column-major: x block, y block, z block
    if base + 3*n_nodes - 1 > numel(lines), return; end
    x = cellfun(@str2double, lines(base              : base +   n_nodes - 1));
    y = cellfun(@str2double, lines(base +   n_nodes  : base + 2*n_nodes - 1));
    z = cellfun(@str2double, lines(base + 2*n_nodes  : base + 3*n_nodes - 1));
    nodes = [x(:), y(:), z(:)];

    % Locate element block (hexa20 / hexa8)
    elem_line = 0;
    for i = base + 3*n_nodes : numel(lines)
        ln = strtrim(lines{i});
        if strncmpi(ln, 'hexa', 4) || strncmpi(ln, 'quad', 4) || strncmpi(ln, 'tet', 3)
            elem_line = i; break;
        end
    end
    if elem_line == 0, return; end

    n_elem = str2double(strtrim(lines{elem_line + 1}));
    if isnan(n_elem) || n_elem < 1, return; end

    conn = zeros(n_elem, 8);
    for e = 1:n_elem
        li = elem_line + 1 + e;
        if li > numel(lines), break; end
        v = sscanf(lines{li}, '%d');
        nc = min(8, numel(v));            % take only corner nodes
        conn(e, 1:nc) = v(1:nc)';
    end
end


% ============================================================
function vals = parse_scalar_elem(fpath, n_elem)
% Parse EnSight Gold per-element scalar file (e.g. matid).
% Layout: description, "part", part_no, element_type, then n_elem values.
    vals = zeros(n_elem, 1);
    fid = fopen(fpath, 'r');
    if fid == -1, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};
    base = 5;   % skip: description, "part", "      1", element_type
    if numel(lines) < base + n_elem - 1, return; end
    vals = cellfun(@str2double, lines(base : base + n_elem - 1));
end


% ============================================================
function displ = parse_displ(displ_path, n_nodes)
% Parse one EnSight Gold per-node vector file.
% Layout: 4 header lines, then all ux, then all uy, then all uz.

    displ = zeros(n_nodes, 3);

    fid = fopen(displ_path, 'r');
    if fid == -1, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    base = 5;   % skip: description, "part", "      1", "coordinates"
    if numel(lines) < base + 3*n_nodes - 1, return; end

    displ(:,1) = cellfun(@str2double, lines(base             : base +   n_nodes - 1));
    displ(:,2) = cellfun(@str2double, lines(base +   n_nodes : base + 2*n_nodes - 1));
    displ(:,3) = cellfun(@str2double, lines(base + 2*n_nodes : base + 3*n_nodes - 1));
end
