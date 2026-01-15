function [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides)
% General YAML-driven run:
% 1) loads YAML
% 2) copies original template .dat into an isolated run folder
% 3) patches ONLY tunable values (currently supports record2 material props)
% 4) runs PFEM in that run folder
%
% overrides: struct keyed by YAML tunable_parameters.name
% Example for p51_3:
% overrides.youngs_modulus_E = 1e7;
% overrides.poisson_ratio_nu = 0.30;

    addpath(fullfile(repo_root,'matlab','utils'));

    y = pfem_yaml_load(yaml_path);

    chap    = sprintf('chap%02d', y.authors.source.chapter);
    program = y.authors.source.program;
    base    = y.authors.source.dataset;

    % original .dat (full template)
    rel_dat = y.inputs.dat_file; % e.g. executable/chap05/p51_3.dat
    dat_src = fullfile(pfem_root, rel_dat);
    if startsWith(dat_src,'~'), dat_src = replace(dat_src,'~',getenv('HOME')); end
    if ~exist(dat_src,'file')
        error('Base .dat not found: %s', dat_src);
    end

    % isolated run folder
    % Use a shorter timestamp to stay under 20-character filename limit
    ts = datestr(now,'HHMMSS');
    run_dir = fullfile(repo_root,'runs','single',chap,program,base,ts);
    if ~exist(run_dir,'dir'), mkdir(run_dir); end

    new_case = sprintf('%s_%s', base, ts);
    dat_dst  = fullfile(run_dir, [new_case '.dat']);

    copyfile(dat_src, dat_dst);

    % patch template using YAML tunables
    if nargin >= 4 && ~isempty(overrides)
        pfem_patch_dat_using_yaml(dat_dst, y, overrides);
    end

    % snapshot for reproducibility
    copyfile(yaml_path, fullfile(run_dir,'case.yaml'));
    save(fullfile(run_dir,'overrides.mat'),'overrides');

    % run PFEM inside run_dir
    [status, out] = pfem_runner(pfem_root, chap, program, new_case, run_dir);
end
