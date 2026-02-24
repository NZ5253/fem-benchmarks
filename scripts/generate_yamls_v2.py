#!/usr/bin/env python3
"""
Generate YAML benchmark files with token-based patch coordinates.

This version computes exact token positions for each tunable parameter,
enabling generic patching across all PFEM chapters without hardcoded assumptions.

Key features:
- Tokenizes .dat files preserving line structure
- Stores global_token_index for each tunable parameter
- Conservative tunable detection (E, nu, k, loads)
- MATLAB patcher uses global_token_index directly

Usage:
    python3 scripts/generate_yamls_v2.py --chapter chap05 [--case p51_3]
    python3 scripts/generate_yamls_v2.py --all-chapters

Author: Naeem
Date: 2026-01-21
"""

import os
import sys
import re
import argparse
from pathlib import Path
from datetime import date
import yaml


# =============================================================================
# TOKENIZER
# =============================================================================

def tokenize_dat_file(dat_path):
    """
    Tokenize a .dat file into a flat list of tokens with position tracking.

    Returns:
        tokens: list of token strings
        token_positions: list of (line_num, token_in_line) tuples (1-based)
        lines: original lines (with newlines stripped)
    """
    tokens = []
    token_positions = []
    lines = []

    with open(dat_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            original_line = line.rstrip('\n')
            lines.append(original_line)

            # Remove comments (Fortran style: !)
            clean_line = line.split('!')[0].strip()
            if not clean_line:
                continue

            # Tokenize: handle quoted strings and regular tokens
            line_tokens = re.findall(r"'[^']*'|[^\s]+", clean_line)

            for tok_in_line, tok in enumerate(line_tokens, 1):
                tokens.append(tok)
                token_positions.append((line_num, tok_in_line))

    return tokens, token_positions, lines


# =============================================================================
# READ STATEMENT EXTRACTION
# =============================================================================

def find_read_statements(source_file):
    """Extract READ(10,*) statements with line numbers and variables.

    Handles Fortran continuation lines (trailing &) by joining physical lines
    into logical lines before searching for READ statements.
    """
    reads = []
    try:
        with open(source_file, 'r', errors='ignore') as f:
            physical_lines = f.readlines()

        # Join Fortran continuation lines (trailing &) into logical lines.
        # Each entry is (start_line_num_1based, joined_code_text).
        logical_lines = []
        i = 0
        while i < len(physical_lines):
            line_num = i + 1  # 1-based; record the start line
            code = physical_lines[i].rstrip('\n').split('!')[0]  # strip inline comment
            while code.rstrip().endswith('&'):
                code = code.rstrip()[:-1]  # strip trailing &
                i += 1
                if i < len(physical_lines):
                    next_code = physical_lines[i].rstrip('\n').split('!')[0]
                    code = code + ' ' + next_code.lstrip()
                else:
                    break
            logical_lines.append((line_num, code))
            i += 1

        for line_num, stmt_text in logical_lines:
            if not re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)', stmt_text, re.IGNORECASE):
                continue

            stmt = re.sub(r'^\d+\s+', '', stmt_text.strip())
            is_conditional = 'IF' in stmt.upper() and 'READ' in stmt.upper()

            match = re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)\s*(.+)', stmt, re.IGNORECASE)
            variables = []
            if match:
                var_part = match.group(1).strip().split('!')[0].strip()
                variables = [v.strip() for v in re.split(r',', var_part) if v.strip()]

            reads.append({
                'line': line_num,
                'stmt': stmt,
                'variables': variables,
                'conditional': is_conditional
            })

    except Exception as e:
        print(f"  Warning: Error reading source file: {e}")
    return reads


# =============================================================================
# TUNABLE PARAMETER DETECTION - COMPREHENSIVE
# =============================================================================

