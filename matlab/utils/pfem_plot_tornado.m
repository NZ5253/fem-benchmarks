function fig = pfem_plot_tornado(result, varargin)
% PFEM_PLOT_TORNADO  Tornado plot from a sensitivity-OAT result struct.
%
%   fig = pfem_plot_tornado(result)
%   fig = pfem_plot_tornado(result, 'Title', 'p612 sensitivity', 'Save', '/tmp/p612_tornado')
%
% Each parameter is a horizontal bar centered at the baseline QoI; the bar
% extends from the QoI value at parameter mean - sigma to the value at
% parameter mean + sigma. Bars are sorted by absolute spread (largest at top).
%
% Inputs:
%   result : struct from pfem_sensitivity_oat
%
% Name-value:
%   'Title'  string for plot title
%   'Save'   path prefix; writes '<prefix>.pdf' and '<prefix>.png'
%
% Output:
%   fig : the figure handle

    p = inputParser;
    addParameter(p, 'Title', 'Sensitivity (tornado)', @(x) ischar(x) || isstring(x));
    addParameter(p, 'Save',  '', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});
    ttl  = char(p.Results.Title);
    save_prefix = char(p.Results.Save);

    if ~isfield(result, 'param_names') || isempty(result.param_names)
        fig = figure('Visible', 'off');  return;
    end

    ord    = result.order(:);
    names  = result.param_names(ord);
    lo     = result.qoi_low(ord);
    hi     = result.qoi_high(ord);
    base   = result.qoi_baseline;
    label  = result.qoi_label;
    unit   = result.qoi_unit;

    % Drop NaN rows (params that failed extraction)
    valid = ~(isnan(lo) | isnan(hi));
    names = names(valid);
    lo    = lo(valid);
    hi    = hi(valid);
    n     = numel(names);
    if n == 0
        fig = figure('Visible', 'off');  return;
    end

    % Plot order: largest spread at the top (so reverse for barh which
    % stacks from the bottom up)
    names = flipud(names);
    lo    = flipud(lo);
    hi    = flipud(hi);

    % Each bar is the segment [lo, hi]; we draw it as a centered span.
    fig = figure('Position', [80 80 720 max(220, 80 + 30 * n)], 'Color', 'w');
    set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
    ax = axes(fig);
    hold(ax, 'on');

    for i = 1:n
        y = i;
        if hi(i) >= lo(i)
            x0 = lo(i);   x1 = hi(i);   c = [0.20 0.50 0.80];   % positive
        else
            x0 = hi(i);   x1 = lo(i);   c = [0.85 0.30 0.30];   % inverted (reduce QoI when increased)
        end
        rectangle(ax, 'Position', [x0, y - 0.35, x1 - x0, 0.70], ...
                  'FaceColor', c, 'EdgeColor', [0.15 0.15 0.20], 'LineWidth', 1);
        % Endpoint labels
        text(ax, x0, y, sprintf('%.3g ', x0), 'HorizontalAlignment', 'right', ...
             'VerticalAlignment', 'middle', 'FontSize', 10, 'Color', [0.20 0.20 0.20]);
        text(ax, x1, y, sprintf(' %.3g', x1), 'HorizontalAlignment', 'left', ...
             'VerticalAlignment', 'middle', 'FontSize', 10, 'Color', [0.20 0.20 0.20]);
    end

    % Baseline reference line
    plot(ax, [base base], [0.5, n + 0.5], 'k--', 'LineWidth', 1.5);
    text(ax, base, n + 0.45, sprintf('  baseline %s = %.4g', label, base), ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
         'FontSize', 11, 'Color', [0.10 0.10 0.10], 'Interpreter', 'none');

    set(ax, 'YTick', 1:n, 'YTickLabel', cellfun(@(s) strrep(s, '_', '\_'), names, 'UniformOutput', false));
    set(ax, 'TickLabelInterpreter', 'latex');
    ylim(ax, [0.4, n + 0.85]);
    if isempty(unit)
        xlabel(ax, sprintf('%s', label), 'Interpreter', 'latex', 'FontSize', 14);
    else
        xlabel(ax, sprintf('%s [%s]', label, unit), 'Interpreter', 'latex', 'FontSize', 14);
    end
    title(ax, ttl, 'Interpreter', 'latex', 'FontSize', 14);
    grid(ax, 'on');
    box(ax, 'on');

    if ~isempty(save_prefix)
        d = fileparts(save_prefix);
        if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
        try exportgraphics(fig, [save_prefix '.pdf'], 'ContentType', 'vector', 'BackgroundColor', 'white'); catch, end
        print(fig, [save_prefix '.png'], '-dpng', '-r250');
    end
end
