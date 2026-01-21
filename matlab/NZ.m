% NZ_sweep.m - Run a loop of simulations with auto-discovery
clear; clc;

% Setup Paths
repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
pfem_root = fullfile(getenv('HOME'), 'Downloads', 'pfem5', '5th_ed');
addpath(fullfile(repo_root, 'matlab'));
addpath(fullfile(repo_root, 'matlab', 'utils'));

%% Configuration - EDIT THIS SECTION
yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p51_2.yaml');

% Show available tunables for this case
fprintf('Loading YAML and discovering tunables...\n');
tunables = pfem_show_tunables(yaml_path);

% Pick parameter to sweep (must match a name from tunables above)
sweep_param = 'youngs_modulus_E';
sweep_values = [1000, 2000, 4000, 8000];  % Adjust based on current_value shown above

%% Validate parameter exists
param_names = {tunables.name};
if ~ismember(sweep_param, param_names)
    error('Parameter "%s" not found! Available: %s', sweep_param, strjoin(param_names, ', '));
end

%% Run Sweep
results = struct();
fprintf('\n');
fprintf('============================================================\n');
fprintf('Sweeping %s over %d values\n', sweep_param, length(sweep_values));
fprintf('============================================================\n\n');

for i = 1:length(sweep_values)
    val = sweep_values(i);

    % Build overrides dynamically
    overrides = struct();
    overrides.(sweep_param) = val;

    fprintf('[Run %d/%d] %s = %.4g ... ', i, length(sweep_values), sweep_param, val);

    % Run Simulation
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);

    % Store Result
    results(i).param = sweep_param;
    results(i).value = val;
    results(i).status = status;
    results(i).run_dir = out.work_dir;
    results(i).files = out.files;

    if status == 0
        fprintf('Success (%d files)\n', out.num_files);
    else
        fprintf('Failed\n');
    end
end

%% Summary
fprintf('\n');
fprintf('============================================================\n');
fprintf('Sweep Complete: %d/%d successful\n', sum([results.status]==0), length(sweep_values));
fprintf('============================================================\n');

% Display results table
fprintf('\n%-12s  %-8s  %s\n', 'VALUE', 'STATUS', 'RUN_DIR');
fprintf('%s\n', repmat('-', 1, 70));
for i = 1:length(results)
    if results(i).status == 0
        status_str = 'OK';
    else
        status_str = 'FAIL';
    end
    fprintf('%-12.4g  %-8s  %s\n', results(i).value, status_str, results(i).run_dir);
end
