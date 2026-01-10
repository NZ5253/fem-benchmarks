#!/usr/bin/env python3
"""
Generate perfect YAML benchmark files from PFEM source code and data files.

This script analyzes Fortran source code, extracts READ(10,*) statements,
parses .dat files, and generates complete YAML specifications.

Usage:
    python3 scripts/generate_perfect_yamls.py --chapter chap05 [--case p54_1]
    python3 scripts/generate_perfect_yamls.py --chapter chap05 --api-key YOUR_KEY

Author: Naeem
Date: 2026-01-10
"""

import os
import sys
import re
import argparse
from pathlib import Path
from datetime import date

try:
    import anthropic
    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False

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

def get_program_metadata(program, chapter):
    """Get basic program metadata."""
    metadata = {
        'p51': {
            'title_template': 'Plane linear elasticity',
            'purpose': 'Plane (or axisymmetric) strain analysis of an elastic solid using triangular or quadrilateral elements.',
            'physics': 'linear elasticity',
            'dimension': 2,
        },
        'p52': {
            'title_template': 'Plane linear elasticity (PCG solver)',
            'purpose': 'Plane strain analysis with preconditioned conjugate gradient solver.',
            'physics': 'linear elasticity',
            'dimension': 2,
        },
        'p53': {
            'title_template': '3D linear elasticity',
            'purpose': '3D analysis of elastic solids using isoparametric elements.',
            'physics': 'linear elasticity',
            'dimension': 3,
        },
        'p54': {
            'title_template': 'Axisymmetric strain of elastic solid',
            'purpose': 'Axisymmetric strain analysis of elastic solids using triangular or quadrilateral elements.',
            'physics': 'linear elasticity',
            'dimension': 2,
        },
        'p55': {
            'title_template': 'Plane strain consolidation',
            'purpose': 'Plane strain consolidation analysis using coupled Biot formulation.',
            'physics': 'consolidation (Biot)',
            'dimension': 2,
        },
        'p56': {
            'title_template': '3D elasticity with PCG solver',
            'purpose': '3D elastic analysis using preconditioned conjugate gradient solver.',
            'physics': 'linear elasticity',
            'dimension': 3,
        },
        'p57': {
            'title_template': '3D elastic-plastic analysis',
            'purpose': '3D elastic-plastic analysis using von Mises yield criterion.',
            'physics': 'elastic-plastic',
            'dimension': 3,
        },
    }
    return metadata.get(program, {
        'title_template': 'FEM analysis',
        'purpose': 'Finite element analysis.',
        'physics': 'unknown',
        'dimension': 2,
    })

def read_dat_file(dat_file_path):
    """Read .dat file contents."""
    try:
        with open(dat_file_path, 'r') as f:
            return f.read()
    except Exception as e:
        return f"[Error reading .dat file: {e}]"

def generate_perfect_yaml_with_api(case_info, template_yaml, api_key):
    """Generate perfect YAML using Anthropic API."""
    if not HAS_ANTHROPIC:
        print("  Error: anthropic module not installed. Install with: pip install anthropic")
        return None

    client = anthropic.Anthropic(api_key=api_key)

    prompt = f"""Generate a complete "perfect YAML" benchmark file for PFEM case {case_info['case']}.

**REFERENCE TEMPLATE (p54_1.yaml - use this exact structure):**
{template_yaml}

**CASE INFORMATION:**
- Program: {case_info['program']}
- Case: {case_info['case']}
- Chapter: {case_info['chapter']}

**FORTRAN SOURCE CODE (first 300 lines with READ statements):**
{case_info['source_code']}

**READ(10,*) STATEMENTS FOUND (with line numbers):**
{case_info['read_statements']}

**DATASET FILE ({case_info['case']}.dat):**
{case_info['dat_content']}

**INSTRUCTIONS:**
1. Follow the EXACT structure from the p54_1.yaml template
2. Use these sections in order:
   - id, title, purpose
   - authors (with created_by: "Naeem", created_on: "{date.today()}")
   - code (with io_reads_from_unit10 using the READ statements with line numbers above)
   - fem (dimension, formulation, dof, element)
   - analysis (physics, type, regime)
   - units
   - tunable_parameters (E, nu, loads, mesh parameters)
   - input_schema (reads_in_order with detailed field descriptions)
   - inputs (parsed .dat values organized by record1, record2, etc.)
   - outputs
   - how_to_run (linux and matlab commands)
   - notes

3. For io_reads_from_unit10: Use EXACT line numbers and statements from READ statements above
4. For input_schema: Map each READ statement to a record with field descriptions
5. For inputs: Parse the .dat file and organize values by record (record1, record2, etc.)
6. For tunable_parameters: Include E, nu, loads, mesh density with paths like "inputs.record2.material.E.value"

Output ONLY the complete YAML content, no explanations."""

    try:
        message = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=8000,
            temperature=0,
            messages=[{"role": "user", "content": prompt}]
        )

        yaml_content = message.content[0].text.strip()

        # Remove markdown code blocks if present
        if yaml_content.startswith('```yaml'):
            yaml_content = yaml_content.split('```yaml')[1].split('```')[0].strip()
        elif yaml_content.startswith('```'):
            yaml_content = yaml_content.split('```')[1].split('```')[0].strip()

        return yaml_content
    except Exception as e:
        print(f"  Error: API call failed: {e}")
        return None

