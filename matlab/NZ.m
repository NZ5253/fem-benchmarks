% NZ.m — PFEM parametric sweep: run, visualise, and save comparison figure
clear; clc; close all;

%% Paths
repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
pfem_root = fullfile(repo_root, 'pfem');
addpath(genpath(fullfile(repo_root, 'matlab')));

%% ---- CONFIGURATION — edit this section ----
%
% Pick a YAML case and a tunable parameter to sweep.
%
% Good starting cases:
%   chap05/p51_4.yaml  — E affects displacements only (load-controlled)
%   chap05/p51_3.yaml  — E affects stresses only (disp-controlled)
%   chap06/p61.yaml    — yield_stress controls plastic zone (von Mises)
%   chap06/p63.yaml    — friction_angle_phi (Mohr-Coulomb bearing capacity)
%
yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p61.yaml');

% Show tunables for this case (comment out once you've chosen)
fprintf('=== Tunable parameters ===\n');
tunables = pfem_show_tunables(yaml_path);

% Parameter to sweep + values to try
sweep_param  = 'yield_stress';
sweep_values = [50, 100, 200, 500];   % e.g. 4 values for a 2×2 comparison panel

%% ---- Validate ----
param_names = {tunables.name};
if ~ismember(sweep_param, param_names)
    error('Parameter "%s" not found.\nAvailable: %s', sweep_param, strjoin(param_names, ', '));
end

%% ---- Run sweep ----
fprintf('\n=== Sweep: %s over %d values ===\n', sweep_param, numel(sweep_values));
results = struct('param',{}, 'value',{}, 'status',{}, 'run_dir',{}, 'files',{}, 'out',{});

for i = 1:numel(sweep_values)
    val = sweep_values(i);
    overrides = struct();
    overrides.(sweep_param) = val;

    fprintf('[%d/%d] %s = %.4g  ...  ', i, numel(sweep_values), sweep_param, val);
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);

    results(i).param   = sweep_param;
    results(i).value   = val;
    results(i).status  = status;
    results(i).run_dir = out.work_dir;
    results(i).files   = out.files;
    results(i).out     = out;

    if status == 0
        fprintf('OK (%d files)\n', out.num_files);
    else
        fprintf('FAILED\n');
    end
end

%% ---- Summary table ----
fprintf('\n%-12s  %-8s  %s\n', 'VALUE', 'STATUS', 'RUN_DIR');
fprintf('%s\n', repmat('-', 1, 80));
for i = 1:numel(results)
    s = 'OK'; if results(i).status ~= 0, s = 'FAIL'; end
    fprintf('%-12.4g  %-8s  %s\n', results(i).value, s, results(i).run_dir);
end
n_ok = sum([results.status] == 0);
fprintf('\n%d/%d runs succeeded.\n', n_ok, numel(results));

%% ---- Text comparison (original vs each run) ----
for i = 1:numel(results)
    if results(i).status == 0
        fprintf('\n--- %s = %.4g ---\n', sweep_param, results(i).value);
        pfem_compare_results(results(i).out, 'plot', false);
    end
end

%% ---- Sweep comparison figure ----
% Generates: parameter-vs-max|u| curve  +  tiled deformed mesh panels.
% Saves to figures/<chap>/<case>_<param>.png  and  stays open in MATLAB.

fprintf('\nGenerating sweep comparison figure...\n');

% Derive save path from yaml_path
[yaml_dir, case_name, ~] = fileparts(yaml_path);
[~, chap_str] = fileparts(yaml_dir);   % e.g. 'chap06'
fig_dir  = fullfile(repo_root, 'figures', chap_str);
fig_path = fullfile(fig_dir, sprintf('%s_%s.png', case_name, sweep_param));

pfem_plot_sweep_summary(results, sweep_param, yaml_path, ...
    'Title', sprintf('PFEM %s — %s sweep', case_name, strrep(sweep_param,'_',' ')), ...
    'Save',  fig_path, ...
    'Show',  true);

fprintf('Figure saved: figures/%s/%s_%s.png\n', chap_str, case_name, sweep_param);

%% ---- Show any previously saved PNG figures for this case ----
% Displays PNGs from figures/<chap>/ that are named for the current case.
if exist(fig_dir, 'dir')
    saved_pngs = dir(fullfile(fig_dir, sprintf('%s_*.png', case_name)));
    for pi = 1:numel(saved_pngs)
        png_full = fullfile(saved_pngs(pi).folder, saved_pngs(pi).name);
        if strcmp(png_full, fig_path), continue; end   % skip the one we just saved
        figure('Name', saved_pngs(pi).name, 'NumberTitle', 'off');
        imshow(imread(png_full));
        title(strrep(saved_pngs(pi).name, '_', ' '), 'Interpreter', 'none');
    end
end

%% ---- Optional: launch interactive studio ----
% Uncomment to open the full interactive PFEM Studio after the sweep:
% pfem_studio(yaml_path, pfem_root);
