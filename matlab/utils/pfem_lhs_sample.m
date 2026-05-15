function samples = pfem_lhs_sample(specs, n, varargin)
% PFEM_LHS_SAMPLE  Latin Hypercube Sampling for multiple distributions.
%
%   samples = pfem_lhs_sample(specs, n)
%   samples = pfem_lhs_sample(specs, n, 'Seed', 42)
%   samples = pfem_lhs_sample(specs, n, 'Correlation', R)
%
% Generates n joint samples across k parameters using Latin Hypercube
% Sampling. For each parameter, the cumulative-probability axis [0,1] is
% divided into n equal-probability strata; one random sample is drawn from
% each stratum, and the resulting n values are randomly permuted before
% being inverse-transformed to the physical scale. This guarantees full
% marginal coverage of every parameter with only n simulations.
%
% When 'Correlation' is supplied the columns are reordered using the
% Iman-Conover (1982) restricted-pairing method, which induces the target
% rank correlation while preserving each column's LHS marginal stratification.
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
%     'Seed'        integer    RNG seed for reproducibility
%     'Correlation' k x k matrix R (symmetric, unit diagonal, |R(i,j)| <= 1)
%                   OR p x 3 list of [i, j, rho] triples to apply over identity
%
% Output:
%   samples : n x k matrix; column j is parameter j on its physical scale
%
% Uses base MATLAB only: erfinv for normal inverse CDF, no Statistics
% Toolbox needed.
%
% References:
%   McKay, Beckman & Conover (1979), Technometrics 21(2):239-245
%   Iman & Conover (1982), Communications in Statistics 11(3):311-334

    p = inputParser;
    addParameter(p, 'Seed',        [], @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'Correlation', [], @(x) isnumeric(x));
    parse(p, varargin{:});
    seed = p.Results.Seed;
    rho_in = p.Results.Correlation;

    if ~isempty(seed)
        rng(seed, 'twister');
    end

    k = numel(specs);
    if k == 0 || n <= 0
        samples = zeros(n, 0);
        return;
    end

    R = build_correlation_matrix(rho_in, k);

    % Step 1: stratified U(0,1) for every (sample, parameter) cell.
    U = zeros(n, k);
    for j = 1:k
        u = ((1:n)' - 1) / n + rand(n, 1) / n;   % one point per stratum
        U(:, j) = u(randperm(n));                % decorrelate across params
    end

    % Step 2 (optional): Iman-Conover reordering to match target correlation.
    if ~isempty(R) && ~isequal(R, eye(k)) && k >= 2
        U = iman_conover_reorder(U, R);
    end

    % Step 3: inverse-transform per parameter to its physical scale.
    samples = zeros(n, k);
    for j = 1:k
        samples(:, j) = inverse_cdf(specs(j), U(:, j));
    end
end


function R = build_correlation_matrix(rho_in, k)
% Accept either a full k x k matrix or a list of [i, j, rho] triples.
    R = [];
    if isempty(rho_in), return; end
    if size(rho_in, 1) == k && size(rho_in, 2) == k
        R = rho_in;
    elseif size(rho_in, 2) == 3
        R = eye(k);
        for r = 1:size(rho_in, 1)
            i   = round(rho_in(r, 1));
            j   = round(rho_in(r, 2));
            rho = rho_in(r, 3);
            if i < 1 || i > k || j < 1 || j > k || i == j
                error('pfem_lhs_sample: bad correlation pair (%d, %d) for k=%d', i, j, k);
            end
            if abs(rho) > 1
                error('pfem_lhs_sample: correlation rho=%g out of [-1, 1]', rho);
            end
            R(i, j) = rho;
            R(j, i) = rho;
        end
    else
        error('pfem_lhs_sample: ''Correlation'' must be %dx%d matrix or Nx3 [i,j,rho] list', k, k);
    end
    % Symmetry and unit diagonal
    R = (R + R') / 2;
    R(1:k+1:end) = 1;
    % Positive-definiteness check via eigenvalues; nudge if borderline
    [V, D] = eig(R);
    d = real(diag(D));
    if any(d < 1e-10)
        d = max(d, 1e-10);
        R = V * diag(d) * V';
        R = (R + R') / 2;
        R(1:k+1:end) = 1;
    end
end


function U_out = iman_conover_reorder(U, R)
% Iman-Conover: reorder each column of U so that the resulting rank
% correlation matches R, while preserving every column's marginal values.
    [n, k] = size(U);

    % Van der Waerden scores: invert standard-normal CDF on rank/(n+1).
    ranks = zeros(n, k);
    for j = 1:k
        [~, p] = sort(U(:, j));
        rj = zeros(n, 1);
        rj(p) = 1:n;
        ranks(:, j) = rj;
    end
    scores = sqrt(2) .* erfinv(2 * (ranks / (n + 1)) - 1);

    % Build a target-correlated reference matrix Y of size n x k.
    L = chol(R, 'lower');
    Z = randn(n, k);
    % De-correlate Z by its own sample correlation, then apply target.
    S = corrcoef(Z);
    if any(~isfinite(S(:)))
        S = eye(k);
    end
    L_S = chol(S, 'lower');
    Y = (Z / L_S') * L';

    % Permute each column of U to match the rank order of Y.
    U_out = zeros(n, k);
    for j = 1:k
        % Sort scores ascending; we want U column reordered so that its
        % rank order in the output matches the rank order of Y(:,j).
        [~, sort_score_idx] = sort(scores(:, j));   % ascending positions of input ranks
        [~, sort_y_idx]     = sort(Y(:, j));         % ascending positions of target ranks
        U_perm = zeros(n, 1);
        U_perm(sort_y_idx) = U(sort_score_idx, j);
        U_out(:, j) = U_perm;
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