# Known scalar tunables that appear directly in READ statements
SCALAR_TUNABLE_DB = {
    # Time stepping
    'dtim':     {'name': 'time_step_dtim',          'type': 'real', 'unit_category': 'time',
                 'description': 'Time step size',
                 'suggested_range': [1e-8, 10.0]},
    'nstep':    {'name': 'number_of_steps',          'type': 'int',  'unit_category': 'count',
                 'description': 'Number of time steps',
                 'suggested_range': [10, 100000]},
    'theta':    {'name': 'theta_integration',        'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Time integration parameter (0.5=Crank-Nicolson, 1.0=backward Euler)',
                 'suggested_range': [0.5, 1.0]},
    # Fluid/material properties (standalone, not in prop array)
    'visc':     {'name': 'dynamic_viscosity',        'type': 'real', 'unit_category': 'viscosity',
                 'description': 'Dynamic viscosity of fluid',
                 'suggested_range': [1e-6, 100.0]},
    'rho':      {'name': 'density_rho',              'type': 'real', 'unit_category': 'density',
                 'description': 'Fluid or solid density',
                 'suggested_range': [0.001, 100000.0]},
    # Iteration / solver control
    'tol':      {'name': 'convergence_tolerance',    'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Convergence tolerance for nonlinear iteration',
                 'suggested_range': [1e-12, 0.1]},
    'limit':    {'name': 'iteration_limit',          'type': 'int',  'unit_category': 'count',
                 'description': 'Maximum number of iterations',
                 'suggested_range': [10, 10000]},
    'incs':     {'name': 'load_increments',          'type': 'int',  'unit_category': 'count',
                 'description': 'Number of load increments',
                 'suggested_range': [1, 1000]},
    'cg_tol':   {'name': 'cg_tolerance',             'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Conjugate gradient convergence tolerance',
                 'suggested_range': [1e-14, 0.01]},
    'cg_limit': {'name': 'cg_iteration_limit',       'type': 'int',  'unit_category': 'count',
                 'description': 'CG maximum iterations',
                 'suggested_range': [100, 1000000]},
    # Newmark dynamics
    'beta':     {'name': 'newmark_beta',             'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Newmark beta (0.25=constant average acceleration)',
                 'suggested_range': [0.0, 0.5]},
    'gamma':    {'name': 'newmark_gamma',            'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Newmark gamma (0.5=linear acceleration)',
                 'suggested_range': [0.0, 1.0]},
    'fm':       {'name': 'mass_damping_factor',      'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Mass matrix Rayleigh damping factor (alpha)',
                 'suggested_range': [0.0, 10.0]},
    'fk':       {'name': 'stiffness_damping_factor', 'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Stiffness matrix Rayleigh damping factor (beta)',
                 'suggested_range': [0.0, 1.0]},
    'dr':       {'name': 'damping_ratio',            'type': 'real', 'unit_category': 'dimensionless',
                 'description': 'Modal damping ratio',
                 'suggested_range': [0.0, 1.0]},
    'omega':    {'name': 'natural_frequency',        'type': 'real', 'unit_category': 'frequency',
                 'description': 'Natural frequency (rad/s)',
                 'suggested_range': [0.001, 10000.0]},
    # Eigenvalue analysis
    'nmodes':   {'name': 'number_of_modes',          'type': 'int',  'unit_category': 'count',
                 'description': 'Number of eigenmodes to extract',
                 'suggested_range': [1, 100]},
    'nev':      {'name': 'num_eigenvalues',          'type': 'int',  'unit_category': 'count',
                 'description': 'Number of eigenvalues to compute (Arnoldi)',
                 'suggested_range': [1, 100]},
    'ncv':      {'name': 'krylov_subspace_size',     'type': 'int',  'unit_category': 'count',
                 'description': 'Krylov subspace size for Arnoldi solver',
                 'suggested_range': [5, 500]},
    'maxitr':   {'name': 'max_arnoldi_iterations',   'type': 'int',  'unit_category': 'count',
                 'description': 'Maximum Arnoldi iterations',
                 'suggested_range': [100, 100000]},
    # Mohr-Coulomb material properties — appear as individual scalars in p611-style reads
    'phi':    {'name': 'friction_angle_phi',     'type': 'real', 'unit_category': 'angle',
               'description': 'Friction angle (degrees)',
               'suggested_range': [0.0, 45.0]},
    'c':      {'name': 'cohesion_c',             'type': 'real', 'unit_category': 'stress',
               'description': 'Cohesion (shear strength intercept)',
               'suggested_range': [0.0, 1e6]},
    'psi':    {'name': 'dilation_angle_psi',     'type': 'real', 'unit_category': 'angle',
               'description': 'Dilation angle (degrees)',
               'suggested_range': [0.0, 45.0]},
    'e':      {'name': 'youngs_modulus_E',       'type': 'real', 'unit_category': 'stress',
               'description': "Young's modulus",
               'suggested_range': [1e3, 1e12]},
    'v':      {'name': 'poisson_ratio_nu',       'type': 'real', 'unit_category': 'dimensionless',
               'description': "Poisson's ratio",
               'suggested_range': [0.0, 0.49]},
    'bulk':   {'name': 'bulk_modulus_ke',        'type': 'real', 'unit_category': 'stress',
               'description': 'Bulk modulus (apparent fluid/skeleton bulk modulus Ke)',
               'suggested_range': [1.0, 1e12]},
    'cons':   {'name': 'initial_effective_stress', 'type': 'real', 'unit_category': 'stress',
               'description': 'Initial effective/consolidation stress',
               'suggested_range': [-1e9, 0.0]},
    'k0':     {'name': 'earth_pressure_coeff_k0', 'type': 'real', 'unit_category': 'dimensionless',
               'description': 'Coefficient of earth pressure at rest (K₀)',
               'suggested_range': [0.0, 2.0]},
    # Two-material (fill/embankment) properties — appear in p69-style combined reads
    'e_f':    {'name': 'youngs_modulus_fill',        'type': 'real', 'unit_category': 'stress',
               'description': "Young's modulus (fill material)",
               'suggested_range': [1e3, 1e12]},
    'v_f':    {'name': 'poisson_ratio_fill',         'type': 'real', 'unit_category': 'dimensionless',
               'description': "Poisson's ratio (fill material)",
               'suggested_range': [0.0, 0.49]},
    'c_f':    {'name': 'cohesion_fill',              'type': 'real', 'unit_category': 'stress',
               'description': 'Cohesion (fill material)',
               'suggested_range': [0.0, 1e6]},
    'phi_f':  {'name': 'friction_angle_fill',        'type': 'real', 'unit_category': 'angle',
               'description': 'Friction angle — fill (degrees)',
               'suggested_range': [0.0, 45.0]},
    'psi_f':  {'name': 'dilation_angle_fill',        'type': 'real', 'unit_category': 'angle',
               'description': 'Dilation angle — fill (degrees)',
               'suggested_range': [0.0, 45.0]},
    'gama_f': {'name': 'unit_weight_fill',           'type': 'real', 'unit_category': 'force_density',
               'description': 'Unit weight (fill material, kN/m³ or consistent units)',
               'suggested_range': [0.0, 100.0]},
    'e_e':    {'name': 'youngs_modulus_embankment',  'type': 'real', 'unit_category': 'stress',
               'description': "Young's modulus (embankment material)",
               'suggested_range': [1e3, 1e12]},
    'v_e':    {'name': 'poisson_ratio_embankment',   'type': 'real', 'unit_category': 'dimensionless',
               'description': "Poisson's ratio (embankment material)",
               'suggested_range': [0.0, 0.49]},
    'c_e':    {'name': 'cohesion_embankment',        'type': 'real', 'unit_category': 'stress',
               'description': 'Cohesion (embankment material)',
               'suggested_range': [0.0, 1e6]},
    'phi_e':  {'name': 'friction_angle_embankment',  'type': 'real', 'unit_category': 'angle',
               'description': 'Friction angle — embankment (degrees)',
               'suggested_range': [0.0, 45.0]},
    'psi_e':  {'name': 'dilation_angle_embankment',  'type': 'real', 'unit_category': 'angle',
               'description': 'Dilation angle — embankment (degrees)',
               'suggested_range': [0.0, 45.0]},
    'gama_e': {'name': 'unit_weight_embankment',     'type': 'real', 'unit_category': 'force_density',
               'description': 'Unit weight (embankment material, kN/m³ or consistent units)',
               'suggested_range': [0.0, 100.0]},
    # Prescribed displacement/load magnitude per increment (Mohr-Coulomb p63/p65/p611)
    'presc':  {'name': 'prescribed_increment',       'type': 'real', 'unit_category': 'mixed',
               'description': 'Prescribed displacement or load increment magnitude per step',
               'suggested_range': [-1e6, 1e6]},
}


