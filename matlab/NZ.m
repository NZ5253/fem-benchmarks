% NZ_sweep.m - Run a loop of simulations with auto-discovery and comparison
clear; clc; close all;

% Setup Paths
repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
pfem_root = fullfile(repo_root, 'pfem');
addpath(fullfile(repo_root, 'matlab'));
addpath(fullfile(repo_root, 'matlab', 'utils'));

%% Configuration - EDIT THIS SECTION
%
% CASE SELECTION:
%   p51_4 (load-controlled):    Changing E affects DISPLACEMENTS only (stresses constant)
%   p51_3 (disp-controlled):    Changing E affects STRESSES only (displacements fixed)
%   Any case + Poisson ratio:   Changing nu affects BOTH stresses and displacements
%
yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p51_4.yaml');

% Show available tunables for this case
fprintf('Loading YAML and discovering tunables...\n');
tunables = pfem_show_tunables(yaml_path);

% Pick parameter to sweep (must match a name from tunables above)
% Options: 'youngs_modulus_E', 'poisson_ratio_nu', etc.
%sweep_param = 'youngs_modulus_E';
%sweep_values = [500, 1000, 5000, 10000];  % Multiple values to compare

% To see BOTH stress and displacement change, try:
sweep_param = 'poisson_ratio_nu';
sweep_values = [0.1, 0.2, 0.3, 0.4];

%% Validate parameter exists
param_names = {tunables.name};
if ~ismember(sweep_param, param_names)
    error('Parameter "%s" not found! Available: %s', sweep_param, strjoin(param_names, ', '));
end

%% Run Sweep
results = struct('param', {}, 'value', {}, 'status', {}, 'run_dir', {}, 'files', {}, 'out', {});
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

    % Store Result (including full output for comparison)
    results(i).param = sweep_param;
    results(i).value = val;
    results(i).status = status;
    results(i).run_dir = out.work_dir;
    results(i).files = out.files;
    results(i).out = out;  % Store full output for comparison

    if status == 0
        fprintf('Success (%d files)\n', out.num_files);
    else
        fprintf('Failed\n');
    end
end

%% Summary Table
fprintf('\n');
fprintf('============================================================\n');
fprintf('Sweep Complete: %d/%d successful\n', sum([results.status]==0), length(sweep_values));
fprintf('============================================================\n');

fprintf('\n%-12s  %-8s  %s\n', 'VALUE', 'STATUS', 'RUN_DIR');
fprintf('%s\n', repmat('-', 1, 80));
for i = 1:length(results)
    if results(i).status == 0
        status_str = 'OK';
    else
        status_str = 'FAIL';
    end
    fprintf('%-12.4g  %-8s  %s\n', results(i).value, status_str, results(i).run_dir);
end

%% Compare Results - Original vs ALL Runs
fprintf('\n');
fprintf('============================================================\n');
fprintf('Comparison: Original vs Modified (ALL RUNS)\n');
fprintf('============================================================\n');

% Show text comparison for ALL successful runs
for i = 1:length(results)
    if results(i).status == 0
        fprintf('\n--- Run %d/%d: %s = %.4g ---\n', i, length(results), sweep_param, results(i).value);
        pfem_compare_results(results(i).out, 'plot', false);
    end
end

%% Open Studio with sweep results
% pfem_studio shows: parameter vs max|u| curve + tiled deformed meshes for each run.
% It also lets you interactively re-run with different parameters.
fprintf('\nLaunching PFEM Studio...\n');
pfem_studio(yaml_path, pfem_root);
