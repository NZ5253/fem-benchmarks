function pfem_batch_figs(chapter_or_yaml, pfem_root)
% PFEM_BATCH_FIGS  Auto-generate sweep comparison figures for benchmark cases
%
% For each YAML case, automatically selects the primary tunable parameter,
% runs 4 sweep values, draws a deformed mesh comparison figure, and saves PNG.
%
% Usage:
%   pfem_batch_figs('chap06')          % all cases in chap06
%   pfem_batch_figs('chap06/p61.yaml') % single case
%   pfem_batch_figs('all')             % all chapters 4-11
%
% Prerequisites:
%   PFEM binaries must be compiled (scripts/pfem_build_chapter.sh).
%   Works for structural cases (chap04-06, 08, 11) where .res has nodal
%   displacements.  Flow / eigenvalue / coupled cases are skipped gracefully.
%
% Output:
%   Figures saved to  figures/<chap>/<case>_<param>.png
%
% Note:
%   For interactive single-case exploration use pfem_studio.
%   For a scripted sweep with the figure shown live, use NZ.m.

    repo_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks');
    if nargin < 2 || isempty(pfem_root)
        pfem_root = fullfile(repo_root, 'pfem');
    end
    if nargin < 1 || isempty(chapter_or_yaml)
        chapter_or_yaml = 'all';
    end

    addpath(genpath(fullfile(repo_root, 'matlab')));
    bench_root = fullfile(repo_root, 'benchmarks', 'pfem5');

    % ----- Collect YAML files -----
    if endsWith(chapter_or_yaml, '.yaml') || endsWith(chapter_or_yaml, '.yml')
        p = chapter_or_yaml;
        if ~isabspath(p), p = fullfile(repo_root, p); end
        process_case(p, repo_root, pfem_root);
        return;
    end

    if strcmp(chapter_or_yaml, 'all')
        chap_dirs = dir(fullfile(bench_root, 'chap*'));
        chapters  = {chap_dirs([chap_dirs.isdir]).name};
    else
        chapters = {chapter_or_yaml};
    end

    total_saved = 0;
    for ci = 1:numel(chapters)
        chap = chapters{ci};
        yaml_files = dir(fullfile(bench_root, chap, '*.yaml'));
        fprintf('\n=== %s  (%d cases) ===\n', chap, numel(yaml_files));
        for fi = 1:numel(yaml_files)
            p = fullfile(yaml_files(fi).folder, yaml_files(fi).name);
            total_saved = total_saved + process_case(p, repo_root, pfem_root);
        end
    end

    fprintf('\nDone. %d figure(s) saved to figures/\n', total_saved);
end


% --------------------------------------------------------------------------
function saved = process_case(yaml_path, repo_root, pfem_root)
    saved = 0;

    try
        yaml = pfem_yaml_load(yaml_path);
    catch ME
        fprintf('  [SKIP] Cannot load YAML %s: %s\n', yaml_path, ME.message);
        return;
    end

    case_name = yaml.inputs.basename;
    chap_str  = sprintf('chap%02d', yaml.authors.source.chapter);

    % --- Pick primary sweep parameter ---
    [sweep_param, sweep_type, sweep_range] = pick_sweep_param(yaml);
    if isempty(sweep_param)
        fprintf('  [skip] %-12s — no sweep-able parameter\n', case_name);
        return;
    end

    % --- Generate 4 sweep values ---
    sweep_values = make_sweep_values(sweep_range, sweep_type, 4);
    fprintf('  [run]  %-12s sweep %-28s [%.3g … %.3g]\n', ...
            case_name, sweep_param, sweep_values(1), sweep_values(end));

    % --- Run sweep ---
    n = numel(sweep_values);
    results = repmat(struct('value',0,'status',-1,'out',[]), 1, n);

    for i = 1:n
        ov = struct();
        ov.(sweep_param) = sweep_values(i);
        try
            [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, ov);
        catch ME
            fprintf('    (%d/%d) Error: %s\n', i, n, ME.message);
            status = -1;
            out    = struct('files',{{}},'param_key','','work_dir','','num_files',0);
        end
        results(i).value  = sweep_values(i);
        results(i).status = status;
        results(i).out    = out;
    end

    % --- Generate + save figures (hidden — batch mode) ---
    fig_dir    = fullfile(repo_root, 'figures', chap_str);
    fig_prefix = fullfile(fig_dir, sprintf('%s_%s', case_name, sweep_param));

    figs = pfem_plot_sweep_summary(results, sweep_param, yaml_path, ...
            'Title', sprintf('PFEM %s — %s sweep', case_name, strrep(sweep_param,'_',' ')), ...
            'Save', fig_prefix, ...
            'Show', false);

    % Check whether anything useful was drawn
    n_ok = sum([results.status] == 0);
    if n_ok == 0
        fprintf('  [skip] %-12s — no results (binary missing or non-structural)\n', case_name);
        fn = fieldnames(figs);
        for fi = 1:numel(fn)
            if ~isempty(figs.(fn{fi})) && ishandle(figs.(fn{fi})), close(figs.(fn{fi})); end
        end
        return;
    end

    fprintf('  [saved] figures/%s/%s_%s_*.png\n', chap_str, case_name, sweep_param);
    fn = fieldnames(figs);
    for fi = 1:numel(fn)
        if ~isempty(figs.(fn{fi})) && ishandle(figs.(fn{fi})), close(figs.(fn{fi})); end
    end
    saved = 1;
end


% --------------------------------------------------------------------------
function [param_name, param_type, param_range] = pick_sweep_param(yaml)
    param_name = ''; param_type = 'real'; param_range = [];
    if ~isfield(yaml, 'tunable_parameters'), return; end

    tparams = yaml.tunable_parameters;
    if ~iscell(tparams), tparams = num2cell(tparams); end

    for k = 1:numel(tparams)
        tp = tparams{k};
        if ~isstruct(tp),                  continue; end
        if ~isfield(tp, 'suggested_range'), continue; end
        if isfield(tp, 'note') && contains(tp.note, 'WARNING'), continue; end
        param_name  = tp.name;
        param_type  = tp.type;
        param_range = tp.suggested_range;
        return;
    end
end


% --------------------------------------------------------------------------
function vals = make_sweep_values(range_arr, param_type, n)
    lo = range_arr(1);
    hi = range_arr(2);
    if strcmp(param_type, 'int')
        vals = unique(round(linspace(max(round(lo),1), min(round(hi),round(lo)*20), n)));
    elseif lo > 0
        vals = 10.^linspace(log10(lo), log10(hi), n);
    else
        vals = linspace(lo, hi, n);
    end
    vals = vals(:)';
end
