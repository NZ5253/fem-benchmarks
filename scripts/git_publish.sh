#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/git_publish.sh "Commit message"
#
# This script:
# - Stages all changes in benchmarks/, scripts/, docs/, matlab/
# - Commits with the provided message
# - Pushes to remote

COMMIT_MSG="${1:-}"

if [[ -z "$COMMIT_MSG" ]]; then
  echo "Usage: $0 \"Commit message\""
  echo ""
  echo "Example:"
  echo "  scripts/git_publish.sh \"Add PFEM benchmark YAMLs for chapter 5\""
  exit 1
fi

# Ensure we're in the repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Check if we're in a git repo
if [[ ! -d ".git" ]]; then
  echo "[ERROR] Not in a git repository. Expected .git folder at: $REPO_ROOT"
  exit 1
fi

echo "[INFO] Repository root: $REPO_ROOT"
echo "[INFO] Commit message: $COMMIT_MSG"
echo ""

# Show current status
echo "========== Current git status =========="
git status
echo ""

# Stage relevant files/directories
echo "========== Staging files =========="
git add benchmarks/ scripts/ docs/ matlab/ README.md .gitignore 2>/dev/null || true
git status --short
echo ""

# Check if there's anything to commit
if git diff --cached --quiet; then
  echo "[INFO] No changes to commit. Everything is up to date."
  exit 0
fi

# Commit
echo "========== Creating commit =========="
git commit -m "$COMMIT_MSG"
echo ""

# Push
echo "========== Pushing to remote =========="
git push
echo ""

echo "[SUCCESS] Changes published to GitHub!"
