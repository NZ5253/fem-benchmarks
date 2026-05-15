function samples = pfem_lhs_sample(specs, n, varargin)
% PFEM_LHS_SAMPLE  Latin Hypercube Sampling for multiple distributions.
%
%   samples = pfem_lhs_sample(specs, n)
%   samples = pfem_lhs_sample(specs, n, 'Seed', 42)
%
% Generates n joint samples across k parameters using Latin Hypercube
% Sampling. For each parameter, the cumulative-probability axis [0,1] is
% divided into n equal-probability strata; one random sample is drawn from
% each stratum, and the resulting n values are randomly permuted before
% being inverse-transformed to the physical scale. This guarantees full
% marginal coverage of every parameter with only n simulations.
%
% Inputs:
%   specs : k x 1 struct array with fields:
%             .dist    'lognormal' | 'normal' | 'truncnormal' | 'uniform'
%             .mu      mean (ignored for 'uniform')
%             .cov     coefficient of variation (ignored for 'uniform')
%             .bounds  [lo hi] (required for 'uniform' and 'truncnormal',
%                       optional clip for others)
%   n     : sample count
%   Name-value:
%     'Seed' integer  RNG seed for reproducibility
%
% Output:
%   samples : n x k matrix; column j is parameter j on its physical scale
%
% Uses base MATLAB only: erfinv for normal inverse CDF, no Statistics
% Toolbox needed.
%
% Reference: McKay, Beckman & Conover (1979), Technometrics 21(2):239-245.

    p = inputParser;
    addParameter(p, 'Seed', [], @(x) isnumeric(x) && isscalar(x));
    parse(p, varargin{:});
    seed = p.Results.Seed;

    if ~isempty(seed)
        rng(seed, 'twister');
    end

    k = numel(specs);
    if k == 0 || n <= 0
        samples = zeros(n, 0);
        return;
    end

    % Step 1: stratified U(0,1) for every (sample, parameter) cell.
    % For each column independently, sample one point per stratum and shuffle.
    U = zeros(n, k);
    for j = 1:k
        u = ((1:n)' - 1) / n + rand(n, 1) / n;   % one point per stratum
        U(:, j) = u(randperm(n));                % decorrelate across params
    end

    % Step 2: inverse-transform per parameter to its physical scale.
    samples = zeros(n, k);
    for j = 1:k
        samples(:, j) = inverse_cdf(specs(j), U(:, j));
    end
end


function x = inverse_cdf(spec, u)
% Map U(0,1) -> physical samples via the inverse CDF of the chosen distribution.
    dist = lower(spec.dist);
    switch dist
        case 'uniform'
            if ~isfield(spec, 'bounds') || numel(spec.bounds) ~= 2
                error('pfem_lhs_sample: uniform requires bounds [lo hi]');
            end
            lo = spec.bounds(1);  hi = spec.bounds(2);
            x = lo + (hi - lo) .* u;

        case 'normal'
            sigma = spec.mu * spec.cov;
            x = spec.mu + sigma * sqrt(2) .* erfinv(2*u - 1);
            if isfield(spec, 'bounds') && numel(spec.bounds) == 2
                x = max(spec.bounds(1), min(spec.bounds(2), x));
            end

        case 'lognormal'
            sigma = spec.mu * spec.cov;
            sig_ln = sqrt(log(1 + (sigma/spec.mu)^2));
            mu_ln  = log(spec.mu) - sig_ln^2 / 2;
            % standard normal inverse CDF via erfinv
            z = sqrt(2) .* erfinv(2*u - 1);
            x = exp(mu_ln + sig_ln * z);
            if isfield(spec, 'bounds') && numel(spec.bounds) == 2
                x = max(spec.bounds(1), min(spec.bounds(2), x));
            end

        case 'truncnormal'
            if ~isfield(spec, 'bounds') || numel(spec.bounds) ~= 2
                error('pfem_lhs_sample: truncnormal requires bounds [lo hi]');
            end
            mu    = spec.mu;
            sigma = spec.mu * spec.cov;
            lo = spec.bounds(1);  hi = spec.bounds(2);
            % Map u in (0,1) into the truncated range via inverse CDF
            Phi_lo = 0.5 * (1 + erf((lo - mu) / (sigma * sqrt(2))));
            Phi_hi = 0.5 * (1 + erf((hi - mu) / (sigma * sqrt(2))));
            u_t = Phi_lo + (Phi_hi - Phi_lo) .* u;
            x   = mu + sigma * sqrt(2) .* erfinv(2*u_t - 1);

        otherwise
            error('pfem_lhs_sample: unknown distribution "%s"', dist);
    end
end
