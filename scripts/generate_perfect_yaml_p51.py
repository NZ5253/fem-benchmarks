#!/usr/bin/env python3
"""
Generate a "perfect YAML" for p51 cases following the complete specification.
This serves as a template for generating comprehensive YAMLs for all programs.
"""

import os
import sys
from pathlib import Path
import re

def parse_dat_file_p51(dat_path):
    """Parse p51 .dat file and extract structured data."""
    with open(dat_path, 'r') as f:
        lines = [l.strip().strip("'\"") for l in f.readlines()]

    data = {}
    idx = 0

    # Record 1: type_2d, element, nod, dir, nxe, nye, nip, np_types
    parts = lines[idx].replace("'", "").split()
    data['type_2d'] = parts[0] if len(parts) > 0 else 'plane'
    idx += 1

    parts = lines[idx].replace("'", "").split()
    data['element'] = parts[0] if len(parts) > 0 else 'quadrilateral'
    data['nod'] = int(parts[1]) if len(parts) > 1 else 4
    data['dir'] = parts[2] if len(parts) > 2 else 'y'
    idx += 1

    parts = lines[idx].split()
    data['nxe'] = int(parts[0]) if len(parts) > 0 else 2
    data['nye'] = int(parts[1]) if len(parts) > 1 else 2
    data['nip'] = int(parts[2]) if len(parts) > 2 else 4
    data['np_types'] = int(parts[3]) if len(parts) > 3 else 1
    idx += 1

    # Record 2: material properties (E, nu)
    parts = lines[idx].split()
    data['E'] = float(parts[0]) if len(parts) > 0 else 1.0e6
    data['nu'] = float(parts[1]) if len(parts) > 1 else 0.3
    idx += 1

    # Record 3: x_coords, y_coords
    parts = lines[idx].split()
    data['x_coords'] = [float(x) for x in parts]
    idx += 1

    parts = lines[idx].split()
    data['y_coords'] = [float(y) for y in parts]
    idx += 1

    # Record 4: boundary conditions
    parts = lines[idx].split()
    data['nr'] = int(parts[0])
    data['bc_table'] = []
    for i in range(data['nr']):
        idx += 1
        bc_parts = lines[idx].split()
        data['bc_table'].append({
            'node': int(bc_parts[0]),
            'dof1': int(bc_parts[1]),
            'dof2': int(bc_parts[2])
        })
    idx += 1

    # Record 5: loaded nodes
    parts = lines[idx].split()
    data['loaded_nodes'] = int(parts[0])
    data['nodal_loads'] = []
    for i in range(data['loaded_nodes']):
        idx += 1
        load_parts = lines[idx].split()
        data['nodal_loads'].append({
            'node': int(load_parts[0]),
            'fx': float(load_parts[1]),
            'fy': float(load_parts[2])
        })
    idx += 1

    # Record 6: fixed_freedoms
    parts = lines[idx].split()
    data['fixed_freedoms'] = int(parts[0])
    idx += 1

    # Record 7: prescribed displacements (if any)
    data['prescribed_displacements'] = []
    for i in range(data['fixed_freedoms']):
        if idx < len(lines):
            pd_parts = lines[idx].split()
            if len(pd_parts) >= 3:
                data['prescribed_displacements'].append({
                    'node': int(pd_parts[0]),
                    'sense': int(pd_parts[1]),
                    'value': float(pd_parts[2])
                })
            idx += 1

    return data

def parse_res_file(res_path):
    """Parse .res file to extract neq and skyline."""
    if not res_path.exists():
        return None

    try:
        with open(res_path, 'r') as f:
            for line in f:
                match = re.search(r'There are (\d+) equations.*skyline storage is (\d+)', line)
                if match:
                    return {
                        'equations_neq': int(match.group(1)),
                        'skyline_storage': int(match.group(2))
                    }
    except:
        pass
    return None

