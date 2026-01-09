#!/usr/bin/env python3
"""
Generate YAML benchmark files from PFEM bundle folders.

Scans bundle folders, extracts information, and creates structured YAML files.

Usage:
    python3 scripts/generate_yaml_from_bundles.py [--chapter chapXX] [--case case_name] [--dry-run]

Examples:
    python3 scripts/generate_yaml_from_bundles.py --chapter chap05
    python3 scripts/generate_yaml_from_bundles.py --dry-run

Author: Naeem
Date: 2026-01-09
"""

import os
import sys
import argparse
from pathlib import Path
import anthropic

# Template for YAML generation
YAML_GENERATION_PROMPT_TEMPLATE = """Analyze the PFEM bundle and generate a structured YAML benchmark file.

**Bundle Contents:**
{bundle_contents}

**Template Example (p51_3.yaml):**
{template_yaml}

**Instructions:**
1. Analyze source code, READ statements, dataset, and outputs
2. Extract FEM details (element type, dimension, formulation, analysis type)
3. Parse .dat file for actual input values
4. List tunable parameters for parametric studies
5. Follow template structure exactly

Output only valid YAML content with all numerical values from .dat file.
"""

def read_file_safe(file_path, max_lines=None):
    """Safely read a file, handling errors gracefully."""
    try:
        with open(file_path, 'r', errors='ignore') as f:
            if max_lines:
                lines = [f.readline() for _ in range(max_lines)]
                return ''.join(lines)
            return f.read()
    except Exception as e:
        return f"[Error reading file: {e}]"

def extract_bundle_info(bundle_path):
    """Extract relevant information from a bundle folder."""
    info = {}

    # Get case info from path
    parts = bundle_path.parts
    info['chapter'] = parts[-2]  # e.g., chap05
    info['case'] = parts[-1]      # e.g., p51_3

    # Infer program name
    info['program'] = info['case'].split('_')[0]  # e.g., p51

    # Read program source (first ~200 lines for header and key parts)
    prog_src = bundle_path / f"{info['program']}.f03"
    if prog_src.exists():
        info['program_source'] = read_file_safe(prog_src, max_lines=200)
    else:
        info['program_source'] = "[Program source not found]"

    # Read READ(10,*) lines
    read_lines = bundle_path / f"{info['program']}_READ10_lines.txt"
    if read_lines.exists():
        info['read10_lines'] = read_file_safe(read_lines)
    else:
        info['read10_lines'] = "[READ10 lines not found]"

    # Read READ(10,*) context (first 500 lines to keep prompt manageable)
    read_context = bundle_path / f"{info['program']}_READ10_context.txt"
    if read_context.exists():
        info['read10_context'] = read_file_safe(read_context, max_lines=500)
    else:
        info['read10_context'] = "[READ10 context not found]"

    # Read dataset file
    dat_file = bundle_path / f"{info['case']}.dat"
    if dat_file.exists():
        info['dat_file'] = read_file_safe(dat_file)
    else:
        info['dat_file'] = "[Dataset file not found]"

    # Read result file head
    res_head = bundle_path / f"{info['case']}_res_head.txt"
    if res_head.exists():
        info['res_head'] = read_file_safe(res_head)
    else:
        # Try reading .res directly
        res_file = bundle_path / f"{info['case']}.res"
        if res_file.exists():
            info['res_head'] = read_file_safe(res_file, max_lines=50)
        else:
            info['res_head'] = "[No result file available]"

    # List output files
    output_files = []
    for ext in ['.res', '.msh', '.vec', '.dis', '.con', '.out']:
        if (bundle_path / f"{info['case']}{ext}").exists():
            output_files.append(f"{info['case']}{ext}")
    info['output_files'] = output_files

    return info

def format_bundle_for_prompt(bundle_info):
    """Format bundle information for the analysis tool prompt."""
    return f"""
CHAPTER: {bundle_info['chapter']}
PROGRAM: {bundle_info['program']}
CASE: {bundle_info['case']}

=== PROGRAM SOURCE (header and key sections) ===
{bundle_info['program_source']}

=== READ(10,*) STATEMENTS (in order) ===
{bundle_info['read10_lines']}

=== READ(10,*) CONTEXT (code around each READ statement) ===
{bundle_info['read10_context']}

=== DATASET FILE ({bundle_info['case']}.dat) ===
{bundle_info['dat_file']}

=== RESULT FILE HEAD ({bundle_info['case']}.res or head) ===
{bundle_info['res_head']}

=== OUTPUT FILES CREATED ===
{', '.join(bundle_info['output_files']) if bundle_info['output_files'] else 'None found'}
"""

