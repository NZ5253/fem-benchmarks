# HANDOVER — PFEM (5th ed.) Benchmark Repository

This document is a full handover of the PFEM benchmark-catalogue work done so far:
- what the original task is
- what has been achieved (including compilation/run)
- where files live on disk
- how to generate YAML for *every dataset in the book*
- how to verify YAMLs
- how to commit/push to GitHub
- how MATLAB will run and parameterize the cases later

> Target machine/environment used in this work: Linux Mint (gfortran).
> Repo: `~/projects/fem-benchmarks`
> PFEM source root: `~/Downloads/pfem5/5th_ed`


---

## 1) The actual project goal (from supervisor)

### Part A — Catalogue examples (benchmark cards)
For each example/dataset in the PFEM references, create a small, standardized record that contains:
- name + purpose of the example
- the associated Fortran code (`pXX.f03`)
- element type (1D/2D/3D, linear/quadratic, triangle/quad, etc.)
- analysis type (linear/nonlinear, transient/steady-state)
- inputs required (and which ones are *tunable*)
- expected outputs (files + key values if possible)

We implement this as **one YAML file per dataset**.

### Part B — Execute Fortran examples from MATLAB
Explore reproducible execution from MATLAB. The simplest and most robust method is:
- compile the Fortran solver once
- from MATLAB, call it using `system()` and manage inputs/outputs via files

We will later add parameter sweeps by:
- writing new `.dat` files from MATLAB
- running the solver
- parsing `.res` outputs


---

## 2) What exists now (state of work)

### 2.1 Git repository
Local repo:
- `~/projects/fem-benchmarks`

Remote repo:
- `https://github.com/NZ5253/fem-benchmarks.git`

You successfully pushed to GitHub (remote is working). The missing step earlier was simply staging files with `git add`.

### 2.2 PFEM code and datasets on disk
PFEM root directory:
- `~/Downloads/pfem5/5th_ed`

Important subfolders:
- `source/`
  Fortran source code
  - `source/library/`  (shared modules used by all programs)
  - `source/chap04 .. chap11` (chapter programs: `p51.f03`, etc.)

- `executable/`
  Example datasets (`*.dat`) and where outputs get written
  - `executable/chap05` contains datasets like `p51_3.dat` etc.

### 2.3 Successful compilation + run (validated)
We successfully compiled and ran:
- **Chapter 5** program **p51** with dataset **p51_3**

Working directory where input `.dat` lives and outputs were produced:
- `~/Downloads/pfem5/5th_ed/executable/chap05`

Confirmed output files created by the run:
- `p51_3.res`
- `p51_3.msh`
- `p51_3.vec`
- `p51_3.dis`

The `.res` file contains:
- number of equations + skyline storage
- nodal displacements
- stresses at integration points

### 2.4 Bundles ("evidence packs") exist
A collector script created per-case folders that contain everything needed to generate a "perfect" YAML:
- the program source (`pXX.f03`)
- the dataset (`*.dat`)
- output files (`*.res`, etc., if run)
- a list of all `READ(10,*)` statements (`*_READ10_lines.txt`)
- context around each `READ(10,*)` (`*_READ10_context.txt`)
- run info (`run_info.txt`)
- a few library files (`main_int.f03`, `geom_int.f03`, `formnf.f03`) to interpret conventions

Example bundle folder (confirmed):
- `pfem_yaml_bundle/cases/chap05/p51_3/`


---

## 3) Key concept: why "READ(10,*)" matters (records/schema)

PFEM programs read `.dat` inputs using Fortran statements like:

```fortran
READ(10,*) type_2d, element, nod, dir, nxe, nye, nip, np_types
```

So the dataset file is not free-form; it's a strict sequence of values that must match the program's READ(10,*) order.

We label each READ(10,*) in order as:
- record 1 = first READ statement
- record 2 = second READ statement
- ...

This lets us define:
- an input schema (records with types/meanings)
- parsed inputs for each dataset
- a list of tunable parameters (the knobs MATLAB will later change)

Example: **p51 (Program 5.1)** input reads extracted

