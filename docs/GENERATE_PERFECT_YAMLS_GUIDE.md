# Complete Guide: Generating Perfect YAMLs for All PFEM Chapters

## ✅ Status: Chapter 5 Complete!

**Chapter 5** now has **13 perfect YAMLs** following the complete HANDOVER.md specification.
All YAMLs include:
- ✓ Complete metadata (authors, verification info)
- ✓ Full code documentation (READ statements with line numbers)
- ✓ Complete input schema (record-by-record mapping)
- ✓ Parsed actual values from .dat files
- ✓ Tunable parameters with MATLAB paths
- ✓ Output summaries (.res parsing)
- ✓ Complete how_to_run instructions

---

## 📋 Remaining Chapters (72 cases)

| Chapter | Cases | Programs | Status |
|---------|-------|----------|--------|
| 4 | 13 | p41-p47 | ⏳ Bundles ready |
| 6 | 15 | p61-p69 | ⏳ Bundles ready |
| 7 | 8 | p71-p75 | ⏳ Bundles ready |
| 8 | 16 | p81-p89 | ⏳ Bundles ready |
| 9 | 7 | p91-p96 | ⏳ Bundles ready |
| 10 | 5 | p101-p104 | ⏳ Bundles ready |
| 11 | 8 | p111-p118 | ⏳ Bundles ready |
| **Total** | **72** | | **Ready to generate** |

---

## 🚀 Method 1: AI-Powered Generation (Recommended)

This is the **fastest and most reliable** method for generating perfect YAMLs.

### Prerequisites
```bash
# Install Python package
pip install anthropic

# Set API key
export ANTHROPIC_API_KEY="your-claude-api-key-here"
```

### Option A: Generate All Remaining Chapters at Once

```bash
cd ~/projects/fem-benchmarks

# Generate perfect YAMLs for all chapters except chap05
for chapter in chap04 chap06 chap07 chap08 chap09 chap10 chap11; do
    echo "Generating $chapter..."
    python3 scripts/generate_yaml_from_bundles.py --chapter $chapter
done

# Verify all YAMLs
python3 scripts/verify_yamls.py

# Commit
scripts/git_publish.sh "Add perfect YAMLs for chapters 4,6-11 (72 cases)"
```

### Option B: Generate One Chapter at a Time

```bash
cd ~/projects/fem-benchmarks

# Chapter 4 (1D problems)
python3 scripts/generate_yaml_from_bundles.py --chapter chap04
python3 scripts/verify_yamls.py
scripts/git_publish.sh "Add perfect YAMLs for Chapter 4 (13 cases)"

# Chapter 6 (Material nonlinearity)
python3 scripts/generate_yaml_from_bundles.py --chapter chap06
python3 scripts/verify_yamls.py
scripts/git_publish.sh "Add perfect YAMLs for Chapter 6 (15 cases)"

# ... and so on for each chapter
```

### Cost Estimate
- **72 API calls** (one per case)
- Estimated cost: **$4-8 USD** (depending on Claude API pricing)
- Time: **~15-20 minutes** for all chapters

---

## 🔧 Method 2: Using Claude Code Agent (What We Used for Chapter 5)

If you're working within Claude Code (like we just did), you can use the Task tool:

### Example Command

```python
# Use the Task tool with general-purpose agent
Task(
    subagent_type="general-purpose",
    description="Generate perfect YAMLs for Chapter X",
    prompt="""
    Generate perfect YAML files for all Chapter X PFEM cases following the specification.

    Repository: ~/projects/fem-benchmarks
    Bundles: pfem_yaml_bundle/cases/chapXX/
    Output: benchmarks/pfem5/chapXX/
    Template: benchmarks/pfem5/chap05/*.yaml (use any as reference)

    For each case:
    1. Read bundle contents (.dat, .f03, READ files, .res)
    2. Generate perfect YAML with ALL required sections
    3. Parse .dat to extract actual input values
    4. Extract output summary from .res
    5. Save to benchmarks/pfem5/chapXX/{case}.yaml
    """
)
```

