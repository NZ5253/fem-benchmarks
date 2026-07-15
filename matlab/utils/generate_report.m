function report_path = generate_report(run_dir, varargin)
% GENERATE_REPORT  Build a self-contained HTML report for a case's runs.
%
%   report_path = generate_report(run_dir)
%   report_path = generate_report(run_dir, 'Out', '/path/to/report.html')
%   report_path = generate_report(run_dir, 'LatestOnly', true)
%
% Walks the run directory of one case (e.g. runs/chap06/p61/), finds all
% aggregated sweep figures (matching <case>_<mode>_<TIMESTAMP>_*.png),
% groups them by timestamp+mode, and emits a single HTML file with every
% PNG embedded as base64. No external asset dependencies, so the file can
% be emailed / opened offline / archived.
%
% Also embeds per-scenario metadata from run_info.txt files found in
% sub-directories, and a short summary table of scenario -> QoI where
% derivable from directory names.
%
% Default output: <run_dir>/report.html

    p = inputParser;
    addParameter(p, 'Out', '');
    addParameter(p, 'LatestOnly', false);
    parse(p, varargin{:});
    out_path   = p.Results.Out;
    latest_only = p.Results.LatestOnly;

    if ~exist(run_dir, 'dir')
        error('generate_report: run_dir does not exist: %s', run_dir);
    end
    if isempty(out_path)
        out_path = fullfile(run_dir, 'report.html');
    end

    [~, case_name] = fileparts(strip_trailing_sep(run_dir));

    % ---- Group aggregated figures by (mode, timestamp) -----------------
    pngs = dir(fullfile(run_dir, '*.png'));
    groups = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:numel(pngs)
        fname = pngs(i).name;
        % Match "<anything>_(stochastic|sensitivity|sweep)_YYYYMMDD_HHMMSS_"
        tok = regexp(fname, '_(stochastic|sensitivity|sweep|tornado)_(\d{8}_\d{6})_', 'tokens', 'once');
        if isempty(tok), continue; end
        key = sprintf('%s_%s', tok{1}, tok{2});
        if ~isKey(groups, key)
            groups(key) = struct('mode', tok{1}, 'ts', tok{2}, 'files', {{}});
        end
        g = groups(key);
        g.files{end+1} = fullfile(run_dir, fname);
        groups(key) = g;
    end
    ks = keys(groups);
    if isempty(ks)
        warning('generate_report: no aggregated sweep figures found in %s', run_dir);
    end

    % Sort keys newest-first by timestamp
    tss = cellfun(@(k) groups(k).ts, ks, 'UniformOutput', false);
    [~, order] = sort(string(tss));
    ks = ks(flip(order));
    if latest_only && ~isempty(ks), ks = ks(1); end

    % ---- Per-scenario summary from subdirs ------------------------------
    subs = dir(run_dir);
    subs = subs([subs.isdir]);
    subs = subs(~ismember({subs.name}, {'.', '..'}));
    scenario_rows = {};
    for i = 1:numel(subs)
        info_path = fullfile(run_dir, subs(i).name, 'run_info.txt');
        summary = '(no run_info.txt)';
        if exist(info_path, 'file')
            summary = extract_status(info_path);
        end
        scenario_rows{end+1, 1} = subs(i).name; %#ok<AGROW>
        scenario_rows{end, 2}   = summary;
    end

    % ---- Build HTML ----------------------------------------------------
    fid = fopen(out_path, 'w');
    if fid < 0, error('generate_report: cannot write %s', out_path); end
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, '<!doctype html>\n<html lang="en"><head>\n');
    fprintf(fid, '<meta charset="utf-8">\n');
    fprintf(fid, '<title>%s -- fem-benchmarks report</title>\n', html_escape(case_name));
    fprintf(fid, '<style>\n%s\n</style>\n', embed_css());
    fprintf(fid, '</head><body>\n');

    fprintf(fid, '<h1>Case <code>%s</code></h1>\n', html_escape(case_name));
    fprintf(fid, '<p class="meta">Generated %s from <code>%s</code></p>\n', ...
        datestr(now, 'yyyy-mm-dd HH:MM'), html_escape(run_dir));
    fprintf(fid, '<p class="meta">Sweeps found: %d.  Scenario sub-directories: %d.</p>\n', ...
        numel(keys(groups)), numel(subs));

    % Scenario table
    if ~isempty(scenario_rows)
        fprintf(fid, '<h2>Scenarios</h2>\n');
        fprintf(fid, '<table><thead><tr><th>Directory</th><th>Status / QoI</th></tr></thead><tbody>\n');
        for r = 1:size(scenario_rows, 1)
            fprintf(fid, '<tr><td><code>%s</code></td><td>%s</td></tr>\n', ...
                html_escape(scenario_rows{r, 1}), html_escape(scenario_rows{r, 2}));
        end
        fprintf(fid, '</tbody></table>\n');
    end

    % Sweep figures
    for i = 1:numel(ks)
        g = groups(ks{i});
        fprintf(fid, '<h2>%s sweep %s</h2>\n', ...
            capitalise(g.mode), format_timestamp(g.ts));
        fprintf(fid, '<div class="figs">\n');
        for j = 1:numel(g.files)
            fname = g.files{j};
            [~, base, ~] = fileparts(fname);
            b64 = read_base64(fname);
            fprintf(fid, '<figure><img src="data:image/png;base64,%s" alt="%s"><figcaption><code>%s.png</code></figcaption></figure>\n', ...
                b64, html_escape(base), html_escape(base));
        end
        fprintf(fid, '</div>\n');
    end

    fprintf(fid, '</body></html>\n');
    report_path = out_path;
    fprintf('Wrote %s (%d sweep(s), %d scenario dir(s))\n', ...
        out_path, numel(ks), numel(subs));
