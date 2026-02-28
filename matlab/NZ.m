% NZ.m — PFEM multi-scenario sweep: run, visualise, and save comparison figures
%
% Supports:
%   • One or more YAML benchmark cases run in one go
%   • Any number of parameters changed simultaneously per scenario
%   • Auto-saved comparison figures (one window per output type) saved
%     alongside run outputs in  runs/<chap>/<case>/
%
clear; clc; close all;

%% ---- Paths ----
repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
pfem_root = fullfile(repo_root, 'pfem');
addpath(genpath(fullfile(repo_root, 'matlab')));

% ============================================================
%% ---- CONFIGURATION — edit this section ----
% ============================================================

%% 1. YAML case(s) to run
%    Add or remove entries; every case runs the same scenario set.
yaml_paths = {
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p61.yaml'),   % von Mises plasticity
    fullfile(repo_root, 'benchmarks', 'pfem5', 'chap06', 'p63.yaml'),   % Mohr-Coulomb bearing cap
};

%% 2. Show tunables for the first case (comment out after choosing parameters)
fprintf('=== Tunable parameters ===\n\n');
pfem_show_tunables(yaml_paths{1});

%% 3. Define parameter scenarios
%    All parameters in a scenario are applied simultaneously to every case.
%
% ---- Option A: single-parameter sweep ----
%      Four yield-stress levels for the p61 von Mises case:
% scenarios = pfem_make_scenarios('yield_stress', [50, 100, 200, 500]);
%
% ---- Option B: multiple parameters varied in lockstep ----
%      (all arrays must be the same length)
scenarios = pfem_make_scenarios( ...
    'yield_stress',     [50,   100,  200,  500], ...
    'youngs_modulus_E', [5e4,  1e5,  2e5,  1e5]);
%
% ---- Option C: fully manual — any mix of params per scenario ----
%      (label is optional; NZ.m auto-fills 'sc1','sc2',... if missing)
% scenarios(1) = struct('label','low-sy',   'yield_stress',  50, 'youngs_modulus_E',5e4);
% scenarios(2) = struct('label','baseline', 'yield_stress', 100, 'youngs_modulus_E',1e5);
% scenarios(3) = struct('label','high-E',   'yield_stress', 100, 'youngs_modulus_E',2e5);
% scenarios(4) = struct('label','high-sy',  'yield_stress', 500, 'youngs_modulus_E',1e5);

% ============================================================
%% ---- End of configuration ----
% ============================================================

%% Ensure every scenario has a label (safety net for manual construction)
for si = 1:numel(scenarios)
    if ~isfield(scenarios(si), 'label') || isempty(scenarios(si).label)
        scenarios(si).label = sprintf('sc%d', si);
    end
end

%% Determine sweep_param for pfem_plot_sweep_summary
%   • Single param  → raw field name with underscores (function converts for display)
%   • Multiple params → 'Scenario'  (valid MATLAB identifier)
sc_fields  = fieldnames(rmfield(scenarios(1), 'label'));   % param fields only
if numel(sc_fields) == 1
    sweep_display = sc_fields{1};        % keep underscores — used as struct field internally
else
    sweep_display = 'Scenario';          % multi-param: use index on x-axis
end

% ============================================================
%% ---- Run all cases × scenarios ----
% ============================================================
for ci = 1:numel(yaml_paths)
    yaml_path = yaml_paths{ci};
    [yaml_dir, case_name, ~] = fileparts(yaml_path);
    [~, chap_str] = fileparts(yaml_dir);      % e.g. 'chap06'

    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('Case: %s  |  Chapter: %s  |  %d scenario(s)\n', ...
            case_name, chap_str, numel(scenarios));
    fprintf('%s\n', repmat('=', 1, 60));

    %% Ensure binary is compiled
    y_tmp   = pfem_yaml_load(yaml_path);
    program = y_tmp.authors.source.program;
    chap    = sprintf('chap%02d', y_tmp.authors.source.chapter);
    if ~pfem_ensure_built(repo_root, pfem_root, program, chap)
        warning('Build failed for %s/%s — skipping case.', chap, program);
        continue;
    end

    %% Run every scenario
    case_results = struct('label',{}, 'value',{}, 'status',{}, ...
                          'run_dir',{}, 'files',{}, 'out',{});

    for si = 1:numel(scenarios)
        sc    = scenarios(si);
        label = sc.label;
        ovr   = rmfield(sc, 'label');   % strip 'label' — not a YAML parameter

        fprintf('\n[%d/%d] Scenario: %s\n', si, numel(scenarios), label);
        fnames = fieldnames(ovr);
        for fi = 1:numel(fnames)
            fprintf('        %-30s = %g\n', fnames{fi}, ovr.(fnames{fi}));
        end
        fprintf('  Running... ');

        [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, ovr);

        % For the summary curve: use actual param value (single-param sweep)
        % or scenario index (multi-param) so the x-axis is meaningful.
        if numel(sc_fields) == 1
            sc_val = ovr.(sc_fields{1});
        else
            sc_val = si;
        end

        case_results(si).label   = label;
        case_results(si).value   = sc_val;
        case_results(si).status  = status;
        case_results(si).run_dir = out.run_dir;
        case_results(si).files   = out.files;
        case_results(si).out     = out;

        if status == 0
            fprintf('OK (%d output file(s))\n', out.num_files);
        else
            fprintf('FAILED (exit code %d)\n', status);
        end
    end

    %% Summary table
    fprintf('\n%-24s  %-8s  %s\n', 'SCENARIO', 'STATUS', 'RUN DIR');
    fprintf('%s\n', repmat('-', 1, 80));
    n_ok = 0;
    for si = 1:numel(case_results)
        s = 'OK'; if case_results(si).status ~= 0, s = 'FAIL'; end
        if strcmp(s,'OK'), n_ok = n_ok + 1; end
        fprintf('%-24s  %-8s  %s\n', case_results(si).label, s, ...
                case_results(si).run_dir);
    end
    fprintf('\n%d / %d scenarios succeeded.\n', n_ok, numel(case_results));

    %% Text comparison: original .res vs each scenario's .res
    for si = 1:numel(case_results)
        if case_results(si).status == 0
            fprintf('\n--- %s  |  %s ---\n', case_name, case_results(si).label);
            pfem_compare_results(case_results(si).out, 'plot', false);
        end
    end

    %% Comparison figures — saved in runs/<chap>/<case>/ alongside run output
    runs_case_dir = fullfile(repo_root, 'runs', chap_str, case_name);
    if ~exist(runs_case_dir,'dir'), mkdir(runs_case_dir); end
    fig_prefix = fullfile(runs_case_dir, sprintf('%s_sweep', case_name));

    fprintf('\nGenerating comparison figures...\n');
    pfem_plot_sweep_summary(case_results, sweep_display, yaml_path, ...
        'Title', sprintf('PFEM %s', case_name), ...
        'Save',  fig_prefix, ...
        'Show',  true);

    fprintf('Figures saved: runs/%s/%s/%s_sweep_{{res,msh,dis,vec}}.png\n', ...
            chap_str, case_name, case_name);
end

fprintf('\nDone.\n');
