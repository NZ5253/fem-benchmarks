function scenarios = pfem_make_scenarios(varargin)
% PFEM_MAKE_SCENARIOS  Build a scenario struct array for multi-parameter sweeps.
%
% Each scenario is one complete set of parameter overrides applied together.
% A 'label' field is auto-generated for each scenario.
%
% ---- Single-parameter sweep ----
%   scenarios = pfem_make_scenarios('yield_stress', [50, 100, 200, 500]);
%
% ---- Multiple parameters varied in lockstep ----
%   (all value arrays must have the same length)
%   scenarios = pfem_make_scenarios( ...
%       'yield_stress',     [50,   100,  200], ...
%       'youngs_modulus_E', [1e5,  2e5,  1e5]);
%
% ---- Fully manual construction ----
%   scenarios(1) = struct('label','soft',  'yield_stress',50,  'youngs_modulus_E',1e5);
%   scenarios(2) = struct('label','stiff', 'yield_stress',200, 'youngs_modulus_E',2e5);
%   % (label is optional — NZ.m auto-fills missing labels with 'sc1','sc2',...)
%
% The returned struct array has one element per scenario, with:
%   .label   — short human-readable identifier (e.g. 'sy=50 E=1e5')
%   .<param> — one field per parameter

    if mod(numel(varargin), 2) ~= 0
        error('pfem_make_scenarios: arguments must be name/value pairs.');
    end

    n_params = numel(varargin) / 2;
    param_names = cell(n_params, 1);
    param_vals  = cell(n_params, 1);
    n_scenarios = [];

    for k = 1:n_params
        param_names{k} = varargin{2*k - 1};
        vals = varargin{2*k};
        if ~isnumeric(vals) || ~isvector(vals)
            error('pfem_make_scenarios: values for "%s" must be a numeric vector.', ...
                  param_names{k});
        end
        param_vals{k} = vals(:)';
        if isempty(n_scenarios)
            n_scenarios = numel(vals);
        elseif numel(vals) ~= n_scenarios
            error('pfem_make_scenarios: all value arrays must be the same length (%d vs %d for "%s").', ...
                  n_scenarios, numel(vals), param_names{k});
        end
    end

    % Build each scenario as a struct, collect in cell, then concat into array.
    % (Pre-initialising with struct() creates a fieldless 1×1 stub that
    %  MATLAB refuses to overwrite with a struct that has fields.)
    sc_list = cell(1, n_scenarios);
    for si = 1:n_scenarios
        sc = struct();
        label_parts = {};
        for k = 1:n_params
            pname = param_names{k};
            pval  = param_vals{k}(si);
            sc.(pname) = pval;
            label_parts{end+1} = sprintf('%s=%s', short_name(pname), fmt(pval)); %#ok<AGROW>
        end
        sc.label   = strjoin(label_parts, ' ');
        sc_list{si} = sc;
    end

    if isempty(sc_list)
        scenarios = struct([]);
    else
        scenarios = [sc_list{:}];
    end
end


% --------------------------------------------------------------------------
function s = short_name(pname)
% Return a brief abbreviation for a parameter name used in scenario labels.
    abbrev = struct( ...
        'youngs_modulus_E',       'E',     ...
        'poisson_ratio_nu',       'nu',    ...
        'yield_stress',           'sy',    ...
        'convergence_tolerance',  'tol',   ...
        'iteration_limit',        'lim',   ...
        'load_increments',        'incs',  ...
        'nels_or_nxe',            'nxe',   ...
        'np_types_or_nye',        'nye',   ...
        'friction_angle_phi',     'phi',   ...
        'cohesion_c',             'c',     ...
        'dilation_angle_psi',     'psi',   ...
        'permeability_k_or_cv',   'k',     ...
        'time_step',              'dt',    ...
        'num_time_steps',         'nstep', ...
        'theta_parameter',        'theta', ...
        'damping_fm',             'fm',    ...
        'damping_fk',             'fk',   ...
        'density_rho',            'rho',  ...
        'bulk_modulus_ke',        'ke'    ...
    );
    if isfield(abbrev, pname)
        s = abbrev.(pname);
    else
        % Strip long common prefixes then cap length
        s = regexprep(pname, ...
            '^(youngs_modulus_|poisson_ratio_|permeability_|convergence_|iteration_|num_)', '');
        s = s(1:min(6, end));
    end
end


% --------------------------------------------------------------------------
function s = fmt(v)
% Compact value string for scenario labels.
    if v == 0
        s = '0';
    elseif abs(v) >= 1e4 || (abs(v) < 0.01 && v ~= 0)
        s = regexprep(sprintf('%.3g', v), 'e[+]?0*(\d)', 'e$1');
        s = regexprep(s, 'e-0*(\d)', 'e-$1');
    else
        s = sprintf('%g', v);
    end
end
