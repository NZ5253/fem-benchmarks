% NZ_sweep.m - Run a loop of simulations
clear; clc;

% Setup Paths
repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
pfem_root = fullfile(getenv('HOME'), 'Downloads', 'pfem5', '5th_ed');
addpath(fullfile(repo_root, 'matlab'));
addpath(fullfile(repo_root, 'matlab', 'utils'));

yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p51_3.yaml');

% Define the Sweep
E_values = [1.0e5, 2.0e5, 5.0e5]; % varying Young's Modulus
results = struct();

fprintf('Starting Sweep over %d values...\n', length(E_values));

for i = 1:length(E_values)
    % 1. Set current parameter
    overrides = struct();
    overrides.youngs_modulus_E = E_values(i);
    
    fprintf('[Run %d] E = %.2e ... ', i, E_values(i));
    
    % 2. Run Simulation
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    
    % 3. Store Result
    results(i).E = E_values(i);
    results(i).status = status;
    results(i).files = out.files;
    
    if status == 0
        fprintf('Success\n');
    else
        fprintf('Failed\n');
    end
end

fprintf('Sweep Complete.\n');