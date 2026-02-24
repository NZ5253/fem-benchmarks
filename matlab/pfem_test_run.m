% PFEM_TEST_RUN  Quick test script to verify the PFEM pipeline works
%
% This script tests:
% 1. YAML loading
% 2. Running a case without overrides
% 3. Running a case with overrides (parameter patching)
%
% Usage:
%   Run this script from MATLAB after setting paths:
%   >> cd ~/projects/fem-benchmarks
%   >> pfem_test_run

fprintf('============================================================\n');
fprintf('PFEM Pipeline Test\n');
fprintf('============================================================\n\n');

% Configuration
repo_root = pwd;  % Assumes running from fem-benchmarks root
pfem_root = fullfile(repo_root, 'pfem');

% Add MATLAB paths
addpath(fullfile(repo_root, 'matlab'));
addpath(fullfile(repo_root, 'matlab', 'utils'));

%% Test 1: YAML Loading
fprintf('TEST 1: YAML Loading\n');
fprintf('------------------------------------------------------------\n');

yaml_path = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap04', 'p41_1.yaml');
try
    y = pfem_yaml_load(yaml_path);
    fprintf('  ✓ Loaded: %s\n', yaml_path);
    fprintf('    - Chapter: %d\n', y.authors.source.chapter);
    fprintf('    - Program: %s\n', y.authors.source.program);
    fprintf('    - Dataset: %s\n', y.authors.source.dataset);
    fprintf('    - Tokens: %d\n', y.input_schema.total_tokens);
    fprintf('    - Tunables: %d\n', numel(y.tunable_parameters));

    % Show tunables
    fprintf('    - Tunable parameters:\n');
    for i = 1:min(3, numel(y.tunable_parameters))
        tp = y.tunable_parameters{i};
        fprintf('      %d. %s (token %d)\n', i, tp.name, tp.global_token_index);
    end
    test1_pass = true;
catch ME
    fprintf('  ✗ Failed: %s\n', ME.message);
    test1_pass = false;
end
fprintf('\n');

%% Test 2: Run without overrides
fprintf('TEST 2: Run without overrides\n');
fprintf('------------------------------------------------------------\n');

try
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, struct());
    if status == 0
        fprintf('  ✓ Run completed successfully\n');
        fprintf('    - Output files: %d\n', out.num_files);
        test2_pass = true;
    else
        fprintf('  ✗ Run failed with status %d\n', status);
        test2_pass = false;
    end
catch ME
    fprintf('  ✗ Error: %s\n', ME.message);
    test2_pass = false;
end
fprintf('\n');

%% Test 3: Run with overrides (parameter patching)
fprintf('TEST 3: Run with overrides\n');
fprintf('------------------------------------------------------------\n');

% Use chap05 p51_3 for this test (has well-defined E and nu)
yaml_path_2 = fullfile(repo_root, 'benchmarks', 'pfem5', 'chap05', 'p51_3.yaml');

try
    % Load YAML
    y2 = pfem_yaml_load(yaml_path_2);
    fprintf('  Loaded: %s\n', y2.authors.source.dataset);

    % Set overrides
    overrides = struct();
    overrides.youngs_modulus_E = 2e6;  % Double the default E

    % Run with overrides
    [status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path_2, overrides);

    if status == 0
        fprintf('  ✓ Run completed successfully with E = 2e6\n');
        fprintf('    - Output files: %d\n', out.num_files);
        test3_pass = true;
    else
        fprintf('  ✗ Run failed with status %d\n', status);
        test3_pass = false;
    end
catch ME
    fprintf('  ✗ Error: %s\n', ME.message);
    test3_pass = false;
end
fprintf('\n');

%% Summary
fprintf('============================================================\n');
fprintf('Summary\n');
fprintf('============================================================\n');
tests = {'YAML Loading', 'Run (no overrides)', 'Run (with overrides)'};
results = [test1_pass, test2_pass, test3_pass];

for i = 1:numel(tests)
    if results(i)
        fprintf('  ✓ %s: PASS\n', tests{i});
    else
        fprintf('  ✗ %s: FAIL\n', tests{i});
    end
end

passed = sum(results);
fprintf('\nTotal: %d/%d tests passed\n', passed, numel(tests));
fprintf('============================================================\n');
