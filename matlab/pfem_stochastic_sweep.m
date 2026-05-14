function results = pfem_stochastic_sweep(repo_root, pfem_root, yaml_path, param_defs, varargin)
% PFEM_STOCHASTIC_SWEEP  Monte Carlo sweep with statistical distributions.
%
%   results = pfem_stochastic_sweep(repo_root, pfem_root, yaml_path, param_defs)
%   results = pfem_stochastic_sweep(..., 'NSamples', 100, 'Seed', 42)
%
% Inputs:
%   repo_root  — path to fem-benchmarks repo
%   pfem_root  — path to pfem/ build directory
%   yaml_path  — path to the YAML benchmark definition
%   param_defs — struct array defining each stochastic parameter:
%       .name   — YAML tunable parameter name (e.g. 'cohesion_c')
%       .dist   — distribution type: 'lognormal','normal','truncnormal','beta','uniform'
%       .mu     — mean value
%       .cov    — coefficient of variation (e.g. 0.30 for 30%)
%       .bounds — [lo hi] physical bounds (optional for lognormal/normal;
%                 required for truncnormal, beta, uniform)
%
% Name-value options:
%   'NSamples'    — number of Monte Carlo realisations (default: 100)
%   'Seed'        — RNG seed for reproducibility (default: [])
%   'Save'        — prefix for saving output figures (default: '' = no save)
%   'Show'        — display figures (default: true)
%   'Title'       — plot title prefix (default: from YAML)
%   'FixedParams' — struct of non-stochastic overrides (e.g. struct('friction_phi', 20))
%
% Returns:
%   results — struct with fields:
%       .samples     — n×p matrix of sampled parameter values
%       .param_names — {p×1} cell of parameter names
%       .fs          — n×1 vector of Factor of Safety for each realisation
%       .max_disp    — n×1 vector of max displacement at failure
%       .status      — n×1 vector (0=success, nonzero=failure)
%       .pf          — probability of failure P(FS < 1.0)
%       .beta        — reliability index
%       .mu_fs       — mean FS
%       .sigma_fs    — std FS
%       .runs        — full run results array (for replotting)
%
% Example:
%   % Lognormal cohesion sweep on p6.12
%   pd = struct('name','cohesion_c', 'dist','lognormal', 'mu',60, 'cov',0.30, 'bounds',[]);
%   r = pfem_stochastic_sweep(repo, pfem, yaml, pd, 'NSamples',50, 'Seed',42);
%   fprintf('P(failure) = %.1f%%,  beta = %.2f\n', r.pf*100, r.beta);

    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));

    % ---- Parse options ----
    p = inputParser;
    addParameter(p, 'NSamples',    100,   @isnumeric);
    addParameter(p, 'Seed',        [],    @isnumeric);
    addParameter(p, 'Save',        '',    @ischar);
    addParameter(p, 'Show',        true,  @islogical);
    addParameter(p, 'Title',       '',    @ischar);
    addParameter(p, 'FixedParams', struct(), @isstruct);
    parse(p, varargin{:});
    opts = p.Results;

    n_samples   = opts.NSamples;
    seed        = opts.Seed;
    save_prefix = opts.Save;
    fixed       = opts.FixedParams;

    n_params = numel(param_defs);

    % ---- Generate samples ----
    all_samples = zeros(n_samples, n_params);
    param_names = cell(n_params, 1);

    for k = 1:n_params
        pd = param_defs(k);
        param_names{k} = pd.name;

        % Use per-parameter seed offset for reproducibility
        if ~isempty(seed)
            s_k = seed + k - 1;
        else
            s_k = [];
        end

        bounds_arg = {};
        if ~isempty(pd.bounds)
            bounds_arg = {'Bounds', pd.bounds};
        end
        seed_arg = {};
        if ~isempty(s_k)
            seed_arg = {'Seed', s_k};
        end

        all_samples(:, k) = pfem_sample_distribution( ...
            pd.dist, pd.mu, pd.cov, n_samples, bounds_arg{:}, seed_arg{:});
    end

    % ---- Print summary ----
    fprintf('\n=== Stochastic Sweep: %d realisations ===\n', n_samples);
    for k = 1:n_params
        fprintf('  %s: %s(mu=%.4g, COV=%.2g)', ...
            param_names{k}, param_defs(k).dist, param_defs(k).mu, param_defs(k).cov);
        if ~isempty(param_defs(k).bounds)
            fprintf(', bounds=[%.4g, %.4g]', param_defs(k).bounds(1), param_defs(k).bounds(2));
        end
        fprintf('\n');
    end
    if ~isempty(fieldnames(fixed))
        fn = fieldnames(fixed);
        for k = 1:numel(fn)
            fprintf('  %s: %.4g (fixed)\n', fn{k}, fixed.(fn{k}));
        end
    end
    fprintf('\n');

    % ---- Run all realisations ----
    fs_vec       = NaN(n_samples, 1);
    max_disp_vec = NaN(n_samples, 1);
    status_vec   = -ones(n_samples, 1);
    run_results  = cell(n_samples, 1);

    t_start = tic;
    for i = 1:n_samples
        % Build overrides struct
        overrides = fixed;
        for k = 1:n_params
            overrides.(param_names{k}) = all_samples(i, k);
        end

        % Run
        fprintf('[%3d/%d] ', i, n_samples);
        for k = 1:n_params
            fprintf('%s=%.4g ', param_names{k}(1:min(end,8)), all_samples(i,k));
        end

        try
            [st, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, overrides);
            status_vec(i) = st;

            if st == 0
                % Extract FS from .res file
                [fs_val, dmax] = extract_factor_of_safety(out);
                fs_vec(i) = fs_val;
                max_disp_vec(i) = dmax;
                fprintf('-> FS=%.3f  dmax=%.4g\n', fs_val, dmax);
            else
                fprintf('-> FAILED (status=%d)\n', st);
            end
        catch e
            fprintf('-> ERROR: %s\n', e.message);
            status_vec(i) = -1;
        end

        run_results{i} = struct('status', status_vec(i), 'overrides', overrides, ...
            'fs', fs_vec(i), 'max_disp', max_disp_vec(i));
    end
    elapsed = toc(t_start);

    % ---- Compute statistics (only successful runs) ----
    valid = status_vec == 0 & ~isnan(fs_vec);
    fs_valid = fs_vec(valid);

    if isempty(fs_valid)
        warning('pfem_stochastic_sweep: no successful runs.');
        mu_fs = NaN; sigma_fs = NaN; pf = NaN; beta_rel = NaN;
    else
        mu_fs    = mean(fs_valid);
        sigma_fs = std(fs_valid);
        pf       = sum(fs_valid < 1.0) / numel(fs_valid);
        if pf > 0 && pf < 1
            beta_rel = -sqrt(2) * erfinv(2*pf - 1);
        elseif pf == 0
            beta_rel = Inf;
        else
            beta_rel = -Inf;
        end
    end

    % ---- Print summary ----
    fprintf('\n=== Results (%d/%d successful, %.1f s) ===\n', ...
        sum(valid), n_samples, elapsed);
    fprintf('  FS:  mean=%.3f  std=%.3f  COV=%.2f%%\n', mu_fs, sigma_fs, sigma_fs/mu_fs*100);
    fprintf('  P(failure) = %.2f%%\n', pf * 100);
    fprintf('  Reliability index beta = %.3f\n', beta_rel);
    fprintf('  FS range: [%.3f, %.3f]\n', min(fs_valid), max(fs_valid));

    % ---- Assemble output struct ----
    results = struct();
    results.samples     = all_samples;
    results.param_names = {param_names};
    results.fs          = fs_vec;
    results.max_disp    = max_disp_vec;
    results.status      = status_vec;
    results.pf          = pf;
    results.beta        = beta_rel;
    results.mu_fs       = mu_fs;
    results.sigma_fs    = sigma_fs;
    results.elapsed     = elapsed;
    results.runs        = run_results;
    results.param_defs  = param_defs;
    results.fixed       = fixed;

    % ---- Plot results ----
    if any(valid)
        plot_stochastic_results(results, opts);
    end
