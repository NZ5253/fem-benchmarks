function b = external_backend()
% EXTERNAL_BACKEND  Generic template-based backend (Phase 3 milestone M4).
%
% Runs any external program that reads an input file and writes an output
% file. YAML shape (all fields under runner:):
%
%   runner:
%     type: external
%     input_template: <path relative to the YAML file>   % substituted with
%                                                        % {param_name} tokens
%     input_file: input.txt        % OPTIONAL basename written into run_dir
%                                  % (default: 'input.txt')
%     command: "python3 solver.py {input_file} {output_file}"
%                                  % {input_file}, {output_file}, {run_dir},
%                                  % {yaml_dir}, {repo_root} substitutions
%     cwd: repo_root | run_dir | yaml_dir   % OPTIONAL, default 'repo_root'
%     output_file: result.txt      % basename written by the program
%     output_parse:
%       pattern: 'P_lim\s*=\s*([0-9.eE+-]+)'   % MATLAB regexp
%       group:   1                             % OPTIONAL capture-group index
%     output:
%       label: P_lim
%       unit:  kPa
%
% Values in `tunable_parameters[*].current_value` provide defaults; the
% `overrides` struct passed to the run supersedes them.
%
% Backend contract: b.name / b.run / b.extract_qoi (passthrough of out.qoi).
% Behaviour on failure: status = non-zero, out.qoi.ok = false, the raw
% program stdout+stderr is captured in run_dir/run.log.

    b.name        = 'external';
    b.run         = @external_run;
    b.extract_qoi = @(out, ~) out.qoi;
end


function [status, out] = external_run(ctx, y, overrides)
    if nargin < 3 || isempty(overrides), overrides = struct(); end
    r = require_field(y, 'runner');

    yaml_dir       = fileparts(ctx.yaml_path);
    [~, yaml_stem] = fileparts(ctx.yaml_path);

    tmpl_path   = resolve_rel(require_field(r, 'input_template'), yaml_dir);
    input_file  = optional_field(r, 'input_file',  'input.txt');
    output_file = require_field(r, 'output_file');
    cmd_tmpl    = require_field(r, 'command');
    parse_spec  = require_field(r, 'output_parse');
    out_spec    = optional_field(r, 'output', struct());
    cwd_mode    = optional_field(r, 'cwd',    'repo_root');

    % Run dir under runs/external/<yaml_stem>/<param_key>/
    param_key = external_param_key(overrides);
    run_dir   = fullfile(ctx.repo_root, 'runs', 'external', yaml_stem, param_key);
    if ~exist(run_dir, 'dir'), mkdir(run_dir); end

    % Merge YAML defaults with overrides
    params = merge_defaults(y, overrides);

    % Write substituted input
    tmpl_txt   = fileread(tmpl_path);
    input_txt  = substitute(tmpl_txt, params);
    input_path = fullfile(run_dir, input_file);
    fid = fopen(input_path, 'w');
    if fid < 0, error('external_backend: cannot write %s', input_path); end
    fprintf(fid, '%s', input_txt); fclose(fid);

    output_path = fullfile(run_dir, output_file);

    % Build the command
    cmd = cmd_tmpl;
    cmd = strrep(cmd, '{input_file}',  input_path);
    cmd = strrep(cmd, '{output_file}', output_path);
    cmd = strrep(cmd, '{run_dir}',     run_dir);
    cmd = strrep(cmd, '{yaml_dir}',    yaml_dir);
    cmd = strrep(cmd, '{repo_root}',   ctx.repo_root);

    cwd = pick_cwd(cwd_mode, ctx.repo_root, run_dir, yaml_dir);
    [status, log] = system(sprintf('cd "%s" && %s', cwd, cmd));

    % Persist raw command output for debugging
    lf = fopen(fullfile(run_dir, 'run.log'), 'w');
    if lf > 0, fprintf(lf, '%s', log); fclose(lf); end

    q.value = NaN; q.label = optional_field(out_spec, 'label', 'QoI');
    q.unit  = optional_field(out_spec, 'unit', ''); q.raw = []; q.ok = false;

    if status ~= 0
        out = pack_out(q, run_dir, yaml_stem, output_path, overrides, ctx);
        return;
    end
    if ~exist(output_path, 'file')
        error('external_backend: %s did not produce %s', cmd, output_path);
    end

    pattern = require_field(parse_spec, 'pattern');
    group   = optional_field(parse_spec, 'group', 1);
    output_txt = fileread(output_path);
    tokens = regexp(output_txt, pattern, 'tokens', 'once');
    if isempty(tokens)
        error('external_backend: pattern "%s" not found in %s', pattern, output_path);
    end
    if numel(tokens) < group
        error('external_backend: regexp matched but capture group %d absent', group);
    end
    val = str2double(tokens{group});
    if isnan(val)
        error('external_backend: cannot parse "%s" as number', tokens{group});
    end

    q.value = val; q.ok = true;
    out = pack_out(q, run_dir, yaml_stem, output_path, overrides, ctx);
