function b = get_backend(y)
% GET_BACKEND  Phase 3 backend factory.
%
%   b = get_backend(y)
%
% Reads an optional top-level YAML key
%
%   runner:
%     type: pfem | analytic | external
%
% and returns the corresponding backend struct (contract in
% docs/PHASE3_PLAN.md Section 2). When the key is absent, defaults to 'pfem'
% so every one of the 87 legacy YAMLs keeps working with no edits.
%
% Only backends implemented so far are recognised; anything else errors so a
% typo in a future non-PFEM YAML fails loudly instead of silently falling
% back to PFEM.

    kind = 'pfem';
    if isstruct(y) && isfield(y, 'runner') && isstruct(y.runner) ...
            && isfield(y.runner, 'type') && ~isempty(y.runner.type)
        kind = lower(strtrim(char(y.runner.type)));
    end

    switch kind
        case 'pfem'
            b = pfem_backend();
        case 'analytic'
            b = analytic_backend();
        case 'external'
            % M4
            error('get_backend: external backend not implemented yet (Phase 3 M4).');
        otherwise
            error('get_backend: unknown runner.type "%s"', kind);
    end
end
