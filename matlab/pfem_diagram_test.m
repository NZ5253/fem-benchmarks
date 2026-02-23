%% pfem_diagram_test.m
% Visual test for pfem_diagram: render two diagrams side-by-side:
%   Left:  original parameters  (E = 1e6, nu = 0.3)
%   Right: modified parameters  (E = 2e5, nu = 0.45)
% Saves test_diagram_original.png, test_diagram_modified.png,
%        test_diagram_comparison.png

matlab_dir = fileparts(mfilename('fullpath'));
repo_root  = fileparts(matlab_dir);
addpath(genpath(matlab_dir));

yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p54_1.yaml');
fprintf('Using YAML: %s\n', yaml_path);

out_dir = matlab_dir;

% ------------------------------------------------------------------
%  helper: export main axes from a pfem_diagram figure to PNG
% ------------------------------------------------------------------
function save_axes_png(fig, png_path)
    % Find main axes (the leftmost / widest one)
    ax_list = findobj(fig, 'Type', 'axes');
    if isempty(ax_list)
        warning('No axes found in figure'); return;
    end
    % Pick the axes with largest width (the diagram, not comparison subplot)
    ax = ax_list(1);
    for k = 2:numel(ax_list)
        pos_k = get(ax_list(k), 'Position');
        pos   = get(ax,         'Position');
        if pos_k(3) > pos(3), ax = ax_list(k); end
    end
    exportgraphics(ax, png_path, 'Resolution', 150);
    fprintf('Saved: %s\n', png_path);
end

% ---- 1. Open diagram (off-screen) with original parameters ----
pfem_diagram(yaml_path);
fig = gcf;
set(fig, 'Visible', 'off');
drawnow;

png_orig = fullfile(out_dir, 'test_diagram_original.png');
save_axes_png(fig, png_orig);

% ---- 2. Programmatically change E and nu via the UI panel ----
e_edit  = findobj(fig, 'Tag', 'youngs_modulus_E');
nu_edit = findobj(fig, 'Tag', 'poisson_ratio_nu');

if isempty(e_edit) || isempty(nu_edit)
    warning('Could not find edit fields — parameter changes skipped.');
else
    set(e_edit,  'String', '2e5');
    set(nu_edit, 'String', '0.45');

    % Trigger Apply button
    apply_btn = findobj(fig, 'Style', 'pushbutton', 'String', 'Apply');
    if ~isempty(apply_btn)
        cb = get(apply_btn(1), 'Callback');
        cb(apply_btn(1), []);
    else
        cb = get(e_edit(1), 'Callback');
        cb(e_edit(1), []);
    end
    drawnow;
end

png_mod = fullfile(out_dir, 'test_diagram_modified.png');
save_axes_png(fig, png_mod);
close(fig);

% ---- 3. Side-by-side comparison ----
fig_cmp = figure('Visible', 'off', 'Position', [0 0 2100 780]);
sgtitle('pfem\_diagram — p54\_1: parameter update', ...
        'FontSize', 13, 'FontWeight', 'bold');

ax1 = subplot(1, 2, 1);
imshow(imread(png_orig), 'Parent', ax1);
title(ax1, 'Original:   E = 10^6,  \nu = 0.3', 'FontSize', 12);

ax2 = subplot(1, 2, 2);
imshow(imread(png_mod), 'Parent', ax2);
title(ax2, 'Modified:   E = 2\times10^5,  \nu = 0.45', 'FontSize', 12);

png_cmp = fullfile(out_dir, 'test_diagram_comparison.png');
exportgraphics(fig_cmp, png_cmp, 'Resolution', 150);
close(fig_cmp);
fprintf('Saved comparison: %s\n', png_cmp);
fprintf('\nAll done.\n');