This is exactly what we used for Chapter 5 and it worked perfectly!

---

## 📖 Method 3: Template-Based Generation (Manual/Semi-Automated)

For those who want more control or don't have API access.

### Step 1: Choose a Template
Use any Chapter 5 YAML as your template:
```bash
# Good templates:
- p51_1.yaml - Simple plane strain (T3 triangles)
- p51_3.yaml - Plane strain (Q4 quads)
- p52.yaml - Non-axisymmetric (2.5D, 3 DOF/node)
- p56.yaml - 3D elasticity (hexahedra)
```

### Step 2: Understand the Program
For each new program (e.g., p61 from Chapter 6):

1. Read the bundle:
```bash
cd ~/projects/fem-benchmarks/pfem_yaml_bundle/cases/chap06/p61
ls -la
# You'll see:
# - p61.f03 (source code)
# - p61.dat (dataset)
# - p61_READ10_lines.txt (READ statements)
# - p61_READ10_context.txt (code context)
# - p61.res (output, if exists)
```

2. Extract key information:
```bash
# Get READ statements with line numbers
cat p61_READ10_lines.txt

# Understand code context
head -100 p61.f03
cat p61_READ10_context.txt

# View dataset structure
cat p61.dat
```

3. Parse the .dat file manually to understand each record

4. Copy and adapt a similar template YAML

### Step 3: Fill in the YAML Sections

#### Required Sections (in order):
1. **id, title, purpose** - Brief description
2. **authors** - source book info + entry metadata
3. **code** - language, source_file, modules, io_reads_from_unit10
4. **fem** - dimension, formulation, dof, element details
5. **analysis** - physics, type, regime
6. **units** - system and notes
7. **tunable_parameters** - list with paths, types, ranges
8. **input_schema** - complete READ record mapping
9. **inputs** - parsed actual values from .dat
10. **outputs** - files + res_summary (if .res exists)
11. **how_to_run** - linux and matlab commands
12. **notes** - any additional information

### Step 4: Verify and Commit
```bash
python3 scripts/verify_yamls.py
scripts/git_publish.sh "Add perfect YAMLs for Chapter X"
```

---

## 🎯 Program-Specific Notes

### Chapter 4 (1D Problems)
- **p41**: 1D rod elements
- **p42-p47**: Various 1D beam/rod problems
- Simpler than 2D/3D (fewer DOF, simpler elements)

### Chapter 6 (Material Nonlinearity)
- **p61-p69**: Elastic-plastic problems
- Need special attention to:
  - Yield criterion parameters
  - Iteration tolerance settings
  - Load increment parameters
- These are **nonlinear** - mark as `analysis.type: "nonlinear"`

### Chapter 7 (Steady State Flow)
- **p71-p75**: Heat/flow problems
- Different physics: `analysis.physics: "steady-state flow"`
- Single DOF per node (temperature or potential)

### Chapter 8 (Transient Problems)
- **p81-p89**: Time-dependent problems
- Mark as `analysis.regime: "transient"`
- Need time-stepping parameters:
  - dt (time step)
  - nstep (number of steps)
  - theta (time integration parameter)

### Chapter 9 (Coupled Problems)
- **p91-p96**: Consolidation, coupled flow-deformation
- Multiple DOF types per node
- More complex input schemas

### Chapter 10 (Eigenvalue Problems)
- **p101-p104**: Modal analysis, buckling
- Different analysis type: `analysis.type: "eigenvalue"`
- Output includes eigenvalues and eigenvectors

### Chapter 11 (Parallel Processing)
- **p111-p118**: MPI-parallelized versions
- Similar to earlier programs but with parallel execution
- May need special notes about MPI requirements

---

## 📚 Reference: Perfect YAML Structure

See any Chapter 5 YAML for the complete structure. Key points:

