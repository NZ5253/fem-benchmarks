function ctype = pfem_detect_case_type(yaml_or_path)
% PFEM_DETECT_CASE_TYPE  Classify a PFEM benchmark by physical case type.
%
%   ctype = pfem_detect_case_type(yaml_struct_or_path)
%
% Returns one of:
%   'slope_srf'         — Mohr-Coulomb slope stability via SRF (FS extraction)
%   'plasticity_load'   — von Mises / MC with load increments (limit load)
%   'elastic_static'    — Linear elastic, steady-state (max displacement)
%   'seepage_steady'    — Steady seepage (head / flow rate)
%   'consolidation'     — Biot consolidation, transient (settlement vs time)
%   'eigenvalue'        — Modal / eigenvalue (natural frequency)
%   'dynamic_transient' — Time-stepping dynamics (peak response)
%   'thermal'           — Heat conduction (temperature)
%   'unknown'           — Falls through; QoI extractor will use generic fallback
%
% Detection is keyed primarily on chapter + program name (most reliable) and
% falls back to analysis.physics / analysis.regime from the YAML.

    if ischar(yaml_or_path) || isstring(yaml_or_path)
        y = pfem_yaml_load(char(yaml_or_path));
    else
        y = yaml_or_path;
    end

    chap = '';  prog = '';  phys = '';  regime = '';
    if isfield(y, 'authors') && isfield(y.authors, 'source')
        s = y.authors.source;
        if isfield(s, 'chapter'), chap = num2str(s.chapter); end
        if isfield(s, 'program'), prog = lower(char(s.program)); end
    end
    if isfield(y, 'analysis')
        a = y.analysis;
        if isfield(a, 'physics'), phys   = lower(char(a.physics)); end
        if isfield(a, 'regime'),  regime = lower(char(a.regime));  end
    end

    % ---- Chapter 6: slope SRF vs plasticity load ----
    if strcmp(chap, '6')
        SLOPE_PROGS = {'p64','p65','p66','p67','p68','p69','p612','p613'};
        if any(strcmp(prog, SLOPE_PROGS))
            ctype = 'slope_srf';  return;
        end
        ctype = 'plasticity_load';  return;   % p61, p62, p63, p610, p611
    end

    % ---- Chapter 9: Biot (consolidation, dynamic, plasticity) ----
    if strcmp(chap, '9')
        if strcmp(prog, 'p96')
            ctype = 'plasticity_load';  return;
        end
        % p91-p95 are Biot time-stepping (consolidation/dynamic).
        % YAML may list phys="linear" but they all write time-series output.
        ctype = 'consolidation';
        return;
    end

    % ---- Chapter 8: consolidation / thermal / dynamic ----
    if strcmp(chap, '8')
        if strcmp(phys, 'thermal'), ctype = 'thermal'; return; end
        if strcmp(phys, 'dynamics'), ctype = 'dynamic_transient'; return;
        end
        ctype = 'consolidation';  return;
    end

    % ---- Chapter 10: eigenvalue ----
    if strcmp(chap, '10')
        ctype = 'eigenvalue';  return;
    end

    % ---- Chapter 11: explicit dynamics ----
    if strcmp(chap, '11')
        ctype = 'dynamic_transient';  return;
    end

    % ---- Chapter 7: seepage vs dynamic ----
    if strcmp(chap, '7')
        if strcmp(phys, 'dynamics') || strcmp(regime, 'transient')
            ctype = 'dynamic_transient';  return;
        end
        ctype = 'seepage_steady';  return;
    end

    % ---- Chapter 4: elastic + p45 (plastic beam) + p47 (dynamic) ----
    if strcmp(chap, '4')
        if strcmp(prog, 'p45'), ctype = 'plasticity_load';  return; end
        if strcmp(prog, 'p47'), ctype = 'dynamic_transient'; return; end
        ctype = 'elastic_static';  return;
    end

    % ---- Chapter 5: linear elastic 2D/3D ----
    if strcmp(chap, '5')
        ctype = 'elastic_static';  return;
    end

    % ---- Fallback ----
    if strcmp(phys, 'elastic-plastic')
        ctype = 'plasticity_load';
    elseif strcmp(phys, 'linear')
        ctype = 'elastic_static';
    elseif strcmp(phys, 'seepage')
        ctype = 'seepage_steady';
    elseif strcmp(phys, 'consolidation')
        ctype = 'consolidation';
    elseif strcmp(phys, 'thermal')
        ctype = 'thermal';
    elseif strcmp(phys, 'dynamics') || strcmp(regime, 'transient')
        ctype = 'dynamic_transient';
    else
        ctype = 'unknown';
    end
end
