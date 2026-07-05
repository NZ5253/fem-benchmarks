function ok = test_golden_qoi(varargin)
% TEST_GOLDEN_QOI  Phase 3 regression gate.
%
% Re-runs each case recorded in matlab/tests/golden_qoi.json and asserts the
% QoI is unchanged: case_type, label and unit must match exactly; value must
% match within RelTol (default 1e-6, since PFEM writes deterministic text).
%
% Usage:
%   ok = test_golden_qoi()
%   ok = test_golden_qoi('RelTol', 1e-4)
%   ok = test_golden_qoi('JsonPath', '/tmp/g.json')
%   ok = test_golden_qoi('Strict', true)   % error() on any failure
%
% Returns true iff every recorded case reproduces its golden value.

    p = inputParser;
    addParameter(p, 'RelTol',   1e-6);
    addParameter(p, 'JsonPath', '');
    addParameter(p, 'Strict',   false);
    parse(p, varargin{:});
    reltol   = p.Results.RelTol;
    json_arg = p.Results.JsonPath;
    strict   = p.Results.Strict;

    here      = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    pfem_root = fullfile(repo_root, 'pfem');
    if isempty(json_arg)
        json_arg = fullfile(here, 'golden_qoi.json');
    end
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));

    if ~exist(json_arg, 'file')
        error('golden JSON not found: %s (run capture_golden_qoi first)', json_arg);
    end
    raw   = jsondecode(fileread(json_arg));
    cases = as_cell(raw.cases);

    fprintf('\n========================================================\n');
    fprintf('  Phase 3 golden regression: %d cases from %s\n', ...
        numel(cases), abbreviate_path(json_arg, repo_root));
    if isfield(raw, 'meta')
        m = raw.meta;
        fprintf('  Captured %s at %s   RelTol=%.1e\n', m.captured, m.commit, reltol);
    end
    fprintf('========================================================\n');

    n_pass = 0; failures = {};
    t_start = tic;

    for i = 1:numel(cases)
        c = cases{i};
        yp = fullfile(repo_root, c.yaml);
        overrides = if_empty_struct(c.overrides);

        try
            [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yp, overrides);
            if status ~= 0
                fail = sprintf('run status=%d', status);
                failures{end+1} = struct('case', c.case, 'probe', c.probe_label, 'why', fail); %#ok<AGROW>
                fprintf('  [%3d] %-14s %-10s  RUN FAILED  (%s)\n', ...
                    i, c.case, c.probe_label, fail);
                continue;
            end
            q = pfem_extract_qoi(out, c.case_type);

            [why, ok_case] = compare_qoi(c, q, reltol);
            if ok_case
                n_pass = n_pass + 1;
                fprintf('  [%3d] %-14s %-10s  OK   %s = %-10.6g %s\n', ...
                    i, c.case, c.probe_label, q.label, q.value, q.unit);
            else
                failures{end+1} = struct('case', c.case, 'probe', c.probe_label, 'why', why); %#ok<AGROW>
                fprintf('  [%3d] %-14s %-10s  FAIL %s\n', ...
                    i, c.case, c.probe_label, why);
            end
        catch ME
            failures{end+1} = struct('case', c.case, 'probe', c.probe_label, 'why', ME.message); %#ok<AGROW>
            fprintf('  [%3d] %-14s %-10s  ERROR  %s\n', ...
                i, c.case, c.probe_label, ME.message);
        end
    end

    fprintf('--------------------------------------------------------\n');
    fprintf('  %d / %d passed   (%.1f s)\n', n_pass, numel(cases), toc(t_start));

    if ~isempty(failures)
        fprintf('  %d failure(s):\n', numel(failures));
        for k = 1:numel(failures)
            f = failures{k};
            fprintf('    %-14s [%-10s]  %s\n', f.case, f.probe, f.why);
        end
    end
    fprintf('========================================================\n\n');

    ok = isempty(failures);
    if ~ok && strict
        error('test_golden_qoi: %d/%d failed', numel(failures), numel(cases));
    end
end


function [why, ok_case] = compare_qoi(golden, observed, reltol)
    why = ''; ok_case = true;

    % case_type is fed IN to pfem_extract_qoi from the golden record, so it
    % can't drift here; label/unit/ok/value are the observed outputs to check.

    if ~strcmp(golden.label, observed.label)
        why = sprintf('label drift: golden=%s, observed=%s', golden.label, observed.label);
        ok_case = false; return;
    end
    if ~strcmp(golden.unit, observed.unit)
        why = sprintf('unit drift: golden=%s, observed=%s', golden.unit, observed.unit);
        ok_case = false; return;
    end
    if golden.ok ~= observed.ok
        why = sprintf('ok drift: golden=%d, observed=%d', golden.ok, observed.ok);
        ok_case = false; return;
    end
    if isnan(golden.value) && isnan(observed.value)
        return;   % both NaN, treat as equal
    end
    if isnan(golden.value) || isnan(observed.value)
        why = sprintf('NaN drift: golden=%g, observed=%g', golden.value, observed.value);
        ok_case = false; return;
    end
    denom = max(abs(golden.value), realmin);
    rel   = abs(observed.value - golden.value) / denom;
    if rel > reltol
        why = sprintf('value drift: golden=%.10g, observed=%.10g, rel=%.2e > %.2e', ...
            golden.value, observed.value, rel, reltol);
        ok_case = false; return;
    end
end


function ov = if_empty_struct(x)
% jsondecode returns [] for empty JSON object {}; normalise to struct().
    if isstruct(x)
        ov = x;
    else
        ov = struct();
    end
end


function c = as_cell(x)
% jsondecode returns a struct-array when every JSON object shares the same
% field set, and a cell of structs otherwise. Normalise to a cell.
    if iscell(x)
        c = x;
    elseif isstruct(x)
        c = num2cell(x);
    else
        error('unexpected cases payload type: %s', class(x));
    end
end


function short = abbreviate_path(p, repo_root)
    short = strrep(p, [repo_root filesep], '');
end
