function results = pfem_parametric_sweep(pfem_root, chapter, program, base_case, param_ranges, output_dir)
% PFEM_PARAMETRIC_SWEEP Run parametric study by varying input parameters
%
% Performs a parameter sweep for a PFEM case by:
%   1. Loading the base dataset
%   2. Modifying specified parameters
%   3. Writing new .dat files
%   4. Running PFEM for each parameter combination
%   5. Collecting and organizing results
%
% Inputs:
%   pfem_root    - Path to PFEM root directory
%   chapter      - Chapter name (e.g., 'chap05')
%   program      - Program name (e.g., 'p51')
%   base_case    - Base dataset name (e.g., 'p51_3')
%   param_ranges - Struct defining parameter variations (see example below)
%   output_dir   - Directory to store sweep results (default: './runs/sweep_<timestamp>')
%
% Outputs:
%   results - Struct array containing results for each parameter combination
%
% Example param_ranges struct:
%   param_ranges.E = [1e5, 1e6, 1e7];      % Young's modulus values to test
%   param_ranges.nu = [0.2, 0.3, 0.4];     % Poisson's ratio values
%
% Example usage:
%   pfem_root = '~/Downloads/pfem5/5th_ed';
%   param_ranges.E = [1e5, 5e5, 1e6];
%   param_ranges.nu = [0.25, 0.30, 0.35];
%   results = pfem_parametric_sweep(pfem_root, 'chap05', 'p51', 'p51_3', param_ranges);
%
% Note: This is a template. The dat_modifier function needs to be customized
%       for each program based on its specific READ(10,*) format.
%
% Author: Generated for PFEM Benchmark Catalogue
% Date: 2026-01-09

    if nargin < 6
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        output_dir = fullfile('.', 'runs', ['sweep_' timestamp]);
    end

    % Create output directory
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    fprintf('=== PFEM Parametric Sweep ===\n');
    fprintf('Base case: %s/%s\n', chapter, base_case);
    fprintf('Output directory: %s\n\n', output_dir);

    % Expand pfem_root path
    if startsWith(pfem_root, '~')
        pfem_root = replace(pfem_root, '~', getenv('HOME'));
    end

    % Read base dataset
    base_dat = fullfile(pfem_root, 'executable', chapter, [base_case '.dat']);
    if ~exist(base_dat, 'file')
        error('Base dataset not found: %s', base_dat);
    end

    % Generate all parameter combinations
    param_names = fieldnames(param_ranges);
    num_params = length(param_names);

    % Build grid of all combinations
    param_grids = cell(1, num_params);
    for i = 1:num_params
        param_grids{i} = param_ranges.(param_names{i});
    end

    [grid_arrays{1:num_params}] = ndgrid(param_grids{:});

    % Flatten to list of combinations
    num_runs = numel(grid_arrays{1});
    param_combinations = zeros(num_runs, num_params);
    for i = 1:num_params
        param_combinations(:,i) = grid_arrays{i}(:);
    end

    fprintf('Total parameter combinations: %d\n', num_runs);
    fprintf('Parameters: %s\n\n', strjoin(param_names, ', '));

    % Initialize results
    results = struct();
    results.base_case = base_case;
    results.param_names = param_names;
    results.runs = cell(num_runs, 1);

    % Run each combination
    for run_idx = 1:num_runs
        fprintf('[%d/%d] ', run_idx, num_runs);

        % Current parameter values
        params_current = struct();
        for p = 1:num_params
            pname = param_names{p};
            params_current.(pname) = param_combinations(run_idx, p);
            fprintf('%s=%.3e ', pname, params_current.(pname));
        end
        fprintf('\n');

        % Create run-specific case name
        run_case = sprintf('%s_run%03d', base_case, run_idx);
        run_dir = fullfile(output_dir, run_case);
        if ~exist(run_dir, 'dir')
            mkdir(run_dir);
        end

        % Modify dataset with current parameters
        % NOTE: dat_modifier needs to be implemented for specific program format
        modified_dat = dat_modifier(base_dat, params_current, program);

        % Write modified .dat to run directory
        new_dat_path = fullfile(run_dir, [run_case '.dat']);
        write_dat_file(new_dat_path, modified_dat);

        % Copy modified .dat to PFEM executable directory for running
        pfem_run_dat = fullfile(pfem_root, 'executable', chapter, [run_case '.dat']);
        copyfile(new_dat_path, pfem_run_dat);

        % Run PFEM
        try
            [status, outputs] = pfem_runner(pfem_root, chapter, program, run_case);

            % Copy outputs to run directory
            if status == 0 && ~isempty(outputs.files)
                for f = 1:length(outputs.files)
                    [~, fname, fext] = fileparts(outputs.files{f});
                    copyfile(outputs.files{f}, fullfile(run_dir, [fname fext]));
                end
            end

            % Store results
            run_result = struct();
            run_result.run_id = run_idx;
            run_result.case_name = run_case;
            run_result.parameters = params_current;
            run_result.status = status;
            run_result.outputs = outputs;
            run_result.run_dir = run_dir;

            results.runs{run_idx} = run_result;

            fprintf('  ✓ Success\n');

        catch e
            fprintf('  ✗ Failed: %s\n', e.message);
            run_result = struct();
            run_result.run_id = run_idx;
            run_result.parameters = params_current;
            run_result.error = e.message;
            results.runs{run_idx} = run_result;
        end

        fprintf('\n');
    end

    % Save results summary
    save(fullfile(output_dir, 'results.mat'), 'results');
    fprintf('=== Sweep Complete ===\n');
    fprintf('Results saved to: %s\n', output_dir);

end

function modified_dat = dat_modifier(base_dat_path, params, program)
    % Modify dataset based on parameters
    % NOTE: This is a template that needs customization for each program
    %
    % Each program has a specific READ(10,*) sequence.
    % This function should:
    %   1. Read the base .dat file
    %   2. Parse values according to program's READ sequence
    %   3. Update specified parameters
    %   4. Return modified data structure
    %
    % For now, this is a placeholder that just reads the file

    fid = fopen(base_dat_path, 'r');
    if fid == -1
        error('Cannot open base dataset: %s', base_dat_path);
    end

    % Read all lines
    modified_dat = {};
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line)
            modified_dat{end+1} = line; %#ok<AGROW>
        end
    end
    fclose(fid);

    % TODO: Implement parameter modification logic based on program
    warning('dat_modifier: Parameter modification not implemented for %s. Using base dataset.', program);

end

function write_dat_file(filepath, dat_lines)
    % Write .dat file from cell array of lines
    fid = fopen(filepath, 'w');
    if fid == -1
        error('Cannot write dataset: %s', filepath);
    end

    for i = 1:length(dat_lines)
        fprintf(fid, '%s\n', dat_lines{i});
    end

    fclose(fid);
end