### Minimal Perfect YAML (skeleton):
```yaml
id: pfem5_chXX_pYY_caseZZ
title: "PFEM Program X.Y (pYY) — Description — case caseZZ"

purpose: >
  Detailed description of what this case does...

authors:
  source:
    book: "Programming the Finite Element Method"
    edition: "5th"
    chapter: X
    program: "pYY"
    dataset: "caseZZ"
  entry:
    created_by: "Automated YAML Generator"
    created_on: "2026-01-09"
    verified_platform: "Linux (gfortran)"

code:
  language: "Fortran (F2003)"
  source_file: "source/chapXX/pYY.f03"
  uses_modules: ["main", "geom"]
  io_reads_from_unit10:
    - {line: NN, stmt: "READ(10,*) ..."}

fem:
  dimension: N
  formulation: {...}
  dof: {...}
  element: {...}

analysis:
  physics: "..."
  type: "linear|nonlinear|eigenvalue"
  regime: "steady-state|transient"

units:
  system: "consistent"
  notes: "..."

tunable_parameters:
  - name: parameter_name
    path: "inputs.recordN.field.subfield"
    type: "real|int"
    unit_category: "..."
    notes: "..."
    suggested_range: [min, max]

input_schema:
  file_type: ".dat"
  reads_in_order:
    - record: 1
      fortran_read: "READ(10,*) ..."
      fields: [...]

inputs:
  working_directory: "executable/chapXX"
  basename: "caseZZ"
  dat_file: "executable/chapXX/caseZZ.dat"
  record1: {...}
  record2: {...}
  # ... all records

outputs:
  output_directory: "executable/chapXX"
  files_created_confirmed: [...]
  res_summary:
    equations_neq: NN
    skyline_storage: MM

how_to_run:
  linux:
    - "cd ~/Downloads/pfem5/5th_ed/executable/chapXX"
    - 'printf "caseZZ\n" | ~/Downloads/pfem5/5th_ed/build/bin/pYY'
  matlab:
    - "pfem_root = '~/Downloads/pfem5/5th_ed';"
    - "[status, outputs] = pfem_runner(pfem_root, 'chapXX', 'pYY', 'caseZZ');"

notes:
  - "..."
```

---

## ✅ Validation Checklist

Before committing, ensure each YAML has:

- [ ] Unique ID (pfem5_chXX_pYY_caseZZ format)
- [ ] Complete authors section with source and entry
- [ ] All READ(10) statements with correct line numbers
- [ ] Correct FEM dimension (1, 2, 2.5D, or 3)
- [ ] Accurate DOF count and names
- [ ] At least 2-3 tunable_parameters
- [ ] Complete input_schema matching READ order
- [ ] Parsed inputs for ALL records from .dat
- [ ] res_summary if .res file exists
- [ ] Both linux and matlab how_to_run examples
- [ ] Passes verify_yamls.py validation

---

## 🎉 Expected Final Result

After completing all chapters, you will have:

- **85 perfect YAMLs** (13 per Chapter 5, 72 for others)
- Complete benchmark catalogue for PFEM 5th edition
- Full parametric study capability from MATLAB
- Comprehensive documentation of all programs
- Ready for advanced FEM research and education

**Estimated total cost:** ~$10-15 USD (using Claude API)
**Estimated total time:** 1-2 hours (mostly automated)

---

## 📞 Need Help?

Refer to:
- `docs/HANDOVER.md` - Complete technical specification
- `docs/YAML_STATUS.md` - Current status and recommendations
- `benchmarks/pfem5/chap05/*.yaml` - Working examples
- `scripts/generate_yaml_from_bundles.py` - Main AI generator
- `scripts/verify_yamls.py` - Validation tool

---

**Generated:** 2026-01-09
**Status:** Chapter 5 complete, 72 cases remaining
**Repository:** https://github.com/NZ5253/fem-benchmarks