end


% =========================================================================
function [fs, dmax] = extract_factor_of_safety(out)
% Extract Factor of Safety from a single PFEM run output.
% FS = last SRF step where Newton-Raphson converged (iters < iter_limit).

    fs   = NaN;
    dmax = NaN;

    % Find .res file
    res_file = '';
    if isfield(out, 'files') && iscell(out.files)
        res_f = out.files(cellfun(@(f) endsWith(f, '.res'), out.files));
        if ~isempty(res_f)
            res_file = res_f{1};
        end
    end
    if isempty(res_file) || ~exist(res_file, 'file')
        % Try constructing path from run_dir
        if isfield(out, 'run_dir') && isfield(out, 'case')
            res_file = fullfile(out.run_dir, [out.case '.res']);
        end
    end
    if isempty(res_file) || ~exist(res_file, 'file')
        return;
    end

    % Read .res and look for SRF table
    % Format: lines with "step  SRF  disp  iters" or similar
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    % Parse numeric rows (typically: step_or_SRF  displacement  iterations)
    data = [];
    for j = 1:numel(lines)
        nums = str2num(lines{j}); %#ok<ST2NM>
        if ~isempty(nums) && numel(nums) >= 3
            data(end+1, :) = nums(1:3); %#ok<AGROW>
        end
    end

    if isempty(data)
        return;
    end

    srf   = data(:, 1);
    disp  = data(:, 2);
    iters = data(:, 3);

    % FS = last SRF where iterations < iteration limit
    ilimit = max(iters);
    if ilimit < 10
        % Not an SRF analysis or trivial — FS = last SRF
        fs   = srf(end);
        dmax = max(abs(disp));
        return;
    end

    fs_k = find(iters < ilimit, 1, 'last');
    if ~isempty(fs_k)
        fs   = srf(fs_k);
        dmax = disp(fs_k);
    else
        % All steps hit the limit — slope already failing at SRF=1.0
        fs   = srf(1);
        dmax = disp(1);
    end
