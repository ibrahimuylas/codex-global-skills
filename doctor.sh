#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DEST="$CODEX_CONFIG_DIR/skills"
GUIDANCE_SRC="$SCRIPT_DIR/guidance/git-safety.md"
GLOBAL_AGENTS_FILE="$CODEX_CONFIG_DIR/AGENTS.md"
GIT_GUIDANCE_START="<!-- codex-global-skills:git-safety:start -->"
GIT_GUIDANCE_END="<!-- codex-global-skills:git-safety:end -->"
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

check_global_git_guidance() {
  local begin_count
  local end_count
  local installed_guidance

  if [[ ! -s "$GUIDANCE_SRC" ]]; then
    echo "[FAIL] missing or empty source Git guidance: $GUIDANCE_SRC"
    status=1
    return
  fi
  echo "[OK] source Git guidance: $GUIDANCE_SRC"

  if [[ -L "$GLOBAL_AGENTS_FILE" ]]; then
    echo "[FAIL] global AGENTS.md must not be a symbolic link: $GLOBAL_AGENTS_FILE"
    status=1
    return
  fi

  if [[ ! -f "$GLOBAL_AGENTS_FILE" ]]; then
    echo "[FAIL] missing global AGENTS.md: $GLOBAL_AGENTS_FILE"
    status=1
    return
  fi

  begin_count="$(grep -Fxc -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" || true)"
  end_count="$(grep -Fxc -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" || true)"
  if [[ "$begin_count" -ne 1 || "$end_count" -ne 1 ]]; then
    echo "[FAIL] expected one managed Git guidance marker pair in $GLOBAL_AGENTS_FILE"
    status=1
    return
  fi
  echo "[OK] managed Git guidance markers: $GLOBAL_AGENTS_FILE"

  installed_guidance="$(mktemp "${TMPDIR:-/tmp}/codex-global-skills-guidance.XXXXXX")"
  awk -v start="$GIT_GUIDANCE_START" -v finish="$GIT_GUIDANCE_END" '
    $0 == start { managed = 1; next }
    $0 == finish { managed = 0; found_end = 1; exit }
    managed { print }
    END {
      if (!found_end) {
        exit 1
      }
    }
  ' "$GLOBAL_AGENTS_FILE" > "$installed_guidance"

  if cmp -s "$GUIDANCE_SRC" "$installed_guidance"; then
    echo "[OK] installed Git guidance matches source"
  else
    echo "[FAIL] installed Git guidance differs from $GUIDANCE_SRC"
    status=1
  fi
  rm -f "$installed_guidance"
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
check_global_git_guidance

echo ""
skill_count=0
for skill_dir in "$SCRIPT_DIR/skills"/*; do
  [[ -d "$skill_dir" ]] || continue

  skill="$(basename "$skill_dir")"
  skill_count=$((skill_count + 1))

  check_path "$skill_dir/SKILL.md" "source SKILL.md for $skill"
  check_path "$skill_dir/agents/openai.yaml" "source agents/openai.yaml for $skill"
  check_path "$SKILLS_DEST/$skill/SKILL.md" "installed SKILL.md for $skill"
  check_path "$SKILLS_DEST/$skill/agents/openai.yaml" "installed agents/openai.yaml for $skill"

  if [[ "$skill" == "equal-experts-workflow" || "$skill" == ee-* ]]; then
    if [[ -L "$SKILLS_DEST/$skill/toolkit" || -d "$SKILLS_DEST/$skill/toolkit" ]]; then
      echo "[OK] EE toolkit linked for $skill"
    else
      echo "[FAIL] EE toolkit not linked for $skill"
      status=1
    fi
  fi
done

if [[ "$skill_count" -eq 0 ]]; then
  echo "[FAIL] no skill directories found under $SCRIPT_DIR/skills"
  status=1
fi

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
