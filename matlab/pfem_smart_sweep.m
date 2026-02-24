function results = pfem_smart_sweep(yaml_path, param_name, values, varargin)
% PFEM_SMART_SWEEP  Run parameter sweep with automatic tunable discovery
%
% Usage:
%   % First, see what's available:
%   pfem_show_tunables('benchmarks/pfem5/chap04/p41_2.yaml')
%
%   % Then sweep any tunable by name:
%   results = pfem_smart_sweep(yaml_path, 'nels_or_nxe', [4, 8, 16]);
%
%   % Or use 'auto' to sweep the first numeric tunable with suggested range:
%   results = pfem_smart_sweep(yaml_path, 'auto', 5);  % 5 points in range
%
% Arguments:
%   yaml_path  - Path to YAML file (relative to repo root or absolute)
%   param_name - Name of tunable parameter, or 'auto'
%   values     - Array of values to sweep, or number of points for 'auto'
%
% Optional:
%   'pfem_root' - PFEM installation path (default: <repo>/pfem)
%
% Returns:
%   results - Struct array with .param_value, .status, .run_dir, .files

    % Setup paths
    repo_root = fileparts(fileparts(mfilename('fullpath')));

    % Parse inputs
    p = inputParser;
    addParameter(p, 'pfem_root', fullfile(repo_root, 'pfem'));
    parse(p, varargin{:});
    pfem_root = p.Results.pfem_root;

    addpath(fullfile(repo_root, 'matlab'));
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
    tp = y.tunable_parameters;

    if isempty(tp)
        error('No tunable parameters found in %s', yaml_path);
    end

    % Handle 'auto' mode
    if strcmpi(param_name, 'auto')
        % Find first tunable with suggested_range
        found = false;
        for i = 1:numel(tp)
            if isfield(tp{i}, 'suggested_range') && ~isempty(tp{i}.suggested_range)
                param_name = tp{i}.name;
                range = tp{i}.suggested_range;
                n_points = values;  % In auto mode, 'values' is number of points
                values = linspace(range{1}, range{2}, n_points);
                fprintf('Auto-selected: %s with range [%.2e, %.2e]\n', param_name, range{1}, range{2});
                found = true;
                break;
            end
        end
        if ~found
            % Fall back to first tunable
            param_name = tp{1}.name;
            current = str2double(tp{1}.current_value);
            if isnan(current), current = 1; end
            values = current * [0.5, 1.0, 2.0];  % Default: 0.5x, 1x, 2x
            fprintf('Auto-selected: %s (no range, using 0.5x, 1x, 2x of current)\n', param_name);
        end
    end

    % Verify parameter exists
    param_exists = false;
    for i = 1:numel(tp)
        if strcmp(tp{i}.name, param_name)
            param_exists = true;
            break;
        end
    end

    if ~param_exists
        fprintf('\nError: Parameter "%s" not found!\n', param_name);
        fprintf('Available parameters:\n');
        for i = 1:numel(tp)
            fprintf('  - %s\n', tp{i}.name);
        end
        error('Invalid parameter name');
    end

    % Run sweep
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('Sweep: %s over %d values\n', param_name, numel(values));
    fprintf('Case: %s (program %s)\n', y.authors.source.dataset, y.authors.source.program);
    fprintf('============================================================\n\n');

    results = struct('param_value', {}, 'status', {}, 'run_dir', {}, 'files', {});

    for i = 1:numel(values)
        val = values(i);

        fprintf('[%d/%d] %s = ', i, numel(values), param_name);
        if abs(val) > 1000 || abs(val) < 0.01
            fprintf('%.3e', val);
        else
            fprintf('%.4f', val);
        end
        fprintf(' ... ');

        % Build overrides
        overrides = struct();
        overrides.(param_name) = val;

        % Run
        try
            [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);

            results(i).param_value = val;
            results(i).status = status;
            results(i).run_dir = out.work_dir;
            results(i).files = out.files;

            if status == 0
                fprintf('✓ Success (%d files)\n', out.num_files);
            else
                fprintf('✗ Failed (status %d)\n', status);
            end
        catch ME
            results(i).param_value = val;
            results(i).status = -1;
            results(i).run_dir = '';
            results(i).files = {};
            fprintf('✗ Error: %s\n', ME.message);
        end
    end

    % Summary
    fprintf('\n');
    fprintf('============================================================\n');
    success_count = sum([results.status] == 0);
    fprintf('Complete: %d/%d successful\n', success_count, numel(values));
    fprintf('============================================================\n');
end