end


% =========================================================================
function plot_stochastic_results(results, opts)
% Generate histogram, CDF, and scatter plots for stochastic sweep results.

    set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
    set(groot, 'defaultAxesFontSize', 16);

    valid = results.status == 0 & ~isnan(results.fs);
    fs = results.fs(valid);

    save_prefix = opts.Save;
    do_show = opts.Show;
    ttl = opts.Title;
    if isempty(ttl), ttl = 'Stochastic Sweep'; end

    % ---- Figure 1: FS Histogram ----
    fig1 = figure('Position', [80 80 560 420], 'Color', 'w', 'Visible', bool2vis(do_show));
    ax1 = axes(fig1);
    histogram(ax1, fs, 'Normalization', 'pdf', 'FaceColor', [0.2 0.5 0.8], ...
        'EdgeColor', 'w', 'FaceAlpha', 0.85);
    hold(ax1, 'on');

    % Overlay fitted lognormal PDF (no toolbox — method of moments)
    if numel(fs) > 5
        log_fs   = log(fs);
        mu_ln    = mean(log_fs);
        sigma_ln = std(log_fs);
        x_pdf    = linspace(min(fs)*0.9, max(fs)*1.1, 200);
        y_pdf    = (1 ./ (x_pdf * sigma_ln * sqrt(2*pi))) .* ...
                   exp(-(log(x_pdf) - mu_ln).^2 / (2 * sigma_ln^2));
        plot(ax1, x_pdf, y_pdf, 'r-', 'LineWidth', 2.5);
    end

    % FS = 1.0 line
    yl = ylim(ax1);
    plot(ax1, [1 1], yl, 'k--', 'LineWidth', 2);
    text(ax1, 1.02, yl(2)*0.9, '$\mathrm{FS}=1$', ...
        'Interpreter', 'latex', 'FontSize', 18, 'Color', 'k');

    xlabel(ax1, 'Factor of Safety', 'Interpreter', 'latex', 'FontSize', 18);
    ylabel(ax1, 'Probability Density', 'Interpreter', 'latex', 'FontSize', 18);
    title(ax1, sprintf('%s --- FS Distribution ($n=%d$)', ttl, numel(fs)), ...
        'Interpreter', 'latex', 'FontSize', 16);
    style_ax(ax1);

    % Stats annotation
    annotation(fig1, 'textbox', [0.58 0.68 0.38 0.22], ...
        'String', sprintf(['$\\mu_{\\mathrm{FS}} = %.3f$\n' ...
                           '$\\sigma_{\\mathrm{FS}} = %.3f$\n' ...
                           '$P_f = %.2f\\%%$\n' ...
                           '$\\beta = %.2f$'], ...
            results.mu_fs, results.sigma_fs, results.pf*100, results.beta), ...
        'Interpreter', 'latex', 'FontSize', 16, ...
        'EdgeColor', [0.5 0.5 0.5], 'BackgroundColor', [1 1 1 0.9], ...
        'FitBoxToText', 'on');
    hold(ax1, 'off');
    do_save(fig1, save_prefix, 'fs_hist');

    % ---- Figure 2: CDF ----
    fig2 = figure('Position', [80 80 560 420], 'Color', 'w', 'Visible', bool2vis(do_show));
    ax2 = axes(fig2);
    fs_sorted = sort(fs);
    cdf_vals = (1:numel(fs_sorted))' / numel(fs_sorted);
    plot(ax2, fs_sorted, cdf_vals, 'b-', 'LineWidth', 2.5);
    hold(ax2, 'on');
    plot(ax2, [1 1], [0 1], 'k--', 'LineWidth', 2);
    % Mark P(failure) on CDF
    if results.pf > 0 && results.pf < 1
        plot(ax2, 1, results.pf, 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
        text(ax2, 1.03, results.pf, sprintf('$P_f = %.2f\\%%$', results.pf*100), ...
            'Interpreter', 'latex', 'FontSize', 16, 'Color', 'r');
    end
    xlabel(ax2, 'Factor of Safety', 'Interpreter', 'latex', 'FontSize', 18);
    ylabel(ax2, '$P(\mathrm{FS} \leq x)$', 'Interpreter', 'latex', 'FontSize', 18);
    title(ax2, sprintf('%s --- CDF', ttl), 'Interpreter', 'latex', 'FontSize', 16);
    style_ax(ax2);
    hold(ax2, 'off');
    do_save(fig2, save_prefix, 'fs_cdf');

    % ---- Figure 3: Scatter — parameter vs FS ----
    samples_valid = results.samples(valid, :);
    param_names = results.param_names;
    if iscell(param_names) && numel(param_names)==1 && iscell(param_names{1})
        param_names = param_names{1};
    end
    n_params = size(samples_valid, 2);

    for k = 1:n_params
        fig_k = figure('Position', [80 80 560 420], 'Color', 'w', 'Visible', bool2vis(do_show));
        ax_k = axes(fig_k);
        scatter(ax_k, samples_valid(:,k), fs, 40, [0.2 0.5 0.8], 'filled', ...
            'MarkerFaceAlpha', 0.6);
        hold(ax_k, 'on');
        plot(ax_k, xlim(ax_k), [1 1], 'k--', 'LineWidth', 2);
        xlabel(ax_k, strrep(param_names{k}, '_', '\_'), ...
            'Interpreter', 'latex', 'FontSize', 18);
        ylabel(ax_k, 'Factor of Safety', 'Interpreter', 'latex', 'FontSize', 18);
        title(ax_k, sprintf('%s --- %s vs FS', ttl, strrep(param_names{k}, '_', '\_')), ...
            'Interpreter', 'latex', 'FontSize', 16);
        style_ax(ax_k);
        hold(ax_k, 'off');
        do_save(fig_k, save_prefix, sprintf('fs_scatter_%s', param_names{k}));
    end

    if ~do_show
        close all;
    end
end


% =========================================================================
function style_ax(ax)
    set(ax, 'Color', [1 1 1], ...
        'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15], ...
        'GridColor', [0.80 0.80 0.80], 'GridAlpha', 0.5, ...
        'FontSize', 16, 'LineWidth', 1.2, ...
        'TickLabelInterpreter', 'latex');
    box(ax, 'on');
    grid(ax, 'on');
end


function do_save(fig, prefix, tag)
    if isempty(prefix), return; end
    out_pdf = [prefix '_' tag '.pdf'];
    out_png = [prefix '_' tag '.png'];
    d = fileparts(out_png);
    if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
    drawnow('expose');
    try
        exportgraphics(fig, out_pdf, 'ContentType', 'vector', 'BackgroundColor', 'white');
        fprintf('  Saved: %s\n', out_pdf);
    catch
    end
    print(fig, out_png, '-dpng', '-r250');
    fprintf('  Saved: %s\n', out_png);
end


function v = bool2vis(b)
    if b, v = 'on'; else, v = 'off'; end
end
