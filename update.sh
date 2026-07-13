#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Cannot update: $SCRIPT_DIR is not a Git worktree" >&2
  exit 1
fi
if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=all)" ]]; then
  echo "Cannot update with local repository changes; preserve or commit them first." >&2
  exit 1
fi
if ! git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD >/dev/null; then
  echo "Cannot update from a detached HEAD; switch to the intended branch first." >&2
  exit 1
fi
if ! git -C "$SCRIPT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  echo "Cannot update because the current branch has no configured upstream." >&2
  exit 1
fi

git -C "$SCRIPT_DIR" pull --ff-only
git -C "$SCRIPT_DIR" submodule sync --recursive
git -C "$SCRIPT_DIR" submodule update --init --recursive
"$SCRIPT_DIR/validate.sh"
"$SCRIPT_DIR/install.sh" --install-dependencies "$@"
"$SCRIPT_DIR/doctor.sh"