end


% =========================================================================
function out = pack_out(q, run_dir, yaml_stem, output_path, overrides, ctx)
    out.qoi       = q;
    out.run_dir   = run_dir;
    out.case      = yaml_stem;
    out.files     = {output_path};
    out.overrides = overrides;
    out.yaml_path = ctx.yaml_path;
end


function params = merge_defaults(y, overrides)
    params = struct();
    if isfield(y, 'tunable_parameters') && ~isempty(y.tunable_parameters)
        tps = y.tunable_parameters;
        if iscell(tps)
            for i = 1:numel(tps)
                t = tps{i};
                if isfield(t, 'name') && isfield(t, 'current_value')
                    params.(t.name) = to_num_or_str(t.current_value);
                end
            end
        elseif isstruct(tps)
            for i = 1:numel(tps)
                t = tps(i);
                if isfield(t, 'name') && isfield(t, 'current_value')
                    params.(t.name) = to_num_or_str(t.current_value);
                end
            end
        end
    end
    fn = fieldnames(overrides);
    for i = 1:numel(fn), params.(fn{i}) = overrides.(fn{i}); end
end


function v = to_num_or_str(x)
    if isnumeric(x), v = double(x); return; end
    if ischar(x) || isstring(x)
        nv = str2double(char(x));
        if ~isnan(nv), v = nv; else, v = char(x); end
        return;
    end
    v = x;
end


function s = substitute(tmpl, params)
    s = tmpl;
    fn = fieldnames(params);
    for i = 1:numel(fn)
        v = params.(fn{i});
        if isnumeric(v), str = num2str(v, '%.15g'); else, str = char(v); end
        s = strrep(s, ['{' fn{i} '}'], str);
    end
end


function p = resolve_rel(rel, base_dir)
    if isempty(rel)
        error('external_backend: template path is empty');
    end
    rel = char(rel);
    if isabsolute(rel)
        p = rel;
    else
        p = fullfile(base_dir, rel);
    end
    if ~exist(p, 'file')
        error('external_backend: template file not found: %s', p);
    end
end


function tf = isabsolute(p)
    tf = ~isempty(p) && (p(1) == filesep || (numel(p) >= 2 && p(2) == ':'));
end


function v = require_field(s, f)
    if ~isstruct(s) || ~isfield(s, f) || isempty(s.(f))
        error('external_backend: y.runner.%s is required', f);
    end
    v = s.(f);
end


function v = optional_field(s, f, dflt)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = dflt;
    end
end


function cwd = pick_cwd(mode, repo_root, run_dir, yaml_dir)
    switch lower(char(mode))
        case 'repo_root', cwd = repo_root;
        case 'run_dir',   cwd = run_dir;
        case 'yaml_dir',  cwd = yaml_dir;
        otherwise, error('external_backend: cwd must be repo_root | run_dir | yaml_dir');
    end
end


function key = external_param_key(overrides)
    if isempty(overrides) || isempty(fieldnames(overrides))
        key = 'default'; return;
    end
    fn = fieldnames(overrides);
    parts = cell(numel(fn), 1);
    for i = 1:numel(fn)
        v = overrides.(fn{i});
        if isnumeric(v), s = sprintf('%.4g', v); else, s = char(v); end
        parts{i} = [fn{i} '_' regexprep(s, '[^a-zA-Z0-9._-]', '_')];
    end
    key = strjoin(parts, '_');
    if length(key) > 60, key = key(1:60); end
end
