function qoi = pfem_extract_qoi(out, case_type)
% PFEM_EXTRACT_QOI  Extract the Quantity of Interest from a PFEM run.
%
%   qoi = pfem_extract_qoi(out, case_type)
%
% Inputs:
%   out        struct returned by pfem_run_from_yaml (has .files, .run_dir, .case)
%   case_type  string from pfem_detect_case_type
%
% Returns a struct with fields:
%   .value      scalar QoI used for stochastic statistics (NaN on failure)
%   .label      short name e.g. 'FS', 'P_lim', 'u_max'
%   .unit       physical unit string e.g. 'm', 'kN', 'Hz' (may be '')
%   .raw        optional raw payload (vector / matrix) for plotting
%   .ok         logical, true if extraction succeeded
%
% The QoI is the scalar plotted in histograms and used to compute
% statistics (mean, std, P(fail), reliability).

    qoi = struct('value', NaN, 'label', 'QoI', 'unit', '', 'raw', [], 'ok', false);
    res_file = locate_res_file(out);
    if isempty(res_file)
        qoi.label = '(no .res)';  return;
    end

    switch lower(case_type)
        case 'slope_srf'
            qoi = qoi_slope_srf(res_file);
        case 'plasticity_load'
            qoi = qoi_plasticity_load(res_file);
        case 'elastic_static'
            qoi = qoi_elastic_static(res_file);
        case 'seepage_steady'
            qoi = qoi_seepage_steady(res_file);
        case 'consolidation'
            qoi = qoi_consolidation(res_file);
        case 'eigenvalue'
            qoi = qoi_eigenvalue(res_file);
        case 'dynamic_transient'
            qoi = qoi_dynamic_transient(res_file);
        case 'thermal'
            qoi = qoi_thermal(res_file);
        otherwise
            qoi = qoi_generic_fallback(res_file);
    end
end


% =========================================================================
% File location
% =========================================================================
function p = locate_res_file(out)
    p = '';
    if isfield(out, 'files') && iscell(out.files)
        idx = cellfun(@(f) endsWith(f, '.res'), out.files);
        if any(idx)
            cand = out.files(idx);
            p = cand{1};
            if exist(p, 'file'), return; end
        end
    end
    if isfield(out, 'run_dir') && isfield(out, 'case')
        cand = fullfile(out.run_dir, [out.case '.res']);
        if exist(cand, 'file'), p = cand; return; end
    end
    p = '';
end


% =========================================================================
% Per-case-type extractors
% =========================================================================
function q = qoi_slope_srf(res_file)
% Format: lines of [srf max_disp iters], FS = last srf with iters < limit.
    q = struct('value', NaN, 'label', 'FS', 'unit', '', 'raw', [], 'ok', false);
    nums = read_numeric_table(res_file, 3);
    if isempty(nums), return; end
    srf = nums(:,1);  dmax = nums(:,2);  it = nums(:,3);
    q.raw = nums;
    ilim = max(it);
    if ilim < 10
        q.value = srf(end);  q.ok = true;  return;
    end
    k = find(it < ilim, 1, 'last');
    if isempty(k)
        q.value = srf(1);
    else
        q.value = srf(k);
    end
    q.ok = true;
end


function q = qoi_plasticity_load(res_file)
% Format: [step load disp iters]. QoI = last converged load (limit load).
    q = struct('value', NaN, 'label', 'P_lim', 'unit', '', 'raw', [], 'ok', false);
    nums = read_numeric_table(res_file, 4);
    if isempty(nums)
        nums = read_numeric_table(res_file, 3);   % some variants drop step col
        if isempty(nums), return; end
        load_v = nums(:,1);  disp_v = nums(:,2);  it = nums(:,3);
    else
        load_v = nums(:,2);  disp_v = nums(:,3);  it = nums(:,4);
    end
    q.raw = [load_v disp_v it];
    ilim = max(it);
    if ilim < 10
        q.value = load_v(end);  q.ok = true;  return;
    end
    k = find(it < ilim, 1, 'last');
    if isempty(k)
        q.value = load_v(end);
    else
        q.value = load_v(k);
    end
    q.ok = true;
end


function q = qoi_elastic_static(res_file)
% Read nodal displacement block, take max |u|.
    q = struct('value', NaN, 'label', 'u_max', 'unit', 'm', 'raw', [], 'ok', false);
    [disp_block, ~] = read_block_after_header(res_file, 'Node');
    if isempty(disp_block), return; end
    % First column is node id; remaining columns are displacement components
    if size(disp_block, 2) < 2, return; end
    u = disp_block(:, 2:end);
    q.value = max(abs(u(:)));
    q.raw   = disp_block;
    q.ok    = true;
end