def generate_yaml_with_claude(bundle_info, template_yaml, api_key):
    """Generate YAML using external API."""
    client = anthropic.Anthropic(api_key=api_key)

    prompt = YAML_GENERATION_PROMPT_TEMPLATE.format(
        bundle_contents=format_bundle_for_prompt(bundle_info),
        template_yaml=template_yaml
    )

    try:
        message = client.messages.create(
            model="model-4-20250514",
            max_tokens=4096,
            temperature=0,
            messages=[
                {"role": "user", "content": prompt}
            ]
        )

        yaml_content = message.content[0].text.strip()

        # Remove markdown code blocks if present
        if yaml_content.startswith('```yaml'):
            yaml_content = yaml_content.split('```yaml')[1].split('```')[0].strip()
        elif yaml_content.startswith('```'):
            yaml_content = yaml_content.split('```')[1].split('```')[0].strip()

        return yaml_content
    except Exception as e:
        print(f"[ERROR] external API call failed: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description='Generate YAML files from PFEM bundles from PFEM bundles')
    parser.add_argument('--chapter', help='Specific chapter to process (e.g., chap05)')
    parser.add_argument('--case', help='Specific case to process (e.g., p51_3)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without generating')
    parser.add_argument('--api-key', help='API key (or set ANTHROPIC_API_KEY env var)')

    args = parser.parse_args()

    # Get paths
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    bundles_dir = repo_root / 'pfem_yaml_bundle' / 'cases'
    benchmarks_dir = repo_root / 'benchmarks' / 'pfem5'
    template_yaml_path = benchmarks_dir / 'chap05' / 'p51_3.yaml'

    # Check if bundles exist
    if not bundles_dir.exists():
        print(f"[ERROR] Bundles directory not found: {bundles_dir}")
        print("        Run pfem_collect_all.sh first to create bundles.")
        return 1

    # Read template YAML
    if not template_yaml_path.exists():
        print(f"[ERROR] Template YAML not found: {template_yaml_path}")
        return 1

    with open(template_yaml_path, 'r') as f:
        template_yaml = f.read()

    # Get API key
    api_key = args.api_key or os.environ.get('ANTHROPIC_API_KEY')
    if not api_key and not args.dry_run:
        print("[ERROR] API key required. Set ANTHROPIC_API_KEY env var or use --api-key")
        return 1

    # Find all bundle cases
    if args.chapter and args.case:
        # Specific case
        cases = [bundles_dir / args.chapter / args.case]
    elif args.chapter:
        # All cases in specific chapter
        chap_dir = bundles_dir / args.chapter
        if not chap_dir.exists():
            print(f"[ERROR] Chapter directory not found: {chap_dir}")
            return 1
        cases = [d for d in chap_dir.iterdir() if d.is_dir()]
    else:
        # All cases in all chapters
        cases = []
        for chap_dir in sorted(bundles_dir.iterdir()):
            if chap_dir.is_dir() and chap_dir.name.startswith('chap'):
                cases.extend([d for d in chap_dir.iterdir() if d.is_dir()])

    if not cases:
        print("[WARN] No bundle cases found.")
        return 0

    print(f"[INFO] Found {len(cases)} case(s) to process")

    # Process each case
    success_count = 0
    for i, case_path in enumerate(sorted(cases), 1):
        print(f"\n[{i}/{len(cases)}] Processing {case_path.parent.name}/{case_path.name}")

        # Extract bundle information
        bundle_info = extract_bundle_info(case_path)

        # Determine output path
        output_dir = benchmarks_dir / bundle_info['chapter']
        output_file = output_dir / f"{bundle_info['case']}.yaml"

        if args.dry_run:
            print(f"  Would generate: {output_file}")
            continue

        # Create output directory
        output_dir.mkdir(parents=True, exist_ok=True)

        # Generate YAML with analysis tool
        print(f"  Generating YAML from bundle analysis...")
        yaml_content = generate_yaml_with_claude(bundle_info, template_yaml, api_key)

        if yaml_content:
            # Save YAML file
            with open(output_file, 'w') as f:
                f.write(yaml_content)
            print(f"  ✓ Generated: {output_file}")
            success_count += 1
        else:
            print(f"  ✗ Failed to generate YAML")

    print(f"\n{'='*60}")
    print(f"[DONE] Successfully generated {success_count}/{len(cases)} YAML files")

    return 0 if success_count == len(cases) else 1

if __name__ == '__main__':
    sys.exit(main())