def generate_perfect_yaml_p51(case_dir, output_dir):
    """Generate perfect YAML for a p51 case."""
    case_name = case_dir.name
    program = 'p51'

    # Parse input data
    dat_file = case_dir / f"{case_name}.dat"
    if not dat_file.exists():
        print(f"✗ {case_name}: .dat file not found")
        return None

    data = parse_dat_file_p51(dat_file)

    # Parse output data if available
    res_file = case_dir / f"{case_name}.res"
    res_summary = parse_res_file(res_file)

    # Build YAML content
    yaml_lines = []

    # Header
    yaml_lines.append(f"id: pfem5_ch05_{program}_{case_name}")
    yaml_lines.append(f'title: "PFEM Program 5.1 (p51) — Plane linear elasticity ({data["element"]} elements) — case {case_name}"')
    yaml_lines.append("")

    # Purpose
    yaml_lines.append("purpose: >")
    yaml_lines.append("  Plane (or axisymmetric) strain analysis of an elastic solid using right-angled triangles")
    yaml_lines.append("  (3/6/10/15-node) or rectangular quadrilaterals (4/8/9-node). This benchmark uses")
    yaml_lines.append(f"  {data['type_2d']} analysis with {data['nod']}-node {data['element']} elements on a structured grid.")
    yaml_lines.append("")

    # Authors/metadata
    yaml_lines.append("authors:")
    yaml_lines.append("  source:")
    yaml_lines.append('    book: "Programming the Finite Element Method"')
    yaml_lines.append('    edition: "5th"')
    yaml_lines.append("    chapter: 5")
    yaml_lines.append(f'    program: "{program}"')
    yaml_lines.append(f'    dataset: "{case_name}"')
    yaml_lines.append("  entry:")
    yaml_lines.append('    created_by: "Naeem"')
    yaml_lines.append('    created_on: "2026-01-09"')
    yaml_lines.append('    verified_platform: "Linux (gfortran)"')
    yaml_lines.append("")

    # Code
    yaml_lines.append("code:")
    yaml_lines.append('  language: "Fortran (F2003)"')
    yaml_lines.append(f'  source_file: "source/chap05/{program}.f03"')
    yaml_lines.append('  uses_modules: ["main", "geom"]')
    yaml_lines.append("  io_reads_from_unit10:")
    yaml_lines.append('    - {line: 27, stmt: "READ(10,*) type_2d, element, nod, dir, nxe, nye, nip, np_types"}')
    yaml_lines.append('    - {line: 36, stmt: "READ(10,*) prop"}')
    yaml_lines.append('    - {line: 39, stmt: "READ(10,*) x_coords, y_coords"}')
    yaml_lines.append('    - {line: 41, stmt: "READ(10,*) nr,(k,nf(:,k),i=1,nr)"}')
    yaml_lines.append('    - {line: 89, stmt: "READ(10,*) loaded_nodes,(k,loads(nf(:,k)),i=1,loaded_nodes)"}')
    yaml_lines.append('    - {line: 90, stmt: "READ(10,*) fixed_freedoms"}')
    yaml_lines.append('    - {line: 94, stmt: "READ(10,*)(node(i),sense(i),value(i),i=1,fixed_freedoms)"}')
    yaml_lines.append("")

    # FEM
    yaml_lines.append("fem:")
    yaml_lines.append("  dimension: 2")
    yaml_lines.append("  formulation:")
    yaml_lines.append('    code_supports: ["plane", "axisymmetric"]')
    yaml_lines.append(f'    this_case: "{data["type_2d"]}"')
    yaml_lines.append("  dof:")
    yaml_lines.append("    per_node: 2")
    yaml_lines.append('    names: ["x-disp", "y-disp"]')
    yaml_lines.append('    dof_indexing: {1: "x-disp", 2: "y-disp"}')
    yaml_lines.append("  element:")
    yaml_lines.append(f'    family: "{data["element"]}"')
    yaml_lines.append(f"    nodes_per_element: {data['nod']}")
    yaml_lines.append("    supported:")
    yaml_lines.append("      triangles_right_angled_nodes: [3, 6, 10, 15]")
    yaml_lines.append("      quads_rectangular_nodes: [4, 8, 9]")
    yaml_lines.append("")

    # Analysis
    yaml_lines.append("analysis:")
    yaml_lines.append('  physics: "linear elasticity"')
    yaml_lines.append('  type: "linear"')
    yaml_lines.append('  regime: "steady-state"')
    yaml_lines.append("")

    # Units
    yaml_lines.append("units:")
    yaml_lines.append('  system: "consistent"')
    yaml_lines.append("  notes: >")
    yaml_lines.append("    PFEM assumes consistent units. Pick a unit system and keep geometry,")
    yaml_lines.append("    E, and loads consistent.")
    yaml_lines.append("")

    # Tunable parameters
    yaml_lines.append("tunable_parameters:")
    yaml_lines.append("  - name: youngs_modulus_E")
    yaml_lines.append('    path: "inputs.record2.material.E.value"')
    yaml_lines.append('    type: "real"')
    yaml_lines.append('    unit_category: "stress"')
    yaml_lines.append('    notes: "Material stiffness. Very common sweep parameter."')
    yaml_lines.append("    suggested_range: [1.0e4, 1.0e9]")
    yaml_lines.append("")
    yaml_lines.append("  - name: poisson_ratio_nu")
    yaml_lines.append('    path: "inputs.record2.material.nu.value"')
    yaml_lines.append('    type: "real"')
    yaml_lines.append('    unit_category: "dimensionless"')
    yaml_lines.append('    notes: "Material parameter. Typically 0.0-0.49 for stability."')
    yaml_lines.append("    suggested_range: [0.0, 0.49]")
    yaml_lines.append("")

    if data['fixed_freedoms'] > 0:
        yaml_lines.append("  - name: prescribed_displacements_values")
        yaml_lines.append('    path: "inputs.record7.prescribed_displacements[*].value"')
        yaml_lines.append('    type: "real"')
        yaml_lines.append('    unit_category: "length"')
        yaml_lines.append('    notes: "Boundary displacements enforced via penalty method."')
        yaml_lines.append("")

    if data['loaded_nodes'] > 0:
        yaml_lines.append("  - name: nodal_loads")
        yaml_lines.append('    path: "inputs.record5.nodal_loads"')
        yaml_lines.append('    type: "struct"')
        yaml_lines.append('    unit_category: "force"')
        yaml_lines.append('    notes: "Applied nodal forces (Fx, Fy)."')
        yaml_lines.append("")

    # Input schema
    yaml_lines.append("input_schema:")
    yaml_lines.append('  file_type: ".dat"')
    yaml_lines.append("  reads_in_order:")
    yaml_lines.append("    - record: 1")
    yaml_lines.append('      fortran_read: "READ(10,*) type_2d, element, nod, dir, nxe, nye, nip, np_types"')
    yaml_lines.append("      fields:")
    yaml_lines.append('        - {name: type_2d, type: string, allowed: ["plane", "axisymmetric"]}')
    yaml_lines.append('        - {name: element, type: string, allowed: ["triangle", "quadrilateral"]}')
    yaml_lines.append("        - {name: nod, type: int}")
    yaml_lines.append("        - {name: dir, type: string}")
    yaml_lines.append("        - {name: nxe, type: int}")
    yaml_lines.append("        - {name: nye, type: int}")
    yaml_lines.append("        - {name: nip, type: int}")
    yaml_lines.append("        - {name: np_types, type: int}")
    yaml_lines.append("")
    yaml_lines.append("    - record: 2")
    yaml_lines.append('      fortran_read: "READ(10,*) prop"')
    yaml_lines.append("      fields:")
    yaml_lines.append("        - name: prop")
    yaml_lines.append('          type: "real_matrix"')
    yaml_lines.append('          shape: "(nprops=2, np_types)"')
    yaml_lines.append('          description: "[E, nu] per material type"')
    yaml_lines.append("")
    yaml_lines.append("    - record: 3")
    yaml_lines.append('      fortran_read: "READ(10,*) x_coords, y_coords"')
    yaml_lines.append("      fields:")
    yaml_lines.append('        - {name: x_coords, type: "real_array", shape: "(nxe+1)"}')
    yaml_lines.append('        - {name: y_coords, type: "real_array", shape: "(nye+1)"}')
    yaml_lines.append("")
    yaml_lines.append("    - record: 4")
    yaml_lines.append('      fortran_read: "READ(10,*) nr,(k,nf(:,k),i=1,nr)"')
    yaml_lines.append("      fields:")
    yaml_lines.append("        - {name: nr, type: int}")
    yaml_lines.append("        - name: bc_table")
    yaml_lines.append('          type: "table"')
    yaml_lines.append("          columns:")
    yaml_lines.append("            - {name: node, type: int}")
    yaml_lines.append("            - {name: nf_flag_dof1, type: int, allowed: [0, 1]}")
    yaml_lines.append("            - {name: nf_flag_dof2, type: int, allowed: [0, 1]}")
    yaml_lines.append('          notes: "Typically 0=fixed, 1=free before numbering."')
    yaml_lines.append("")
    yaml_lines.append("    - record: 5")
    yaml_lines.append('      fortran_read: "READ(10,*) loaded_nodes,(k,loads(nf(:,k)),i=1,loaded_nodes)"')
    yaml_lines.append("      fields:")
    yaml_lines.append("        - {name: loaded_nodes, type: int}")
    yaml_lines.append("        - name: nodal_loads")
    yaml_lines.append('          type: "table"')
    yaml_lines.append("          columns:")
    yaml_lines.append("            - {name: node, type: int}")
    yaml_lines.append("            - {name: load_dof1, type: real}")
    yaml_lines.append("            - {name: load_dof2, type: real}")
    yaml_lines.append("")
    yaml_lines.append("    - record: 6")
    yaml_lines.append('      fortran_read: "READ(10,*) fixed_freedoms"')
    yaml_lines.append("      fields:")
    yaml_lines.append("        - {name: fixed_freedoms, type: int}")
    yaml_lines.append("")
    yaml_lines.append("    - record: 7")
    yaml_lines.append('      fortran_read: "READ(10,*)(node(i),sense(i),value(i),i=1,fixed_freedoms)"')
    yaml_lines.append('      condition: "only if fixed_freedoms > 0"')
    yaml_lines.append("      fields:")
    yaml_lines.append("        - name: prescribed_displacements")
    yaml_lines.append('          type: "table"')
    yaml_lines.append("          columns:")
    yaml_lines.append("            - {name: node, type: int}")
    yaml_lines.append("            - {name: sense_dof, type: int, allowed: [1, 2]}")
    yaml_lines.append("            - {name: value, type: real}")
    yaml_lines.append("")

    # Actual inputs for this dataset
    yaml_lines.append("inputs:")
    yaml_lines.append('  working_directory: "executable/chap05"')
    yaml_lines.append(f'  basename: "{case_name}"')
    yaml_lines.append(f'  dat_file: "executable/chap05/{case_name}.dat"')
    yaml_lines.append("")
    yaml_lines.append("  record1:")
    yaml_lines.append(f'    type_2d: "{data["type_2d"]}"')
    yaml_lines.append(f'    element: "{data["element"]}"')
    yaml_lines.append(f'    nod: {data["nod"]}')
    yaml_lines.append(f'    dir: "{data["dir"]}"')
    yaml_lines.append(f'    nxe: {data["nxe"]}')
    yaml_lines.append(f'    nye: {data["nye"]}')
    yaml_lines.append(f'    nip: {data["nip"]}')
    yaml_lines.append(f'    np_types: {data["np_types"]}')
    yaml_lines.append("")
    yaml_lines.append("  record2:")
    yaml_lines.append("    material:")
    yaml_lines.append(f'      E: {{value: {data["E"]}, unit_category: "stress"}}')
    yaml_lines.append(f'      nu: {{value: {data["nu"]}, unit_category: "dimensionless"}}')
    yaml_lines.append("")
    yaml_lines.append("  record3:")
    yaml_lines.append(f'    x_coords: {{values: {data["x_coords"]}, unit_category: "length"}}')
    yaml_lines.append(f'    y_coords: {{values: {data["y_coords"]}, unit_category: "length"}}')
    yaml_lines.append("")
    yaml_lines.append("  record4:")
    yaml_lines.append(f'    nr: {data["nr"]}')
    yaml_lines.append("    bc_table:")
    for bc in data['bc_table']:
        yaml_lines.append(f'      - {{node: {bc["node"]}, nf_flag_dof1: {bc["dof1"]}, nf_flag_dof2: {bc["dof2"]}}}')
    yaml_lines.append("")
    yaml_lines.append("  record5:")
    yaml_lines.append(f'    loaded_nodes: {data["loaded_nodes"]}')
    if data['nodal_loads']:
        yaml_lines.append("    nodal_loads:")
        for load in data['nodal_loads']:
            yaml_lines.append(f'      - {{node: {load["node"]}, fx: {load["fx"]}, fy: {load["fy"]}}}')
    else:
        yaml_lines.append("    nodal_loads: []")
    yaml_lines.append("")
    yaml_lines.append("  record6:")
    yaml_lines.append(f'    fixed_freedoms: {data["fixed_freedoms"]}')
    yaml_lines.append("")
    if data['prescribed_displacements']:
        yaml_lines.append("  record7:")
        yaml_lines.append("    prescribed_displacements:")
        for pd in data['prescribed_displacements']:
            yaml_lines.append(f'      - {{node: {pd["node"]}, sense_dof: {pd["sense"]}, value: {pd["value"]}}}')
        yaml_lines.append("")

    # Outputs
    yaml_lines.append("outputs:")
    yaml_lines.append('  output_directory: "executable/chap05"')
    yaml_lines.append("  files_created_confirmed:")
    yaml_lines.append(f'    - "{case_name}.res"')
    yaml_lines.append(f'    - "{case_name}.msh"')
    yaml_lines.append(f'    - "{case_name}.vec"')
    yaml_lines.append(f'    - "{case_name}.dis"')
    if res_summary:
        yaml_lines.append("  res_summary:")
        yaml_lines.append(f"    equations_neq: {res_summary['equations_neq']}")
        yaml_lines.append(f"    skyline_storage: {res_summary['skyline_storage']}")
    yaml_lines.append("")

    # How to run
    yaml_lines.append("how_to_run:")
    yaml_lines.append("  linux:")
    yaml_lines.append('    - "cd ~/Downloads/pfem5/5th_ed/executable/chap05"')
    yaml_lines.append(f'    - \'printf "{case_name}\\n" | ~/Downloads/pfem5/5th_ed/build/bin/p51\'')
    yaml_lines.append("  matlab:")
    yaml_lines.append("    - \"pfem_root = '~/Downloads/pfem5/5th_ed';\"")
    yaml_lines.append(f"    - \"[status, outputs] = pfem_runner(pfem_root, 'chap05', 'p51', '{case_name}');\"")
    yaml_lines.append("")
    yaml_lines.append("notes:")
    yaml_lines.append("  - \"Program prompts for the base name of the .dat file (do not type the .dat extension).\"")
    yaml_lines.append("  - \"This YAML follows the 'perfect YAML' specification with complete input schema and tunable parameters.\"")

    # Write YAML
    output_file = output_dir / f"{case_name}.yaml"
    with open(output_file, 'w') as f:
        f.write('\n'.join(yaml_lines))

    return output_file

def main():
    repo_root = Path(__file__).parent.parent
    bundles_dir = repo_root / 'pfem_yaml_bundle' / 'cases' / 'chap05'
    output_dir = repo_root / 'benchmarks' / 'pfem5' / 'chap05'

    output_dir.mkdir(parents=True, exist_ok=True)

    # Get all p51* cases
    cases = sorted([d for d in bundles_dir.iterdir() if d.is_dir() and d.name.startswith('p51')])

    print(f"Generating perfect YAMLs for {len(cases)} p51 cases...\n")

    generated = []
    for case_dir in cases:
        try:
            output_file = generate_perfect_yaml_p51(case_dir, output_dir)
            if output_file:
                print(f"✓ Generated: {output_file.name}")
                generated.append(output_file)
        except Exception as e:
            print(f"✗ Failed to generate {case_dir.name}: {e}")
            import traceback
            traceback.print_exc()

    print(f"\n{'='*60}")
    print(f"Generated {len(generated)} perfect YAML files for p51 cases")

if __name__ == '__main__':
    main()