def process_case(pfem_root, chapter, case, template_yaml, api_key, dry_run=False):
    """Process a single case and generate perfect YAML."""
    program = case.split('_')[0]  # e.g., p54 from p54_1

    # Paths
    source_file = pfem_root / 'source' / chapter / f'{program}.f03'
    dat_file = pfem_root / 'executable' / chapter / f'{case}.dat'

    # Check files exist
    if not source_file.exists():
        print(f"  Error: Source file not found: {source_file}")
        return False
    if not dat_file.exists():
        print(f"  Error: Data file not found: {dat_file}")
        return False

    print(f"  Reading source: {source_file.name}")
    print(f"  Reading data: {dat_file.name}")

    # Extract READ statements
    read_stmts = find_read_statements(source_file)
    print(f"  Found {len(read_stmts)} READ(10,*) statements")

    # Read source code (first 300 lines)
    with open(source_file, 'r', errors='ignore') as f:
        source_lines = [f.readline() for _ in range(300)]
        source_code = ''.join(source_lines)

    # Read .dat file
    dat_content = read_dat_file(dat_file)

    # Format READ statements for prompt
    read_stmts_formatted = '\n'.join([
        f"Line {r['line']}: {r['stmt']}" for r in read_stmts
    ])

    # Build case info
    case_info = {
        'program': program,
        'case': case,
        'chapter': chapter,
        'source_code': source_code,
        'read_statements': read_stmts_formatted,
        'dat_content': dat_content,
        'metadata': get_program_metadata(program, chapter)
    }

    if dry_run:
        print(f"  [DRY RUN] Would generate YAML with {len(read_stmts)} READ statements")
        return True

    # Generate YAML with API
    print(f"  Generating perfect YAML...")
    yaml_content = generate_perfect_yaml_with_api(case_info, template_yaml, api_key)

    return yaml_content

def main():
    parser = argparse.ArgumentParser(
        description='Generate perfect YAML files from PFEM source and data files'
    )
    parser.add_argument('--chapter', required=True, help='Chapter to process (e.g., chap05)')
    parser.add_argument('--case', help='Specific case (e.g., p54_1). If not specified, processes all cases.')
    parser.add_argument('--pfem-root', default='/home/naeem/Downloads/pfem5/5th_ed',
                       help='Root directory of PFEM source code')
    parser.add_argument('--api-key', help='Anthropic API key (or set ANTHROPIC_API_KEY env var)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done')
    parser.add_argument('--output-dir', help='Output directory (default: benchmarks/pfem5/{chapter})')

    args = parser.parse_args()

    # Paths
    pfem_root = Path(args.pfem_root)
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent

    if args.output_dir:
        output_dir = Path(args.output_dir)
    else:
        output_dir = repo_root / 'benchmarks' / 'pfem5' / args.chapter

    # Check PFEM root exists
    if not pfem_root.exists():
        print(f"Error: PFEM root not found: {pfem_root}")
        return 1

    # Read template YAML (use p54_1 as template)
    template_file = output_dir / 'p54_1.yaml'
    if not template_file.exists():
        print(f"Error: Template YAML not found: {template_file}")
        print("       p54_1.yaml is used as the template for perfect YAMLs")
        return 1

    with open(template_file, 'r') as f:
        template_yaml = f.read()

    # Get API key
    api_key = args.api_key or os.environ.get('ANTHROPIC_API_KEY')
    if not api_key and not args.dry_run:
        print("Error: API key required. Set ANTHROPIC_API_KEY env var or use --api-key")
        return 1

    # Find cases to process
    exec_dir = pfem_root / 'executable' / args.chapter
    if not exec_dir.exists():
        print(f"Error: Executable directory not found: {exec_dir}")
        return 1

    if args.case:
        cases = [args.case]
    else:
        # Find all .dat files in chapter
        dat_files = list(exec_dir.glob('*.dat'))
        cases = [f.stem for f in sorted(dat_files)]

    if not cases:
        print(f"Warning: No cases found in {exec_dir}")
        return 0

    print(f"Found {len(cases)} case(s) to process in {args.chapter}")
    print(f"Output directory: {output_dir}")
    print()

    # Process each case
    success_count = 0
    for i, case in enumerate(cases, 1):
        print(f"[{i}/{len(cases)}] Processing {case}")

        result = process_case(pfem_root, args.chapter, case, template_yaml, api_key, args.dry_run)

        if result and not args.dry_run:
            # Save YAML
            output_dir.mkdir(parents=True, exist_ok=True)
            output_file = output_dir / f'{case}.yaml'

            with open(output_file, 'w') as f:
                f.write(result)

            print(f"  ✓ Generated: {output_file}")
            success_count += 1
        elif result and args.dry_run:
            success_count += 1
        else:
            print(f"  ✗ Failed to generate YAML")

        print()

    print('=' * 60)
    print(f"Successfully processed {success_count}/{len(cases)} cases")

    return 0 if success_count == len(cases) else 1

if __name__ == '__main__':
    sys.exit(main())
