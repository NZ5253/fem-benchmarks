#!/usr/bin/env python3
"""
run_all_tests.py — Run every PFEM benchmark case with default parameters.

Mirrors what pfem_run_from_yaml.m does:
  1. Build program if not in build/bin/  (via pfem_build_chapter.sh)
  2. Create a temp run dir, copy .dat and binary
  3. Run, check exit code and output files

Usage:
    python3 scripts/run_all_tests.py [--chapter chapXX] [--case pYY_Z]
                                     [--timeout 120] [--rebuild]
"""

import argparse
import glob
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import yaml

REPO  = Path(__file__).resolve().parent.parent
PFEM  = REPO / 'pfem'
BENCH = REPO / 'benchmarks' / 'pfem5'
BIN   = PFEM / 'build' / 'bin'


# ── build helpers ─────────────────────────────────────────────────────────────

_built_chapters = set()

def ensure_built(program: str, chapter: str, rebuild: bool = False) -> bool:
    """Build chapter if needed. Return True if binary exists."""
    exe = BIN / program
    if exe.exists() and not rebuild:
        return True
    if chapter in _built_chapters and not rebuild:
        return exe.exists()

    build_sh = REPO / 'scripts' / 'pfem_build_chapter.sh'
    args = ['bash', str(build_sh), str(PFEM), chapter]
    if rebuild:
        args.append('--rebuild')
    print(f'  [build] Building {chapter}...')
    r = subprocess.run(args, capture_output=True, text=True)
    _built_chapters.add(chapter)
    if not exe.exists():
        print(f'  [build] FAILED for {program}:\n{r.stdout[-800:]}\n{r.stderr[-400:]}')
        return False
    return True


# ── per-case runner ────────────────────────────────────────────────────────────

def run_case(yaml_path: Path, timeout: int, rebuild: bool) -> dict:
    result = {
        'yaml': str(yaml_path.relative_to(REPO)),
        'status': 'UNKNOWN', 'exit_code': None, 'outputs': [], 'note': '',
    }

    try:
        with open(yaml_path) as f:
            d = yaml.safe_load(f)
    except Exception as e:
        result.update(status='YAML_ERROR', note=str(e)); return result

    # ── identifiers ───────────────────────────────────────────────────────
    chapter  = f"chap{d['authors']['source']['chapter']:02d}"
    program  = d['authors']['source']['program']    # e.g. p51
    dataset  = d['authors']['source']['dataset']    # e.g. p51_3

    # ── .dat source ───────────────────────────────────────────────────────
    dat_src = PFEM / d['inputs']['dat_file']
    if not dat_src.exists():
        result.update(status='NO_DAT', note=str(dat_src)); return result

    # ── per-case timeout override ─────────────────────────────────────────
    timeout = d.get('outputs', {}).get('timeout_override', timeout)

    # ── binary ────────────────────────────────────────────────────────────
    if not ensure_built(program, chapter, rebuild):
        result.update(status='NO_EXE', note=f'build failed: {program}'); return result
    exe_src = BIN / program

    # ── run dir ───────────────────────────────────────────────────────────
    with tempfile.TemporaryDirectory(prefix='pfem_test_') as run_dir:
        run_dir = Path(run_dir)

        # Stage inputs
        # PFEM binary reads <dataset>.dat and writes <dataset>.res/.msh
        # dataset may differ from program (e.g. program=p41, dataset=p41_1)
        dat_dst = run_dir / f'{dataset}.dat'
        if dat_src.resolve() != dat_dst.resolve():
            shutil.copy2(dat_src, dat_dst)

        exe_dst = run_dir / program
        shutil.copy2(exe_src, exe_dst)
        exe_dst.chmod(exe_dst.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP)

        # Run
        try:
            proc = subprocess.run(
                [str(exe_dst)],
                input=f'{dataset}\n',
                capture_output=True, text=True,
                cwd=str(run_dir),
                timeout=timeout,
            )
            result['exit_code'] = proc.returncode
        except subprocess.TimeoutExpired:
            result.update(status='TIMEOUT', note=f'>{timeout}s'); return result
        except Exception as e:
            result.update(status='EXEC_ERROR', note=str(e)); return result

        # Check outputs
        expected = d.get('outputs', {}).get('files_expected', [])
        found = [f for f in expected if (run_dir / f).exists()
                 and (run_dir / f).stat().st_size > 0]
        result['outputs'] = found

        if proc.returncode != 0:
            stderr_hint = (proc.stderr or proc.stdout or '')[-200:].strip()
            result.update(status='FAIL',
                          note=f'exit {proc.returncode}' +
                               (f' | {stderr_hint}' if stderr_hint else ''))
        elif expected and not found:
            result.update(status='NO_OUTPUT',
                          note=f'expected {expected}, none created')
        else:
            result['status'] = 'OK'

    return result


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--chapter', default=None)
    ap.add_argument('--case',    default=None)
    ap.add_argument('--timeout', type=int, default=120)
    ap.add_argument('--rebuild', action='store_true')
    args = ap.parse_args()

    pattern = str(BENCH / (args.chapter or 'chap*') / '*.yaml')
    yamls = sorted(glob.glob(pattern))
    if args.case:
        yamls = [p for p in yamls if Path(p).stem == args.case]
    if not yamls:
        print('No YAML files found.'); sys.exit(1)

    print(f'Running {len(yamls)} cases  (timeout={args.timeout}s)\n')
    print(f"{'':2}{'Case':<18} {'Status':<12} Note")
    print('─' * 65)

    totals = {}
    fails  = []

    for yf in yamls:
        name = Path(yf).stem
        t0   = time.time()
        res  = run_case(Path(yf), args.timeout, args.rebuild)
        dt   = time.time() - t0
        s    = res['status']
        totals[s] = totals.get(s, 0) + 1
        icon = '✓' if s == 'OK' else '✗'
        print(f'{icon} {name:<18} {s:<12} {res["note"][:35]:<36} {dt:.1f}s')
        if s != 'OK':
            fails.append((name, s, res['note']))

    n_ok = totals.get('OK', 0)
    print()
    print('=' * 65)
    print(f'RESULT: {n_ok}/{len(yamls)} passed')
    for s, c in sorted(totals.items()):
        if s != 'OK':
            print(f'  {s}: {c}')
    if fails:
        print('\nFailed cases:')
        for name, s, note in fails:
            print(f'  {name:<20} {s:<12} {note}')

    sys.exit(0 if n_ok == len(yamls) else 1)


if __name__ == '__main__':
    main()