From `p51_READ10_lines.txt`:
- record 1: setup + mesh settings
- record 2: material properties prop (E, nu)
- record 3: coordinate arrays
- record 4: boundary flags (nf)
- record 5: nodal loads
- record 6–7: prescribed displacement constraints (penalty method)

That mapping is why we can distinguish "changeable knobs" vs structural fields.


---

## 4) Paths used everywhere (standard variables)

Use these in all scripts/commands:
```bash
PFEM_ROOT=~/Downloads/pfem5/5th_ed
REPO=~/projects/fem-benchmarks
```

Inside PFEM:
- Sources: `$PFEM_ROOT/source`
- Datasets: `$PFEM_ROOT/executable`
- Build artifacts (created by our build script): `$PFEM_ROOT/build`

Inside repo:
- Bundles: `$REPO/pfem_yaml_bundle/cases/...`
- YAMLs: `$REPO/benchmarks/pfem5/chapXX/<dataset>.yaml`
- Scripts: `$REPO/scripts/...`
- Docs: `$REPO/docs/...`
- MATLAB: `$REPO/matlab/...`


---

## 5) Scripts created/used and what they do

### 5.1 scripts/pfem_build_and_run.sh

**Purpose:**
- build PFEM library (modules + archive)
- compile a specific chapter program (e.g., p51)
- run a specific dataset (e.g., p51_3) by piping the basename into the program prompt
- print output files created

This script exists because the naive compile attempt failed with:
```
Fatal Error: Cannot open module file 'main.mod'
```

**Fix:**
- modules live in `source/library/main/main_int.f03` and `source/library/geom/geom_int.f03`
- Fortran module compilation order + .mod output folder must be controlled
- the script compiles modules first and uses:
  - `-J <mod_dir>` to place .mod files
  - `-I <mod_dir>` so programs can find them during compilation
  - archive static library with `ar rcs`

**Example run (rebuild everything):**
```bash
scripts/pfem_build_and_run.sh ~/Downloads/pfem5/5th_ed chap05 p51 p51_3 --rebuild
```

Outputs appear in:
```
$PFEM_ROOT/executable/chap05
```

### 5.2 scripts/pfem_collect_all.sh

**Purpose:**
- iterate through PFEM dataset folders
- for each .dat, infer the program name (e.g., `p51_3.dat` -> `p51`)
- copy into a per-case bundle folder:
  - program source
  - dataset .dat
  - outputs (if present)
  - READ(10) mapping files + context
  - run environment info
- optionally run each dataset first so outputs exist
- produce .tar.gz bundle archives

**Examples:**

Collect chapter 5 (no runs):
```bash
scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --chap chap05
```

Collect all chapters + run cases first:
```bash
scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --all-chaps --run --rebuild-first
```

**Result:**
- `pfem_yaml_bundle/cases/...` folders
- `pfem_yaml_bundle/tars/...` archives

### 5.3 scripts/generate_yaml_from_bundles.py

**Purpose:**
- Scan all bundle folders
- For each case, extract information and generate YAML
- Save YAMLs to `benchmarks/pfem5/<chapter>/<case>.yaml`

**Requirements:**
- Python 3
- `anthropic` package: `# pip install anthropic (optional for advanced generation)`
- API key: set `ANTHROPIC_API_KEY` environment variable

**Examples:**

Generate YAMLs for all cases:
```bash
python3 scripts/generate_yaml_from_bundles.py
```

Generate for specific chapter:
```bash
python3 scripts/generate_yaml_from_bundles.py --chapter chap05
```

Dry run (see what would be done):
```bash
python3 scripts/generate_yaml_from_bundles.py --dry-run
```

### 5.4 scripts/verify_yamls.py

**Purpose:**
- Verify that all YAML files are valid
- Check required keys exist
- Ensure IDs are unique
- Validate basic structure

**Requirements:**
- Python 3
- `pyyaml` package: `pip install pyyaml`

**Usage:**
```bash
python3 scripts/verify_yamls.py
```

### 5.5 scripts/git_publish.sh

