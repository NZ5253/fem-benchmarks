function ok = pfem_ensure_built(repo_root, pfem_root, program, chapter)
% PFEM_ENSURE_BUILT  Build the PFEM binary for a program/chapter if not present.
%
% Checks pfem_root/build/bin/<program>; if the binary is missing, runs
% scripts/pfem_build_chapter.sh to compile it (and the shared library if
% needed).  Returns true when the binary is ready, false on build failure.
%
% Usage:
%   ok = pfem_ensure_built(repo_root, pfem_root, 'p61', 'chap06')
%
% Called automatically by pfem_run_from_yaml, so NZ.m, pfem_batch_figs,
% and pfem_studio all benefit without extra setup.

    exe = fullfile(pfem_root, 'build', 'bin', program);

    if exist(exe, 'file')
        ok = true;   % already built — fast path
        return;
    end

    fprintf('  [build] Binary not found: %s\n', exe);
    fprintf('  [build] Building %s for %s ...\n', program, chapter);

    build_script = fullfile(repo_root, 'scripts', 'pfem_build_chapter.sh');
    if ~exist(build_script, 'file')
        fprintf('  [build] Build script not found: %s\n', build_script);
        ok = false;
        return;
    end

    cmd = sprintf('bash "%s" "%s" %s 2>&1', build_script, pfem_root, chapter);
    [rc, output] = system(cmd);

    % Determine success by whether OUR binary now exists.
    % The build script may exit non-zero when other programs in the chapter
    % fail (e.g. stale YAML entries with no matching .f03 source), even
    % though the specific binary we need was compiled successfully.
    ok = exist(exe, 'file') > 0;
    if ok
        fprintf('  [build] OK — binary ready: %s\n', exe);
    else
        fprintf('  [build] BUILD FAILED (exit code %d) — binary still missing:\n%s\n', rc, output);
    end
end
