#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="$ROOT/skills/ralph/assets/ralph-pin.env"
RUN_SAFE="$ROOT/skills/ralph/scripts/run-build-no-push.sh"
RUN_PLAN="$ROOT/skills/ralph/scripts/run-plan-guarded.sh"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-ralph-integration.XXXXXX")"
WORKTREE="$TEST_ROOT/worktree"
LOG_DIR="$TEST_ROOT/logs"

# shellcheck source=../installer/lib/common.sh
source "$ROOT/installer/lib/common.sh"
# shellcheck source=../skills/ralph/assets/ralph-pin.env
source "$PIN_FILE"
RALPH_RUNTIME_DIR="$STATE_DIR/ralph-runtimes/$RALPH_PIN_RUNTIME_ID"
RALPH_CONFIG_DIR="${RALPH_CONFIG_DIR:-$RALPH_RUNTIME_DIR/config}"
RALPH_BINARY="${RALPH_BIN_PATH:-${RALPH_BIN_DIR:-$RALPH_RUNTIME_DIR/bin}/ralph}"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

if ! verify_regular_file_sha256 "$RALPH_BINARY" "$RALPH_PIN_CLI_SHA256" ||
  [[ ! -x "$RALPH_BINARY" ]] ||
  ! verify_regular_file_sha256 "$RALPH_CONFIG_DIR/prompts/plan.md" "$RALPH_PIN_PLAN_PROMPT_SHA256" ||
  ! verify_regular_file_sha256 "$RALPH_CONFIG_DIR/prompts/build.md" "$RALPH_PIN_BUILD_PROMPT_SHA256" ||
  ! verify_regular_file_sha256 "$RALPH_CONFIG_DIR/global-skill.env" "$RALPH_PIN_GLOBAL_SKILL_DEFAULTS_SHA256"; then
  echo "[SKIP] pinned Ralph CLI/config are not installed; installer and fake-runtime tests still cover source behavior"
  exit 0
fi

mkdir -p "$WORKTREE" "$LOG_DIR"
git -C "$WORKTREE" init -q
git -C "$WORKTREE" config user.name 'Codex Test'
git -C "$WORKTREE" config user.email 'codex-test@example.invalid'
git -C "$WORKTREE" commit -q --allow-empty -m 'base'
printf '%s\n' '# Plan' '- [ ] Verify safe wrapper integration' > "$WORKTREE/IMPLEMENTATION_PLAN.md"
printf '%s\n' '# Progress' > "$WORKTREE/PROGRESS.md"
head_before="$(git -C "$WORKTREE" rev-parse HEAD)"
index_before="$(git -C "$WORKTREE" write-tree)"
refs_before="$(git -C "$WORKTREE" for-each-ref --format='%(refname)%09%(objectname)')"

(
  cd "$WORKTREE"
  RALPH_BIN_PATH="$RALPH_BINARY" RALPH_CONFIG_DIR="$RALPH_CONFIG_DIR" \
    "$RUN_SAFE" -n 1 --dry-run --yes > "$LOG_DIR/ralph.log"
  RALPH_BIN_PATH="$RALPH_BINARY" RALPH_CONFIG_DIR="$RALPH_CONFIG_DIR" \
    "$RUN_PLAN" -n 1 --dry-run --yes > "$LOG_DIR/ralph-plan.log"
)

[[ ! -e "$WORKTREE/PROMPT_build.md" ]]
[[ ! -e "$WORKTREE/PROMPT_plan.md" ]]
[[ "$(git -C "$WORKTREE" rev-parse HEAD)" == "$head_before" ]]
[[ "$(git -C "$WORKTREE" write-tree)" == "$index_before" ]]
[[ "$(git -C "$WORKTREE" for-each-ref --format='%(refname)%09%(objectname)')" == "$refs_before" ]]
grep -Fq '[dry-run] Prompt content (PROMPT_build.md with goal substituted):' "$LOG_DIR/ralph.log"
grep -Fq 'Backend: codex' "$LOG_DIR/ralph.log"
grep -Fq 'Model:   gpt-5.2-codex' "$LOG_DIR/ralph.log"
grep -Fq 'Do not stage files, create commits, amend history, tag, publish, or write to any remote.' "$LOG_DIR/ralph.log"
grep -Fq '[dry-run] Prompt content (PROMPT_plan.md with goal substituted):' "$LOG_DIR/ralph-plan.log"
grep -Fq 'Backend: codex' "$LOG_DIR/ralph-plan.log"
grep -Fq 'Model:   gpt-5.2-codex' "$LOG_DIR/ralph-plan.log"
grep -Fq 'Do not implement source changes, fix tests, install dependencies, or start a build item.' "$LOG_DIR/ralph-plan.log"

echo "[OK] real pinned Ralph plan/build dry-runs honor the reviewed wrapper contract"
