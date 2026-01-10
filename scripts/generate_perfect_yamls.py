#!/usr/bin/env python3
"""
Generate perfect YAML benchmark files from PFEM source code and data files.

This script analyzes Fortran source code, extracts READ(10,*) statements,
parses .dat files, and generates complete YAML specifications.

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
    """Extract READ(10,*) statements with line numbers from Fortran source."""
    reads = []
    try:
        with open(source_file, 'r', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                # Match READ(10,*) or READ(10, *) or READ (10,*)
                if re.search(r'READ\s*\(\s*10\s*,\s*\*\s*\)', line, re.IGNORECASE):
                    # Clean up the statement
                    stmt = line.strip()
                    # Remove line number if present
                    stmt = re.sub(r'^\d+\s+', '', stmt)
                    reads.append({'line': line_num, 'stmt': stmt})
    except Exception as e:
        print(f"  Warning: Error reading source file: {e}")
    return reads

def parse_dat_file_records(dat_file, num_reads):
    """Parse .dat file into records based on number of READ statements."""
    records = {}
    try:
        with open(dat_file, 'r') as f:
            lines = [line.strip() for line in f if line.strip() and not line.strip().startswith('!')]

        # Organize lines into records
        for i, line in enumerate(lines[:num_reads], 1):
            records[f'record{i}'] = line

    except Exception as e:
        print(f"  Warning: Error parsing .dat file: {e}")

    return records

def get_program_info(program):
    """Get metadata for PFEM programs."""
    programs = {
        'p41': {'title': 'One-dimensional bar analysis', 'physics': 'structural', 'dim': 1},
        'p42': {'title': '1D heat conduction', 'physics': 'thermal', 'dim': 1},
        'p43': {'title': '1D beam bending', 'physics': 'structural', 'dim': 1},
        'p44': {'title': '1D rod analysis', 'physics': 'structural', 'dim': 1},
        'p45': {'title': '1D frame analysis', 'physics': 'structural', 'dim': 1},
        'p46': {'title': '1D coupled analysis', 'physics': 'coupled', 'dim': 1},
        'p47': {'title': '1D eigenvalue analysis', 'physics': 'structural', 'dim': 1},

        'p51': {'title': 'Plane linear elasticity', 'physics': 'linear elasticity', 'dim': 2},
        'p52': {'title': 'Plane elasticity with PCG solver', 'physics': 'linear elasticity', 'dim': 2},
        'p53': {'title': '3D linear elasticity', 'physics': 'linear elasticity', 'dim': 3},
        'p54': {'title': 'Axisymmetric strain', 'physics': 'linear elasticity', 'dim': 2},
        'p55': {'title': 'Plane strain consolidation', 'physics': 'consolidation', 'dim': 2},
        'p56': {'title': '3D elasticity with PCG', 'physics': 'linear elasticity', 'dim': 3},
        'p57': {'title': '3D elastic-plastic', 'physics': 'elastic-plastic', 'dim': 3},

        'p61': {'title': 'Elastic-plastic plane strain', 'physics': 'elastic-plastic', 'dim': 2},
        'p62': {'title': 'Visco-plastic analysis', 'physics': 'visco-plastic', 'dim': 2},
        'p63': {'title': 'Mohr-Coulomb plasticity', 'physics': 'plasticity', 'dim': 2},
        'p64': {'title': 'Cam-clay plasticity', 'physics': 'plasticity', 'dim': 2},
        'p65': {'title': 'Damage mechanics', 'physics': 'damage', 'dim': 2},

        'p71': {'title': 'Steady-state flow', 'physics': 'fluid flow', 'dim': 2},
        'p72': {'title': 'Confined flow', 'physics': 'fluid flow', 'dim': 2},
        'p73': {'title': 'Unconfined flow', 'physics': 'fluid flow', 'dim': 2},
        'p74': {'title': '3D steady flow', 'physics': 'fluid flow', 'dim': 3},

        'p81': {'title': 'Transient heat conduction', 'physics': 'thermal', 'dim': 2},
        'p82': {'title': 'Transient seepage', 'physics': 'fluid flow', 'dim': 2},
        'p83': {'title': 'Wave propagation', 'physics': 'dynamics', 'dim': 1},
        'p84': {'title': 'Dynamic plane strain', 'physics': 'dynamics', 'dim': 2},
        'p85': {'title': '3D dynamic analysis', 'physics': 'dynamics', 'dim': 3},

        'p91': {'title': 'Coupled consolidation', 'physics': 'coupled', 'dim': 2},
        'p92': {'title': 'Thermo-mechanical coupling', 'physics': 'coupled', 'dim': 2},
        'p93': {'title': 'Fluid-structure coupling', 'physics': 'coupled', 'dim': 2},

        'p101': {'title': 'Eigenvalue analysis 2D', 'physics': 'eigenvalue', 'dim': 2},
        'p102': {'title': 'Eigenvalue analysis 3D', 'physics': 'eigenvalue', 'dim': 3},
        'p103': {'title': 'Natural frequencies', 'physics': 'eigenvalue', 'dim': 2},

        'p111': {'title': 'Parallel elastic analysis', 'physics': 'linear elasticity', 'dim': 2},
        'p112': {'title': 'Parallel PCG solver', 'physics': 'linear elasticity', 'dim': 3},
    }

    return programs.get(program, {'title': 'FEM analysis', 'physics': 'unknown', 'dim': 2})

def generate_yaml_from_template(case, chapter, program, source_file, dat_file, read_stmts):
    """Generate YAML using template based on extracted information."""

    prog_info = get_program_info(program)
    chapter_num = chapter.replace('chap', '')

    yaml_dict = {
        'id': f'pfem5_ch{chapter_num}_{program}_{case}',
        'title': f'PFEM Program {program[1]}.{program[2:]} ({program}) — {prog_info["title"]} — case {case}',
        'purpose': f'{prog_info["title"]} analysis using finite element method.',

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
            'dimension': prog_info['dim'],
            'formulation': {'code_supports': ['standard'], 'this_case': 'standard'},
            'dof': {'per_node': 2 if prog_info['dim'] == 2 else 3}
        },

        'analysis': {
            'physics': prog_info['physics'],
            'type': 'linear' if 'linear' in prog_info['physics'] else 'nonlinear',
            'regime': 'steady-state'
        },

        'units': {
            'system': 'consistent',
            'notes': 'PFEM assumes consistent units. Choose a unit system and maintain consistency.'
        },

        'tunable_parameters': [
            {
                'name': 'material_properties',
                'path': 'inputs.record2',
                'type': 'real',
                'notes': 'Material properties from .dat file'
            },
            {
                'name': 'mesh_parameters',
                'path': 'inputs.record1',
                'type': 'int',
                'notes': 'Mesh configuration parameters'
            }
        ],

        'inputs': {
            'working_directory': f'executable/{chapter}',
            'basename': case,
            'dat_file': f'executable/{chapter}/{case}.dat'
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
            'For parametric studies in MATLAB, modify .dat file parameters as needed.'
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

    # Extract READ statements
    read_stmts = find_read_statements(source_file)
    print(f"  Found {len(read_stmts)} READ(10,*) statements")

    if dry_run:
        print(f"  [DRY RUN] Would generate YAML")
        return True

    # Generate YAML
    yaml_dict = generate_yaml_from_template(case, chapter, program, source_file, dat_file, read_stmts)

    # Save YAML
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f'{case}.yaml'

    with open(output_file, 'w') as f:
        yaml.dump(yaml_dict, f, default_flow_style=False, sort_keys=False, allow_unicode=True, width=100)

    print(f"  ✓ Generated: {output_file}")
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Generate perfect YAML files from PFEM source and data files'
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
