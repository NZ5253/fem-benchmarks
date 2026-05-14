function samples = pfem_sample_distribution(type, mu, cov_or_sigma, n, varargin)
% PFEM_SAMPLE_DISTRIBUTION  Draw n samples from a named distribution.
%
%   samples = pfem_sample_distribution(type, mu, cov, n)
%   samples = pfem_sample_distribution(type, mu, cov, n, 'Bounds', [lo hi])
%
% No Statistics Toolbox required — uses base MATLAB only.
%
% Inputs:
%   type  — 'lognormal', 'normal', 'truncnormal', 'uniform'
%   mu    — mean value of the physical quantity
%   cov_or_sigma — coefficient of variation (dimensionless, e.g. 0.3 = 30%)
%                  For 'uniform': ignored (uses Bounds instead)
%   n     — number of samples to generate
%
% Name-value options:
%   'Bounds'  [lo hi] — hard physical bounds (required for 'truncnormal';
%                        optional for others — clips output)
%   'Seed'    integer — RNG seed for reproducibility
%
% Examples:
%   c   = pfem_sample_distribution('lognormal', 60, 0.30, 100);
%   nu  = pfem_sample_distribution('truncnormal', 0.3, 0.10, 50, 'Bounds', [0 0.499]);
%   c   = pfem_sample_distribution('lognormal', 60, 0.30, 100, 'Seed', 42);

    % ---- Parse optional arguments ----
    p = inputParser;
    addParameter(p, 'Bounds', [], @(x) isnumeric(x) && numel(x)==2);
    addParameter(p, 'Seed',   [], @(x) isnumeric(x) && isscalar(x));
    parse(p, varargin{:});
    bounds = p.Results.Bounds;
    seed   = p.Results.Seed;

    if ~isempty(seed)
        rng(seed, 'twister');
    end

    sigma = mu * cov_or_sigma;   % physical standard deviation

    switch lower(type)

        case 'lognormal'
            % X = exp(Z) where Z ~ Normal(mu_ln, sigma_ln)
            % Parameterised so E[X] = mu, Std[X] = sigma
            sigma_ln = sqrt(log(1 + (sigma/mu)^2));
            mu_ln    = log(mu) - sigma_ln^2 / 2;
            samples  = exp(mu_ln + sigma_ln * randn(n, 1));

        case 'normal'
            samples = mu + sigma * randn(n, 1);

        case 'truncnormal'
            if isempty(bounds)
                error('pfem_sample_distribution: ''truncnormal'' requires ''Bounds'' [lo hi].');
            end
            lo = bounds(1);  hi = bounds(2);
            % Inverse-CDF method for truncated normal (no toolbox needed)
            Phi_lo = 0.5 * (1 + erf((lo - mu) / (sigma * sqrt(2))));
            Phi_hi = 0.5 * (1 + erf((hi - mu) / (sigma * sqrt(2))));
            u = Phi_lo + (Phi_hi - Phi_lo) * rand(n, 1);
            % norminv via erfinv
            samples = mu + sigma * sqrt(2) * erfinv(2*u - 1);

        case 'uniform'
            if isempty(bounds)
                error('pfem_sample_distribution: ''uniform'' requires ''Bounds'' [lo hi].');
            end
            lo = bounds(1);  hi = bounds(2);
            samples = lo + (hi - lo) * rand(n, 1);

        otherwise
            error('pfem_sample_distribution: unknown distribution type "%s".', type);
    end

    % ---- Apply hard bounds (clip) for unbounded distributions ----
    if ~isempty(bounds) && ~ismember(lower(type), {'uniform', 'truncnormal'})
        samples = max(bounds(1), min(bounds(2), samples));
    end
end
