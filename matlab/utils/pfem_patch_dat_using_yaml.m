function pfem_patch_dat_using_yaml(dat_path, y, overrides)
% PFEM_PATCH_DAT_USING_YAML  Generic token-based .dat file patcher
%
% This function patches a PFEM .dat file using token-based coordinates
% from the YAML file. It replaces specific tokens by their global index.
%
% Usage:
%   pfem_patch_dat_using_yaml(dat_path, yaml_struct, overrides)
%
% Arguments:
%   dat_path   - Path to the .dat file to modify (will be overwritten)
%   y          - YAML struct loaded by pfem_yaml_load
%   overrides  - Struct with field names matching tunable_parameters names
%
% Example:
%   overrides.youngs_modulus_E = 2e6;
%   overrides.poisson_ratio_nu = 0.25;
%   pfem_patch_dat_using_yaml('case.dat', yaml_struct, overrides);
%
% The function uses global_token_index from tunable_parameters to locate
% and replace tokens. This approach is generic across all PFEM chapters.

    if isempty(overrides) || isempty(fieldnames(overrides))
        return;  % Nothing to patch
    end

    % Build map: tunable name -> global_token_index
    tp = y.tunable_parameters;
    tunable_map = containers.Map();
    for i = 1:numel(tp)
        name = tp{i}.name;
        idx = tp{i}.global_token_index;
        tunable_map(name) = idx;
    end

    % Tokenize the file
    [tokens, token_positions, lines] = tokenize_dat(dat_path);

    % Apply overrides
    override_names = fieldnames(overrides);
    for i = 1:numel(override_names)
        name = override_names{i};

        if ~isKey(tunable_map, name)
            % Silently skip — expected for cross-case sweeps where not all
            % parameters apply to every YAML (e.g. yield_stress not in p63).
            continue;
        end

        token_idx = tunable_map(name);

        if token_idx < 1 || token_idx > numel(tokens)
            error('pfem_patch:invalid_index', ...
                'Token index %d for "%s" is out of range (1-%d).', ...
                token_idx, name, numel(tokens));
        end

        new_val = overrides.(name);
        if isnumeric(new_val)
            tokens{token_idx} = num2str(new_val, '%.12g');
        else
            tokens{token_idx} = char(new_val);
        end
    end

    % Rebuild and write the file
    rebuild_dat(dat_path, tokens, token_positions, lines);

    % ── Topology post-patch ────────────────────────────────────────────────
    % If nxe or nye changed, the coordinate arrays (x_coords / y_coords) in
    % the .dat file now have the wrong number of tokens.  Regenerate them
    % from the original domain bounds preserved in the YAML all_tokens.
    new_nxe = []; new_nye = [];
    if isKey(tunable_map, 'nels_or_nxe')   && isfield(overrides, 'nels_or_nxe')
        new_nxe = round(overrides.nels_or_nxe);
    end
    if isKey(tunable_map, 'np_types_or_nye') && isfield(overrides, 'np_types_or_nye')
        new_nye = round(overrides.np_types_or_nye);
    end

    if ~isempty(new_nxe) || ~isempty(new_nye)
        regen_structured_coords(dat_path, y, new_nxe, new_nye);
    end
end


