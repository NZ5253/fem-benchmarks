function pfem_patch_dat_using_yaml(dat_path, y, overrides)
% Patch only targeted values in a copied .dat, guided by YAML tunables.
% Current support: inputs.record2.material.<prop>.value (E, nu, kx, ky, ...)

    % map: tunable name -> YAML path
    tp = y.tunable_parameters;
    tmap = containers.Map();
    for i=1:numel(tp)
        tmap(tp{i}.name) = tp{i}.path;
    end

    % tokenize file
    lines = readlines_char(dat_path);
    [tokens_by_line, map] = tokenize_with_map(lines);

    % record1 token count (typical PFEM): 8 tokens
    rec1_start = 1;
    rec1_count = 8;

    % np_types is token 8 of record1
    np_types_tok = rec1_start + 7;
    np_types = str2double(strip_quotes(map.tokens{np_types_tok}));

    % record2 props ordering from YAML record2 schema description
    [prop_order, nprops] = get_record2_prop_order(y);

    rec2_start = rec1_start + rec1_count;
    rec2_count = nprops * np_types; %#ok<NASGU>

    if numel(map.tokens) < 8
        error("DAT tokenization failed: expected at least 8 tokens for record1, got %d. Check tokenizer or .dat file.", numel(map.tokens));
    end


    % apply overrides (material type 1 only for now)
    names = fieldnames(overrides);
    for i=1:numel(names)
        nm = names{i};
        if ~isKey(tmap, nm)
            error("Override '%s' not found in YAML tunable_parameters", nm);
        end
        path = tmap(nm);

        if startsWith(path, "inputs.record2.material.")
            prop = extractBetween(path, "inputs.record2.material.", ".value");
            prop = char(prop);

            if ~isKey(prop_order, prop)
                error("Property '%s' not in record2 prop list for this program.", prop);
            end
            prop_idx = prop_order(prop); % 1..nprops

            t = 1; % material type 1
            token_idx = rec2_start + (t-1)*nprops + (prop_idx-1);

            map = replace_token(map, token_idx, overrides.(nm));
        else
            error("Currently unsupported YAML path: %s", path);
        end
    end

    % rebuild file
    new_lines = rebuild_lines(tokens_by_line, map);
    writelines_char(dat_path, new_lines);
end

function [prop_order, nprops] = get_record2_prop_order(y)
    reads = y.input_schema.reads_in_order;
    rec2 = [];
    for i=1:numel(reads)
        if reads{i}.record == 2
            rec2 = reads{i};
            break;
        end
    end
    if isempty(rec2), error('YAML missing record2 schema'); end

    desc = "";
    for j=1:numel(rec2.fields)
        if isfield(rec2.fields{j},'description')
            desc = string(rec2.fields{j}.description);
        end
    end

    m = regexp(desc, '\[(.*?)\]', 'tokens', 'once');
    if isempty(m)
        error("Cannot determine record2 prop order. Add description like: [E, nu, kx, ky] per material type");
    end

    props = strtrim(strsplit(string(m{1}), ','));
    nprops = numel(props);

    prop_order = containers.Map();
    for k=1:nprops
        prop_order(char(props{k})) = k;
    end
end

function x = strip_quotes(s)
    s = strtrim(s);
    if startsWith(s,"'") && endsWith(s,"'")
        x = extractBetween(s,"'","'");
        x = char(x);
    else
        x = char(s);
    end
end

function lines = readlines_char(p)
    fid = fopen(p,'r'); if fid==-1, error('Cannot open %s', p); end
    c = {};
    while ~feof(fid)
        c{end+1} = fgetl(fid); %#ok<AGROW>
    end
    fclose(fid);
    lines = c;
end

function writelines_char(p, lines)
    fid = fopen(p,'w'); if fid==-1, error('Cannot write %s', p); end
    for i=1:numel(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);
end

function [tokens_by_line, map] = tokenize_with_map(lines)
    tokens_by_line = cell(numel(lines),1);
    map.tokens = {};
    map.line_of_token = [];
    map.tok_in_line = [];

    g = 0;
    for i=1:numel(lines)
        toks = tokenize_line(lines{i});
        tokens_by_line{i} = toks;
        for j=1:numel(toks)
            g = g + 1;
            map.tokens{g} = toks{j};
            map.line_of_token(g) = i;
            map.tok_in_line(g) = j;
        end
    end
end

function toks = tokenize_line(line)
    % remove comments after !
    excl = strfind(line,'!');
    if ~isempty(excl)
        line = extractBefore(line, excl(1));
    end

    line = strtrim(line);
    if isempty(line)
        toks = {};
        return;
    end

    % Robust tokenization:
    % - keep quoted strings like 'plane' as one token
    % - capture any non-space chunk (numbers, scientific notation, etc.)
    toks = regexp(line, '(''[^'']*''|[^\s]+)', 'match');
end


function map = replace_token(map, token_idx, val)
    if token_idx < 1 || token_idx > numel(map.tokens)
        error('Token index out of range');
    end
    if isnumeric(val)
        map.tokens{token_idx} = num2str(val,'%.12g');
    else
        map.tokens{token_idx} = char(val);
    end
end

function new_lines = rebuild_lines(tokens_by_line, map)
    new_lines = cell(numel(tokens_by_line),1);
    per_line = tokens_by_line;

    for g=1:numel(map.tokens)
        i = map.line_of_token(g);
        j = map.tok_in_line(g);
        per_line{i}{j} = map.tokens{g};
    end

    for i=1:numel(per_line)
        if isempty(per_line{i})
            new_lines{i} = "";
        else
            new_lines{i} = strjoin(per_line{i}, ' ');
        end
    end
end

