function s = pfem_yaml_load(yaml_path)
% Load YAML into MATLAB struct via Python (requires python3-yaml).

    if startsWith(yaml_path,'~')
        yaml_path = replace(yaml_path,'~',getenv('HOME'));
    end
    if ~exist(yaml_path,'file')
        error('YAML not found: %s', yaml_path);
    end

    yaml = py.importlib.import_module('yaml');
    f = py.open(yaml_path,'r',pyargs('encoding','utf-8'));
    data = yaml.safe_load(f);
    f.close();

    s = py2mat(data);
end

function out = py2mat(x)
    if isa(x,'py.dict')
        out = struct();

        keys_py = py.list(x.keys());
        keys = cell(keys_py);

        for i = 1:numel(keys)
            k_raw = keys{i};

            % --- SAFE key -> MATLAB field name string ---
            if isa(k_raw,'py.str')
                k_txt = char(k_raw);
            elseif isa(k_raw,'py.int') || isa(k_raw,'py.float')
                k_txt = num2str(double(k_raw));
            else
                % fallback: Python str()
                k_txt = char(py.str(k_raw));
            end

            fld = matlab.lang.makeValidName(k_txt);

            % Important: use the ORIGINAL key object to index the dict
            out.(fld) = py2mat(x{k_raw});
        end

    elseif isa(x,'py.list') || isa(x,'py.tuple')
        out = cell(x);
        for i = 1:numel(out)
            out{i} = py2mat(out{i});
        end

    elseif isa(x,'py.str')
        out = char(x);

    elseif isa(x,'py.int') || isa(x,'py.float')
        out = double(x);

    elseif isa(x,'py.bool')
        out = logical(x);

    else
        out = x;
    end
end