end


function s = extract_status(info_path)
% Grab the Status line + any Time or Overrides content from run_info.txt.
    s = '(unreadable)';
    try
        txt = fileread(info_path);
        st  = regexp(txt, 'Status\s*:\s*([^\n]+)', 'tokens', 'once');
        tm  = regexp(txt, 'Time\s*:\s*([^\n]+)', 'tokens', 'once');
        if ~isempty(st)
            s = strtrim(st{1});
            if ~isempty(tm), s = [s '   (' strtrim(tm{1}) ')']; end
        end
    catch
    end
end


function s = format_timestamp(ts)
% '20260715_143022' -> '2026-07-15  14:30:22'
    if numel(ts) == 15
        s = sprintf('%s-%s-%s  %s:%s:%s', ts(1:4), ts(5:6), ts(7:8), ...
            ts(10:11), ts(12:13), ts(14:15));
    else
        s = ts;
    end
end


function s = capitalise(w)
    s = w; s(1) = upper(s(1));
end


function p = strip_trailing_sep(p)
    while ~isempty(p) && p(end) == filesep, p = p(1:end-1); end
end


function s = html_escape(x)
    s = char(x);
    s = strrep(s, '&', '&amp;');
    s = strrep(s, '<', '&lt;');
    s = strrep(s, '>', '&gt;');
    s = strrep(s, '"', '&quot;');
end


function b64 = read_base64(path)
    fid = fopen(path, 'rb');
    if fid < 0, b64 = ''; return; end
    bytes = fread(fid, Inf, 'uint8=>uint8');
    fclose(fid);
    b64 = matlab.net.base64encode(bytes);
end


function css = embed_css()
    css = [ ...
'  body { font-family: -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;', newline, ...
'         color: #222; background: #fafafa; max-width: 1100px;', newline, ...
'         margin: 40px auto; padding: 0 20px; line-height: 1.5; }', newline, ...
'  h1 { border-bottom: 3px solid #4361ee; padding-bottom: 8px; }', newline, ...
'  h2 { border-bottom: 1px solid #ddd; padding-bottom: 4px; margin-top: 40px;', newline, ...
'       color: #333; font-weight: 600; }', newline, ...
'  code { background: #eef2f6; padding: 1px 5px; border-radius: 3px;', newline, ...
'         font-family: "SF Mono", Consolas, monospace; font-size: 90%; }', newline, ...
'  .meta { color: #888; font-size: 0.9em; }', newline, ...
'  table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 0.92em; }', newline, ...
'  th, td { border-bottom: 1px solid #e0e0e0; padding: 6px 10px; text-align: left; }', newline, ...
'  thead th { background: #eef2f6; }', newline, ...
'  .figs { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));', newline, ...
'          gap: 16px; margin-top: 12px; }', newline, ...
'  figure { margin: 0; text-align: center; }', newline, ...
'  figure img { width: 100%; height: auto; border: 1px solid #ddd; border-radius: 4px;', newline, ...
'               background: white; }', newline, ...
'  figcaption { font-size: 0.85em; color: #666; margin-top: 4px; }' ];
end
