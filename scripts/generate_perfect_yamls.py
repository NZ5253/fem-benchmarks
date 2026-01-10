#!/usr/bin/env python3
"""
Generate perfect YAML benchmark files from PFEM source code and data files.

Extracts information directly from Fortran source and .dat files without hardcoding.

Usage:
    python3 scripts/generate_perfect_yamls.py --chapter chap05 [--case p54_1]
    python3 scripts/generate_perfect_yamls.py --all-chapters

Author: Naeem
Date: 2026-01-10
"""

import os
import sys
import re
import argparse
from pathlib import Path
from datetime import date
import yaml

def find_read_statements(source_file):
    """Extract READ(10,*) statements with line numbers and variables."""
    reads = []
    try:
        with open(source_file, 'r', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                if re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)', line, re.IGNORECASE):
                    stmt = line.strip()
                    stmt = re.sub(r'^\d+\s+', '', stmt)

                    # Extract variables from READ statement
                    match = re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)\s*(.+)', stmt, re.IGNORECASE)
                    variables = []
                    if match:
                        var_part = match.group(1).strip()
                        # Remove trailing comments
                        if '!' in var_part:
                            var_part = var_part.split('!')[0].strip()
                        variables = [v.strip() for v in re.split(r'[,\s]+', var_part) if v.strip()]

                    reads.append({
                        'line': line_num,
                        'stmt': stmt,
                        'variables': variables
                    })
    except Exception as e:
        print(f"  Warning: Error reading source file: {e}")
    return reads

def parse_dat_file(dat_file):
    """Parse .dat file and return lines with values."""
    try:
        with open(dat_file, 'r') as f:
            lines = []
            for line in f:
                stripped = line.strip()
                # Skip empty lines and comments
                if stripped and not stripped.startswith('!'):
                    lines.append(stripped)
            return lines
    except Exception as e:
        print(f"  Warning: Error parsing .dat file: {e}")
        return []

def analyze_source_for_metadata(source_file):
    """Analyze source code to extract physics type, dimensions, etc."""
    metadata = {
        'dimension': 2,
        'physics': 'unknown',
        'dof_per_node': 2
    }

    try:
        with open(source_file, 'r', errors='ignore') as f:
            content = f.read().lower()

            # Detect dimension
            if 'ndim=3' in content or 'ndim = 3' in content:
                metadata['dimension'] = 3
                metadata['dof_per_node'] = 3
            elif 'ndim=2' in content:
                metadata['dimension'] = 2
            elif 'ndim=1' in content:
                metadata['dimension'] = 1
                metadata['dof_per_node'] = 1

            # Detect physics type
            if 'elastic' in content and 'plastic' in content:
                metadata['physics'] = 'elastic-plastic'
            elif 'elastic' in content:
                metadata['physics'] = 'linear elasticity'
            elif 'consolidation' in content or 'biot' in content:
                metadata['physics'] = 'consolidation'
            elif 'thermal' in content or 'heat' in content:
                metadata['physics'] = 'thermal'
            elif 'flow' in content or 'seepage' in content:
                metadata['physics'] = 'fluid flow'
            elif 'dynamic' in content or 'transient' in content:
                metadata['physics'] = 'dynamics'
            elif 'eigenvalue' in content or 'frequency' in content:
                metadata['physics'] = 'eigenvalue'

    except Exception as e:
        print(f"  Warning: Error analyzing source: {e}")

    return metadata

def extract_tunable_parameters(read_stmts, dat_lines):
    """Extract tunable parameters from READ statements and dat file."""
    tunables = []

    for i, read_stmt in enumerate(read_stmts):
        vars_list = read_stmt['variables']

        # Common material property patterns
        if any('prop' in v.lower() for v in vars_list):
            tunables.append({
                'name': 'material_properties',
                'path': f'inputs.record{i+1}.prop',
                'type': 'real',
                'notes': 'Material properties (E, nu, density, etc.)'
            })

        # Mesh parameters
        if any(v in ['nxe', 'nye', 'nze', 'nels', 'nn'] for v in vars_list):
            tunables.append({
                'name': 'mesh_parameters',
                'path': f'inputs.record{i+1}',
                'type': 'int',
                'notes': 'Mesh configuration (elements, nodes, divisions)'
            })

        # Loads
        if any('load' in v.lower() for v in vars_list):
            tunables.append({
                'name': 'applied_loads',
                'path': f'inputs.record{i+1}',
                'type': 'real',
                'notes': 'Applied nodal or distributed loads'
            })

        # Coordinates
        if any('coord' in v.lower() for v in vars_list):
            tunables.append({
                'name': 'nodal_coordinates',
                'path': f'inputs.record{i+1}',
                'type': 'real',
                'notes': 'Node  coordinate values'
            })

    return tunables if tunables else [{
        'name': 'parameters',
        'path': 'inputs',
        'type': 'mixed',
        'notes': 'Model parameters from .dat file'
    }]

def create_input_schema(read_stmts):
    """Create input_schema from READ statements."""
    schema = []

    for i, read_stmt in enumerate(read_stmts):
        record = {
            'record': i + 1,
            'fortran_read': read_stmt['stmt'],
            'variables': read_stmt['variables']
        }

        # Add condition if present
        if 'IF' in read_stmt['stmt'] or 'if' in read_stmt['stmt'].lower():
            condition_match = re.search(r'IF\s*\(([^)]+)\)', read_stmt['stmt'], re.IGNORECASE)
            if condition_match:
                record['condition'] = f"only if {condition_match.group(1)}"

        schema.append(record)

    return schema

