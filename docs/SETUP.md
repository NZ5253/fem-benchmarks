<p align="center">
  <img src="figures/tudortmund_logo.svg" alt="Technische Universität Dortmund" height="60">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="figures/cre_logo.png" alt="Chair for Reliability Engineering (CRE)" height="60">
</p>

<h1 align="center">fem-benchmarks — Setup Guide</h1>

<p align="center">
  <sub>Full installation walkthrough for <b>Linux</b> and <b>Windows</b> (via WSL2)<br>
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> · <a href="GUIDE.md">GUIDE.md</a></sub>
</p>

---

## Table of contents

- [1. Which platform are you on?](#1-which-platform-are-you-on)
- [2. Linux setup (Ubuntu / Debian / Mint)](#2-linux-setup-ubuntu--debian--mint)
- [3. Windows setup (via WSL2)](#3-windows-setup-via-wsl2)
- [4. macOS notes](#4-macos-notes)
- [5. Restoring the PFEM source](#5-restoring-the-pfem-source)
- [6. Verifying the install](#6-verifying-the-install)
- [7. First run (no PFEM required)](#7-first-run-no-pfem-required)
- [8. Common install problems](#8-common-install-problems)

---

## 1. Which platform are you on?

The framework is **Linux-native**. The Fortran build script (`pfem_build_chapter.sh`)
is bash, `pfem_ensure_built.m` shells out to bash, and runners use POSIX
paths with `printf | ./binary`.

| Your platform | Recommended path | Verified? |
|---|---|---|
| Ubuntu / Debian / Mint | Native install (§2) | Yes, ongoing |
| Windows 10 / 11 | WSL2 with Ubuntu 22.04+ (§3) | Yes |
| macOS | Native install with Homebrew (§4) | Not verified — should work |
| Windows without WSL | MSYS2 / MinGW-w64 | Not supported |

If you have any Windows machine less than ~5 years old you can run WSL2.
It is the correct path — a native-Windows build would require rewriting
every bash script and every MATLAB `system()` call.

---

## 2. Linux setup (Ubuntu / Debian / Mint)

Tested on Ubuntu 22.04 / 24.04, Linux Mint 21+, and Debian 12.

### 2.1 System packages

```bash
sudo apt update
sudo apt install -y \
    gfortran make \
    python3 python3-pip python3-yaml \
    libarpack2t64 libarpack2-dev \
    liblapack-dev libblas-dev \
    git
```

Notes:
- `libarpack2t64` is the runtime; `libarpack2-dev` provides the linker
  headers. Both are needed to build and run p104.
- On older Ubuntu (< 24.04) the package is just `libarpack2`, without the
  `t64` suffix.
- If `python3-yaml` isn't found, use `pip install pyyaml`.

### 2.2 MATLAB

Install MATLAB R2022b or newer from your MathWorks account. Verified on
R2025b. Any release with `uifigure` and `matlab.net.base64encode` works
(that's R2020a+).

Ensure `matlab` is on your PATH:

```bash
which matlab
# → /home/<you>/MATLAB/R2025b/bin/matlab (or similar)
```

If not, add the MATLAB `bin` directory to your `~/.bashrc`:

```bash
echo 'export PATH="$HOME/MATLAB/R2025b/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 2.3 Clone the repository

```bash
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks
```

### 2.4 Restore the PFEM source

The Fortran textbook code is gitignored (see §5). If you only want to
try the analytic and external backends, skip this — see §7.

### 2.5 First-time build

```bash
scripts/pfem_build_chapter.sh ./pfem chap06
```

This builds the PFEM library once, then every `p6*` binary. Chapter 6 is
a good first target (it has the well-known p612 slope-stability case).

### 2.6 Continue to §6 to verify.

---

## 3. Windows setup (via WSL2)

WSL2 gives you a real Linux kernel inside Windows. MATLAB can be run
either inside WSL (Linux MATLAB) or on Windows (Windows MATLAB with WSL
paths); both work.

### 3.1 Enable WSL2 and install Ubuntu

Open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu-24.04
```

Reboot when prompted. On first login create a Linux user account
(username + password).

Verify:

```powershell
wsl --list --verbose
# → Ubuntu-24.04    Running    2   (the "2" is the WSL2 version)
```

If your Ubuntu shows version 1, upgrade it:

```powershell
wsl --set-version Ubuntu-24.04 2
```

### 3.2 Inside WSL, install system packages

Open the **Ubuntu** app from your Start menu. Then follow §2.1:

```bash
sudo apt update
sudo apt install -y \
    gfortran make \
    python3 python3-pip python3-yaml \
    libarpack2t64 libarpack2-dev \
    liblapack-dev libblas-dev \
    git
```

### 3.3 MATLAB — two options

**Option A — Linux MATLAB inside WSL (recommended).** Cleanest end-to-end
integration; the framework was written and tested this way.

Download the Linux installer from MathWorks:
https://www.mathworks.com/downloads/. Move it into WSL:

```bash
# from PowerShell (assuming you downloaded to Downloads):
wsl cp "/mnt/c/Users/<you>/Downloads/matlab_R2025b_glnxa64.zip" ~/
```

Then in the WSL Ubuntu shell:

```bash
sudo apt install -y default-jre  # required by the MATLAB installer
mkdir -p ~/matlab_install && cd ~/matlab_install
unzip ~/matlab_R2025b_glnxa64.zip
sudo ./install
# follow the graphical or console installer
echo 'export PATH="/usr/local/MATLAB/R2025b/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
matlab -nodesktop -nosplash -r "disp('ok'); exit"
```

For GUI display you need an X server. On Windows 11 this is built in
(WSLg — just launch `matlab` from WSL and the window opens). On Windows
10 install VcXsrv or X410 first.

**Option B — Windows MATLAB with WSL paths.** Keep your existing Windows
MATLAB and access the WSL filesystem from Windows.

In Windows MATLAB:

```matlab
cd '\\wsl$\Ubuntu-24.04\home\<you>\fem-benchmarks'
addpath matlab matlab/utils matlab/backends;
pfem_sweep_gui
```

The `system()` calls in the framework will fail because they use bash.
For batch runs this option is not recommended. Use Option A.

### 3.4 Clone the repository (inside WSL)

```bash
cd ~
git clone https://github.com/NZ5253/fem-benchmarks.git
cd fem-benchmarks
```

Keep the repo inside the WSL filesystem (`~/`, not `/mnt/c/...`). Cross-
filesystem I/O is 5-10× slower and can cause build glitches.

### 3.5 Restore the PFEM source (§5) and continue to §6.

---

## 4. macOS notes

Not officially verified but should work. Substitute Homebrew for apt:

```bash
brew install gfortran python arpack lapack
pip3 install pyyaml
```

Install MATLAB from mathworks.com. The rest of the workflow is
identical to Linux.

`chmod +x`, bash, and POSIX paths all exist natively on macOS, so
`pfem_build_chapter.sh` and `pfem_run_from_yaml.m` should work
unchanged. Report any issues via GitHub Issues.

---

## 5. Restoring the PFEM source

The `pfem/` directory is gitignored because the Fortran source code from
*Programming the Finite Element Method* (Smith / Griffiths / Margetts,
5<sup>th</sup> ed., Wiley 2014) is proprietary and cannot be
redistributed under MIT. See [LICENSE](../LICENSE).

Two restore options.

### 5.1 From USB backup (if you have one)

The patched tree is ~56 MB on the USB drive labelled `USB Drive`:

```bash
# Linux (native or WSL):
cp -r "/media/<user>/USB Drive/fem-benchmarks-cleaned-20260522_140600/pfem" ./
# Or from WSL when the USB is mounted in Windows first:
cp -r "/mnt/e/fem-benchmarks-cleaned-20260522_140600/pfem" ./
```

The USB copy already has the five patches applied. Continue to §6.

### 5.2 Fresh download + apply patches

Download the textbook source from http://www.pfem.org.uk/, unpack it into
`pfem/`, then apply the patches:

```bash
# From the repo root:
for p in scripts/pfem_patches/*.patch; do
    (cd pfem && patch -p1 < "../$p")
done
cp scripts/pfem_patches/*.f03 pfem/source/library/misc/
```

The five patches:

- `p42_add_use_geom.patch` — fixes SIGSEGV in `formnf`
- `p44_add_use_geom.patch` — same for p44
- `p57_umat_alloc.patch` — allocates UMAT arrays
- `main_int_elap_time_interface.patch` — timer interface
- Three new library files added: `elap_time.f03`, `umat_elastic.f03`,
  `lancz.f03`

See [scripts/pfem_patches/README.md](../scripts/pfem_patches/README.md)
for the reasoning behind each patch.

### 5.3 Build every chapter

```bash
for ch in chap04 chap05 chap06 chap07 chap08 chap09 chap10 chap11; do
    scripts/pfem_build_chapter.sh ./pfem "$ch"
done
```

Takes ~2 min on a modern laptop. Produces 87 binaries in
`pfem/build/bin/`.

---

## 6. Verifying the install

Run these in order. Any failure indicates a real problem — the framework
is regression-locked at four levels, so tests either pass cleanly or fail
loudly.

### 6.1 All 87 PFEM binaries run at defaults (~30 s)

```bash
python3 scripts/run_all_tests.py
# expected: RESULT: 87/87 passed
```

### 6.2 Fast MATLAB regression gates (~5 s combined)

```bash
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    test_all_analytic_oracles; \
    test_stochastic_gate; \
    test_physics_sanity; \
    test_analytic_backend; \
    test_external_backend"
# expected:
#   9 / 9 oracles agree with hand-derived formula
#   2 / 2 backends locked to reference within 1e-6
#   20 / 20 monotonicity checks pass
#   M3 accuracy proof PASSED
#   M5-followup sensitivity via b.extract_qoi PASSED
#   M4 external backend PASSED
```

### 6.3 Broad per-case Monte Carlo (~40 s)

```bash
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    test_all_cases_stochastic"
# expected: TOTAL: 180 / 180 samples across 18 cases
```

### 6.4 Golden regression gate — the definitive test (~5 min)

```bash
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    test_golden_qoi"
# expected: 92 / 92 passed
```

### 6.5 GUI launches

```bash
matlab -nodesktop -nosplash \
    -r "addpath matlab matlab/utils matlab/backends; pfem_sweep_gui"
```

A window titled **PFEM Sweep Studio** should open. Cases panel empty,
Tunable Parameters panel empty, mode dropdown showing "Lockstep".

If everything above passes, your install is complete.

---

## 7. First run (no PFEM required)

You can run the **analytic** and **external** backends without any PFEM
source. Useful for a first look at the framework without the build step.

After §2/§3 (system packages + clone), and even before §5 (PFEM restore):

```bash
matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; \
    test_all_analytic_oracles; \
    test_external_backend"
```

Should print:

```
9 / 9 oracles agree with hand-derived formula
M4 external backend PASSED
```

Or launch the GUI and pick **Load preset ... → Analytic + External Prandtl
(fast, no PFEM)** — sub-second-per-sample, no Fortran needed.

This gives you a working framework demo in **under 3 minutes** from a
fresh clone.

---

## 8. Common install problems

### 8.1 `gfortran: command not found`

Missing compiler. Install:

```bash
sudo apt install gfortran           # Linux / WSL
brew install gcc                    # macOS
```

### 8.2 `libarpack.so.2: cannot open shared object file`

Missing runtime. Install:

```bash
sudo apt install libarpack2t64      # Ubuntu 24.04+
sudo apt install libarpack2         # Ubuntu < 24.04
```

### 8.3 `p56_1` or other case fails to build

Likely a missing patch. Check `scripts/pfem_patches/README.md` and reapply
the corresponding patch. Rebuild:

```bash
scripts/pfem_build_chapter.sh ./pfem chap05 --rebuild
```

### 8.4 MATLAB opens then instantly dies

On Linux MATLAB with certain OpenGL drivers this happens. Add the
software-OpenGL flag:

```bash
matlab -nodesktop -nosplash -softwareopengl \
    -r "addpath matlab matlab/utils matlab/backends; pfem_sweep_gui"
```

### 8.5 In WSL, MATLAB says "Cannot connect to X server"

Windows 10 without WSLg: install an X server (VcXsrv or X410) and export
`DISPLAY=:0`. Windows 11 with WSLg: should be automatic — try `wsl
--update` in PowerShell.

### 8.6 `Unrecognized field "source"` when loading a non-PFEM YAML

Old bytecode cached. In MATLAB Command Window:

```matlab
close all; clear functions; pfem_sweep_gui
```

Or quit MATLAB entirely and reopen.

### 8.7 GUI parameter table stays empty after adding YAMLs

Same cause as 8.6. Cure is the same.

### 8.8 Golden test fails on one case

Something has drifted. Diagnose with `git bisect run`:

```bash
git bisect start
git bisect bad HEAD
git bisect good v1.0-phase3-complete
git bisect run matlab -batch "addpath matlab matlab/utils matlab/backends matlab/tests; test_golden_qoi"
```

If the drift is intentional (e.g., you fixed a real bug in an extractor),
regenerate the golden reference:

```matlab
addpath matlab matlab/utils matlab/backends matlab/tests;
capture_golden_qoi
% commit the updated matlab/tests/golden_qoi.json
```

### 8.9 External bash solver prints commas instead of decimal points

Non-English system locale (German, French, ...). Force POSIX in the
solver:

```bash
export LC_ALL=C
```

`prandtl.sh` already does this internally. If you write your own external
solver, include the same line.

### 8.10 `Build failed for p<N>` in the GUI log after a chapter build

`pfem_ensure_built` looks for the compiled binary at
`pfem/build/bin/p<N>`. If your build put binaries elsewhere (custom
Makefile), symlink them:

```bash
ln -s /path/to/your/binaries/p61 pfem/build/bin/p61
```

---

<p align="center"><sub>
  <a href="https://github.com/NZ5253/fem-benchmarks">github.com/NZ5253/fem-benchmarks</a> ·
  Companion to <a href="HANDOVER.md">HANDOVER.md</a> ·
  Naeem Zainuddin, Technische Universität Dortmund
</sub></p>