function regen_structured_coords(dat_path, y, new_nxe, new_nye)
% Regenerate x_coords / y_coords lines in the .dat file after nxe or nye
% has been patched.  Reads domain bounds from the YAML all_tokens, then
% rewrites the coordinate lines in the .dat file.
%
% Approach:
%   1. Extract original nxe, nye and domain bounds from YAML all_tokens.
%   2. Determine the line range of x_coords / y_coords in the .dat file
%      using tokenize_dat + token-position lookup.
%   3. Replace those lines with new uniform coordinate values.

    if ~isfield(y,'inputs') || ~isfield(y.inputs,'all_tokens')
        return;
    end

    % ---- Step 1: reproduce header detection on YAML tokens ---------------
    tokens_yaml = y.inputs.all_tokens;
    vals = cell(size(tokens_yaml));
    for i = 1:numel(tokens_yaml)
        t = tokens_yaml{i};
        if isnumeric(t),  vals{i} = t;
        elseif ischar(t), vals{i} = strrep(t,'''','');
        else,             vals{i} = t;
        end
    end

    program = '';
    chapter = 0;
    if isfield(y,'code') && isfield(y.code,'source_file')
        src = y.code.source_file;
        [~,prog_name,~] = fileparts(src);
        program = prog_name;
        ch_m = regexp(src,'chap(\d+)','tokens');
        if ~isempty(ch_m), chapter = str2double(ch_m{1}{1}); end
    end

    first_read = '';
    if isfield(y,'code') && isfield(y.code,'io_reads_from_unit10')
        reads = y.code.io_reads_from_unit10;
        if numel(reads) > 0 && isfield(reads{1},'stmt')
            first_read = reads{1}.stmt;
        end
    end

    [nxe_orig, nye_orig, nze, ~, ~, np_types, header_tokens] = ...
        detect_header_format_simple(first_read, vals, program, chapter);

    if isempty(nxe_orig) || isempty(nye_orig)
        return;  % Cannot determine header format — skip
    end

    % Decide final new_nxe / new_nye
    if isempty(new_nxe), new_nxe = nxe_orig; end
    if isempty(new_nye), new_nye = nye_orig;  end
    if new_nxe == nxe_orig && new_nye == nye_orig
        return;  % No change needed
    end

    % nprops (hardcoded per chapter, same as pfem_extract_coords.get_nprops)
    nprops = get_nprops_local(program, chapter);
    prop_count = nprops * np_types;
    coord_start = header_tokens + prop_count + 1;  % 1-based token index

    if np_types > 1
        coord_start = coord_start + nxe_orig * nye_orig;
    end

    % ---- Step 2: read original domain bounds from YAML tokens ------------
    x_start_idx = coord_start;
    y_start_idx = coord_start + nxe_orig + 1;

    if x_start_idx < 1 || y_start_idx + nye_orig > numel(vals)
        return;  % Token positions out of range
    end

    x_min = to_num_local(vals{x_start_idx});
    x_max = to_num_local(vals{x_start_idx + nxe_orig});
    y_min = to_num_local(vals{y_start_idx});
    y_max = to_num_local(vals{y_start_idx + nye_orig});

    new_x = linspace(x_min, x_max, new_nxe + 1);
    new_y = linspace(y_min, y_max, new_nye + 1);

    % ---- Step 3: find the lines in the .dat file -------------------------
    [~, tok_pos, dat_lines] = tokenize_dat(dat_path);

    % Identify which dat-file tokens correspond to x_coords and y_coords.
    % The .dat file was just patched, so its token count equals the YAML's
    % all_tokens count (we only changed scalar values, not array sizes yet).
    if coord_start > numel(tok_pos) || ...
       coord_start + nxe_orig + 1 + nye_orig > numel(tok_pos)
        return;
    end

    x_line_first = tok_pos(x_start_idx, 1);
    x_line_last  = tok_pos(x_start_idx + nxe_orig, 1);
    y_line_first = tok_pos(y_start_idx, 1);
    y_line_last  = tok_pos(y_start_idx + nye_orig, 1);

    % ---- Step 4: build replacement lines ---------------------------------
    x_line_new = strjoin(arrayfun(@(v) sprintf('%.10g',v), new_x, 'UniformOutput',false), '  ');
    y_line_new = strjoin(arrayfun(@(v) sprintf('%.10g',v), new_y, 'UniformOutput',false), '  ');

    % Replace x_coords lines (x_line_first..x_line_last) with one new line
    new_lines = [dat_lines(1:x_line_first-1); {x_line_new}; ...
                 dat_lines(x_line_last+1:y_line_first-1); {y_line_new}; ...
                 dat_lines(y_line_last+1:end)];

    % ---- Step 5: write ---------------------------------------------------
    fid = fopen(dat_path, 'w');
    if fid == -1, return; end
    for i = 1:numel(new_lines)
        fprintf(fid, '%s\n', new_lines{i});
    end
    fclose(fid);
end


% ── Local helpers (avoid dependency on pfem_extract_coords internals) ─────

function [nxe,nye,nze,nod,dir,np_types,htok] = detect_header_format_simple(first_read,vals,~,~)
% Minimal copy of detect_header_format for use inside the patcher.
    nxe=[]; nye=[]; nze=[]; nod=4; dir='x'; np_types=1; htok=0;
    if isempty(first_read), return; end

    if contains(first_read,'type_2d') && contains(first_read,'element') && contains(first_read,'nod')
        nod=to_num_local(vals{3}); dir=vals{4};
        nxe=to_num_local(vals{5}); nye=to_num_local(vals{6});
        np_types=to_num_local(vals{8}); htok=8;
    elseif contains(first_read,'type_2d') && contains(first_read,'dir') && ~contains(first_read,'element')
        dir=vals{2};
        nxe=to_num_local(vals{3}); nye=to_num_local(vals{4});
        np_types=to_num_local(vals{5}); nod=4; htok=5;
    elseif contains(first_read,'nxe') && contains(first_read,'nye') && contains(first_read,'nod') && contains(first_read,'np_types')
        nxe=to_num_local(vals{1}); nye=to_num_local(vals{2});
        nod=to_num_local(vals{3}); np_types=to_num_local(vals{4}); htok=4;
    elseif contains(first_read,'nxe') && contains(first_read,'nye') && contains(first_read,'np_types') && ~contains(first_read,'nod')
        nxe=to_num_local(vals{1}); nye=to_num_local(vals{2});
        np_types=to_num_local(vals{3}); nod=8; dir='y'; htok=3;
    elseif contains(first_read,'nod') && contains(first_read,'nxe') && contains(first_read,'nye') && contains(first_read,'nze')
        nod=to_num_local(vals{1});
        nxe=to_num_local(vals{2}); nye=to_num_local(vals{3}); nze=to_num_local(vals{4});
        np_types=to_num_local(vals{6}); htok=6;
    end
end

function n = get_nprops_local(program, chapter)
    if chapter==4,      n=1;
    elseif chapter==5,  n=2;
    elseif chapter==6,  n=3;  % most p6x: E, nu, yield_stress
    elseif chapter==7,  n=1;
    elseif chapter==8,  n=1;
    elseif chapter==9,  n=2;
    elseif chapter==10, n=2;
    elseif chapter==11, n=2;
    else,               n=2;
    end
    % Honour any program-specific overrides
    if startsWith(program,'p61') || startsWith(program,'p62') || ...
       startsWith(program,'p63') || startsWith(program,'p64') || ...
       startsWith(program,'p65') || startsWith(program,'p66') || ...
       startsWith(program,'p67') || startsWith(program,'p68')
        n=3;
    end
end

function v = to_num_local(x)
    if isnumeric(x),  v=x;
    elseif ischar(x), v=str2double(x); if isnan(v), v=0; end
    else,             v=0;
    end
end


function [tokens, token_positions, lines] = tokenize_dat(dat_path)
% Tokenize a .dat file into flat token list with position tracking
%
% Returns:
%   tokens          - Cell array of token strings
%   token_positions - Nx2 array: [line_num, token_in_line] (1-based)
%   lines           - Cell array of original lines

    fid = fopen(dat_path, 'r');
    if fid == -1
        error('Cannot open file: %s', dat_path);
    end

    tokens = {};
    token_positions = [];
    lines = {};

    line_num = 0;
    while ~feof(fid)
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        line_num = line_num + 1;
        lines{line_num} = line;

        % Remove comments (Fortran style: !)
        excl_pos = strfind(line, '!');
        if ~isempty(excl_pos)
            line = line(1:excl_pos(1)-1);
        end

        clean_line = strtrim(line);
        if isempty(clean_line)
            continue;
        end

        % Tokenize: handle quoted strings and regular tokens
        line_tokens = regexp(clean_line, '''[^'']*''|[^\s]+', 'match');

        for tok_in_line = 1:numel(line_tokens)
            tokens{end+1} = line_tokens{tok_in_line}; %#ok<AGROW>
            token_positions(end+1, :) = [line_num, tok_in_line]; %#ok<AGROW>
        end
    end

    fclose(fid);
end


function rebuild_dat(dat_path, tokens, token_positions, lines)
% Rebuild .dat file from tokens, preserving line structure
%
% This reconstructs the file by replacing tokens in their original
% line positions while maintaining formatting.

    % Group tokens by line
    n_lines = numel(lines);
    tokens_per_line = cell(n_lines, 1);
    for i = 1:n_lines
        tokens_per_line{i} = {};
    end

    for t = 1:numel(tokens)
        line_num = token_positions(t, 1);
        tokens_per_line{line_num}{end+1} = tokens{t};
    end

    % Rebuild lines
    new_lines = cell(n_lines, 1);
    for i = 1:n_lines
        if isempty(tokens_per_line{i})
            % Preserve empty lines and comments
            new_lines{i} = lines{i};
        else
            % Reconstruct with spaces between tokens
            new_lines{i} = strjoin(tokens_per_line{i}, '  ');
        end
    end

    % Write file
    fid = fopen(dat_path, 'w');
    if fid == -1
        error('Cannot write file: %s', dat_path);
    end

    for i = 1:numel(new_lines)
        fprintf(fid, '%s\n', new_lines{i});
    end

    fclose(fid);
end