def map_dat_to_inputs(dat_lines, read_stmts):
    """Map .dat file lines to input records."""
    inputs = {}

    for i, line in enumerate(dat_lines[:len(read_stmts)]):
        record_num = i + 1
        inputs[f'record{record_num}'] = {
            'raw_value': line,
            'description': f'Values for {", ".join(read_stmts[i]["variables"])}' if i < len(read_stmts) else 'Additional data'
        }

    return inputs

def infer_program_title(program, source_file):
    """Infer program title from source code comments."""
    try:
        with open(source_file, 'r', errors='ignore') as f:
            # Read first 50 lines looking for program description
            for i, line in enumerate(f):
                if i > 50:
                    break
                if 'program' in line.lower() and ('!' in line or 'c' == line[0].lower()):
                    # Found a comment with program description
                    match = re.search(r'[!c]\s*(.+)', line, re.IGNORECASE)
                    if match:
                        desc = match.group(1).strip()
                        if len(desc) > 10 and 'program' in desc.lower():
                            return desc.replace('program', '').replace('Program', '').strip()
    except:
        pass

    # Fallback to generic title
    prog_type = program[1]  # First digit
    return f'FEM analysis program {program}'

def generate_yaml_from_source(case, chapter, program, source_file, dat_file, read_stmts, dat_lines):
    """Generate YAML by analyzing actual source code and data."""

    chapter_num = chapter.replace('chap', '')
    metadata = analyze_source_for_metadata(source_file)
    title = infer_program_title(program, source_file)

    yaml_dict = {
        'id': f'pfem5_ch{chapter_num}_{program}_{case}',
        'title': f'PFEM Program {program[1]}.{program[2:]} ({program}) — {title} — case {case}',
        'purpose': f'Analysis using {metadata["physics"]} formulation in {metadata["dimension"]}D.',

        'authors': {
            'source': {
                'book': 'Programming the Finite Element Method',
                'edition': '5th',
                'chapter': int(chapter_num),
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
            'type': 'linear' if 'linear' in metadata['physics'] else 'nonlinear',
            'regime': 'steady-state'
        },

        'units': {
            'system': 'consistent',
            'notes': 'PFEM assumes consistent units. Choose a unit system and maintain consistency.'
        },

        'tunable_parameters': extract_tunable_parameters(read_stmts, dat_lines),

        'input_schema': {
            'file_type': '.dat',
            'reads_in_order': create_input_schema(read_stmts)
        },

        'inputs': {
            'working_directory': f'executable/{chapter}',
            'basename': case,
            'dat_file': f'executable/{chapter}/{case}.dat',
            **map_dat_to_inputs(dat_lines, read_stmts)
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
                f'pfem_root = \'~/Downloads/pfem5/5th_ed\';',
                f'[status, outputs] = pfem_runner(pfem_root, \'{chapter}\', \'{program}\', \'{case}\');'
            ]
        },

        'notes': [
            'Program prompts for the base name of the .dat file (do not type the .dat extension).',
            f'This case has {len(read_stmts)} READ(10,*) statements reading from the .dat file.'
        ]
    }

    return yaml_dict

def process_case(pfem_root, chapter, case, output_dir, dry_run=False):
    """Process a single case and generate YAML."""
    program = case.split('_')[0]

    # Paths
    source_file = pfem_root / 'source' / chapter / f'{program}.f03'
    dat_file = pfem_root / 'executable' / chapter / f'{case}.dat'

    # Check files exist
    if not source_file.exists():
        print(f"  Warning: Source file not found: {source_file}")
        return False
    if not dat_file.exists():
        print(f"  Warning: Data file not found: {dat_file}")
        return False

    print(f"  Reading source: {source_file.name}")
    print(f"  Reading data: {dat_file.name}")

    # Extract information
    read_stmts = find_read_statements(source_file)
    dat_lines = parse_dat_file(dat_file)

    print(f"  Found {len(read_stmts)} READ(10,*) statements")
    print(f"  Parsed {len(dat_lines)} data lines")

    if dry_run:
        print(f"  [DRY RUN] Would generate YAML")
        return True

    # Generate YAML from actual source analysis
    yaml_dict = generate_yaml_from_source(case, chapter, program, source_file, dat_file, read_stmts, dat_lines)

    # Save YAML
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f'{case}.yaml'

    with open(output_file, 'w') as f:
        yaml.dump(yaml_dict, f, default_flow_style=False, sort_keys=False, allow_unicode=True, width=100)

    print(f"  ✓ Generated: {output_file}")
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Generate YAML files from PFEM source and data files'
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

    # Paths
    pfem_root = Path(args.pfem_root)
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent

    # Check PFEM root exists
    if not pfem_root.exists():
        print(f"Error: PFEM root not found: {pfem_root}")
        print(f"       Set correct path with --pfem-root")
        return 1

    # Determine chapters to process
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
            print(f"Warning: Executable directory not found: {exec_dir}")
            continue

        # Find cases
        if args.case:
            cases = [args.case]
        else:
            dat_files = list(exec_dir.glob('*.dat'))
            cases = [f.stem for f in sorted(dat_files)]

        if not cases:
            print(f"Warning: No cases found in {exec_dir}")
            continue

        print(f"Found {len(cases)} case(s)\n")

        # Process each case
        success_count = 0
        for i, case in enumerate(cases, 1):
            print(f"[{i}/{len(cases)}] Processing {case}")

            if process_case(pfem_root, chapter, case, output_dir, args.dry_run):
                success_count += 1

            print()

        total_success += success_count
        total_cases += len(cases)

        print(f"Chapter {chapter}: {success_count}/{len(cases)} successful")

    print('\n' + '='*60)
    print(f"TOTAL: Successfully processed {total_success}/{total_cases} cases")
    print('='*60)

    return 0 if total_success == total_cases else 1

if __name__ == '__main__':
    sys.exit(main())
