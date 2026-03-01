function [status, outputs] = pfem_runner(pfem_root, chapter, program, case_name, work_dir)
% PFEM_RUNNER Execute PFEM case from MATLAB.
% If work_dir is provided, PFEM runs in work_dir and reads <case_name>.dat from there.

    outputs = struct();
    outputs.case      = case_name;
    outputs.timestamp = datetime('now');
    outputs.files     = {};       % always set so callers never hit missing-field errors
    outputs.num_files = 0;

    if startsWith(pfem_root, '~')
        pfem_root = replace(pfem_root, '~', getenv('HOME'));
    end

    exe_path = fullfile(pfem_root, 'build', 'bin', program);
    if ~exist(exe_path, 'file')
        error('PFEM executable not found: %s', exe_path);
    end

    if nargin < 5 || isempty(work_dir)
        work_dir = fullfile(pfem_root, 'executable', chapter);
    else
        if startsWith(work_dir, '~')
            work_dir = replace(work_dir, '~', getenv('HOME'));
        end
    end

    dat_file = fullfile(work_dir, [case_name '.dat']);
    if ~exist(dat_file, 'file')
        error('Dataset file not found: %s', dat_file);
    end

    outputs.pfem_root = pfem_root;
    outputs.work_dir = work_dir;
    outputs.dat_file = dat_file;
    outputs.executable = exe_path;

    cmd = sprintf('cd "%s" && printf "%s\\n" | "%s"', work_dir, case_name, exe_path);
    fprintf('Running: %s\n', cmd);

    [status, cmdout] = system(['bash -lc ''' cmd '''']);
    outputs.status = status;
    outputs.command_output = cmdout;

    if status ~= 0
        warning('PFEM execution returned non-zero status: %d', status);
        fprintf('%s\n', cmdout);
        return;
    end

    exts = {'.res','.msh','.vec','.dis','.con','.out'};
    files = {};
    for i=1:numel(exts)
        f = fullfile(work_dir, [case_name exts{i}]);
        if exist(f,'file'), files{end+1} = f; end %#ok<AGROW>
    end
    outputs.files = files;
    outputs.num_files = numel(files);

    fprintf('✓ PFEM run completed (%d output file(s))\n', outputs.num_files);
end
