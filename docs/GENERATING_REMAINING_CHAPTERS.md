# Guide: Generating YAMLs for Remaining Chapters

## Current Status

✅ **Chapter 5 Complete** - 13 benchmark YAMLs created and verified
⏳ **Chapters 4, 6-11** - 72 cases ready (bundles collected)

---

## Bundle Collection Complete

All case bundles have been collected and are ready for YAML generation:

| Chapter | Cases | Programs | Topics |
|---------|-------|----------|--------|
| 4 | 13 | p41-p47 | 1D rod/beam elements |
| 6 | 15 | p61-p69 | Material nonlinearity |
| 7 | 8 | p71-p75 | Steady state flow |
| 8 | 16 | p81-p89 | Transient problems |
| 9 | 7 | p91-p96 | Coupled problems |
| 10 | 5 | p101-p104 | Eigenvalue analysis |
| 11 | 8 | p111-p118 | Parallel processing |

Each bundle contains:
- Program source code (.f03)
- Dataset file (.dat)
- READ(10) statement extraction
- Output files (.res, .msh, etc.)
- Run information

---

## YAML Structure

Follow the Chapter 5 templates in `benchmarks/pfem5/chap05/`. Each YAML contains:

### Required Sections

1. **Metadata**: id, title, purpose
2. **Authors**: source book info + created_by
3. **Code**: source file, modules, READ statements with line numbers
4. **FEM**: dimension, formulation, DOF details, element info
5. **Analysis**: physics type, linear/nonlinear, steady/transient
6. **Units**: system and notes
7. **Tunable Parameters**: for parametric studies (paths, ranges)
8. **Input Schema**: complete READ(10) mapping
9. **Inputs**: parsed values from .dat file
10. **Outputs**: expected files + .res summary (neq, skyline)
11. **How to Run**: Linux and MATLAB commands
12. **Notes**: additional information

---

## Creating YAMLs

### Method 1: Use Existing Templates

1. Choose a similar template from Chapter 5:
   - For 1D problems (Ch 4): use p51_1.yaml structure
   - For nonlinear (Ch 6): use p52.yaml or p53.yaml
   - For 3D (Ch 6-8): use p53.yaml or p56.yaml
   - For transient (Ch 8): add time-stepping parameters
   - For coupled (Ch 9): use multi-DOF structure from p52.yaml

2. Update the following:
   - id, title, purpose
   - chapter number and program name
   - READ statements (from bundle's _READ10_lines.txt)
   - FEM details (dimension, elements, DOF)
   - Input values (parse from .dat file)
   - Output summary (from .res file if exists)

3. Verify:
   ```bash
   python3 scripts/verify_yamls.py
   ```

### Method 2: Generate from Scripts

The repository includes a YAML generator script that can process bundles:

```bash
cd ~/projects/fem-benchmarks

# For specific chapter
python3 scripts/generate_yaml_from_bundles.py --chapter chap04

# Verify results
python3 scripts/verify_yamls.py
```

---

## Program-Specific Notes

### Chapter 4 (1D Elements)
- Single DOF per node (axial displacement)
- Simpler input schemas
- Rod and beam elements

### Chapter 6 (Material Nonlinearity)
- Mark as `analysis.type: "nonlinear"`
- Include yield criterion parameters
- Iteration tolerance and load increments are tunable

### Chapter 7 (Flow Problems)
- Single DOF (temperature or potential)
- `analysis.physics: "steady-state flow"`
- Different from structural problems

### Chapter 8 (Transient)
- `analysis.regime: "transient"`
- Time-stepping parameters (dt, nstep, theta)
- Initial conditions in input schema

### Chapter 9 (Coupled Problems)
- Multiple DOF types (e.g., u, v, p for consolidation)
- More complex input schemas
- Coupling parameters

### Chapter 10 (Eigenvalue)
- `analysis.type: "eigenvalue"`
- Outputs include eigenvalues and mode shapes
- Mass and stiffness matrices

### Chapter 11 (Parallel)
- Similar to earlier programs
- Note MPI requirements in how_to_run
- May have domain decomposition parameters

---

## Verification Steps

Before committing YAMLs:

1. **Syntax Check**:
   ```bash
   python3 scripts/verify_yamls.py
   ```

2. **Check Required Sections**: Ensure all 12 sections present

3. **Verify Tunable Parameters**: At least 2-3 per case

4. **Input Schema Completeness**: All READ statements documented

5. **Parsed Values**: All records from .dat file included

6. **Output Files**: List matches actual outputs

---

## Committing Work

```bash
# After creating/verifying YAMLs for a chapter
cd ~/projects/fem-benchmarks

python3 scripts/verify_yamls.py

scripts/git_publish.sh "Add Chapter X benchmark YAMLs"
```

---

## Reference Files

- **Templates**: `benchmarks/pfem5/chap05/*.yaml`
- **Bundles**: `pfem_yaml_bundle/cases/chapXX/`
- **Verification**: `scripts/verify_yamls.py`
- **Technical Spec**: `docs/HANDOVER.md`

---

**Author**: Naeem
**Date**: 2026-01-09
**Status**: Chapter 5 complete, 72 cases remaining
