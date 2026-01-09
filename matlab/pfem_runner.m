function [status, outputs] = pfem_runner(pfem_root, chapter, program, case_name)
% PFEM_RUNNER Execute a PFEM case from MATLAB
%
% Runs a compiled PFEM program with a specific dataset and returns outputs.
%
% Inputs:
%   pfem_root  - Path to PFEM root directory (e.g., '~/Downloads/pfem5/5th_ed')
%   chapter    - Chapter name (e.g., 'chap05')
%   program    - Program name (e.g., 'p51')
%   case_name  - Dataset basename (e.g., 'p51_3')
%
% Outputs:
%   status   - Execution status (0 = success, non-zero = error)
%   outputs  - Struct containing output file paths and basic info
%
% Example:
%   [status, outputs] = pfem_runner('~/Downloads/pfem5/5th_ed', 'chap05', 'p51', 'p51_3');
%
% Requirements:
%   - PFEM must be compiled (binary exists at pfem_root/build/bin/<program>)
%   - Dataset file must exist at pfem_root/executable/<chapter>/<case_name>.dat
%
% Author: Generated for PFEM Benchmark Catalogue
% Date: 2026-01-09

    % Initialize outputs
    outputs = struct();
    outputs.case = case_name;
    outputs.timestamp = datetime('now');

    % Expand paths
    if startsWith(pfem_root, '~')
        pfem_root = replace(pfem_root, '~', getenv('HOME'));
    end

    % Construct paths
    exe_path = fullfile(pfem_root, 'build', 'bin', program);
    work_dir = fullfile(pfem_root, 'executable', chapter);
    dat_file = fullfile(work_dir, [case_name '.dat']);

    % Verify prerequisites
    if ~exist(exe_path, 'file')
        error('PFEM executable not found: %s\nRun build script first.', exe_path);
    end

    if ~exist(dat_file, 'file')
        error('Dataset file not found: %s', dat_file);
    end

    % Record input info
    outputs.pfem_root = pfem_root;
    outputs.work_dir = work_dir;
    outputs.dat_file = dat_file;
    outputs.executable = exe_path;

    % Run the PFEM program
    % PFEM programs prompt for basename (without .dat extension)
    cmd = sprintf('cd "%s" && printf "%s\\n" | "%s"', work_dir, case_name, exe_path);
    fprintf('Running: %s\n', cmd);

    [status, cmdout] = system(['bash -lc ''' cmd '''']);

    outputs.status = status;
    outputs.command_output = cmdout;

    if status ~= 0
        warning('PFEM execution returned non-zero status: %d', status);
        fprintf('Output:\n%s\n', cmdout);
        return;
    end

    % Collect output files
    output_extensions = {'.res', '.msh', '.vec', '.dis', '.con', '.out'};
    output_files = {};

    for i = 1:length(output_extensions)
        ext = output_extensions{i};
        filepath = fullfile(work_dir, [case_name ext]);
        if exist(filepath, 'file')
            output_files{end+1} = filepath; %#ok<AGROW>
        end
    end

    outputs.files = output_files;
    outputs.num_files = length(output_files);

    % Parse basic info from .res if it exists
    res_file = fullfile(work_dir, [case_name '.res']);
    if exist(res_file, 'file')
        outputs.res_info = parse_res_basic(res_file);
    end

    fprintf('✓ PFEM run completed successfully\n');
    fprintf('  Generated %d output file(s)\n', outputs.num_files);

end

function info = parse_res_basic(res_file)
    % Parse basic information from .res file
    info = struct();
    info.file = res_file;

    try
        fid = fopen(res_file, 'r');
        if fid == -1
            info.error = 'Could not open file';
            return;
        end

        % Read first few lines to extract basic info
        line_count = 0;
        while ~feof(fid) && line_count < 20
            line = fgetl(fid);
            line_count = line_count + 1;

            % Look for "There are XX equations"
            if contains(line, 'equations')
                tokens = regexp(line, 'There are (\d+) equations', 'tokens');
                if ~isempty(tokens)
                    info.num_equations = str2double(tokens{1}{1});
                end
            end

            % Look for skyline storage
            if contains(line, 'skyline')
                tokens = regexp(line, 'skyline storage is (\d+)', 'tokens');
                if ~isempty(tokens)
                    info.skyline_storage = str2double(tokens{1}{1});
                end
            end
        end

        fclose(fid);
    catch e
        info.error = e.message;
    end
end
