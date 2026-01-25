function pfem_compare_results(out, varargin)
% PFEM_COMPARE_RESULTS  Compare original vs modified PFEM results
%
% Usage:
%   pfem_compare_results(out)              % Compare single run vs original
%   pfem_compare_results(results_array)    % Compare multiple sweep runs
%   pfem_compare_results(out, 'plot', true)
%
% Arguments:
%   out - Output struct from pfem_run_from_yaml (or array from sweep)
%
% Options:
%   'plot'   - true/false to show plots (default: true)
%   'save'   - true/false to save figures (default: false)
%   'text'   - true/false to show text output (default: true)

    p = inputParser;
    addParameter(p, 'plot', true);
    addParameter(p, 'save', false);
    addParameter(p, 'text', true);
    parse(p, varargin{:});
    do_plot = p.Results.plot;
    do_save = p.Results.save;
    do_text = p.Results.text;

    % Handle array of results (from sweep)
    if numel(out) > 1
        compare_sweep(out, do_plot, do_save);
        return;
    end

    % Single run comparison
    if do_text
        fprintf('\n');
        fprintf('============================================================\n');
        fprintf('Comparing Results: Original vs Modified\n');
        fprintf('============================================================\n\n');
    end

    % Parse original .res
    if isfield(out, 'original_res') && exist(out.original_res, 'file')
        if do_text
            fprintf('Original: %s\n', out.original_res);
        end
        [orig_disp, orig_stress] = parse_res_file(out.original_res);
    else
        if do_text
            fprintf('Original .res not found. Run the base case first.\n');
        end
        return;
    end

    % Parse modified .res
    res_files = out.files(endsWith(out.files, '.res'));
    if isempty(res_files)
        if do_text
            fprintf('No .res file in run output.\n');
        end
        return;
    end
    mod_res = res_files{1};
    if do_text
        fprintf('Modified: %s\n', mod_res);
    end
    [mod_disp, mod_stress] = parse_res_file(mod_res);

    % Get parameter info
    param_name = '';
    param_value = [];
    if isfield(out, 'overrides') && ~isempty(out.overrides) && ~isempty(fieldnames(out.overrides))
        if do_text
            fprintf('\nParameter changes:\n');
        end
        fnames = fieldnames(out.overrides);
        for i = 1:numel(fnames)
            if do_text
                fprintf('  %s = %g\n', fnames{i}, out.overrides.(fnames{i}));
            end
        end
        param_name = fnames{1};
        param_value = out.overrides.(param_name);
    end

    % Compare displacements
    if do_text
        fprintf('\n--- Displacement Comparison ---\n');
    end
    if ~isempty(orig_disp) && ~isempty(mod_disp)
        if do_text
            fprintf('%-6s  %12s  %12s  %12s  %12s\n', 'Node', 'Orig_X', 'Mod_X', 'Orig_Y', 'Mod_Y');
            fprintf('%s\n', repmat('-', 1, 60));
            n_nodes = min(size(orig_disp, 1), size(mod_disp, 1));
            for i = 1:min(n_nodes, 12)
                fprintf('%-6d  %12.4e  %12.4e  %12.4e  %12.4e\n', ...
                    i, orig_disp(i,1), mod_disp(i,1), orig_disp(i,2), mod_disp(i,2));
            end
            if n_nodes > 12
                fprintf('... (%d more nodes)\n', n_nodes - 12);
            end

            disp_diff = mod_disp - orig_disp(1:size(mod_disp,1), :);
            max_diff = max(abs(disp_diff(:)));
            rel_diff = max_diff / max(abs(orig_disp(:)));
            fprintf('\nMax absolute difference: %.4e\n', max_diff);
            fprintf('Max relative difference: %.2f%%\n', rel_diff * 100);
        end
    else
        if do_text
            fprintf('Could not parse displacement data.\n');
        end
    end

    % Compare stresses
    if do_text
        fprintf('\n--- Stress Comparison ---\n');
    end
    if ~isempty(orig_stress) && ~isempty(mod_stress)
        if do_text
            fprintf('%-4s  %10s  %10s  %10s  %10s  %10s  %10s\n', ...
                'Elem', 'Orig_sigX', 'Mod_sigX', 'Orig_sigY', 'Mod_sigY', 'Orig_tauXY', 'Mod_tauXY');
            fprintf('%s\n', repmat('-', 1, 75));
            n_elem = min(size(orig_stress, 1), size(mod_stress, 1));
            for i = 1:min(n_elem, 10)
                fprintf('%-4d  %10.3e  %10.3e  %10.3e  %10.3e  %10.3e  %10.3e\n', ...
                    i, orig_stress(i,3), mod_stress(i,3), ...
                    orig_stress(i,4), mod_stress(i,4), ...
                    orig_stress(i,5), mod_stress(i,5));
            end

            if max(abs(mod_stress(:,3))) > 0
                stress_ratio = orig_stress(1,3) / mod_stress(1,3);
                fprintf('\nStress ratio (orig/mod): %.2f\n', stress_ratio);
            end
        end
    else
        if do_text
            fprintf('Could not parse stress data.\n');
        end
    end

    % Plot if requested
    if do_plot && ~isempty(orig_disp) && ~isempty(mod_disp)
        plot_single_comparison(orig_disp, mod_disp, orig_stress, mod_stress, out, do_save);
    end

    if do_text
        fprintf('\n============================================================\n');
    end
