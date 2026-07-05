function capture_golden_qoi(varargin)
% CAPTURE_GOLDEN_QOI  Capture reference QoI values for the Phase 3 regression
% gate. Runs every YAML in benchmarks/pfem5/chap*/ at its default parameters,
% plus a handful of override probes that exercise the run/patch plumbing, and
% writes matlab/tests/golden_qoi.json (schema in docs/PHASE3_PLAN.md Section 6).
%
% Usage:
%   capture_golden_qoi()                          % writes to default path
%   capture_golden_qoi('Out', '/tmp/g.json')      % custom output path
%   capture_golden_qoi('SkipSlow', true)          % skip p56_1, p57 (~250s each)
%
% The JSON produced here is the ground truth for test_golden_qoi.m. Regenerate
% only on a known-good tree: any refactor after M1 must reproduce these
% values.

    p = inputParser;
    addParameter(p, 'Out', '');
    addParameter(p, 'SkipSlow', false);
    parse(p, varargin{:});
    out_path  = p.Results.Out;
    skip_slow = p.Results.SkipSlow;

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    if isempty(out_path)
        out_path = fullfile(here, 'golden_qoi.json');
    end
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));

    yaml_paths = list_yamls(repo_root);
    if skip_slow
        slow = {'p56_1', 'p57'};
        keep = true(size(yaml_paths));
        for i = 1:numel(yaml_paths)
            [~, name] = fileparts(yaml_paths{i});
            if any(strcmp(name, slow)), keep(i) = false; end
        end
        yaml_paths = yaml_paths(keep);
    end

    probes = default_probes();

    fprintf('Capturing QoI on %d default cases + %d override probes ...\n', ...
        numel(yaml_paths), numel(probes));

    records = {};
    t_start = tic;

    % 1. Defaults on every case
    for i = 1:numel(yaml_paths)
        yp = yaml_paths{i};
        [~, case_name] = fileparts(yp);
        try
            rec = capture_one(repo_root, pfem_root, yp, 'default', struct());
            fprintf('  [%3d/%3d] %-14s %-18s %s = %-14.6g %s\n', ...
                i, numel(yaml_paths), case_name, rec.case_type, rec.label, ...
                rec.value, rec.unit);
            records{end+1} = rec; %#ok<AGROW>
        catch ME
            fprintf('  [%3d/%3d] %-14s FAILED: %s\n', ...
                i, numel(yaml_paths), case_name, ME.message);
        end
    end

    % 2. Override probes to exercise patching / plumbing
    for j = 1:numel(probes)
        pr = probes(j);
        yp = fullfile(repo_root, pr.yaml);
        try
            rec = capture_one(repo_root, pfem_root, yp, pr.probe_label, pr.overrides);
            fprintf('  [probe %d ] %-14s %-18s %s = %-14.6g %s   [%s]\n', ...
                j, pr.case, rec.case_type, rec.label, rec.value, rec.unit, ...
                pr.probe_label);
            records{end+1} = rec; %#ok<AGROW>
        catch ME
            fprintf('  [probe %d ] %-14s FAILED (%s): %s\n', ...
                j, pr.case, pr.probe_label, ME.message);
        end
    end

    meta = struct(...
        'captured', datestr(now, 'yyyy-mm-dd'), ...
        'commit',   get_git_sha(repo_root), ...
        'n_cases',  numel(records));

    root.meta  = meta;
    root.cases = records;
    j = jsonencode(root, 'PrettyPrint', true);

    fid = fopen(out_path, 'w');
    assert(fid > 0, 'cannot open %s for writing', out_path);
    fprintf(fid, '%s\n', j);
    fclose(fid);

    fprintf('\nWrote %s (%d cases, %.1f s)\n', out_path, numel(records), toc(t_start));
end


function rec = capture_one(repo_root, pfem_root, yaml_path, probe_label, overrides)
    y = pfem_yaml_load(yaml_path);
    case_type = pfem_detect_case_type(y);
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
    if status ~= 0
        error('pfem run exited with status %d', status);
    end
    q = pfem_extract_qoi(out, case_type);

    [~, case_name] = fileparts(yaml_path);
    rel_yaml = strrep(yaml_path, [repo_root filesep], '');
    rel_yaml = strrep(rel_yaml, filesep, '/');

    rec.case        = case_name;
    rec.yaml        = rel_yaml;
    rec.probe_label = probe_label;
    rec.overrides   = overrides;
    rec.case_type   = case_type;
    rec.value       = q.value;
    rec.label       = q.label;
    rec.unit        = q.unit;
    rec.ok          = q.ok;
    if isfield(q, 'f1') && ~isnan(q.f1)
        rec.f1 = q.f1;
    end
end


function paths = list_yamls(repo_root)
    d = dir(fullfile(repo_root, 'benchmarks/pfem5/chap*/*.yaml'));
    paths = arrayfun(@(f) fullfile(f.folder, f.name), d, 'UniformOutput', false);
    paths = paths(:);
end


function probes = default_probes()
% Small hand-picked set that exercises the patcher on 5 of the 8 case types.
% Values chosen inside YAML suggested_range to keep runs quick and stable.
    probes = struct( ...
        'case',        {'p61',      'p612',     'p51_3',   'p101',           'p81_5'}, ...
        'yaml',        {'benchmarks/pfem5/chap06/p61.yaml', ...
                        'benchmarks/pfem5/chap06/p612.yaml', ...
                        'benchmarks/pfem5/chap05/p51_3.yaml', ...
                        'benchmarks/pfem5/chap10/p101.yaml', ...
                        'benchmarks/pfem5/chap08/p81_5.yaml'}, ...
        'probe_label', {'sy_200',   'c_80',     'E_2e6',   'EI_0.05',        'k_5e-4'}, ...
        'overrides',   {struct('yield_stress',       200), ...
                        struct('cohesion_c',          80), ...
                        struct('youngs_modulus_E',   2e6), ...
                        struct('stiffness_E_or_EI', 0.05), ...
                        struct('permeability_k_or_cv', 5e-4)});
end


function sha = get_git_sha(repo_root)
    [rc, out] = system(sprintf('git -C "%s" rev-parse HEAD 2>/dev/null', repo_root));
    if rc == 0
        sha = strtrim(out);
    else
        sha = 'unknown';
    end
end
