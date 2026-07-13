#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_TEMPLATE="$SCRIPT_DIR/../assets/IMPLEMENTATION_PLAN.safe.md"
PROGRESS_TEMPLATE="$SCRIPT_DIR/../assets/PROGRESS.safe.md"
TEMP_FILES=()

cleanup() {
  local temporary

  if [[ "${#TEMP_FILES[@]}" -gt 0 ]]; then
    for temporary in "${TEMP_FILES[@]}"; do
      rm -f "$temporary"
    done
  fi
}

trap cleanup EXIT

if [[ "$#" -ne 0 ]]; then
  echo "Safe Ralph initialization accepts no options" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Run safe Ralph initialization inside a Git worktree" >&2
  exit 1
fi
for template in "$PLAN_TEMPLATE" "$PROGRESS_TEMPLATE"; do
  if [[ ! -f "$template" || -L "$template" ]]; then
    echo "Missing regular Ralph template: $template" >&2
    exit 1
  fi
done
for artifact in IMPLEMENTATION_PLAN.md PROGRESS.md; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    if [[ ! -f "$artifact" || -L "$artifact" ]]; then
      echo "Existing Ralph artifact is not a regular file: $artifact" >&2
      exit 1
    fi
  fi
done
if [[ -L specs || ( -e specs && ! -d specs ) ]]; then
  echo "Existing specs path is not a regular directory: specs" >&2
  exit 1
fi

publish_template() {
  local source="$1"
  local destination="$2"
  local temporary

  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ ! -f "$destination" || -L "$destination" ]]; then
      echo "Existing Ralph artifact is not a regular file: $destination" >&2
      return 1
    fi
    echo "Preserved: $destination"
    return
  fi

  temporary="$(mktemp "./.${destination}.ralph-init.XXXXXX")"
  TEMP_FILES+=("$temporary")
  cp "$source" "$temporary"
  if ! ln "$temporary" "$destination"; then
    echo "Ralph artifact appeared during initialization; preserving it and stopping: $destination" >&2
    return 1
  fi
  rm -f "$temporary"
  echo "Created: $destination"
}

if [[ ! -d specs ]]; then
  mkdir specs
  echo "Created: specs/"
else
  echo "Preserved: specs/"
fi

publish_template "$PLAN_TEMPLATE" IMPLEMENTATION_PLAN.md
publish_template "$PROGRESS_TEMPLATE" PROGRESS.md

echo "Left .gitignore and .claude/ unchanged; decide locally whether Ralph artifacts should be ignored."
