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
% Two formats: standard SRF (p64-p68, p612, p613) and embankment lift (p69).
%   Standard:    lines of [srf max_disp iters], FS = last srf with iters < limit
%   Lift (p69):  "Max displacement is X" per lift; QoI = final max disp
    q = struct('value', NaN, 'label', 'FS', 'unit', '', 'raw', [], 'ok', false);
    nums = read_numeric_table(res_file, 3);
    if ~isempty(nums)
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
        return;
    end

    % Fallback for embankment-lift programs (p69): regex on "Max displacement is X"
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    dmaxs = [];
    for j = 1:numel(raw{1})
        tok = regexp(raw{1}{j}, 'Max displacement is\s+([-+0-9.eE]+)', 'tokens', 'once');
        if ~isempty(tok)
            v = str2double(tok{1});
            if ~isnan(v), dmaxs(end+1) = v; end %#ok<AGROW>
        end
    end
    if ~isempty(dmaxs)
        q.label = 'u_max_final_lift';
        q.unit  = 'm';
        q.value = dmaxs(end);
        q.raw   = dmaxs(:);
        q.ok    = true;
    end
end


function q = qoi_plasticity_load(res_file)
% Heterogeneous .res formats across chap06 plasticity programs.
% Strategy: count actual data columns first, then parse header tokens to
% locate the load/stress and iteration columns within that width.
%
%   p61, p62  : "step   load        disp      iters [cg iters]"  (4-5 cols)
%   p63       : "step   disp        load1    load2  iters"        (5 cols)
%   p611      : "step   disp      dev stress  pore press  iters" (5 cols)
%   p118      : "time   load        x-disp      y-disp"           (4 cols, no iters)
    q = struct('value', NaN, 'label', 'P_lim', 'unit', '', 'raw', [], 'ok', false);

    % Step 1: read all rows that are numeric, find dominant column count
    [nums, ncols] = read_widest_numeric_table(res_file, 3);
    if isempty(nums), return; end

    % Step 2: find the header line preceding the data
    header_tokens = find_header_tokens(res_file, ncols);

    % Step 3: identify load/stress and iters columns from header tokens
    [load_col, iter_col] = identify_columns_from_tokens(header_tokens, ncols);

    load_v = nums(:, load_col);
    q.raw  = nums;

    if iter_col > 0 && iter_col <= size(nums, 2)
        it   = nums(:, iter_col);
        ilim = max(it);
        if ilim >= 10
            k = find(it < ilim, 1, 'last');
            if isempty(k)
                q.value = load_v(end);
            else
                q.value = load_v(k);
            end
            q.ok = true;
            return;
        end
    end
    % No iteration column or no obvious non-converged tail: take last load
    q.value = load_v(end);
    q.ok    = true;
end


function [nums, ncols] = read_widest_numeric_table(res_file, min_cols)
% Read consecutive numeric rows in blocks; pick the block that follows the
% first header containing "Time", "step", "srf" or "time" (the analysis-
% history block, not a per-node block).
    if nargin < 2, min_cols = 2; end
    nums = [];  ncols = 0;
    [blocks, headers] = read_blocks(res_file, min_cols);
    if isempty(blocks), return; end

    % Pick the LARGEST block whose preceding header names a time-like
    % column. We match "time", "step" or "srf" as a column name (start of
    % the header line, possibly preceded by whitespace) rather than as a
    % free-text mention so blocks like "Depth  Pressure (time=...)" do
    % not get mistaken for a time-history block.
    pick = 0;
    pick_size = -1;
    for b = 1:numel(blocks)
        h = lower(headers{b});
        if header_is_time_axis(h)
            sz = size(blocks{b}, 1);
            if sz > pick_size
                pick = b;
                pick_size = sz;
            end
        end
    end
    if pick == 0
        % Fallback: largest block overall
        [~, pick] = max(cellfun(@(b) size(b,1), blocks));
    end
    nums  = blocks{pick};
    ncols = size(nums, 2);
end


function tf = header_is_time_axis(h_lower)
% Recognise headers whose first column is time/step/srf (an analysis-history
% block), not headers that merely mention time inside a depth profile etc.
% MATLAB's \b after ^\s* is unreliable, so match the whitespace explicitly.
    tf = ~isempty(regexp(h_lower, '^\s*(time|step|srf)(\s|$)', 'once'));
end


