function b = analytic_backend()
% ANALYTIC_BACKEND  Closed-form oracle backend (Phase 3 milestone M3).
%
% Selects a small library of analytic solutions used as independent
% references against PFEM. Which formula runs is chosen by y.runner.model
% (also read from y.runner.type='analytic' via get_backend).
%
% Currently supported models:
%
%   prandtl_bearing  P_lim = (2 + pi) * yield_stress
%                    (Prandtl strip-footing limit load, Tresca / undrained)
%                    Cross-checked against PFEM p61 in test_analytic_backend.
%
% out.qoi carries the computed QoI struct; b.extract_qoi passes it through so
% callers see the same {value, label, unit, ok} shape as pfem_extract_qoi.

    b.name           = 'analytic';
    b.run            = @analytic_run;
    b.extract_qoi    = @(out, ~) out.qoi;
    b.non_sampleable = @(y) {};   % nothing off-limits for closed-form models
end


function [status, out] = analytic_run(ctx, y, overrides)
    if nargin < 3 || isempty(overrides), overrides = struct(); end

    model = '';
    if isfield(y, 'runner') && isstruct(y.runner) && isfield(y.runner, 'model')
        model = lower(strtrim(char(y.runner.model)));
    end
    if isempty(model)
        error('analytic_backend: y.runner.model is required (e.g. "prandtl_bearing")');
    end

    switch model
        case 'prandtl_bearing'
            sigma_y = fetch_param(y, overrides, 'yield_stress');
            q.value = (2 + pi) * sigma_y;
            q.label = 'P_lim';
            q.unit  = fetch_unit(y, 'yield_stress', 'kPa');
            q.raw   = [];
            q.ok    = true;
        otherwise
            error('analytic_backend: unknown model "%s"', model);
    end

    out.qoi     = q;
    out.model   = model;
    out.case    = model;
    out.files   = {};
    out.run_dir = '';
    if isfield(ctx, 'yaml_path'), out.yaml_path = ctx.yaml_path; end
    out.overrides = overrides;

    status = 0;
end


function v = fetch_param(y, overrides, name)
% Look up a scalar parameter: overrides take precedence over YAML default.
    if isfield(overrides, name) && ~isempty(overrides.(name))
        v = double(overrides.(name));
        return;
    end
    tp = find_tunable(y, name);
    if isempty(tp)
        error('analytic_backend: parameter "%s" not in overrides or tunables', name);
    end
    if isfield(tp, 'current_value')
        v = to_num(tp.current_value);
    else
        error('analytic_backend: tunable "%s" has no current_value', name);
    end
end


function u = fetch_unit(y, name, default_unit)
    tp = find_tunable(y, name);
    if ~isempty(tp) && isfield(tp, 'unit') && ~isempty(tp.unit)
        u = char(tp.unit);
    else
        u = default_unit;
    end
end


function tp = find_tunable(y, name)
% Return the tunable_parameter entry matching `name` or [] if not found.
% Handles both cell-of-structs (typical from pfem_yaml_load) and struct arrays.
    tp = [];
    if ~isfield(y, 'tunable_parameters') || isempty(y.tunable_parameters)
        return;
    end
    tps = y.tunable_parameters;
    if iscell(tps)
        for i = 1:numel(tps)
            if isfield(tps{i}, 'name') && strcmp(tps{i}.name, name)
                tp = tps{i}; return;
            end
        end
    elseif isstruct(tps)
        for i = 1:numel(tps)
            if isfield(tps(i), 'name') && strcmp(tps(i).name, name)
                tp = tps(i); return;
            end
        end
    end
end


function v = to_num(x)
    if isnumeric(x), v = double(x); return; end
    if ischar(x) || isstring(x)
        v = str2double(char(x));
        if isnan(v)
            error('analytic_backend: cannot parse numeric value from "%s"', char(x));
        end
        return;
    end
    error('analytic_backend: unexpected numeric type %s', class(x));
end
