#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: prepare-safe-build-prompt.sh <source-prompt> <output-prompt>" >&2
  exit 2
fi

SOURCE_PROMPT="$1"
OUTPUT_PROMPT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_TEMPLATE="$SCRIPT_DIR/../assets/PROMPT_build.safe.md"

if [[ ! -f "$SOURCE_PROMPT" || -L "$SOURCE_PROMPT" ]]; then
  echo "Source build prompt must be a regular file: $SOURCE_PROMPT" >&2
  exit 1
fi
if [[ ! -f "$SAFE_TEMPLATE" || -L "$SAFE_TEMPLATE" ]]; then
  echo "Bundled safe build prompt is missing or invalid: $SAFE_TEMPLATE" >&2
  exit 1
fi
if [[ -e "$OUTPUT_PROMPT" || -L "$OUTPUT_PROMPT" ]]; then
  echo "Refusing to overwrite an existing build prompt: $OUTPUT_PROMPT" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_PROMPT")"
mkdir -p "$OUTPUT_DIR"
TEMP_PROMPT="$(mktemp "$OUTPUT_DIR/.PROMPT_build.safe.XXXXXX")"

cleanup() {
  rm -f "$TEMP_PROMPT"
}

trap cleanup EXIT

# The pinned Ralph prompt is executable behavior. Check its known unsafe contract
# before replacing it with our reviewed prompt so upstream drift fails closed.
if ! grep -Fq 'If tests unrelated to your work fail, resolve them as part of this increment' "$SOURCE_PROMPT" ||
  ! grep -Fq 'invoking the **`/commit` skill**' "$SOURCE_PROMPT" ||
  ! grep -Eq '^[[:space:]]*[0-9]+[.)][[:space:]]*`git push`[[:space:]]*$' "$SOURCE_PROMPT"; then
  echo "Ralph's configured build prompt differs from the reviewed pinned contract; refusing to derive a build prompt" >&2
  exit 1
fi

cp "$SAFE_TEMPLATE" "$TEMP_PROMPT"

if ! ln "$TEMP_PROMPT" "$OUTPUT_PROMPT"; then
  echo "Build prompt destination appeared during preparation; preserving it and stopping: $OUTPUT_PROMPT" >&2
  exit 1
fi
rm -f "$TEMP_PROMPT"
trap - EXIT
