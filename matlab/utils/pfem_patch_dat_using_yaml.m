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
            warning('pfem_patch:unknown_tunable', ...
                'Override "%s" not found in YAML tunable_parameters. Skipping.', name);
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