**Purpose:**
- Stage changes in benchmarks/, scripts/, docs/, matlab/
- Commit with provided message
- Push to remote

**Usage:**
```bash
scripts/git_publish.sh "Add PFEM benchmark YAMLs for all chapters"
```


---

## 6) Output locations (common confusion)

PFEM programs write output files to the **current working directory**.

For example, when running p51 with dataset p51_3, we ran from:
```bash
cd ~/Downloads/pfem5/5th_ed/executable/chap05
printf "p51_3\n" | ~/Downloads/pfem5/5th_ed/build/bin/p51
```

So outputs were created in:
```
~/Downloads/pfem5/5th_ed/executable/chap05/
```

NOT in `build/bin/` and not in the source folder.


---

## 7) YAML generation for every dataset (automation plan)

### 7.1 What "perfect YAML" means here

A "perfect YAML" should contain:

**Identification + description:**
- id, title, purpose
- source: book/edition/chapter/program/dataset

**Code mapping:**
- source_file (`source/chapXX/pYY.f03`)
- used modules

**FEM + analysis classification:**
- dimension, element type/nodes, dof, physics, linear/nonlinear, steady/transient

**Input schema and parsed inputs:**
- record-by-record mapping derived from READ(10,*)
- the parsed values for this dataset

**Tunable knobs (important for MATLAB):**
- list of "paths" to the changeable parameters (E, nu, loads, prescribed displacements, etc.)

**Outputs:**
- expected files
- parse .res to record neq + skyline storage if present

**How to run:**
- linux commands
- MATLAB system() call call example

### 7.2 How YAML generation is done (Script-based)

We generate YAMLs using scripts by feeding it the bundle contents:
- program header and key parts of `pXX.f03`
- `*_READ10_lines.txt`
- `*_READ10_context.txt`
- dataset `.dat`
- `.res` head if exists

The script outputs a single YAML file per dataset.

**IMPORTANT:** keep YAML generation scripts and outputs in the repo, but avoid committing PFEM source/datasets to a public repo (see licensing section).


---

## 8) Verification of YAMLs (script-based)

We verify that:
- YAML parses correctly
- required top-level keys exist
- IDs are unique
- minimal structure is valid

This is done by `scripts/verify_yamls.py` (PyYAML required).


---

## 9) Git automation (add/commit/push)

Git flow for generated YAMLs:
```bash
git add benchmarks/pfem5/...
git commit -m "..."
git push
```

We use a helper script `scripts/git_publish.sh` to ensure repeatable publishing.


---

## 10) MATLAB roadmap (how the MATLAB part works exactly)

We use MATLAB as a run manager + parameter generator. The simplest robust approach:

**Phase 1 — Build once**

Compile PFEM binary once (already done by scripts).
Example binary path:
```
~/Downloads/pfem5/5th_ed/build/bin/p51
```

**Phase 2 — Treat .dat as a structured config**

For each program, MATLAB has a serializer that writes the .dat format in the exact READ order.

That READ order is documented in the YAML input schema.

**Phase 3 — Run from MATLAB using system()**

MATLAB runs:
```bash
cd <run_folder>
printf "<basename>\n" | <binary>
```

Example:
```matlab
system('bash -lc "cd ~/Downloads/pfem5/5th_ed/executable/chap05 && printf ''p51_3\n'' | ~/Downloads/pfem5/5th_ed/build/bin/p51"');
```

**Phase 4 — Parse results**

MATLAB parses `.res` to extract:
- nodal displacements
- stresses
- any other reported quantities

**Phase 5 — Parameter sweeps**

MATLAB changes only `tunable_parameters` (from YAML), writes new .dat, runs again, and stores outputs in per-run folders.

This is how the deterministic textbook datasets become a benchmark suite for experimentation.


---

## 11) Licensing / what to store in Git (IMPORTANT)

PFEM sources and datasets may not be redistributable under a public license, even if downloadable.

**Recommended safe defaults:**

**Commit:**
- scripts you wrote
- YAML metadata you generated (benchmark catalogue)
- docs + MATLAB scripts

