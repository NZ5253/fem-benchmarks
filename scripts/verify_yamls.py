#!/usr/bin/env python3
"""
Verify YAML benchmark files in the repository.

Checks:
- YAML syntax is valid
- Required top-level keys exist
- IDs are unique
- Basic structure validation
"""

import sys
import yaml
from pathlib import Path
from collections import defaultdict

# Required top-level keys for a valid benchmark YAML
# Note: 'source' can be either top-level or under 'authors.source' (perfect YAML format)
REQUIRED_KEYS = ['id', 'title', 'code', 'fem', 'analysis', 'inputs', 'outputs']

def verify_token_consistency(data):
    """Check token-level consistency within a YAML file.

    Runs four checks:
    1. len(all_tokens) == input_schema.total_tokens
    2. Every global_token_index is within 1..len(all_tokens)
    3. tunable current_value matches all_tokens[global_token_index-1]
    4. tunable book_reference.value (if present) matches all_tokens[global_token_index-1]

    Note: book_reference.value must be a quoted string in the YAML file
    (e.g. value: '1.0e6') to prevent YAML float coercion breaking comparison.

    Returns list of error strings (empty if all pass).
    """
    errors = []
    inputs = data.get('inputs', {})
    input_schema = data.get('input_schema', {})
    tunables = data.get('tunable_parameters', [])
    all_tokens = inputs.get('all_tokens')
    total_tokens = input_schema.get('total_tokens')

    # Check 1: token count consistency
    if all_tokens is not None and total_tokens is not None:
        if len(all_tokens) != total_tokens:
            errors.append(
                f"Token count mismatch: input_schema.total_tokens={total_tokens} "
                f"but len(inputs.all_tokens)={len(all_tokens)}"
            )

    if not all_tokens or not isinstance(tunables, list):
        return errors

    n = len(all_tokens)
    for param in tunables:
        if not isinstance(param, dict):
            continue
        name = param.get('name', '?')
        gidx = param.get('global_token_index')
        if gidx is None:
            continue

        # Check 2: index in bounds
        if not isinstance(gidx, int) or gidx < 1 or gidx > n:
            errors.append(
                f"tunable '{name}': global_token_index={gidx} out of bounds (1..{n})"
            )
            continue

        actual = str(all_tokens[gidx - 1])

        # Check 3: current_value matches token
        cv = param.get('current_value')
        if cv is not None and str(cv) != actual:
            errors.append(
                f"tunable '{name}': current_value='{cv}' != all_tokens[{gidx}]='{actual}'"
            )

        # Check 4: book_reference.value matches token
        book_ref = param.get('book_reference')
        if isinstance(book_ref, dict) and 'value' in book_ref:
            bval = str(book_ref['value'])
            if bval != actual:
                fig = book_ref.get('figure', 'unknown figure')
                errors.append(
                    f"tunable '{name}': book_reference.value='{bval}' ({fig}) "
                    f"!= all_tokens[{gidx}]='{actual}'"
                )

    return errors


def verify_yaml_file(yaml_path):
    """Verify a single YAML file. Returns (is_valid, errors, data)."""
    errors = []

    try:
        with open(yaml_path, 'r') as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return False, [f"YAML parse error: {e}"], None
    except Exception as e:
        return False, [f"File read error: {e}"], None

    if not isinstance(data, dict):
        return False, ["YAML root must be a dictionary"], None

    # Check required keys
    missing_keys = [k for k in REQUIRED_KEYS if k not in data]
    if missing_keys:
        errors.append(f"Missing required keys: {', '.join(missing_keys)}")

    # Check for source information (either 'source' or 'authors.source')
    if 'source' not in data and 'authors' not in data:
        errors.append("Missing source information: need either 'source' or 'authors'")
    elif 'authors' in data and 'source' not in data.get('authors', {}):
        errors.append("'authors' present but missing 'authors.source'")

    # Validate ID format
    if 'id' in data:
        yaml_id = data['id']
        if not isinstance(yaml_id, str) or not yaml_id.strip():
            errors.append("'id' must be a non-empty string")

    # Basic structure checks
    if 'source' in data and not isinstance(data['source'], dict):
        errors.append("'source' must be a dictionary")

    if 'code' in data and not isinstance(data['code'], dict):
        errors.append("'code' must be a dictionary")

    if 'fem' in data and not isinstance(data['fem'], dict):
        errors.append("'fem' must be a dictionary")

    if 'analysis' in data and not isinstance(data['analysis'], dict):
        errors.append("'analysis' must be a dictionary")

    errors.extend(verify_token_consistency(data))
    return len(errors) == 0, errors, data

def main():
    repo_root = Path(__file__).parent.parent
    benchmarks_dir = repo_root / 'benchmarks'

    if not benchmarks_dir.exists():
        print(f"[ERROR] Benchmarks directory not found: {benchmarks_dir}")
        return 1

    # Find all YAML files
    yaml_files = list(benchmarks_dir.rglob('*.yaml')) + list(benchmarks_dir.rglob('*.yml'))

    # Exclude template files
    yaml_files = [f for f in yaml_files if not f.name.startswith('_')]

    if not yaml_files:
        print(f"[WARN] No YAML files found in {benchmarks_dir}")
        return 0

    print(f"[INFO] Found {len(yaml_files)} YAML file(s) to verify\n")

    all_valid = True
    ids = defaultdict(list)
    valid_count = 0

    for yaml_file in sorted(yaml_files):
        rel_path = yaml_file.relative_to(repo_root)
        is_valid, errors, data = verify_yaml_file(yaml_file)

        if is_valid:
            print(f"✓ {rel_path}")
            valid_count += 1
            if data and 'id' in data:
                ids[data['id']].append(rel_path)
        else:
            print(f"✗ {rel_path}")
            for err in errors:
                print(f"  - {err}")
            all_valid = False

    # Check for duplicate IDs
    print("\n" + "="*60)
    duplicates = {yaml_id: paths for yaml_id, paths in ids.items() if len(paths) > 1}
    if duplicates:
        print("[ERROR] Duplicate IDs found:")
        for yaml_id, paths in duplicates.items():
            print(f"  ID '{yaml_id}' appears in:")
            for p in paths:
                print(f"    - {p}")
        all_valid = False

    # Summary
    print("="*60)
    print(f"Valid: {valid_count}/{len(yaml_files)}")

    if all_valid:
        print("\n[SUCCESS] All YAML files are valid!")
        return 0
    else:
        print("\n[FAILURE] Some YAML files have errors.")
        return 1

if __name__ == '__main__':
    sys.exit(main())
