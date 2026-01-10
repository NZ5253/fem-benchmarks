# Generating Perfect YAML Benchmark Files

This guide explains how to use the Python script to generate complete "perfect YAML" benchmark files for PFEM programs.

## Overview

The `generate_perfect_yamls.py` script automatically creates comprehensive YAML benchmark files by:
1. Analyzing Fortran source code to extract READ(10,*) statements with line numbers
2. Parsing .dat input files
3. Using the Anthropic API to generate structured YAML following the p54_1.yaml template
4. Creating complete specifications with all sections

## Prerequisites

### 1. Install Python Dependencies

```bash
pip install anthropic
```

### 2. Get API Key

You need an Anthropic API key. Set it as an environment variable:

```bash
export ANTHROPIC_API_KEY='your-api-key-here'
```

Or pass it directly with `--api-key` flag.

### 3. Verify PFEM Source Location

Default location: `/home/naeem/Downloads/pfem5/5th_ed`

If different, use `--pfem-root` flag.

## Basic Usage

### Generate YAML for a Single Case

```bash
cd /home/naeem/projects/fem-benchmarks

python3 scripts/generate_perfect_yamls.py \
  --chapter chap05 \
  --case p54_1
```

### Generate YAMLs for All Cases in a Chapter

```bash
python3 scripts/generate_perfect_yamls.py --chapter chap05
```

This will process all .dat files found in `executable/chap05/` and generate corresponding YAML files.

### Dry Run (Preview Only)

```bash
python3 scripts/generate_perfect_yamls.py \
  --chapter chap05 \
  --dry-run
```

## Command-Line Options

```
--chapter CHAP     Required. Chapter to process (e.g., chap05)
--case CASE        Optional. Specific case (e.g., p54_1). If omitted, processes all cases.
--pfem-root PATH   Optional. PFEM source root directory (default: /home/naeem/Downloads/pfem5/5th_ed)
--api-key KEY      Optional. Anthropic API key (or set ANTHROPIC_API_KEY env var)
--output-dir DIR   Optional. Output directory (default: benchmarks/pfem5/{chapter})
--dry-run          Optional. Show what would be done without generating files
```

## Examples

### Chapter 5 (All 13 Cases)

```bash
# Generate all Chapter 5 YAMLs
python3 scripts/generate_perfect_yamls.py --chapter chap05

# Expected output:
# Found 13 case(s) to process in chap05
# [1/13] Processing p51_1
#   Reading source: p51.f03
#   Reading data: p51_1.dat
#   Found 7 READ(10,*) statements
#   Generating perfect YAML...
#   ✓ Generated: benchmarks/pfem5/chap05/p51_1.yaml
# ...
```

### Chapter 4

```bash
python3 scripts/generate_perfect_yamls.py --chapter chap04
```

### Single Case

```bash
python3 scripts/generate_perfect_yamls.py --chapter chap06 --case p62_1
```

### Custom PFEM Location

```bash
python3 scripts/generate_perfect_yamls.py \
  --chapter chap05 \
  --pfem-root /custom/path/to/pfem
```

## Generated YAML Structure

Each generated YAML includes:

1. **id, title, purpose** - Basic identification
2. **authors** - Source book info and entry metadata (created_by: "Naeem")
3. **code** - Language, source file, io_reads_from_unit10 with line numbers
4. **fem** - Dimension, formulation, DOF, element details
5. **analysis** - Physics, type, regime
6. **units** - Unit system notes
7. **tunable_parameters** - Parameters for parametric studies (E, nu, loads, mesh)
8. **input_schema** - Detailed field descriptions for each READ statement
9. **inputs** - Parsed .dat values organized by record (record1, record2, etc.)
10. **outputs** - Expected output files
11. **how_to_run** - Linux and MATLAB commands
12. **notes** - Usage notes

## Template Reference

The script uses `benchmarks/pfem5/chap05/p54_1.yaml` as the template. This file defines:
- Complete structure and formatting
- Section organization
- Field naming conventions
- Documentation style

## Workflow for Remaining Chapters

To generate YAMLs for all remaining chapters (4, 6-11):

```bash
cd /home/naeem/projects/fem-benchmarks

# Chapter 4
python3 scripts/generate_perfect_yamls.py --chapter chap04

# Chapter 6
python3 scripts/generate_perfect_yamls.py --chapter chap06

# Chapter 7
python3 scripts/generate_perfect_yamls.py --chapter chap07

# Chapter 8
python3 scripts/generate_perfect_yamls.py --chapter chap08

# Chapter 9
python3 scripts/generate_perfect_yamls.py --chapter chap09

# Chapter 10
python3 scripts/generate_perfect_yamls.py --chapter chap10

# Chapter 11
python3 scripts/generate_perfect_yamls.py --chapter chap11
```

## Validation

After generation, validate all YAMLs:

```bash
python3 scripts/verify_yamls.py benchmarks/pfem5/chap05/*.yaml
```

Expected output:
```
✓ benchmarks/pfem5/chap05/p51_1.yaml
✓ benchmarks/pfem5/chap05/p51_2.yaml
...
Valid: 13/13
[SUCCESS] All YAML files are valid!
```

## Troubleshooting

### Error: "anthropic module not installed"

```bash
pip install anthropic
```

### Error: "API key required"

Set the environment variable:
```bash
export ANTHROPIC_API_KEY='your-key'
```

Or pass directly:
```bash
python3 scripts/generate_perfect_yamls.py --chapter chap05 --api-key 'your-key'
```

### Error: "Source file not found"

Check PFEM root path:
```bash
python3 scripts/generate_perfect_yamls.py --chapter chap05 --pfem-root /path/to/pfem
```

### Error: "Template YAML not found"

The script requires `benchmarks/pfem5/chap05/p54_1.yaml` as the template. Ensure this file exists.

## Manual Review

After generation:
1. Review generated YAMLs for accuracy
2. Verify READ statement line numbers match source code
3. Check parsed .dat values are correct
4. Validate tunable_parameters paths
5. Test with verification script

## Cost Estimation

Each YAML generation uses approximately:
- Model: claude-sonnet-4-20250514
- Tokens: ~6,000-8,000 per case
- Cost: ~$0.02-0.03 per case (estimate)

For all 85 cases: ~$1.50-2.50 total

## Next Steps

After generating YAMLs:
1. Validate with `verify_yamls.py`
2. Test running cases with `pfem_runner.m` (MATLAB)
3. Commit to repository
4. Document any program-specific notes or variations