def extract_source_constants(source_file):
    """Extract hardcoded integer constants from Fortran source declarations (e.g. nprops=3)."""
    constants = {'nprops': 2, 'nodof': 2, 'ndim': 2, 'nst': 3}
    try:
        with open(source_file, 'r', errors='ignore') as f:
            for line in f:
                clean = line.strip().upper()
                for key in ('NPROPS', 'NODOF', 'NDIM', 'NST'):
                    m = re.search(rf'\b{key}\s*=\s*(\d+)', clean)
                    if m:
                        constants[key.lower()] = int(m.group(1))
    except Exception:
        pass
    return constants


def split_top_level(text):
    """Split text on commas that are NOT inside parentheses."""
    result, current, depth = [], [], 0
    for ch in text:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            tok = ''.join(current).strip()
            if tok:
                result.append(tok)
            current = []
        else:
            current.append(ch)
    tok = ''.join(current).strip()
    if tok:
        result.append(tok)
    return result


def extract_read_var_part(stmt):
    """Extract the variable list from a READ(10,*) statement string."""
    m = re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)\s*(.+)', stmt, re.IGNORECASE)
    if not m:
        return ''
    var_part = m.group(1).strip()
    if '!' in var_part:
        var_part = var_part.split('!')[0].strip()
    return var_part


def estimate_token_count(var_spec, symbol_table, constants):
    """
    Estimate how many flat tokens the variable specification consumes.
    Returns -1 if size cannot be determined (caller should abort token walking).
    """
    vs = var_spec.lower().strip()
    vn = vs.split('(')[0].strip()

    nxe      = int(symbol_table.get('nxe',    1))
    nye      = int(symbol_table.get('nye',    1))
    nze      = int(symbol_table.get('nze',    1))
    nels     = int(symbol_table.get('nels',    0))
    if nels <= 0:
        # Derive nels from mesh parameters when not directly available
        if all(k in symbol_table for k in ['nx1', 'nx2', 'ny1', 'ny2']):
            # 3D embanking mesh formula (p612, p613)
            _nx1 = int(symbol_table['nx1']); _nx2 = int(symbol_table['nx2'])
            _ny1 = int(symbol_table['ny1']); _ny2 = int(symbol_table['ny2'])
            nels = (_nx1 * _ny1 + _ny2 * (_nx1 + _nx2)) * nze
        elif nxe > 1 and nye > 1:
            nels = nxe * nye
        else:
            nels = 1
    nr       = int(symbol_table.get('nr',     0))
    np_types = int(symbol_table.get('np_types', 1))
    nn       = int(symbol_table.get('nn',     1))
    loaded_nodes = int(symbol_table.get('loaded_nodes', 0))
    fixed_ff = int(symbol_table.get('fixed_freedoms', 0))
    nlfp     = int(symbol_table.get('nlfp',   0))
    incs     = int(symbol_table.get('incs',   1))
    ncon     = int(symbol_table.get('ncon',   0))
    nof      = int(symbol_table.get('nof',    0))
    nsrf     = int(symbol_table.get('nsrf',   1))

    nprops = constants.get('nprops', 2)
    nodof  = constants.get('nodof',  2)
    ndim   = constants.get('ndim',   2)

    # Implied-do patterns (start with '(')
    if vs.startswith('('):
        if 'nf(' in vs and 'nr' in vs:
            return nr * (1 + nodof)
        if 'val(i,:)' in vs and ('loaded_nodes' in vs or 'no(i)' in vs):
            return loaded_nodes * (1 + ndim)
        if 'val(i)' in vs and ('loaded_nodes' in vs or 'no(i)' in vs):
            return loaded_nodes * 2
        if 'value(i)' in vs and 'fixed_freedoms' in vs:
            return fixed_ff * 2
        if 'sense(i)' in vs and 'value(i)' in vs:
            return fixed_ff * 3
        if 'sense(i)' in vs and 'nof' in vs:
            return nof * 2
        if 'node(' in vs and 'sense(i)' in vs:
            # (node(i),sense(i),i=1,fixed_freedoms) — prescribed fixed DOFs
            return fixed_ff * 2
        if 'rt(' in vs or 'rl(' in vs:
            return nlfp * 2
        if 'srf' in vs:
            return nsrf
        if 'econn' in vs or 'econv' in vs:
            return ncon * 4
        return -1   # Unknown implied-do

    # Known named arrays
    ARRAY_SIZES = {
        'prop':     nprops * max(1, np_types),
        'ell':      nels,
        'etype':    nels,
        'x_coords': nxe + 1,
        'y_coords': nye + 1,
        'z_coords': nze + 1,
        'qinc':     incs,
        'lf':       nlfp * 2,
        'g_coord':  -1,
        'g_num':    -1,
    }
    if vn in ARRAY_SIZES:
        sz = ARRAY_SIZES[vn]
        return sz if sz >= 0 else -1

    if vn == 'loads' or vs.startswith('loads('):
        return nn + 1

    return 1