function [blocks, headers] = read_blocks(res_file, min_cols)
% Split the .res file into consecutive numeric blocks. blocks{k} is a matrix
% of same-width numeric rows. headers{k} is the most recent non-numeric line.
    blocks = {};  headers = {};
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    cur_header = '';
    cur_rows = {};
    cur_width = 0;
    for j = 1:numel(lines)
        L = strtrim(lines{j});
        if isempty(L)
            if ~isempty(cur_rows)
                [blocks, headers, cur_rows, cur_width] = flush(blocks, headers, cur_rows, cur_width, cur_header);
            end
            continue;
        end
        v = str2num(L); %#ok<ST2NM>
        if isempty(v) || numel(v) < min_cols
            if isempty(v)
                cur_header = L;
                if ~isempty(cur_rows)
                    [blocks, headers, cur_rows, cur_width] = flush(blocks, headers, cur_rows, cur_width, cur_header);
                end
            end
            continue;
        end
        if isempty(cur_rows)
            cur_width = numel(v);
            cur_rows{1} = v(:)';
        elseif numel(v) == cur_width
            cur_rows{end+1} = v(:)'; %#ok<AGROW>
        else
            [blocks, headers, cur_rows, cur_width] = flush(blocks, headers, cur_rows, cur_width, cur_header);
            cur_width = numel(v);
            cur_rows{1} = v(:)';
        end
    end
    if ~isempty(cur_rows)
        [blocks, headers, ~, ~] = flush(blocks, headers, cur_rows, cur_width, cur_header);
    end
end


function [blocks, headers, cur_rows, cur_width] = flush(blocks, headers, cur_rows, cur_width, cur_header)
    if isempty(cur_rows)
        return;
    end
    M = zeros(numel(cur_rows), cur_width);
    for ii = 1:numel(cur_rows)
        M(ii, :) = cur_rows{ii};
    end
    blocks{end+1} = M;
    headers{end+1} = cur_header;
    cur_rows = {};
    cur_width = 0;
end


function toks = find_header_tokens(res_file, expected_ncols)
% Find a header line near the data with token count >= expected_ncols.
    toks = {};
    fid = fopen(res_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};
    for j = 1:numel(lines)
        L = strtrim(lines{j});
        if isempty(L), continue; end
        v = str2num(L); %#ok<ST2NM>
        if ~isempty(v), continue; end
        Llow = lower(L);
        if ~contains(Llow, 'step') && ~contains(Llow, 'time') && ~contains(Llow, 'srf')
            continue;
        end
        % Merge known two-word labels
        parts = strsplit(L);
        merged = {};
        i = 1;
        while i <= numel(parts)
            t = lower(parts{i});
            if i+1 <= numel(parts) && any(strcmp(t, {'dev','pore','x','y','z','total','max'}))
                merged{end+1} = [t '_' lower(parts{i+1})]; %#ok<AGROW>
                i = i + 2;
            else
                merged{end+1} = t; %#ok<AGROW>
                i = i + 1;
            end
        end
        toks = merged;
        return;
    end
end


function [load_col, iter_col] = identify_columns_from_tokens(toks, ncols)
% Match tokens to data columns. If tokens > ncols, take first ncols.
    load_col = 0;  iter_col = 0;
    if isempty(toks)
        load_col = 2;  return;
    end
    if numel(toks) > ncols
        toks = toks(1:ncols);
    end

    for k = 1:min(ncols, numel(toks))
        t = toks{k};
        if (~isempty(regexp(t, '^load', 'once')) || strcmp(t, 'load1')) && load_col == 0
            load_col = k;
        elseif ~isempty(regexp(t, 'stress$', 'once')) && load_col == 0
            load_col = k;
        end
        if startsWith(t, 'iter') && iter_col == 0
            iter_col = k;
        end
    end

    if load_col == 0, load_col = 2; end
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
% Several formats across chap08 (Terzaghi) and chap09 (Biot):
%   3-col  "Time | Uav | Pressure(node)"           -> Uav_end (chap08 p81-p85)
%   2-col  "Time | Pressure(node)"                  -> P_end  (chap08 p86, p87, p88)
%   5-col  "Time | Uav | Uavs | Settle | Pressure"  -> Uav_end (chap09 p93-p95)
%   4-col  Biot dynamic time-history                -> u_peak
    q = struct('value', NaN, 'label', 'Uav_end', 'unit', '', 'raw', [], 'ok', false);
    [tbl, ncols] = read_widest_numeric_table(res_file);
    if isempty(tbl), return; end

    if ncols >= 3
        % Locate the Uav-like column: numeric values in [0, 1] across all rows
        uav_col = 0;
        for c = 2:min(ncols, 5)
            vals = tbl(:, c);
            if all(vals >= -1e-6) && all(vals <= 1 + 1e-3)
                uav_col = c;  break;
            end
        end
        if uav_col > 0
            [~, idx] = max(tbl(:, 1));   % latest time
            q.value = tbl(idx, uav_col);
            q.raw   = tbl;
            q.label = 'Uav_end';
            q.ok    = true;
            return;
        end
    end

    % 2-col Time|Pressure format -> report final pressure as QoI
    if ncols >= 2
        [~, idx] = max(tbl(:, 1));
        q.value = tbl(idx, end);
        q.raw   = tbl;
        q.label = 'P_end';
        q.ok    = true;
        return;
    end
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