function q = qoi_seepage_steady(res_file)
% chap07 .res: "Node Total Head Flow rate" -> max head magnitude.
    q = struct('value', NaN, 'label', 'h_max', 'unit', 'm', 'raw', [], 'ok', false);
    [tbl, ~] = read_block_after_header(res_file, 'Node');
    if isempty(tbl) || size(tbl, 2) < 2, return; end
    head = tbl(:, 2);
    q.value = max(abs(head));
    q.raw   = tbl;
    q.ok    = true;
end


function q = qoi_consolidation(res_file)
% chap08 .res: "Time Uav Pressure(node...)" -> final Uav (degree of consolidation).
% Uav lies in [0, 1]; the value at the largest reported time is the QoI.
    q = struct('value', NaN, 'label', 'Uav_end', 'unit', '', 'raw', [], 'ok', false);
    tbl = read_numeric_table(res_file, 3);
    if isempty(tbl), return; end
    % Only keep rows whose 2nd column is in [0,1] (Uav block, not depth block)
    mask = tbl(:,2) >= 0 & tbl(:,2) <= 1 + 1e-6;
    if any(mask)
        sub = tbl(mask, :);
        [~, idx] = max(sub(:,1));   % latest time
        q.value = sub(idx, 2);
        q.raw   = sub;
    else
        q.value = tbl(end, 2);
        q.raw   = tbl;
    end
    q.ok = true;
end


function q = qoi_eigenvalue(res_file)
% chap10 .res: "The eigenvalues are:" followed by numbers (often omega^2).
% QoI = smallest eigenvalue (lowest natural frequency or its square).
    q = struct('value', NaN, 'label', 'lambda_1', 'unit', '', 'raw', [], 'ok', false);
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};
    eigs = [];
    in_block = false;
    for j = 1:numel(lines)
        L = lines{j};
        if contains(lower(L), 'eigenvalue')
            in_block = true;  continue;
        end
        if in_block
            v = str2num(L); %#ok<ST2NM>
            if isempty(v)
                if ~isempty(eigs), break; end   % left the block
                continue;
            end
            eigs = [eigs, v(:)']; %#ok<AGROW>
        end
    end
    if isempty(eigs), return; end
    eigs = eigs(eigs > 0);
    if isempty(eigs), return; end
    q.value = min(eigs);
    q.raw   = eigs(:);
    q.ok    = true;
end


function q = qoi_dynamic_transient(res_file)
% Time-history output (chap11): "time disp velo accel" -> peak |disp|.
    q = struct('value', NaN, 'label', 'u_peak', 'unit', 'm', 'raw', [], 'ok', false);
    tbl = read_numeric_table(res_file, 4);
    if isempty(tbl)
        tbl = read_numeric_table(res_file, 2);
        if isempty(tbl), return; end
        q.value = max(abs(tbl(:,2)));  q.raw = tbl;  q.ok = true;  return;
    end
    q.value = max(abs(tbl(:,2)));
    q.raw   = tbl;
    q.ok    = true;
end


function q = qoi_thermal(res_file)
% chap08 p811: temperature field -> max temperature.
    q = struct('value', NaN, 'label', 'T_max', 'unit', '', 'raw', [], 'ok', false);
    tbl = read_numeric_table(res_file, 2);
    if isempty(tbl), return; end
    q.value = max(abs(tbl(:, end)));
    q.raw   = tbl;
    q.ok    = true;
end


function q = qoi_generic_fallback(res_file)
% Last resort: max absolute number anywhere in the file.
    q = struct('value', NaN, 'label', 'max|val|', 'unit', '', 'raw', [], 'ok', false);
    tbl = read_numeric_table(res_file, 1);
    if isempty(tbl), return; end
    q.value = max(abs(tbl(:)));
    q.raw   = tbl;
    q.ok    = true;
end


% =========================================================================
% Generic .res parsers
% =========================================================================
function nums = read_numeric_table(res_file, ncols)
% Read every line that parses to >= ncols numbers; stack into a matrix.
    nums = [];
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};
    for j = 1:numel(lines)
        v = str2num(lines{j}); %#ok<ST2NM>
        if isempty(v) || numel(v) < ncols, continue; end
        nums(end+1, :) = v(1:ncols); %#ok<AGROW>
    end
end


function [block, header_line] = read_block_after_header(res_file, header_keyword)
% Find the first line containing header_keyword, then collect numeric rows
% until the block ends (blank line, another header, or eof).
    block = [];  header_line = '';
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};
    started = false;
    for j = 1:numel(lines)
        L = strtrim(lines{j});
        if ~started
            if contains(L, header_keyword)
                started = true;
                header_line = L;
            end
            continue;
        end
        if isempty(L), if ~isempty(block), break; else, continue; end, end
        v = str2num(L); %#ok<ST2NM>
        if isempty(v)
            if ~isempty(block), break; end
            continue;
        end
        if isempty(block)
            block = v(:)';
        else
            if numel(v) == size(block, 2)
                block(end+1, :) = v(:)'; %#ok<AGROW>
            else
                break;
            end
        end
    end
end
