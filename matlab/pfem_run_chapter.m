function results = pfem_run_chapter(repo_root, pfem_root, chapter, overrides_map)
% PFEM_RUN_CHAPTER  Run all benchmark cases for a chapter
%
% Usage:
%   results = pfem_run_chapter(repo_root, pfem_root, chapter)
%   results = pfem_run_chapter(repo_root, pfem_root, chapter, overrides_map)
%
% Arguments:
%   repo_root     - Path to fem-benchmarks repository
%   pfem_root     - Path to PFEM source (e.g., ~/Downloads/pfem5/5th_ed)
%   chapter       - Chapter name (e.g., 'chap04', 'chap05')
%   overrides_map - (Optional) containers.Map with case_name -> override_struct
%
% Returns:
%   results - Struct array with fields:
%             .case      - Case name
%             .yaml_file - Path to YAML file
%             .status    - 0=success, non-zero=failure
%             .outputs   - Output struct from pfem_runner
%             .error     - Error message if failed
%
% Example:
%   % Run all chap05 cases with no overrides
%   results = pfem_run_chapter('~/projects/fem-benchmarks', ...
%                              '~/Downloads/pfem5/5th_ed', 'chap05');
%
%   % Run with specific overrides for some cases
%   overrides_map = containers.Map();
%   overrides_map('p51_3') = struct('youngs_modulus_E', 2e6);
%   results = pfem_run_chapter(repo_root, pfem_root, 'chap05', overrides_map);

    % Expand paths
    if startsWith(repo_root, '~')
        repo_root = replace(repo_root, '~', getenv('HOME'));
    end
    if startsWith(pfem_root, '~')
        pfem_root = replace(pfem_root, '~', getenv('HOME'));
    end

    % Default empty overrides
    if nargin < 4
        overrides_map = containers.Map();
    end

    % Find all YAML files for this chapter
    yaml_dir = fullfile(repo_root, 'benchmarks', 'pfem5', chapter);
    yaml_files = dir(fullfile(yaml_dir, '*.yaml'));

    if isempty(yaml_files)
        warning('No YAML files found in %s', yaml_dir);
        results = [];
        return;
    end

    fprintf('============================================================\n');
    fprintf('Running %s: %d cases\n', chapter, numel(yaml_files));
    fprintf('============================================================\n\n');

    results = struct('case', {}, 'yaml_file', {}, 'status', {}, 'outputs', {}, 'error', {});

    success_count = 0;
    fail_count = 0;

    for i = 1:numel(yaml_files)
        yaml_path = fullfile(yaml_files(i).folder, yaml_files(i).name);
        [~, case_name, ~] = fileparts(yaml_files(i).name);

        fprintf('[%d/%d] %s\n', i, numel(yaml_files), case_name);

        % Get overrides for this case (if any)
        if isKey(overrides_map, case_name)
            overrides = overrides_map(case_name);
        else
            overrides = struct();
        end

        % Run the case
        try
            [status, outputs] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);

            results(end+1).case = case_name; %#ok<AGROW>
            results(end).yaml_file = yaml_path;
            results(end).status = status;
            results(end).outputs = outputs;
            results(end).error = '';

            if status == 0
                success_count = success_count + 1;
                fprintf('  ✓ Success (%d output files)\n', outputs.num_files);
            else
                fail_count = fail_count + 1;
                fprintf('  ✗ Failed (status %d)\n', status);
            end

        catch ME
            results(end+1).case = case_name; %#ok<AGROW>
            results(end).yaml_file = yaml_path;
            results(end).status = -1;
            results(end).outputs = struct();
            results(end).error = ME.message;

            fail_count = fail_count + 1;
            fprintf('  ✗ Error: %s\n', ME.message);
        end

        fprintf('\n');
    end

    fprintf('============================================================\n');
    fprintf('Summary: %d/%d passed, %d failed\n', success_count, numel(yaml_files), fail_count);
    fprintf('============================================================\n');
end
