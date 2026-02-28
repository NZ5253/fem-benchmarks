function [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides)
% PFEM_RUN_FROM_YAML  Run PFEM case with optional parameter overrides
%
% Each run is stored in a self-contained directory:
%
%   runs/<chap>/<case>/<param_key>/
%   ├── <case>         ← compiled binary (copy — re-runnable without pfem/)
%   ├── <case>.dat     ← patched input data
%   ├── <case>.res     ← main results
%   ├── <case>.msh     ← mesh (PostScript)
%   ├── <case>.dis     ← deformed shape (PostScript, if produced)
%   ├── <case>.vec     ← displacement vectors (PostScript, if produced)
%   ├── case.yaml      ← full parameter snapshot
%   ├── overrides.mat  ← override values (MATLAB)
%   └── run_info.txt   ← human-readable summary
%
% To re-run a completed run from the shell:
%   cd runs/chap06/p61/sy_200 && printf "p61\n" | ./p61
%
% overrides: struct keyed by YAML tunable_parameters.name, e.g.:
%   overrides.youngs_modulus_E = 1e7;
%   overrides.poisson_ratio_nu = 0.30;

    addpath(fullfile(repo_root,'matlab','utils'));

    y = pfem_yaml_load(yaml_path);

    chap    = sprintf('chap%02d', y.authors.source.chapter);
    program = y.authors.source.program;
    base    = y.authors.source.dataset;

    % original .dat template
    rel_dat = y.inputs.dat_file;
    dat_src = fullfile(pfem_root, rel_dat);
    if startsWith(dat_src,'~'), dat_src = replace(dat_src,'~',getenv('HOME')); end
    if ~exist(dat_src,'file')
        error('Base .dat not found: %s', dat_src);
    end

    % Build param key → folder name
    param_key = build_param_key(overrides);

    % Run directory: runs/<chap>/<base>/<param_key>/
    run_dir = fullfile(repo_root, 'runs', chap, base, param_key);
    if ~exist(run_dir,'dir'), mkdir(run_dir); end

    % Case name = base (short; stays within PFEM 20-char limit)
    new_case = base;

    % ---- stage inputs ----
    dat_dst = fullfile(run_dir, [new_case '.dat']);
    copyfile(dat_src, dat_dst);

    % patch using YAML tunables
    if nargin >= 4 && ~isempty(overrides) && ~isempty(fieldnames(overrides))
        pfem_patch_dat_using_yaml(dat_dst, y, overrides);
    end

    % Auto-build binary if missing, then copy to run dir so it is self-contained.
    % chmod +x is needed because MATLAB copyfile strips the execute bit on Linux.
    pfem_ensure_built(repo_root, pfem_root, program, chap);
    exe_src = fullfile(pfem_root, 'build', 'bin', program);
    exe_dst = fullfile(run_dir, program);
    if exist(exe_src, 'file')
        copyfile(exe_src, exe_dst);
        system(sprintf('chmod +x "%s"', exe_dst));
    end

    % parameter snapshots
    copyfile(yaml_path, fullfile(run_dir, 'case.yaml'));
    if nargin >= 4 && ~isempty(overrides)
        save(fullfile(run_dir, 'overrides.mat'), 'overrides');
    end

    % ---- run ----
    [status, out] = pfem_runner(pfem_root, chap, program, new_case, run_dir);

    % ---- write run_info.txt ----
    write_run_info(run_dir, new_case, yaml_path, overrides, param_key, status, out);

    % ---- annotate output struct ----
    out.original_dat = dat_src;
    out.original_res = fullfile(pfem_root, 'executable', chap, [base '.res']); % for pfem_compare_results
    out.param_key    = param_key;
    out.overrides    = overrides;
    out.yaml_path    = yaml_path;
    out.case         = base;
    out.run_dir      = run_dir;
end