def classify_prop_structure(nprops, prop_tokens, constants, symbol_table=None):
    """
    Determine the physical meaning of each element in the prop array.

    Uses (nprops, actual values, symbol_table context) to disambiguate:
      nprops=1: [k or cv]
      nprops=2: [E, nu]  OR  [kx, ky] (2D seepage)  OR  [EI, rhoA] (1D beam)
      nprops=3: [sigma_y, E, nu] (ch6)  OR  [E, nu, rho] (ch10/11)  OR  [kx, ky, rho_c] (ch8 thermal)
      nprops=4: [kx, ky, E, nu] (ch9 Biot)  OR  [E, nu, rho, sigma_y] (ch11 explicit)
      nprops>=5: Mohr-Coulomb or complex coupled

    symbol_table is used to detect 1D context:
      - 'nels' present but 'nxe'/'nye' absent  →  1D elements (beam/rod/bar)
      - 'nxe'/'nye' present                    →  2D/3D structured mesh
    """
    if symbol_table is None:
        symbol_table = {}

    vals = []
    for (_, raw) in prop_tokens:
        try:
            vals.append(float(raw))
        except (ValueError, TypeError):
            vals.append(None)

    def v(i):
        return vals[i] if i < len(vals) else None

    # Context flags
    is_1d = ('nels' in symbol_table and
              'nxe' not in symbol_table and
              'nye' not in symbol_table)

    if nprops == 1:
        v0 = v(0)
        if v0 is not None and v0 < 100:
            return [{'name': 'permeability_k_or_cv',
                     'description': 'Permeability k or consolidation cv',
                     'unit_category': 'permeability', 'suggested_range': [1e-10, 100.0]}]
        return [{'name': 'material_prop_1',
                 'description': 'Material property 1',
                 'unit_category': 'mixed', 'suggested_range': [1e-10, 1e12]}]

    if nprops == 2:
        v0, v1 = v(0), v(1)
        # Large first value → [E, nu] regardless of mesh type
        if v0 is not None and v0 > 100:
            return [
                {'name': 'youngs_modulus_E',
                 'description': "Young's modulus",
                 'unit_category': 'stress',        'suggested_range': [1e3, 1e12]},
                {'name': 'poisson_ratio_nu',
                 'description': "Poisson's ratio",
                 'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]},
            ]
        # 1D beam/rod context (nels in symbol_table, no nxe/nye) → [EI or E, rhoA]
        if is_1d:
            return [
                {'name': 'stiffness_E_or_EI',
                 'description': "Young's modulus E or flexural stiffness EI",
                 'unit_category': 'stress',  'suggested_range': [1e-6, 1e12]},
                {'name': 'mass_per_length_rhoA',
                 'description': 'Mass per unit length (rho * area)',
                 'unit_category': 'density', 'suggested_range': [1e-6, 1e6]},
            ]
        # 2D with both values < 10 → [kx, ky] seepage
        if v0 is not None and v1 is not None and v0 < 10 and v1 < 10:
            return [
                {'name': 'permeability_kx',
                 'description': 'Permeability (x-direction)',
                 'unit_category': 'permeability',  'suggested_range': [1e-8, 100.0]},
                {'name': 'permeability_ky',
                 'description': 'Permeability (y-direction)',
                 'unit_category': 'permeability',  'suggested_range': [1e-8, 100.0]},
            ]
        return [
            {'name': 'youngs_modulus_E',
             'description': "Young's modulus",
             'unit_category': 'stress',        'suggested_range': [1e3, 1e12]},
            {'name': 'poisson_ratio_nu',
             'description': "Poisson's ratio",
             'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]},
        ]

    if nprops == 3:
        v0, v1, v2 = v(0), v(1), v(2)
        if v1 is not None and v1 > 100:
            # v1 is E → v0 is yield_stress (ch6 von Mises [sigma_y, E, nu])
            return [
                {'name': 'yield_stress',
                 'description': 'von Mises yield stress',
                 'unit_category': 'stress',        'suggested_range': [10.0, 1e6]},
                {'name': 'youngs_modulus_E',
                 'description': "Young's modulus",
                 'unit_category': 'stress',        'suggested_range': [1e3, 1e12]},
                {'name': 'poisson_ratio_nu',
                 'description': "Poisson's ratio",
                 'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]},
            ]
        # v1 in [0, 0.5) → v1 is Poisson's ratio → [E, nu, rho] dynamics/eigenvalue.
        # This also catches normalized (E=1) cases where v0 is NOT > 100.
        # Thermal [kx, ky, rho_c] is the fallback because ky (v1) is typically > 0.5.
        if v1 is not None and 0.0 <= v1 < 0.5:
            return [
                {'name': 'youngs_modulus_E',
                 'description': "Young's modulus (or stiffness)",
                 'unit_category': 'stress',        'suggested_range': [1e-6, 1e12]},
                {'name': 'poisson_ratio_nu',
                 'description': "Poisson's ratio",
                 'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]},
                {'name': 'density_rho',
                 'description': 'Mass density',
                 'unit_category': 'density',       'suggested_range': [1e-8, 100000.0]},
            ]
        # [kx, ky, rho_c] thermal (ch8 p811) — ky (v1) is NOT in [0, 0.5)
        return [
            {'name': 'conductivity_kx',
             'description': 'Thermal conductivity (x)',
             'unit_category': 'conductivity',  'suggested_range': [1e-6, 1000.0]},
            {'name': 'conductivity_ky',
             'description': 'Thermal conductivity (y)',
             'unit_category': 'conductivity',  'suggested_range': [1e-6, 1000.0]},
            {'name': 'heat_capacity_rhoc',
             'description': 'Volumetric heat capacity (rho*c)',
             'unit_category': 'heat_capacity', 'suggested_range': [1e-6, 1e8]},
        ]

    if nprops == 4:
        v0, v1, v2, v3 = v(0), v(1), v(2), v(3)
        # [E, nu, rho, sigma_y] ch11 explicit — E (v0) is large
        if v0 is not None and v0 > 100 and v1 is not None and 0.0 <= v1 < 0.5:
            return [
                {'name': 'youngs_modulus_E',
                 'description': "Young's modulus",
                 'unit_category': 'stress',        'suggested_range': [1e3, 1e12]},
                {'name': 'poisson_ratio_nu',
                 'description': "Poisson's ratio",
                 'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]},
                {'name': 'density_rho',
                 'description': 'Mass density',
                 'unit_category': 'density',       'suggested_range': [0.001, 100000.0]},
                {'name': 'yield_stress',
                 'description': 'Yield stress',
                 'unit_category': 'stress',        'suggested_range': [10.0, 1e6]},
            ]
        # [kx, ky, E, nu] ch9 Biot — detect by E (v2) large OR nu (v3) in [0, 0.5)
        if (v2 is not None and v2 > 100) or (v3 is not None and 0.0 <= v3 < 0.5):
            return [
                {'name': 'permeability_kx',
                 'description': 'Permeability (x)',
                 'unit_category': 'permeability',  'suggested_range': [1e-12, 100.0]},
                {'name': 'permeability_ky',
                 'description': 'Permeability (y)',
                 'unit_category': 'permeability',  'suggested_range': [1e-12, 100.0]},
                {'name': 'youngs_modulus_E',
                 'description': "Young's modulus",
                 'unit_category': 'stress',        'suggested_range': [1e-6, 1e12]},
                {'name': 'poisson_ratio_nu',
                 'description': "Poisson's ratio",
                 'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]},
            ]
        return [{'name': f'material_prop_{i+1}',
                 'description': f'Material property {i+1}',
                 'unit_category': 'mixed', 'suggested_range': [0.0, 1e12]} for i in range(4)]

    # nprops == 6 or 7: Mohr-Coulomb patterns.
    # PFEM 5th ed. standard: [phi, c, psi, gamma, (k0,) E, nu]
    # Detect by checking that the last two props are E (>100) and nu (0..0.5).

    _MC_PROPS = [
        {'name': 'friction_angle_phi',
         'description': 'Friction angle (degrees)',
         'unit_category': 'angle',         'suggested_range': [0.0, 45.0]},
        {'name': 'cohesion_c',
         'description': 'Cohesion (shear strength intercept)',
         'unit_category': 'stress',        'suggested_range': [0.0, 1e6]},
        {'name': 'dilation_angle_psi',
         'description': 'Dilation angle (degrees)',
         'unit_category': 'angle',         'suggested_range': [0.0, 45.0]},
        {'name': 'unit_weight_gamma',
         'description': 'Unit weight (body force per unit volume)',
         'unit_category': 'force_density', 'suggested_range': [0.0, 100.0]},
    ]
    _E_PROP  = {'name': 'youngs_modulus_E',
                'description': "Young's modulus",
                'unit_category': 'stress',        'suggested_range': [1e3, 1e12]}
    _NU_PROP = {'name': 'poisson_ratio_nu',
                'description': "Poisson's ratio",
                'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]}
    _K0_PROP = {'name': 'earth_pressure_coeff_k0',
                'description': 'Coefficient of earth pressure at rest (K₀)',
                'unit_category': 'dimensionless', 'suggested_range': [0.0, 2.0]}

    if nprops == 6:
        v4, v5 = v(4), v(5)
        # [phi, c, psi, gamma, E, nu]
        if v4 is not None and v4 > 100 and v5 is not None and 0.0 <= v5 < 0.5:
            return _MC_PROPS + [_E_PROP, _NU_PROP]

    if nprops == 7:
        v0, v1, v2, v3, v4, v5, v6 = v(0), v(1), v(2), v(3), v(4), v(5), v(6)
        # Biot + Mohr-Coulomb: [kx, ky, E, nu, phi, c, psi]  (e.g. p96)
        # Detected by first two being permeability-like (< 0.01) and next two being E, nu
        if (v0 is not None and v0 < 0.01 and
                v1 is not None and v1 < 0.01 and
                v2 is not None and v2 > 100 and
                v3 is not None and 0.0 <= v3 < 0.5):
            _KX_PROP = {'name': 'permeability_kx',
                        'description': 'Permeability (x)',
                        'unit_category': 'permeability', 'suggested_range': [1e-12, 100.0]}
            _KY_PROP = {'name': 'permeability_ky',
                        'description': 'Permeability (y)',
                        'unit_category': 'permeability', 'suggested_range': [1e-12, 100.0]}
            return [_KX_PROP, _KY_PROP, _E_PROP, _NU_PROP,
                    {'name': 'friction_angle_phi',  'description': 'Friction angle (degrees)',
                     'unit_category': 'angle',  'suggested_range': [0.0, 45.0]},
                    {'name': 'cohesion_c',  'description': 'Cohesion (shear strength intercept)',
                     'unit_category': 'stress', 'suggested_range': [0.0, 1e6]},
                    {'name': 'dilation_angle_psi', 'description': 'Dilation angle (degrees)',
                     'unit_category': 'angle',  'suggested_range': [0.0, 45.0]}]
        # [phi, c, psi, gamma, k0, E, nu]  — k0 between gamma and E
        if v5 is not None and v5 > 100 and v6 is not None and 0.0 <= v6 < 0.5:
            return _MC_PROPS + [_K0_PROP, _E_PROP, _NU_PROP]
        # [phi, c, psi, gamma, E, nu, k0]  — k0 after nu
        if v4 is not None and v4 > 100 and v5 is not None and 0.0 <= v5 < 0.5:
            return _MC_PROPS + [_E_PROP, _NU_PROP, _K0_PROP]

    # nprops >= 5 generic fallback: use value thresholds.
    # Treat very small values as permeability/coefficient (nu is always >= 0.01 in practice).
    result = []
    for i in range(nprops):
        vi = v(i)
        if vi is not None and vi > 100:
            result.append({'name': f'youngs_modulus_E_prop{i+1}',
                           'description': f"Young's modulus (prop {i+1})",
                           'unit_category': 'stress',        'suggested_range': [1e3, 1e12]})
        elif vi is not None and 0.01 <= vi < 0.5:
            # Realistic Poisson's ratio range (exclude tiny permeability values)
            result.append({'name': f'poisson_ratio_nu_prop{i+1}',
                           'description': f"Poisson's ratio (prop {i+1})",
                           'unit_category': 'dimensionless', 'suggested_range': [0.0, 0.49]})
        elif vi is not None and 1.0 <= vi <= 90.0:
            result.append({'name': f'angle_or_prop_{i+1}',
                           'description': f'Friction/dilation angle or material property {i+1}',
                           'unit_category': 'angle',         'suggested_range': [0.0, 90.0]})
        elif vi is not None and vi < 0.01 and vi > 0.0:
            result.append({'name': f'permeability_or_coeff_{i+1}',
                           'description': f'Permeability or small coefficient (prop {i+1})',
                           'unit_category': 'permeability',  'suggested_range': [1e-12, 0.01]})
        else:
            result.append({'name': f'material_prop_{i+1}',
                           'description': f'Material property {i+1}',
                           'unit_category': 'mixed',         'suggested_range': [0.0, 1e12]})
    return result


def detect_tunables_comprehensive(tokens, token_positions, read_stmts, source_file):
    """
    Detect tunable parameters by walking READ statements in order and matching variable names.

    Algorithm:
    1. Extract nprops, nodof, ndim from source file declarations
    2. Walk READ statements, consuming the correct number of tokens per variable
    3. Record scalar variables that appear in SCALAR_TUNABLE_DB
    4. For 'prop' arrays, classify each element using classify_prop_structure()
    5. Add first-READ integer tokens as mesh parameters

    Returns list of tunable dicts with correct global_token_index values.
    """
    constants    = extract_source_constants(source_file)
    tunables     = []
    seen_indices = set()
    symbol_table = {}   # variable name → scalar value (for array-size computation)
    token_idx    = 0    # 0-based index into flat token list
    uncertain    = False  # True once we lose track of exact token position

    for read_stmt in read_stmts:
        stmt = read_stmt['stmt']

        # Handle conditional READ (e.g. IF(np_types>1)READ(10,*)etype)
        if read_stmt.get('conditional'):
            cond_false = False
            m = re.search(r'IF\s*\(\s*(\w+)\s*([><=!]+)\s*(\d+)\s*\)', stmt, re.IGNORECASE)
            if m:
                var, op, rhs = m.group(1).lower(), m.group(2), int(m.group(3))
                lhs = symbol_table.get(var)
                if lhs is not None:
                    lhs_int = int(float(lhs))
                    cond_false = not eval(f'{lhs_int}{op}{rhs}')  # noqa: S307
            if cond_false:
                continue

        var_part = extract_read_var_part(stmt)
        if not var_part:
            continue
        variables = split_top_level(var_part)

        for var_spec in variables:
            vn = var_spec.lower().split('(')[0].strip()

            n = estimate_token_count(var_spec, symbol_table, constants)

            if n < 0:
                uncertain = True
                break

            # Record scalar tunables
            if n == 1 and not uncertain and vn in SCALAR_TUNABLE_DB:
                if token_idx < len(tokens):
                    gidx = token_idx + 1
                    if gidx not in seen_indices:
                        db = SCALAR_TUNABLE_DB[vn]
                        tunables.append({
                            'name':               db['name'],
                            'global_token_index': gidx,
                            'line':               token_positions[token_idx][0],
                            'type':               db['type'],
                            'description':        db['description'],
                            'unit_category':      db['unit_category'],
                            'current_value':      tokens[token_idx],
                            'suggested_range':    db['suggested_range'],
                        })
                        seen_indices.add(gidx)

            # Handle prop array
            elif vn == 'prop' and not uncertain:
                nprops   = constants.get('nprops', 2)
                np_types = max(1, int(symbol_table.get('np_types', 1)))
                prop_tokens = []
                for i in range(nprops):
                    gi = token_idx + i
                    if gi < len(tokens):
                        prop_tokens.append((gi + 1, tokens[gi]))
                structure = classify_prop_structure(nprops, prop_tokens, constants, symbol_table)
                for i, param in enumerate(structure):
                    gi = token_idx + i
                    if gi < len(tokens):
                        gidx = gi + 1
                        if gidx not in seen_indices:
                            tunables.append({
                                'name':               param['name'],
                                'global_token_index': gidx,
                                'line':               token_positions[gi][0],
                                'type':               'real',
                                'description':        param['description'],
                                'unit_category':      param['unit_category'],
                                'current_value':      tokens[gi],
                                'suggested_range':    param['suggested_range'],
                            })
                            seen_indices.add(gidx)

            # Update symbol table for scalar values
            if n == 1 and token_idx < len(tokens):
                raw = tokens[token_idx]
                try:
                    symbol_table[vn] = float(raw.strip("'"))
                except ValueError:
                    symbol_table[vn] = raw.strip("'")

            token_idx += n

    # Mesh parameters — first READ's integer tokens (document but warn about topology change)
    mesh_count = 0
    for idx, tok in enumerate(tokens[:12]):
        gidx = idx + 1
        if gidx in seen_indices:
            continue
        try:
            val = float(tok.strip("'"))
            if val == int(val) and 0 < val < 10000:
                line_num, _ = token_positions[idx]
                if mesh_count == 0:
                    name, desc = 'nels_or_nxe', 'Number of elements (nels) or x-divisions (nxe)'
                elif mesh_count == 1:
                    name, desc = 'np_types_or_nye', 'Material types (np_types) or y-divisions (nye)'
                else:
                    break
                tunables.append({
                    'name':               name,
                    'global_token_index': gidx,
                    'line':               line_num,
                    'type':               'int',
                    'description':        desc,
                    'unit_category':      'count',
                    'current_value':      tok,
                    'note':               'WARNING: changing this invalidates coordinate arrays',
                })
                seen_indices.add(gidx)
                mesh_count += 1
                if mesh_count >= 2:
                    break
        except ValueError:
            pass

    return tunables


# Backwards compatibility alias
def detect_tunables_conservative(tokens, token_positions, read_stmts):
    """Legacy alias — calls detect_tunables_comprehensive with empty source path."""
    return detect_tunables_comprehensive(tokens, token_positions, read_stmts, '')


# =============================================================================
# METADATA ANALYSIS
# =============================================================================

def analyze_source_for_metadata(source_file):
    """Analyze source code to extract physics type, dimensions, etc."""
    metadata = {
        'dimension': 2,
        'physics': 'unknown',
        'dof_per_node': 2,
        'analysis_type': 'linear',
        'regime': 'steady-state'
    }

    try:
        with open(source_file, 'r', errors='ignore') as f:
            content = f.read().lower()

            # Detect dimension from nodof
            if 'nodof=1' in content or 'nodof = 1' in content:
                metadata['dimension'] = 1
                metadata['dof_per_node'] = 1
            elif 'nodof=2' in content or 'nodof = 2' in content:
                metadata['dimension'] = 2
                metadata['dof_per_node'] = 2
            elif 'nodof=3' in content or 'nodof = 3' in content:
                metadata['dimension'] = 3
                metadata['dof_per_node'] = 3
            elif 'ndim=3' in content or 'ndim = 3' in content:
                metadata['dimension'] = 3
            elif 'ndim=1' in content or 'ndim = 1' in content:
                metadata['dimension'] = 1
                metadata['dof_per_node'] = 1

            # Detect physics
            if 'plastic' in content:
                metadata['physics'] = 'elastic-plastic'
                metadata['analysis_type'] = 'nonlinear'
            elif 'elastic' in content:
                metadata['physics'] = 'linear elasticity'
            elif 'consolidation' in content or 'biot' in content:
                metadata['physics'] = 'consolidation'
                metadata['regime'] = 'transient'
            elif 'thermal' in content or 'heat' in content:
                metadata['physics'] = 'thermal'
            elif 'seepage' in content or 'groundwater' in content:
                metadata['physics'] = 'seepage'
            elif 'eigenvalue' in content or 'frequency' in content:
                metadata['physics'] = 'eigenvalue'
            elif 'dynamic' in content or 'transient' in content:
                metadata['physics'] = 'dynamics'
                metadata['regime'] = 'transient'
            elif 'pipe' in content or 'network' in content:
                metadata['physics'] = 'pipe network'
            elif 'flow' in content:
                metadata['physics'] = 'flow'

    except Exception as e:
        print(f"  Warning: Error analyzing source: {e}")

    return metadata


# =============================================================================
# YAML GENERATION
# =============================================================================

def generate_yaml(case, chapter, program, source_file, dat_file):
    """Generate complete YAML with token-based patch coordinates."""

    chapter_num = int(chapter.replace('chap', ''))

    # Read source and data
    read_stmts = find_read_statements(source_file)
    tokens, token_positions, dat_lines = tokenize_dat_file(dat_file)

    # Detect tunable parameters
    tunables = detect_tunables_comprehensive(tokens, token_positions, read_stmts, source_file)

    # Get metadata
    metadata = analyze_source_for_metadata(source_file)

    # Build input_schema from READ statements
    input_schema = []
    for i, read_stmt in enumerate(read_stmts):
        schema_rec = {
            'record': i + 1,
            'fortran_read': read_stmt['stmt'],
            'variables': read_stmt['variables']
        }
        if read_stmt.get('conditional'):
            schema_rec['conditional'] = True
        input_schema.append(schema_rec)

    # Build the YAML structure
    yaml_dict = {
        'id': f'pfem5_ch{chapter_num:02d}_{program}_{case}',
        'title': f'PFEM Program {program} — case {case}',
        'purpose': f'{metadata["physics"].title()} analysis in {metadata["dimension"]}D.',

        'authors': {
            'source': {
                'book': 'Programming the Finite Element Method',
                'edition': '5th',
                'chapter': chapter_num,
                'program': program,
                'dataset': case
            },
            'entry': {
                'created_by': 'Naeem',
                'created_on': str(date.today()),
                'verified_platform': 'Linux (gfortran)'
            }
        },

        'code': {
            'language': 'Fortran (F2003)',
            'source_file': f'source/{chapter}/{program}.f03',
            'uses_modules': ['main', 'geom'],
            'io_reads_from_unit10': [
                {'line': r['line'], 'stmt': r['stmt']} for r in read_stmts
            ]
        },

        'fem': {
            'dimension': metadata['dimension'],
            'dof': {'per_node': metadata['dof_per_node']}
        },

        'analysis': {
            'physics': metadata['physics'],
            'type': metadata['analysis_type'],
            'regime': metadata['regime']
        },

        'units': {
            'system': 'consistent',
            'notes': 'PFEM assumes consistent units.'
        },

        # Token-based tunable parameters (KEY FEATURE)
        'tunable_parameters': tunables,

        # Input schema with READ statements
        'input_schema': {
            'file_type': '.dat',
            'total_tokens': len(tokens),
            'reads_in_order': input_schema
        },

        'inputs': {
            'working_directory': f'executable/{chapter}',
            'basename': case,
            'dat_file': f'executable/{chapter}/{case}.dat',
            'all_tokens': tokens  # Store all tokens for reference
        },

        'outputs': {
            'output_directory': f'executable/{chapter}',
            'files_expected': [f'{case}.res', f'{case}.msh']
        },

        'how_to_run': {
            'linux': [
                f'cd ~/projects/fem-benchmarks/pfem/executable/{chapter}',
                f'printf "{case}\\n" | ~/projects/fem-benchmarks/pfem/build/bin/{program}'
            ],
            'matlab': [
                f"pfem_root = fullfile(getenv('HOME'), 'projects', 'fem-benchmarks', 'pfem');",
                f"[status, out] = pfem_run_from_yaml(repo_root, pfem_root, yaml_path, struct());"
            ]
        },

        'notes': [
            'Use global_token_index from tunable_parameters for patching.',
            'The patcher replaces tokens by their 1-based index in the flat token list.',
            f'This file has {len(tokens)} tokens and {len(read_stmts)} READ statements.'
        ]
    }

    return yaml_dict


# =============================================================================
# MAIN PROCESSING
# =============================================================================

def process_case(pfem_root, chapter, case, output_dir, dry_run=False):
    """Process a single case and generate YAML."""
    program = case.split('_')[0]

    source_file = pfem_root / 'source' / chapter / f'{program}.f03'
    dat_file = pfem_root / 'executable' / chapter / f'{case}.dat'

    if not source_file.exists():
        print(f"  Warning: Source file not found: {source_file}")
        return False
    if not dat_file.exists():
        print(f"  Warning: Data file not found: {dat_file}")
        return False

    print(f"  Source: {source_file.name}, Data: {dat_file.name}")

    if dry_run:
        print(f"  [DRY RUN] Would generate YAML")
        return True

    try:
        yaml_dict = generate_yaml(case, chapter, program, source_file, dat_file)

        output_dir.mkdir(parents=True, exist_ok=True)
        output_file = output_dir / f'{case}.yaml'

        with open(output_file, 'w') as f:
            yaml.dump(yaml_dict, f, default_flow_style=False, sort_keys=False,
                     allow_unicode=True, width=120)

        n_tunables = len(yaml_dict.get('tunable_parameters', []))
        n_tokens = yaml_dict['input_schema']['total_tokens']
        print(f"  ✓ Generated: {output_file.name} ({n_tokens} tokens, {n_tunables} tunables)")
        return True

    except Exception as e:
        print(f"  ✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Generate YAML files with token-based patch coordinates'
    )
    parser.add_argument('--chapter', help='Chapter to process (e.g., chap05)')
    parser.add_argument('--case', help='Specific case (e.g., p54_1)')
    parser.add_argument('--all-chapters', action='store_true', help='Process all chapters 4-11')
    parser.add_argument('--pfem-root', default=str(Path(__file__).parent.parent / 'pfem'),
                       help='Root directory of PFEM source code')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done')

    args = parser.parse_args()

    if not args.chapter and not args.all_chapters:
        print("Error: Must specify either --chapter or --all-chapters")
        return 1

    pfem_root = Path(args.pfem_root)
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent

    if not pfem_root.exists():
        print(f"Error: PFEM root not found: {pfem_root}")
        return 1

    # Determine chapters
    if args.all_chapters:
        chapters = [f'chap{i:02d}' for i in range(4, 12)]
    else:
        chapters = [args.chapter]

    total_success = 0
    total_cases = 0

    for chapter in chapters:
        print(f"\n{'='*60}")
        print(f"Processing {chapter}")
        print('='*60)

        output_dir = repo_root / 'benchmarks' / 'pfem5' / chapter
        exec_dir = pfem_root / 'executable' / chapter

        if not exec_dir.exists():
            print(f"Warning: Directory not found: {exec_dir}")
            continue

        # Find cases
        if args.case:
            cases = [args.case]
        else:
            dat_files = list(exec_dir.glob('*.dat'))
            cases = [f.stem for f in sorted(dat_files)]

        if not cases:
            print(f"Warning: No cases found")
            continue

        print(f"Found {len(cases)} case(s)\n")

        success_count = 0
        for i, case in enumerate(cases, 1):
            print(f"[{i}/{len(cases)}] {case}")
            if process_case(pfem_root, chapter, case, output_dir, args.dry_run):
                success_count += 1
            print()

        total_success += success_count
        total_cases += len(cases)
        print(f"Chapter {chapter}: {success_count}/{len(cases)} successful")

    print('\n' + '='*60)
    print(f"TOTAL: {total_success}/{total_cases} cases processed")
    print('='*60)

    return 0 if total_success == total_cases else 1


if __name__ == '__main__':
    sys.exit(main())
