#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: prepare-safe-plan-prompt.sh <source-prompt> <output-prompt>" >&2
  exit 2
fi

SOURCE_PROMPT="$1"
OUTPUT_PROMPT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_TEMPLATE="$SCRIPT_DIR/../assets/PROMPT_plan.safe.md"

if [[ ! -f "$SOURCE_PROMPT" || -L "$SOURCE_PROMPT" ]]; then
  echo "Source plan prompt must be a regular file: $SOURCE_PROMPT" >&2
  exit 1
fi
if [[ ! -f "$SAFE_TEMPLATE" || -L "$SAFE_TEMPLATE" ]]; then
  echo "Bundled safe plan prompt is missing or invalid: $SAFE_TEMPLATE" >&2
  exit 1
fi
if [[ -e "$OUTPUT_PROMPT" || -L "$OUTPUT_PROMPT" ]]; then
  echo "Refusing to overwrite an existing plan prompt: $OUTPUT_PROMPT" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_PROMPT")"
mkdir -p "$OUTPUT_DIR"
TEMP_PROMPT="$(mktemp "$OUTPUT_DIR/.PROMPT_plan.safe.XXXXXX")"

cleanup() {
  rm -f "$TEMP_PROMPT"
}

trap cleanup EXIT

if ! grep -Fq 'You are a planning agent in an autonomous loop.' "$SOURCE_PROMPT" ||
  ! grep -Fq 'Create or update `IMPLEMENTATION_PLAN.md`' "$SOURCE_PROMPT" ||
  ! grep -Fq 'Plan only. Do NOT implement anything.' "$SOURCE_PROMPT"; then
  echo "Ralph's configured plan prompt differs from the reviewed pinned contract; refusing to derive a plan prompt" >&2
  exit 1
fi

cp "$SAFE_TEMPLATE" "$TEMP_PROMPT"
if ! ln "$TEMP_PROMPT" "$OUTPUT_PROMPT"; then
  echo "Plan prompt destination appeared during preparation; preserving it and stopping: $OUTPUT_PROMPT" >&2
  exit 1
fi
rm -f "$TEMP_PROMPT"
trap - EXIT
