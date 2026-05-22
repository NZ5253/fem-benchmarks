function test_phase2_multi_case()
% TEST_PHASE2_MULTI_CASE  Verify Phase 2 features across multiple PFEM
% case types: LHS marginals, correlated sampling (Iman-Conover), and
% one-at-a-time sensitivity.
%
% This is the script that produces the verification numbers cited in
% docs/PROGRESS.md.
%
% Tests:
%   A. p61  plasticity_load    sensitivity of P_lim wrt yield_stress, E, nu
%   B. p101 eigenvalue         sensitivity of lambda_1 wrt EI, rhoA
%   C. p81_5 consolidation     sensitivity of Uav_end wrt permeability
%   D. LHS marginals for lognormal, truncnormal, normal, uniform
%   E. Iman-Conover correlated LHS with 3 mixed distributions
%
% Run from the project root or anywhere with paths set:
%   >> addpath('matlab', 'matlab/utils')
%   >> test_phase2_multi_case

    here = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
    addpath(fullfile(repo_root, 'matlab'));
    addpath(fullfile(repo_root, 'matlab', 'utils'));
    pfem_root = fullfile(repo_root, 'pfem');

    fprintf('\n========================================================\n');
    fprintf('  PHASE 2 multi-case verification\n');
    fprintf('========================================================\n');

    % -----------------------------------------------------------------
    % A. p61 plasticity - yield_stress should dominate P_lim
    % -----------------------------------------------------------------
    fprintf('\n--- A. p61 (plasticity_load): sensitivity for sy, E, nu ---\n');
    fprintf('    Physics: yield_stress controls limit load; E and nu only affect elastic regime\n');
    yp = fullfile(repo_root, 'benchmarks/pfem5/chap06/p61.yaml');
    specs = struct( ...
        'name',   {'yield_stress',  'youngs_modulus_E', 'poisson_ratio_nu'}, ...
        'dist',   {'lognormal',     'lognormal',        'truncnormal'}, ...
        'mu',     {100,             1e5,                0.30}, ...
        'cov',    {0.40,            0.30,               0.10}, ...
        'bounds', {[],              [],                 [0, 0.49]});
    rA = pfem_sensitivity_oat(repo_root, pfem_root, yp, specs, 'Verbose', false);
    print_ranking(rA);

    % -----------------------------------------------------------------
    % B. p101 eigenvalue - both EI and rhoA matter (lambda ~ EI/rhoA)
    % -----------------------------------------------------------------
    fprintf('\n--- B. p101 (eigenvalue): sensitivity for EI, rhoA ---\n');
    fprintf('    Physics: omega^2 = pi^4 * EI / (rhoA * L^4); both should appear\n');
    yp = fullfile(repo_root, 'benchmarks/pfem5/chap10/p101.yaml');
    specs = struct( ...
        'name',   {'stiffness_E_or_EI', 'mass_per_length_rhoA'}, ...
        'dist',   {'lognormal',          'lognormal'},           ...
        'mu',     {0.0833,               1.0},                   ...
        'cov',    {0.30,                 0.10},                  ...
        'bounds', {[],                   []});
    rB = pfem_sensitivity_oat(repo_root, pfem_root, yp, specs, 'Verbose', false);
    print_ranking(rB);

    % -----------------------------------------------------------------
    % C. p81_5 consolidation - permeability drives Uav at fixed time
    % -----------------------------------------------------------------
    fprintf('\n--- C. p81_5 (consolidation): sensitivity for k ---\n');
    fprintf('    Physics: higher k -> faster consolidation -> higher Uav at given t\n');
    yp = fullfile(repo_root, 'benchmarks/pfem5/chap08/p81_5.yaml');
    specs = struct( ...
        'name',   {'permeability_k_or_cv'}, ...
        'dist',   {'lognormal'},            ...
        'mu',     {1e-3},                   ...
        'cov',    {0.50},                   ...
        'bounds', {[]});
    rC = pfem_sensitivity_oat(repo_root, pfem_root, yp, specs, 'Verbose', false);
    print_ranking(rC);

    % -----------------------------------------------------------------
    % D. LHS marginals across multiple distributions
    % -----------------------------------------------------------------
    fprintf('\n--- D. LHS marginals (n=300) for 4 distributions ---\n');
    specsD = struct( ...
        'dist',   {'lognormal', 'truncnormal', 'normal', 'uniform'}, ...
        'mu',     {60,          25,             0.30,    0},          ...
        'cov',    {0.40,        0.10,           0.10,    0},          ...
        'bounds', {[],          [0, 45],        [],      [10, 30]});
    s = pfem_lhs_sample(specsD, 300, 'Seed', 42);
    targets     = [60, 25, 0.30, 20];
    target_stds = [60*0.40, 25*0.10, 0.30*0.10, (30-10)/sqrt(12)];
    names = {'c (lognormal)', 'phi (truncnormal)', 'nu (normal)', 'gamma (uniform)'};
    for j = 1:4
        fprintf('  %-22s mean=%.4g (target %.4g), std=%.4g (target %.4g)\n', ...
            names{j}, mean(s(:,j)), targets(j), std(s(:,j)), target_stds(j));
    end

    % -----------------------------------------------------------------
    % E. Correlation in a mixed-distribution multi-param case
    % -----------------------------------------------------------------
    fprintf('\n--- E. Correlated LHS, n=400, c-phi rho=-0.5, c-E rho=+0.3 ---\n');
    specsE = struct( ...
        'dist',   {'lognormal', 'truncnormal', 'lognormal'}, ...
        'mu',     {60,          25,             1e5},         ...
        'cov',    {0.40,        0.10,           0.30},        ...
        'bounds', {[],          [0, 45],        []});
    R = [1.0   -0.5   0.3;
        -0.5    1.0   0.0;
         0.3    0.0   1.0];
    s = pfem_lhs_sample(specsE, 400, 'Seed', 42, 'Correlation', R);
    Robs = corrcoef(s);
    fprintf('  observed rho(c,phi) = %+.3f (target -0.5)\n', Robs(1,2));
    fprintf('  observed rho(c,E)   = %+.3f (target +0.3)\n', Robs(1,3));
    fprintf('  observed rho(phi,E) = %+.3f (target  0.0)\n', Robs(2,3));
    fprintf('  marginals: c mean=%.2f std=%.2f, phi mean=%.2f std=%.2f, E mean=%.0f std=%.0f\n', ...
        mean(s(:,1)), std(s(:,1)), mean(s(:,2)), std(s(:,2)), mean(s(:,3)), std(s(:,3)));

    fprintf('\n========================================================\n');
    fprintf('  Phase 2 multi-case verification done.\n');
    fprintf('========================================================\n');
end


function print_ranking(r)
    if isnan(r.qoi_baseline)
        fprintf('    BASELINE FAILED\n'); return;
    end
    fprintf('    baseline %s = %.4g\n', r.qoi_label, r.qoi_baseline);
    for ii = 1:numel(r.order)
        j = r.order(ii);
        if isnan(r.qoi_low(j)) || isnan(r.qoi_high(j))
            fprintf('    %d. %-22s  RUN FAILED\n', ii, r.param_names{j});
        else
            fprintf('    %d. %-22s  %s: %.4g -> %.4g  spread=%.4g\n', ...
                ii, r.param_names{j}, r.qoi_label, r.qoi_low(j), r.qoi_high(j), ...
                r.qoi_high(j) - r.qoi_low(j));
        end
    end
end
