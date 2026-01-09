#!/usr/bin/env python3
"""
Generate YAML files for Chapter 5 based on p51_3 template and bundle data.
This is a simplified generator for Chapter 5 specifically.
"""

import os
from pathlib import Path
import yaml

# Template based on p51_3
YAML_TEMPLATE = """id: pfem5_ch05_{program}_{case}
title: "PFEM Program 5.{prog_num} ({program}) — {title_desc} dataset {case}"
purpose: >
  {purpose_desc}
source:
  book: "Programming the Finite Element Method (5th ed.)"
  chapter: 5
  program: "{program}"
code:
  language: "Fortran (F2003)"
  source_file: "source/chap05/{program}.f03"
  uses_modules: ["main", "geom"]
fem:
  dimension: 2
  formulation: "{formulation}"
  element_family: "{element_family}"
  element_nodes: {element_nodes}
analysis:
  physics: "{physics}"
  type: "{analysis_type}"
  regime: "steady-state"
inputs:
  working_directory: "executable/chap05"
  basename: "{case}"
  dat_file: "executable/chap05/{case}.dat"
outputs:
  files_expected:
    - "{case}.res"
    - "{case}.msh"
    - "{case}.vec"
    - "{case}.dis"
how_to_run:
  linux_build:
    notes: "Build PFEM library modules (main, geom, etc.) then compile {program}."
    executable: "build/bin/{program}"
  linux_run:
    commands:
      - "cd ~/Downloads/pfem5/5th_ed/executable/chap05"
      - 'printf "{case}\\n" | ~/Downloads/pfem5/5th_ed/build/bin/{program}'
notes:
  - "Program prompts for the base name of the .dat file (do not type the .dat extension)."
  - "Created with YAML generator for PFEM benchmarks."
"""

# Program descriptions
PROGRAM_INFO = {
    'p51': {
        'num': '1',
        'title': 'Plane strain linear elasticity',
        'purpose': 'Plane (or axisymmetric) strain analysis of an elastic solid using triangular or quadrilateral isoparametric elements.',
        'physics': 'linear elasticity',
        'analysis_type': 'linear'
    },
    'p52': {
        'num': '2',
        'title': 'Plane strain elastic-plastic analysis',
        'purpose': 'Plane strain elastic-plastic analysis using von Mises yield criterion with triangular or quadrilateral elements.',
        'physics': 'elastic-plastic mechanics',
        'analysis_type': 'nonlinear'
    },
    'p53': {
        'num': '3',
        'title': 'Slope stability analysis',
        'purpose': 'Slope stability analysis using gravity loading and elastic-plastic material with strength reduction.',
        'physics': 'slope stability',
        'analysis_type': 'nonlinear'
    },
    'p54': {
        'num': '4',
        'title': 'Axisymmetric strain of elastic solid',
        'purpose': 'Axisymmetric strain analysis of elastic solids using triangular or quadrilateral isoparametric elements.',
        'physics': 'linear elasticity',
        'analysis_type': 'linear'
    },
    'p55': {
        'num': '5',
        'title': 'Plane strain consolidation',
        'purpose': 'Plane strain consolidation analysis (coupled flow-deformation) using Biot theory.',
        'physics': 'consolidation',
        'analysis_type': 'linear'
    },
    'p56': {
        'num': '6',
        'title': '3D strain of elastic solid',
        'purpose': '3D analysis of elastic solids using hexahedral (brick) isoparametric elements.',
        'physics': 'linear elasticity',
        'analysis_type': 'linear'
    },
    'p57': {
        'num': '7',
        'title': '3D elastic-plastic analysis',
        'purpose': '3D elastic-plastic analysis using hexahedral elements with von Mises yield criterion.',
        'physics': 'elastic-plastic mechanics',
        'analysis_type': 'nonlinear'
    }
}

def detect_element_info(dat_file):
    """Detect element type from .dat file."""
    try:
        with open(dat_file, 'r') as f:
            lines = [l.strip().strip("'") for l in f.readlines()[:3]]

            formulation = lines[0] if len(lines) > 0 else 'plane'
            element_type = lines[1].split()[0].strip("'") if len(lines) > 1 else 'quadrilateral'

            if 'triangle' in element_type.lower():
                element_family = 'triangle'
                # Try to get nod from line 2
                try:
                    nod = int(lines[1].split()[1])
                except:
                    nod = 3
            elif 'quadrilateral' in element_type.lower():
                element_family = 'quadrilateral'
                try:
                    nod = int(lines[1].split()[1])
                except:
                    nod = 4
            else:
                element_family = 'hexahedron'
                nod = 8

            return formulation, element_family, nod
    except:
        return 'plane', 'quadrilateral', 4

def generate_yaml(case_dir, output_dir):
    """Generate YAML for a single case."""
    case_name = case_dir.name
    program = case_name.split('_')[0]

    # Get program info
    prog_info = PROGRAM_INFO.get(program, {
        'num': '?',
        'title': 'Unknown',
        'purpose': 'Unknown program.',
        'physics': 'unknown',
        'analysis_type': 'unknown'
    })

    # Try to detect element info from .dat file
    dat_file = case_dir / f"{case_name}.dat"
    if dat_file.exists():
        formulation, element_family, element_nodes = detect_element_info(dat_file)
    else:
        formulation, element_family, element_nodes = 'plane', 'quadrilateral', 4

    # Fill template
    yaml_content = YAML_TEMPLATE.format(
        program=program,
        case=case_name,
        prog_num=prog_info['num'],
        title_desc=prog_info['title'],
        purpose_desc=prog_info['purpose'],
        formulation=formulation,
        element_family=element_family,
        element_nodes=element_nodes,
        physics=prog_info['physics'],
        analysis_type=prog_info['analysis_type']
    )

    # Save YAML
    output_file = output_dir / f"{case_name}.yaml"
    with open(output_file, 'w') as f:
        f.write(yaml_content)

    print(f"✓ Generated: {output_file.name}")
    return output_file

def main():
    repo_root = Path(__file__).parent.parent
    bundles_dir = repo_root / 'pfem_yaml_bundle' / 'cases' / 'chap05'
    output_dir = repo_root / 'benchmarks' / 'pfem5' / 'chap05'

    output_dir.mkdir(parents=True, exist_ok=True)

    # Get all case directories
    cases = sorted([d for d in bundles_dir.iterdir() if d.is_dir()])

    print(f"Generating YAMLs for {len(cases)} Chapter 5 cases...\n")

    generated = []
    for case_dir in cases:
        # Skip p51_3 as it already exists
        if case_dir.name == 'p51_3':
            print(f"⊘ Skipping {case_dir.name} (already exists)")
            continue

        try:
            output_file = generate_yaml(case_dir, output_dir)
            generated.append(output_file)
        except Exception as e:
            print(f"✗ Failed to generate {case_dir.name}: {e}")

    print(f"\n{'='*60}")
    print(f"Generated {len(generated)} YAML files for Chapter 5")
    print(f"Total Chapter 5 YAMLs: {len(list(output_dir.glob('*.yaml')))}")

if __name__ == '__main__':
    main()