end


function compare_sweep(results, do_plot, do_save)
% Compare multiple runs from a sweep
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('Sweep Results Comparison\n');
    fprintf('============================================================\n\n');

    n_runs = numel(results);
    param_values = zeros(n_runs, 1);
    max_disp = zeros(n_runs, 1);
    max_stress = zeros(n_runs, 1);
    param_name = '';

    % Get parameter name from first result
    if isfield(results(1), 'param')
        param_name = results(1).param;
    elseif isfield(results(1), 'out') && isfield(results(1).out, 'overrides')
        fnames = fieldnames(results(1).out.overrides);
        if ~isempty(fnames)
            param_name = fnames{1};
        end
    end

    for i = 1:n_runs
        if results(i).status ~= 0
            continue;
        end

        % Get parameter value
        if isfield(results(i), 'value')
            param_values(i) = results(i).value;
        elseif isfield(results(i), 'param_value')
            param_values(i) = results(i).param_value;
        end

        % Parse .res file
        res_files = results(i).files(endsWith(results(i).files, '.res'));
        if ~isempty(res_files)
            [disp_data, stress_data] = parse_res_file(res_files{1});
            if ~isempty(disp_data)
                max_disp(i) = max(abs(disp_data(:)));
            end
            if ~isempty(stress_data)
                max_stress(i) = max(abs(stress_data(:,3:5)), [], 'all');
            end
        end
    end

    % Make param_name more readable
    param_label = strrep(param_name, '_', ' ');
    param_label = strrep(param_label, 'youngs modulus ', 'E (');
    param_label = strrep(param_label, 'poisson ratio ', '\nu (');
    if contains(param_name, 'youngs') || contains(param_name, 'poisson')
        param_label = [param_label ')'];
    end

    % Display table
    fprintf('%-15s  %15s  %15s\n', 'Param Value', 'Max Disp', 'Max Stress');
    fprintf('%s\n', repmat('-', 1, 50));
    for i = 1:n_runs
        fprintf('%-15.4g  %15.4e  %15.4e\n', param_values(i), max_disp(i), max_stress(i));
    end

    % Plot sweep results
    if do_plot && sum(param_values > 0) > 1
        figure('Name', 'PFEM Sweep Results', 'Position', [100 100 1200 500]);

        % Get case info for title
        case_name = '';
        program = '';
        if isfield(results(1), 'out') && isfield(results(1).out, 'case')
            case_name = results(1).out.case;
        end

        % Subplot 1: Displacement vs Parameter
        subplot(1, 2, 1);
        plot(param_values, max_disp, 'bo-', 'LineWidth', 2, 'MarkerSize', 10, 'MarkerFaceColor', 'b');
        xlabel(sprintf('%s', param_label), 'FontSize', 12, 'FontWeight', 'bold');
        ylabel('Maximum Displacement (m)', 'FontSize', 12, 'FontWeight', 'bold');
        title(sprintf('Displacement vs %s', param_name), 'FontSize', 14, 'FontWeight', 'bold');
        grid on;
        set(gca, 'FontSize', 11);

        % Add data labels
        for i = 1:length(param_values)
            text(param_values(i), max_disp(i), sprintf('  %.2e', max_disp(i)), ...
                'FontSize', 9, 'VerticalAlignment', 'bottom');
        end

        % Subplot 2: Stress vs Parameter
        subplot(1, 2, 2);
        plot(param_values, max_stress, 'rs-', 'LineWidth', 2, 'MarkerSize', 10, 'MarkerFaceColor', 'r');
        xlabel(sprintf('%s', param_label), 'FontSize', 12, 'FontWeight', 'bold');
        ylabel('Maximum Stress (Pa)', 'FontSize', 12, 'FontWeight', 'bold');
        title(sprintf('Stress vs %s', param_name), 'FontSize', 14, 'FontWeight', 'bold');
        grid on;
        set(gca, 'FontSize', 11);

        % Add data labels
        for i = 1:length(param_values)
            text(param_values(i), max_stress(i), sprintf('  %.2e', max_stress(i)), ...
                'FontSize', 9, 'VerticalAlignment', 'bottom');
        end

        % Main title
        sgtitle(sprintf('PFEM Parameter Sweep: %s\nSweeping: %s', case_name, param_name), ...
            'FontSize', 14, 'FontWeight', 'bold');

        if do_save
            saveas(gcf, 'sweep_results.png');
            fprintf('\nSaved: sweep_results.png\n');
        end
    end
