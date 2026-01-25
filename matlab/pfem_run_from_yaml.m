function [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides)
% PFEM_RUN_FROM_YAML  Run PFEM case with optional parameter overrides
%
% General YAML-driven run:
% 1) loads YAML
% 2) copies original template .dat into an isolated run folder
% 3) patches tunable values using token-based coordinates
% 4) runs PFEM in that run folder
% 5) stores original .res path for comparison
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

    % Build run folder name with parameter values
    ts = datestr(now,'yymmdd_HHMMSS');

    % Add parameter values to folder name
    param_suffix = '';
    if nargin >= 4 && ~isempty(overrides) && ~isempty(fieldnames(overrides))
        fnames = fieldnames(overrides);
        param_parts = {};
        for i = 1:numel(fnames)
            pname = fnames{i};
            pval = overrides.(pname);
            % Create short suffix: E_500 or nu_0.3
            short_name = strrep(pname, 'youngs_modulus_', '');
            short_name = strrep(short_name, 'poisson_ratio_', '');
            short_name = strrep(short_name, '_or_nxe', '');
            short_name = strrep(short_name, '_or_nye', '');
            if isnumeric(pval)
                if pval >= 1000 || pval < 0.01
                    val_str = sprintf('%.2e', pval);
                else
                    val_str = sprintf('%.4g', pval);
                end
            else
                val_str = char(pval);
            end
            param_parts{end+1} = sprintf('%s_%s', short_name, val_str);
        end
        param_suffix = ['_' strjoin(param_parts, '_')];
    end

    % Create unique run folder with timestamp and parameter values
    run_name = [ts param_suffix];
    run_dir = fullfile(repo_root,'runs','single',chap,program,base,run_name);
    if ~exist(run_dir,'dir'), mkdir(run_dir); end

    new_case = sprintf('%s_%s', base, run_name);

    % Truncate if too long (PFEM has 20-char limit for case names)
    if length(new_case) > 20
        % Use hash for uniqueness
        hash_str = sprintf('%04d', mod(round(now*1e6), 10000));
        new_case = [base '_' hash_str];
    end

    dat_dst = fullfile(run_dir, [new_case '.dat']);
    copyfile(dat_src, dat_dst);

    % patch template using YAML tunables
    if nargin >= 4 && ~isempty(overrides) && ~isempty(fieldnames(overrides))
        pfem_patch_dat_using_yaml(dat_dst, y, overrides);
    end

    % snapshot for reproducibility
    copyfile(yaml_path, fullfile(run_dir,'case.yaml'));
    if nargin >= 4
        save(fullfile(run_dir,'overrides.mat'),'overrides');
    end

    % Store original paths for comparison
    original_res = fullfile(pfem_root, 'executable', chap, [base '.res']);
    original_dat = dat_src;

    % run PFEM inside run_dir
    [status, out] = pfem_runner(pfem_root, chap, program, new_case, run_dir);

    % Add original paths to output for comparison
    out.original_res = original_res;
    out.original_dat = original_dat;
    out.run_name = run_name;
    out.overrides = overrides;
end
