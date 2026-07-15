function ok = plot_analytic_vs_pfem(varargin)
% PLOT_ANALYTIC_VS_PFEM  Correlation figure showing PFEM p61 vs the
% analytic Prandtl oracle across a swept yield_stress parameter range.
%
% Runs 50 LHS samples through both backends via pfem_run_from_yaml,
% produces figures/analytic_vs_pfem_p61.png showing:
%
%   - Scatter of (analytic P_lim, PFEM P_lim)
%   - The y = x reference line
%   - The load-step ceiling of p61 (visible as a horizontal cluster)
%   - Sample-count / correlation coefficient
%
% Asserts Pearson r > 0.9 for samples below the plateau — a hard
% quantitative correlation gate to catch future regressions in either
% backend.
%
% Usage:
%   plot_analytic_vs_pfem()          % n = 50 samples, seed = 42
%   plot_analytic_vs_pfem('N', 30, 'Seed', 7)

    p = inputParser;
    addParameter(p, 'N',    50);
    addParameter(p, 'Seed', 42);
    parse(p, varargin{:});
    n = p.Results.N; seed = p.Results.Seed;

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    addpath(fullfile(repo_root, 'matlab', 'backends'));

    yaml_pfem = fullfile(repo_root, 'benchmarks/pfem5/chap06/p61.yaml');
    yaml_ana  = fullfile(repo_root, 'benchmarks/analytic/prandtl_bearing.yaml');

    spec = struct('name', 'yield_stress', 'dist', 'lognormal', ...
                  'mu', 100, 'cov', 0.4, 'bounds', []);
    samples = pfem_lhs_sample(spec, n, 'Seed', seed);

    fprintf('\n=== Analytic-vs-PFEM correlation (n=%d, seed=%d) ===\n', n, seed);
    plim_pfem = NaN(n, 1);
    plim_ana  = NaN(n, 1);
    for i = 1:n
        ov.yield_stress = samples(i);

        [st_p, out_p] = pfem_run_from_yaml(repo_root, pfem_root, yaml_pfem, ov);
        if st_p == 0
            qp = pfem_extract_qoi(out_p, pfem_detect_case_type(pfem_yaml_load(yaml_pfem)));
            if qp.ok, plim_pfem(i) = qp.value; end
        end

        [st_a, out_a] = pfem_run_from_yaml(repo_root, pfem_root, yaml_ana, ov);
        if st_a == 0
            plim_ana(i) = out_a.qoi.value;
        end
        if mod(i, 10) == 0, fprintf('  ... %d/%d\n', i, n); end
    end

    valid = ~isnan(plim_pfem) & ~isnan(plim_ana);
    fprintf('  valid samples: %d / %d\n', sum(valid), n);

    % Off-plateau samples where PFEM has not saturated: analytic < 500
    off_cap = valid & (plim_ana < 500);
    if sum(off_cap) >= 5
        r_off = corrcoef(plim_ana(off_cap), plim_pfem(off_cap));
        r_off = r_off(1, 2);
        fprintf('  Pearson r on off-plateau samples: %.4f  (%d samples)\n', ...
            r_off, sum(off_cap));
        assert(r_off > 0.9, 'off-plateau correlation dropped to %.3f (<0.9)', r_off);
    else
        r_off = NaN;
        fprintf('  (too few off-plateau samples to compute r)\n');
    end

    r_all = corrcoef(plim_ana(valid), plim_pfem(valid));
    r_all = r_all(1, 2);
    fprintf('  Pearson r on all valid samples:    %.4f\n', r_all);

    % ---- Figure ----
    fig = figure('Position', [80 80 640 560], 'Color', 'w');
    ax  = axes(fig);
    scatter(ax, plim_ana(valid), plim_pfem(valid), 45, [0.2 0.5 0.8], ...
        'filled', 'MarkerFaceAlpha', 0.7);
    hold(ax, 'on');
    xmax = max(plim_ana(valid)) * 1.1;
    plot(ax, [0, xmax], [0, xmax], 'k--', 'LineWidth', 1.5, 'DisplayName', 'y = x');

    % Annotate the load-step plateau at ~515 kPa (empirical)
    pcap = 515;
    if any(plim_pfem(valid) > pcap * 0.98)
        plot(ax, [0, xmax], [pcap, pcap], 'r:', 'LineWidth', 1.5, ...
            'DisplayName', sprintf('PFEM load-step ceiling ~%.0f kPa', pcap));
    end

    xlabel(ax, 'Analytic P\_lim = (2+\pi)\cdot\sigma_y   [kPa]', 'FontSize', 14);
    ylabel(ax, 'PFEM p61 P\_lim   [kPa]', 'FontSize', 14);
    if isnan(r_off)
        title(ax, sprintf('Analytic Prandtl vs PFEM p61   (n=%d,  r_{all}=%.3f)', ...
            sum(valid), r_all), 'FontSize', 13);
    else
        title(ax, sprintf('Analytic Prandtl vs PFEM p61   (n=%d,  r_{off-plateau}=%.3f)', ...
            sum(valid), r_off), 'FontSize', 13);
    end
    grid(ax, 'on'); box(ax, 'on');
    legend(ax, 'Location', 'southeast');

    fig_dir = fullfile(repo_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
    fig_path = fullfile(fig_dir, 'analytic_vs_pfem_p61.png');
    print(fig, fig_path, '-dpng', '-r200');
    fprintf('  wrote %s\n', fig_path);
    fprintf('==================================================\n');
    close(fig);
    ok = true;
end
