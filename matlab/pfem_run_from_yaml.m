function [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides)
% PFEM_RUN_FROM_YAML  Run PFEM case with optional parameter overrides
%
% Run directory layout:
%   runs/<chap>/<case>/<param_key>/
%   e.g.  runs/chap06/p61/default/
%         runs/chap06/p61/yield_stress_200/
%         runs/chap06/p61/E_1e5_nu_0.3/
%
% Each run directory contains: <case>.dat, <case>.res, <case>.msh,
%   case.yaml (snapshot), overrides.mat
%
% overrides: struct keyed by YAML tunable_parameters.name
% Example:
%   overrides.youngs_modulus_E = 1e7;
%   overrides.poisson_ratio_nu = 0.30;

    addpath(fullfile(repo_root,'matlab','utils'));

    y = pfem_yaml_load(yaml_path);

    chap    = sprintf('chap%02d', y.authors.source.chapter);
    program = y.authors.source.program;
    base    = y.authors.source.dataset;

    % original .dat (full template)
    rel_dat = y.inputs.dat_file;
    dat_src = fullfile(pfem_root, rel_dat);
    if startsWith(dat_src,'~'), dat_src = replace(dat_src,'~',getenv('HOME')); end
    if ~exist(dat_src,'file')
        error('Base .dat not found: %s', dat_src);
    end

    % Build param key for folder name
    param_key = build_param_key(overrides);

    % Run directory: runs/<chap>/<base>/<param_key>/
    run_dir = fullfile(repo_root, 'runs', chap, base, param_key);
    if ~exist(run_dir,'dir'), mkdir(run_dir); end

    % Case name = base (always short, stays within PFEM 20-char limit)
    new_case = base;

    dat_dst = fullfile(run_dir, [new_case '.dat']);
    copyfile(dat_src, dat_dst);

    % patch template using YAML tunables
    if nargin >= 4 && ~isempty(overrides) && ~isempty(fieldnames(overrides))
        pfem_patch_dat_using_yaml(dat_dst, y, overrides);
    end

    % snapshot for reproducibility
    copyfile(yaml_path, fullfile(run_dir,'case.yaml'));
    if nargin >= 4 && ~isempty(overrides)
        save(fullfile(run_dir,'overrides.mat'),'overrides');
    end

    % Store original paths for comparison
    original_res = fullfile(pfem_root, 'executable', chap, [base '.res']);
    original_dat = dat_src;

    % run PFEM inside run_dir
    [status, out] = pfem_runner(pfem_root, chap, program, new_case, run_dir);

    % Add metadata to output
    out.original_res = original_res;
    out.original_dat = original_dat;
    out.param_key    = param_key;
    out.overrides    = overrides;
    out.yaml_path    = yaml_path;
    out.case         = base;
end


function key = build_param_key(overrides)
% Build a short, readable folder name from parameter overrides.
% No overrides → 'default'
% One override → e.g. 'yield_stress_200' or 'E_1.00e+05'
% Multiple    → e.g. 'E_1e5_nu_0.3'
    if nargin < 1 || isempty(overrides) || isempty(fieldnames(overrides))
        key = 'default';
        return;
    end

    % Abbreviation map: long tunable names → short labels
    abbrev = struct( ...
        'youngs_modulus_E',       'E', ...
        'poisson_ratio_nu',       'nu', ...
        'yield_stress',           'sy', ...
        'convergence_tolerance',  'tol', ...
        'iteration_limit',        'lim', ...
        'load_increments',        'incs', ...
        'nels_or_nxe',            'nxe', ...
        'np_types_or_nye',        'nye', ...
        'permeability_k_or_cv',   'k', ...
        'time_step',              'dt', ...
        'num_time_steps',         'nstep', ...
        'theta_parameter',        'theta', ...
        'damping_fm',             'fm', ...
        'damping_fk',             'fk', ...
        'density_rho',            'rho' ...
    );

    fnames = fieldnames(overrides);
    parts = {};
    for i = 1:numel(fnames)
        pname = fnames{i};
        pval  = overrides.(pname);

        % Look up abbreviation
        if isfield(abbrev, pname)
            label = abbrev.(pname);
        else
            % Shorten automatically: remove common prefixes
            label = regexprep(pname, '^(youngs_modulus_|poisson_ratio_|permeability_|convergence_|iteration_|num_)', '');
            label = label(1:min(8, end));  % cap at 8 chars
        end

        % Format value
        if isnumeric(pval)
            if pval == 0
                val_str = '0';
            elseif abs(pval) >= 1e4 || (abs(pval) < 0.01 && pval ~= 0)
                % Scientific notation, compact: 1e5 not 1.00e+05
                val_str = format_sci(pval);
            else
                val_str = sprintf('%.4g', pval);
            end
        else
            val_str = char(pval);
            val_str = regexprep(val_str, '[^a-zA-Z0-9_]', '_');
        end

        parts{end+1} = sprintf('%s_%s', label, val_str);
    end

    key = strjoin(parts, '_');

    % Sanitise: remove filesystem-unfriendly chars
    key = regexprep(key, '[^a-zA-Z0-9_\-\.]', '_');

    % Cap total length
    if length(key) > 60
        key = key(1:60);
    end
end


function s = format_sci(v)
% Format a number in compact scientific notation: 1e5, 2.5e-3, etc.
    if v == 0
        s = '0'; return;
    end
    e = floor(log10(abs(v)));
    m = v / 10^e;
    if abs(m - round(m)) < 1e-9
        s = sprintf('%de%d', round(m), e);
    else
        s = sprintf('%.2ge%d', m, e);
        s = regexprep(s, 'e%d', sprintf('e%d', e));
        s = sprintf('%.3g', v);
        s = strrep(s, '+', '');
        s = strrep(s, 'e0', 'e');
        s = strrep(s, 'e-0', 'e-');
    end
end