% =========================================================================
function write_run_info(run_dir, case_name, yaml_path, overrides, param_key, status, out)
% Write a plain-text summary of the run into run_dir/run_info.txt
    fpath = fullfile(run_dir, 'run_info.txt');
    fid = fopen(fpath, 'w');
    if fid == -1, return; end

    fprintf(fid, 'PFEM Run Summary\n');
    fprintf(fid, '================\n');
    fprintf(fid, 'Date     : %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Case     : %s\n', case_name);
    fprintf(fid, 'Param key: %s\n', param_key);
    fprintf(fid, 'YAML     : %s\n', yaml_path);
    fprintf(fid, 'Status   : %s\n', ifelse(status==0, 'SUCCESS', sprintf('FAILED (code %d)', status)));
    fprintf(fid, '\n');

    % overrides
    if ~isempty(overrides) && ~isempty(fieldnames(overrides))
        fprintf(fid, 'Parameter overrides:\n');
        fnames = fieldnames(overrides);
        for i = 1:numel(fnames)
            v = overrides.(fnames{i});
            if isnumeric(v)
                fprintf(fid, '  %-30s = %g\n', fnames{i}, v);
            else
                fprintf(fid, '  %-30s = %s\n', fnames{i}, char(v));
            end
        end
        fprintf(fid, '\n');
    end

    % output files
    if isfield(out,'files') && ~isempty(out.files)
        fprintf(fid, 'Output files:\n');
        for i = 1:numel(out.files)
            [~,fn,ext] = fileparts(out.files{i});
            info = dir(out.files{i});
            if ~isempty(info)
                fprintf(fid, '  %s%s  (%s)\n', fn, ext, format_bytes(info.bytes));
            else
                fprintf(fid, '  %s%s\n', fn, ext);
            end
        end
        fprintf(fid, '\n');
    end

    % re-run instruction
    fprintf(fid, 'To re-run (from this directory):\n');
    fprintf(fid, '  printf "%s\\n" | ./%s\n', case_name, case_name);

    fclose(fid);
end


function s = ifelse(cond, a, b)
    if cond, s = a; else, s = b; end
end


function s = format_bytes(n)
    if n < 1024
        s = sprintf('%d B', n);
    elseif n < 1024^2
        s = sprintf('%.1f KB', n/1024);
    else
        s = sprintf('%.1f MB', n/1024^2);
    end
end


% =========================================================================
function key = build_param_key(overrides)
% Build a short, readable folder name from parameter overrides.
% No overrides → 'default'
% One override  → e.g. 'sy_200'  or  'E_1e5'
% Multiple      → e.g. 'E_1e5_nu_0.3'
    if nargin < 1 || isempty(overrides) || isempty(fieldnames(overrides))
        key = 'default';
        return;
    end

    abbrev = struct( ...
        'youngs_modulus_E',       'E',     ...
        'poisson_ratio_nu',       'nu',    ...
        'yield_stress',           'sy',    ...
        'convergence_tolerance',  'tol',   ...
        'iteration_limit',        'lim',   ...
        'load_increments',        'incs',  ...
        'nels_or_nxe',            'nxe',   ...
        'np_types_or_nye',        'nye',   ...
        'permeability_k_or_cv',   'k',     ...
        'time_step',              'dt',    ...
        'num_time_steps',         'nstep', ...
        'theta_parameter',        'theta', ...
        'damping_fm',             'fm',    ...
        'damping_fk',             'fk',   ...
        'density_rho',            'rho'   ...
    );

    fnames = fieldnames(overrides);
    parts  = {};
    for i = 1:numel(fnames)
        pname = fnames{i};
        pval  = overrides.(pname);

        if isfield(abbrev, pname)
            label = abbrev.(pname);
        else
            label = regexprep(pname, '^(youngs_modulus_|poisson_ratio_|permeability_|convergence_|iteration_|num_)', '');
            label = label(1:min(8, end));
        end

        if isnumeric(pval)
            val_str = format_sci(pval);
        else
            val_str = regexprep(char(pval), '[^a-zA-Z0-9_]', '_');
        end

        parts{end+1} = sprintf('%s_%s', label, val_str); %#ok<AGROW>
    end

    key = strjoin(parts, '_');
    key = regexprep(key, '[^a-zA-Z0-9_\-\.]', '_');
    if length(key) > 60
        key = key(1:60);
    end
end


function s = format_sci(v)
% Compact scientific notation: 0→'0', 100→'100', 1e5→'1e5', 1.5e4→'1.5e4'
    if v == 0
        s = '0';
        return;
    end
    % Use MATLAB's default %g, then tidy exponent format
    s = sprintf('%.4g', v);           % e.g. '1e+05', '1.5e+04', '200', '0.3'
    s = regexprep(s, 'e\+0*(\d)', 'e$1');  % e+05 → e5
    s = regexprep(s, 'e-0*(\d)',  'e-$1'); % e-05 → e-5
end