**Do NOT commit:**
- PFEM source code
- PFEM datasets
- raw bundle packs

**Add to .gitignore:**
```
pfem_yaml_bundle/
runs/
**/*.exe
**/*.o
**/*.a
**/*.mod
```

If the repo is private and redistribution is permitted in your context, adjust accordingly.


---

## 12) End-to-end "one shot" runbook (do this to regenerate everything)

### Step A — Collect bundles for all datasets (and run to ensure outputs)
```bash
cd ~/projects/fem-benchmarks
scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --all-chaps --run --rebuild-first
```

### Step B — Generate YAMLs from all bundles (LLM)

Run your LLM YAML generator script:
```bash
# Set your API key
export ANTHROPIC_API_KEY="your-api-key-here"

# Generate YAMLs for all cases
python3 scripts/generate_yaml_from_bundles.py
```

The script will:
- iterate `pfem_yaml_bundle/cases/**/**`
- for each case, process program and data files
- write YAML into `benchmarks/pfem5/<chapXX>/<case>.yaml`

### Step C — Verify YAMLs
```bash
cd ~/projects/fem-benchmarks
python3 scripts/verify_yamls.py
```

### Step D — Publish (commit + push)
```bash
cd ~/projects/fem-benchmarks
scripts/git_publish.sh "Add/update generated PFEM benchmark YAML catalogue"
```


---

## 13) Reference: p51_3 validated outputs (example ground truth)

**Bundle folder:**
```
pfem_yaml_bundle/cases/chap05/p51_3
```

This folder contains:
- `p51.f03` (program source)
- `p51_3.dat` (dataset)
- `p51_3.res` (output)
- `p51_READ10_lines.txt` (all input reads)
- `p51_READ10_context.txt` (code context around reads)

The `.res` head shows:
- "There are 12 equations and the skyline storage is 58"
- displacement table labeled x-disp / y-disp
- stresses table for elements

This is used as the template example for the rest of the book datasets.


---

## 14) Troubleshooting notes (from what happened in this chat)

### "Cannot open module file main.mod"

**Cause:**
- program uses `USE main` and `USE geom` modules
- modules must be compiled before the program
- .mod files must be placed in a known folder and included with `-I`

**Fix:**
- compile module interface files first:
  - `source/library/main/main_int.f03`
  - `source/library/geom/geom_int.f03`
- use `-J <build/mod>` and `-I <build/mod>`
- archive objects to `libpfem.a` and link programs against it

### Where did outputs go?

Outputs go into the directory where you ran the program (working directory).
PFEM usually expects you to run inside `executable/chapXX`.

### Why bundle "READ context"?

Because the only reliable way to understand the .dat structure is to follow the READ(10,*) order and its usage in code.
This prevents mislabeling loads vs prescribed displacements, etc.


---

## 15) Repository structure (recommended)

```
fem-benchmarks/
  benchmarks/
    pfem5/
      chap04/
      chap05/
      chap06/
      ...
      chap11/
  scripts/
    pfem_build_and_run.sh
    pfem_collect_all.sh
    generate_yaml_from_bundles.py
    verify_yamls.py
    git_publish.sh
  matlab/
    (MATLAB runners + serializers)
  docs/
    HANDOVER.md
  pfem_yaml_bundle/        (ignored by git)
  README.md
  .gitignore
```


---

## Next steps (immediate actions)

1. **Install Python dependencies:**
```bash
pip install pyyaml
```

2. **Set API key:**
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

3. **Run the complete pipeline:**
```bash
# Collect all bundles (with runs)
cd ~/projects/fem-benchmarks
scripts/pfem_collect_all.sh --pfem-root ~/Downloads/pfem5/5th_ed --all-chaps --run --rebuild-first

# Generate all YAMLs
python3 scripts/generate_yaml_from_bundles.py

# Verify YAMLs
python3 scripts/verify_yamls.py

# Publish to GitHub
scripts/git_publish.sh "Complete PFEM benchmark catalogue for chapters 4-11"
```

---

**End of Handover Document**
