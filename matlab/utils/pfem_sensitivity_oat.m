function result = pfem_sensitivity_oat(repo_root, pfem_root, yaml_path, specs, varargin)
% PFEM_SENSITIVITY_OAT  One-at-a-time (OAT) sensitivity analysis.
%
%   result = pfem_sensitivity_oat(repo_root, pfem_root, yaml_path, specs)
%
% For each parameter, run PFEM at the parameter's mean while all other
% parameters are also at their means (baseline), then run at mean - sigma
% and mean + sigma with all other parameters fixed at their means. The
% spread (QoI_high - QoI_low) measures how much that single parameter
% influences the QoI; it is what tornado plots display.
%
% A k-parameter analysis costs 2k + 1 PFEM runs.
%
% Inputs:
%   repo_root, pfem_root  paths
%   yaml_path             benchmark YAML
%   specs : struct array, one per parameter, with fields
%     .name    parameter name (must appear in the YAML's tunables)
%     .dist    'lognormal' | 'normal' | 'truncnormal' | 'uniform'
%     .mu      mean (or midpoint for uniform)
%     .cov     coefficient of variation (defines sigma = mu*cov)
%     .bounds  [lo hi] (used by truncnormal and uniform; clip otherwise)
%
% Name-value:
%   'Fixed'    struct of additional parameters to fix at given values
%   'Verbose'  logical, default true
%
% Output:
%   result struct with fields:
%     .param_names   cell array of parameter names
%     .qoi_label     string from the QoI dispatcher
%     .qoi_unit      string
%     .qoi_baseline  scalar, baseline QoI at all means
%     .qoi_low       k x 1, QoI when each param is at mean - sigma
%     .qoi_high      k x 1, QoI when each param is at mean + sigma
%     .lo_value      k x 1, the actual mean - sigma value used (with clipping)
%     .hi_value      k x 1, the actual mean + sigma value used (with clipping)
%     .sensitivity   k x 1, signed sensitivity = (qoi_high - qoi_low) / 2
%     .abs_sens      k x 1, absolute sensitivity
%     .order         k x 1, indices sorted by abs_sens descending
%     .case_type     case-type string used by the QoI dispatcher
%
% Internal use note: assumes pfem_run_from_yaml, pfem_detect_case_type,
% and pfem_extract_qoi are on the path.

    p = inputParser;
    addParameter(p, 'Fixed', struct(), @isstruct);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, varargin{:});
    fixed   = p.Results.Fixed;
    verbose = p.Results.Verbose;

    k = numel(specs);
    result = struct( ...
        'param_names', {{}}, 'qoi_label', '', 'qoi_unit', '', ...
        'qoi_baseline', NaN, ...
        'qoi_low',  NaN(k, 1), 'qoi_high',  NaN(k, 1), ...
        'lo_value', NaN(k, 1), 'hi_value',  NaN(k, 1), ...
        'sensitivity', NaN(k, 1), 'abs_sens', NaN(k, 1), 'order', (1:k)', ...
        'case_type', '');
    if k == 0, return; end

    addpath(fullfile(repo_root, 'matlab', 'backends'));
    y = pfem_yaml_load(yaml_path);
    case_type = pfem_detect_case_type(y);
    b = get_backend(y);              % backend-dispatched QoI extraction
    result.case_type = case_type;

    names = cell(k, 1);
    for j = 1:k, names{j} = specs(j).name; end
    result.param_names = names;

    % Baseline: all parameters at their mean.
    base_overrides = fixed;
    for j = 1:k
        base_overrides.(specs(j).name) = mean_value(specs(j));
    end

    if verbose, fprintf('  baseline (all means)... '); end
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, base_overrides);
    if status ~= 0
        if verbose, fprintf('FAILED (status=%d)\n', status); end
        return;
    end
    q0 = b.extract_qoi(out, case_type);
    if ~q0.ok
        if verbose, fprintf('extraction failed\n'); end
        return;
    end
    result.qoi_baseline = q0.value;
    result.qoi_label    = q0.label;
    result.qoi_unit     = q0.unit;
    if verbose, fprintf('%s = %.4g\n', q0.label, q0.value); end

    % For each parameter, run at mean - sigma and mean + sigma.
    for j = 1:k
        s = specs(j);
        [v_lo, v_hi] = pm_sigma(s);
        result.lo_value(j) = v_lo;
        result.hi_value(j) = v_hi;

        for tag = {'lo', 'hi'}
            ov = base_overrides;
            if strcmp(tag{1}, 'lo'), ov.(s.name) = v_lo; else, ov.(s.name) = v_hi; end
            if verbose
                fprintf('  %s @ %s = %.4g ... ', s.name, tag{1}, ov.(s.name));
            end
            try
                [status_j, out_j] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, ov);
                if status_j == 0
                    qj = b.extract_qoi(out_j, case_type);
                    if qj.ok
                        if strcmp(tag{1}, 'lo')
                            result.qoi_low(j) = qj.value;
                        else
                            result.qoi_high(j) = qj.value;
                        end
                        if verbose, fprintf('%s = %.4g\n', qj.label, qj.value); end
                    else
                        if verbose, fprintf('extraction failed\n'); end
                    end
                else
                    if verbose, fprintf('FAILED (status=%d)\n', status_j); end
                end
            catch ME
                if verbose, fprintf('ERROR: %s\n', ME.message); end
            end
        end
    end

    result.sensitivity = (result.qoi_high - result.qoi_low) / 2;
    result.abs_sens    = abs(result.sensitivity);
    [~, ord] = sort(result.abs_sens, 'descend', 'MissingPlacement', 'last');
    result.order = ord(:);
end


function v = mean_value(s)
% Mean of a distribution spec. For uniform, this is the midpoint of bounds.
    if strcmpi(s.dist, 'uniform')
        if isfield(s, 'bounds') && numel(s.bounds) == 2
            v = (s.bounds(1) + s.bounds(2)) / 2;
        else
            v = 0;
        end
    else
        v = s.mu;
    end
end


function [v_lo, v_hi] = pm_sigma(s)
% Return mean - sigma and mean + sigma, clipped to bounds when present.
% For lognormal with cov >= 0.5 the lower bound can collide with 0; we use
% the lognormal's geometric +/- 1 sigma instead so the lower value stays
% strictly positive (matches what the lognormal sampler would draw).
    if strcmpi(s.dist, 'uniform')
        if isfield(s, 'bounds') && numel(s.bounds) == 2
            v_lo = s.bounds(1);
            v_hi = s.bounds(2);
        else
            v_lo = -1; v_hi = 1;
        end
        return;
    end

    if strcmpi(s.dist, 'lognormal')
        sigma = s.mu * s.cov;
        sig_ln = sqrt(log(1 + (sigma/s.mu)^2));
        mu_ln  = log(s.mu) - sig_ln^2 / 2;
        v_lo = exp(mu_ln - sig_ln);
        v_hi = exp(mu_ln + sig_ln);
    else
        sigma = s.mu * s.cov;
        v_lo = s.mu - sigma;
        v_hi = s.mu + sigma;
    end

    if isfield(s, 'bounds') && numel(s.bounds) == 2
        v_lo = max(s.bounds(1), v_lo);
        v_hi = min(s.bounds(2), v_hi);
    end
end
