#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DEST="${CODEX_HOME:-$HOME/.codex}/skills"
BIN_DIR="${RALPH_BIN_DIR:-$HOME/.local/bin}"
status=0

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "[OK] command: $command_name ($(command -v "$command_name"))"
  else
    echo "[FAIL] command missing: $command_name"
    status=1
  fi
}

check_path() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    echo "[OK] $label: $path"
  else
    echo "[FAIL] missing $label: $path"
    status=1
  fi
}

echo "Codex global skills doctor"
echo ""

check_command git
check_command npm
check_command codex
check_command devcontainer

if command -v ralph >/dev/null 2>&1; then
  echo "[OK] command: ralph ($(command -v ralph))"
elif [[ -x "$BIN_DIR/ralph" ]]; then
  echo "[WARN] ralph exists at $BIN_DIR/ralph but is not on PATH"
else
  echo "[FAIL] ralph is not installed"
  status=1
fi

echo ""
check_path "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit/rules" "EE toolkit rules"

echo ""
for skill in ralph equal-experts-workflow ee-clarify ee-breakdown ee-control-plane commit; do
  check_path "$SKILLS_DEST/$skill/SKILL.md" "installed skill $skill"
done

echo ""
for skill in equal-experts-workflow ee-clarify ee-breakdown ee-control-plane; do
  if [[ -L "$SKILLS_DEST/$skill/toolkit" || -d "$SKILLS_DEST/$skill/toolkit" ]]; then
    echo "[OK] EE toolkit linked for $skill"
  else
    echo "[FAIL] EE toolkit not linked for $skill"
    status=1
  fi
done

echo ""
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    echo "[OK] Docker daemon is reachable"
  else
    echo "[WARN] docker exists but the daemon is not reachable"
  fi
else
  echo "[WARN] docker command is missing; Ralph sandbox needs Docker"
fi

exit "$status"
