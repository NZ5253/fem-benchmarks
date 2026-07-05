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
%
% Phase 3: since M1, this function is a thin dispatcher that delegates to a
% backend. Signature and behaviour are unchanged for the PFEM path. M2 added
% get_backend(y) so a YAML with the optional key
%
%   runner:
%     type: pfem | analytic | external
%
% selects a different backend. Absent key defaults to pfem, keeping all 87
% legacy YAMLs working with no edits.

    if nargin < 4, overrides = struct(); end

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, 'backends'));
    addpath(fullfile(here, 'utils'));

    y   = pfem_yaml_load(yaml_path);
    b   = get_backend(y);
    ctx = struct('repo_root', repo_root, ...
                 'pfem_root', pfem_root, ...
                 'yaml_path', yaml_path);

    [status, out] = b.run(ctx, y, overrides);
end