end


function [disp_data, stress_data] = parse_res_file(res_path)
% Parse PFEM .res file to extract displacements and stresses
    disp_data = [];
    stress_data = [];

    if ~exist(res_path, 'file')
        return;
    end

    fid = fopen(res_path, 'r');
    if fid == -1
        return;
    end

    content = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = content{1};

    % Find displacement section
    disp_start = 0;
    stress_start = 0;

    for i = 1:numel(lines)
        line = strtrim(lines{i});
        if contains(line, 'Node') && contains(line, 'disp')
            disp_start = i + 1;
        elseif contains(line, 'Element') && contains(line, 'sig')
            stress_start = i + 1;
        end
    end

    % Parse displacements
    if disp_start > 0
        disp_rows = {};
        for i = disp_start:numel(lines)
            line = strtrim(lines{i});
            if isempty(line) || contains(line, 'integration') || contains(line, 'Element')
                break;
            end
            vals = sscanf(line, '%f');
            if numel(vals) >= 3
                disp_rows{end+1} = vals(2:3)';
            end
        end
        if ~isempty(disp_rows)
            disp_data = vertcat(disp_rows{:});
        end
    end

    % Parse stresses
    if stress_start > 0
        stress_rows = {};
        for i = stress_start:numel(lines)
            line = strtrim(lines{i});
            if isempty(line)
                break;
            end
            vals = sscanf(line, '%f');
            if numel(vals) >= 5
                stress_rows{end+1} = vals';
            end
        end
        if ~isempty(stress_rows)
            stress_data = vertcat(stress_rows{:});
        end
    end
end


