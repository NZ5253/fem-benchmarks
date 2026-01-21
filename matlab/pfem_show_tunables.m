function tunables = pfem_show_tunables(yaml_path)
% PFEM_SHOW_TUNABLES  Display available tunable parameters for a YAML case
%
% Usage:
%   pfem_show_tunables('benchmarks/pfem5/chap04/p41_2.yaml')
%   tunables = pfem_show_tunables(yaml_path);
%
% Returns a struct array with tunable info

    repo_root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repo_root, 'matlab', 'utils'));

    % Handle relative paths
    if ~startsWith(yaml_path, '/') && ~startsWith(yaml_path, '~')
        yaml_path = fullfile(repo_root, yaml_path);
    end
    if startsWith(yaml_path, '~')
        yaml_path = replace(yaml_path, '~', getenv('HOME'));
    end

    % Load YAML
    y = pfem_yaml_load(yaml_path);

    % Display header
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('Tunable Parameters for: %s\n', y.authors.source.dataset);
    fprintf('Program: %s | Chapter: %d\n', y.authors.source.program, y.authors.source.chapter);
    fprintf('============================================================\n\n');

    tp = y.tunable_parameters;

    if isempty(tp)
        fprintf('No tunable parameters detected.\n');
        tunables = struct([]);
        return;
    end

    % Build output struct
    tunables = struct('name', {}, 'token', {}, 'current', {}, 'type', {}, 'range', {});

    fprintf('%-25s  %5s  %15s  %8s  %s\n', 'NAME', 'TOKEN', 'CURRENT', 'TYPE', 'SUGGESTED RANGE');
    fprintf('%s\n', repmat('-', 1, 80));

    for i = 1:numel(tp)
        t = tp{i};

        name = t.name;
        token = t.global_token_index;
        current = t.current_value;
        typ = t.type;

        if isfield(t, 'suggested_range') && ~isempty(t.suggested_range)
            range = t.suggested_range;
            range_str = sprintf('[%.2e, %.2e]', range{1}, range{2});
        else
            range = [];
            range_str = '-';
        end

        % Store in output
        tunables(i).name = name;
        tunables(i).token = token;
        tunables(i).current = current;
        tunables(i).type = typ;
        tunables(i).range = range;

        % Display
        if isnumeric(current)
            current_str = num2str(current);
        else
            current_str = char(current);
        end
        fprintf('%-25s  %5d  %15s  %8s  %s\n', name, token, current_str, typ, range_str);
    end

    fprintf('\n');
    fprintf('Usage example:\n');
    fprintf('  overrides = struct();\n');
    fprintf('  overrides.%s = <new_value>;\n', tp{1}.name);
    fprintf('  [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);\n');
    fprintf('\n');
end
