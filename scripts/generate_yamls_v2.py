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
    """Extract READ(10,*) statements with line numbers and variables."""
    reads = []
    try:
        with open(source_file, 'r', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                if re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)', line, re.IGNORECASE):
                    stmt = line.strip()
                    # Remove leading line numbers (if any)
                    stmt = re.sub(r'^\d+\s+', '', stmt)

                    # Check if this is a conditional READ
                    is_conditional = 'IF' in stmt.upper() and 'READ' in stmt.upper()

                    # Extract variables from READ statement
                    match = re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)\s*(.+)', stmt, re.IGNORECASE)
                    variables = []
                    if match:
                        var_part = match.group(1).strip()
                        if '!' in var_part:
                            var_part = var_part.split('!')[0].strip()
                        # Simple split on comma (doesn't handle all cases but good enough)
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
# TUNABLE PARAMETER DETECTION
# =============================================================================

def detect_tunables_conservative(tokens, token_positions, read_stmts):
    """
    Detect tunable parameters with conservative heuristics.

    Strategy:
    1. Find READ statements containing 'prop' to locate material properties
    2. First large numeric value after mesh params is likely E (Young's modulus)
    3. Value in (0, 0.5) after E is likely nu (Poisson's ratio)
    4. Mesh parameters (integer tokens early in file)

    Returns list of tunable dicts with global_token_index.
    """
    tunables = []
    seen_indices = set()

    # Find which READ statement reads 'prop' (material properties)
    prop_read_idx = None
    for i, stmt in enumerate(read_stmts):
        vars_lower = [v.lower() for v in stmt.get('variables', [])]
        if 'prop' in vars_lower:
            prop_read_idx = i
            break

    # Count tokens consumed by first records to estimate where prop starts
    # Heuristic: first READ usually has mesh params (integers)
    mesh_token_count = 0
    for idx, tok in enumerate(tokens[:15]):  # First 15 tokens max
        try:
            tok_clean = tok.strip("'")
            val = float(tok_clean)
            # If it's a large number or has decimal, likely not mesh param
            if val > 100 or '.' in tok_clean or 'e' in tok_clean.lower():
                break
            mesh_token_count = idx + 1
        except ValueError:
            # String token (like 'plane') - might be mesh param too
            mesh_token_count = idx + 1

    # Material properties typically start after mesh parameters
    prop_start_idx = mesh_token_count

    e_found = False
    nu_found = False

    for idx, tok in enumerate(tokens):
        global_idx = idx + 1  # 1-based
        line_num, tok_in_line = token_positions[idx]

        # Skip if already added
        if global_idx in seen_indices:
            continue

        # Try to parse as number
        try:
            tok_clean = tok.strip("'")
            val = float(tok_clean)
            is_numeric = True
        except ValueError:
            is_numeric = False
            val = None

        if not is_numeric:
            continue

        # Heuristic 1: First large numeric value (> 100) after mesh params is likely E
        # Use lower threshold (100) to catch cases like E=2000
        if not e_found and val is not None and idx >= prop_start_idx and val > 100 and val < 1e15:
            tunables.append({
                'name': 'youngs_modulus_E',
                'global_token_index': global_idx,
                'line': line_num,
                'type': 'real',
                'description': "Young's modulus",
                'unit_category': 'stress',
                'current_value': tok,
                'suggested_range': [1.0e4, 1.0e12]
            })
            seen_indices.add(global_idx)
            e_found = True
            continue

        # Heuristic 2: Value in (0, 0.5) after E is likely Poisson's ratio
        if e_found and not nu_found and val is not None and 0 < val < 0.5:
            tunables.append({
                'name': 'poisson_ratio_nu',
                'global_token_index': global_idx,
                'line': line_num,
                'type': 'real',
                'description': "Poisson's ratio",
                'unit_category': 'dimensionless',
                'current_value': tok,
                'suggested_range': [0.0, 0.49]
            })
            seen_indices.add(global_idx)
            nu_found = True
            continue

        # Heuristic 3: Small positive values (< 100) after nu might be permeability
        if e_found and nu_found and val is not None and 0 < val < 100:
            if 'permeability_k' not in [t['name'] for t in tunables]:
                tunables.append({
                    'name': 'permeability_k',
                    'global_token_index': global_idx,
                    'line': line_num,
                    'type': 'real',
                    'description': 'Permeability or conductivity',
                    'unit_category': 'permeability',
                    'current_value': tok,
                    'suggested_range': [1.0e-6, 100.0]
                })
                seen_indices.add(global_idx)
                # Don't continue - might be other props
                break  # Stop after first few material properties

    # Add mesh parameters (first few integer tokens)
    mesh_params_added = 0
    for idx, tok in enumerate(tokens[:10]):  # Only first 10 tokens
        global_idx = idx + 1
        if global_idx in seen_indices:
            continue
        try:
            tok_clean = tok.strip("'")
            val = int(float(tok_clean))
            # Integer > 0 and < 1000 is likely a mesh parameter
            if 0 < val < 1000 and float(tok_clean) == val:
                line_num, _ = token_positions[idx]
                name = f'mesh_param_{mesh_params_added + 1}'
                if mesh_params_added == 0:
                    name = 'nels_or_nxe'
                    desc = 'Number of elements (nels) or x-divisions (nxe)'
                elif mesh_params_added == 1:
                    name = 'np_types_or_nye'
                    desc = 'Material types (np_types) or y-divisions (nye)'
                else:
                    desc = f'Mesh parameter {mesh_params_added + 1}'

                tunables.append({
                    'name': name,
                    'global_token_index': global_idx,
                    'line': line_num,
                    'type': 'int',
                    'description': desc,
                    'unit_category': 'count',
                    'current_value': tok
                })
                seen_indices.add(global_idx)
                mesh_params_added += 1
                if mesh_params_added >= 2:
                    break
        except ValueError:
            continue

    return tunables


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
    tunables = detect_tunables_conservative(tokens, token_positions, read_stmts)

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
                f'cd ~/Downloads/pfem5/5th_ed/executable/{chapter}',
                f'printf "{case}\\n" | ~/Downloads/pfem5/5th_ed/build/bin/{program}'
            ],
            'matlab': [
                f"pfem_root = '~/Downloads/pfem5/5th_ed';",
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
    parser.add_argument('--pfem-root', default='/home/naeem/Downloads/pfem5/5th_ed',
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