function plot_single_comparison(orig_disp, mod_disp, orig_stress, mod_stress, out, do_save)
% Create comparison plots for single run vs original
% Uses line plots with markers + difference subplot for clarity
    figure('Name', 'Original vs Modified Comparison', 'Position', [100 100 1400 900]);

    % Get parameter info for title
    param_str = 'No changes';
    param_name = '';
    param_value = [];
    if isfield(out, 'overrides') && ~isempty(out.overrides) && ~isempty(fieldnames(out.overrides))
        fnames = fieldnames(out.overrides);
        parts = {};
        for i = 1:numel(fnames)
            parts{end+1} = sprintf('%s = %.4g', fnames{i}, out.overrides.(fnames{i}));
        end
        param_str = strjoin(parts, ', ');
        param_name = fnames{1};
        param_value = out.overrides.(param_name);
    end

    case_name = '';
    if isfield(out, 'case')
        case_name = out.case;
    end

    n_nodes = size(orig_disp, 1);
    nodes = 1:n_nodes;

    % Calculate differences
    disp_diff_x = mod_disp(:,1) - orig_disp(:,1);
    disp_diff_y = mod_disp(:,2) - orig_disp(:,2);

    % Subplot 1: Displacement values (line plot)
    subplot(2, 2, 1);
    plot(nodes, orig_disp(:,2), 'b-o', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'b');
    hold on;
    plot(nodes, mod_disp(:,2), 'r-s', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'r');
    hold off;
    xlabel('Node Number', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Y-Displacement (m)', 'FontSize', 11, 'FontWeight', 'bold');
    title('Y-Displacement: Original vs Modified', 'FontSize', 12, 'FontWeight', 'bold');
    legend({'Original (E=1e6)', sprintf('Modified (%s=%.4g)', param_name, param_value)}, ...
        'Location', 'best', 'FontSize', 10);
    grid on;
    set(gca, 'FontSize', 10);

    % Subplot 2: Displacement DIFFERENCE
    subplot(2, 2, 2);
    stem(nodes, disp_diff_y, 'filled', 'LineWidth', 1.5, 'MarkerSize', 6, 'Color', [0.8 0.2 0.2]);
    xlabel('Node Number', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('\Delta Y-Displacement (m)', 'FontSize', 11, 'FontWeight', 'bold');
    title('Y-Displacement Difference (Modified - Original)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;
    set(gca, 'FontSize', 10);
    % Add zero line
    hold on;
    plot(xlim, [0 0], 'k--', 'LineWidth', 1);
    hold off;

    % Subplot 3: Stress values (line plot)
    if ~isempty(orig_stress) && ~isempty(mod_stress)
        n_elem = size(orig_stress, 1);
        elements = 1:n_elem;
        stress_diff = mod_stress(:,3) - orig_stress(:,3);

        subplot(2, 2, 3);
        plot(elements, orig_stress(:,3), 'b-o', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
        hold on;
        plot(elements, mod_stress(:,3), 'r-s', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
        hold off;
        xlabel('Element Number', 'FontSize', 11, 'FontWeight', 'bold');
        ylabel('\sigma_x (Pa)', 'FontSize', 11, 'FontWeight', 'bold');
        title('Stress \sigma_x: Original vs Modified', 'FontSize', 12, 'FontWeight', 'bold');
        legend({'Original', 'Modified'}, 'Location', 'best', 'FontSize', 10);
        grid on;
        set(gca, 'FontSize', 10);

        % Subplot 4: Stress DIFFERENCE
        subplot(2, 2, 4);
        stem(elements, stress_diff, 'filled', 'LineWidth', 1.5, 'MarkerSize', 8, 'Color', [0.2 0.6 0.2]);
        xlabel('Element Number', 'FontSize', 11, 'FontWeight', 'bold');
        ylabel('\Delta \sigma_x (Pa)', 'FontSize', 11, 'FontWeight', 'bold');
        title('Stress \sigma_x Difference (Modified - Original)', 'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        set(gca, 'FontSize', 10);
        hold on;
        plot(xlim, [0 0], 'k--', 'LineWidth', 1);
        hold off;
    end

    % Main title with case and parameter info
    sgtitle(sprintf('PFEM Results Comparison: %s\n%s', case_name, param_str), ...
        'FontSize', 14, 'FontWeight', 'bold');

    if do_save && isfield(out, 'work_dir')
        saveas(gcf, fullfile(out.work_dir, 'comparison.png'));
        fprintf('\nSaved: %s\n', fullfile(out.work_dir, 'comparison.png'));
    end
end
