#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-ralph.XXXXXX")"
TEST_RUNTIME="$TEST_ROOT/ralph-skill"
TEST_CODEX_BIN="$TEST_ROOT/codex-bin"
export CODEX_GLOBAL_SKILLS_HOME="$TEST_ROOT/state"
mkdir -p "$TEST_RUNTIME"
cp -R "$ROOT/skills/ralph/scripts" "$TEST_RUNTIME/scripts"
cp -R "$ROOT/skills/ralph/assets" "$TEST_RUNTIME/assets"
PREPARE="$TEST_RUNTIME/scripts/prepare-safe-build-prompt.sh"
RUN_SAFE="$TEST_RUNTIME/scripts/run-build-no-push.sh"
RUN_PLAN="$TEST_RUNTIME/scripts/run-plan-guarded.sh"
INIT_SAFE="$TEST_RUNTIME/scripts/init-safe.sh"
RUN_SANDBOX="$TEST_RUNTIME/scripts/run-sandbox-guarded.sh"
SAFE_TEMPLATE="$TEST_RUNTIME/assets/PROMPT_build.safe.md"
mkdir -p "$TEST_CODEX_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-cli 0.144.4"' > "$TEST_CODEX_BIN/codex"
printf '%s\n' '#!/usr/bin/env bash' 'echo "0.87.0"' > "$TEST_CODEX_BIN/devcontainer"
chmod +x "$TEST_CODEX_BIN/codex" "$TEST_CODEX_BIN/devcontainer"
PATH="$TEST_CODEX_BIN:$PATH"
export PATH

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail_test() {
  echo "[FAIL] $1" >&2
  exit 1
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

set_test_pin_value() {
  local key="$1"
  local value="$2"
  local pin_file="$TEST_RUNTIME/assets/ralph-pin.env"
  local next_pin="$TEST_RUNTIME/assets/.ralph-pin.next"

  awk -v key="$key" -v value="$value" '
    index($0, key "=") == 1 { print key "=" value; next }
    { print }
  ' "$pin_file" > "$next_pin"
  mv "$next_pin" "$pin_file"
}

set_test_ralph_pin() {
  set_test_pin_value RALPH_PIN_CLI_SHA256 "$(sha256_file "$1")"
  local runtime_id
  runtime_id="$(awk -F= '$1 == "RALPH_PIN_RUNTIME_ID" { print $2 }' "$TEST_RUNTIME/assets/ralph-pin.env")"
  mkdir -p "$CODEX_GLOBAL_SKILLS_HOME/ralph-runtimes/$runtime_id/config"
  cp "$TEST_RUNTIME/assets/global-skill.env" "$CODEX_GLOBAL_SKILLS_HOME/ralph-runtimes/$runtime_id/config/global-skill.env"
}

set_test_sandbox_pin() {
  local config="$1"
  local codex_version="${2:-0.144.4}"
  local safe_dockerfile="$TEST_RUNTIME/assets/Dockerfile.safe"
  local next_dockerfile="$TEST_RUNTIME/assets/.Dockerfile.safe.next"

  sed -E "s#@openai/codex@[0-9]+\\.[0-9]+\\.[0-9]+#@openai/codex@$codex_version#" "$safe_dockerfile" > "$next_dockerfile"
  mv "$next_dockerfile" "$safe_dockerfile"
  set_test_pin_value RALPH_PIN_CODEX_VERSION "$codex_version"
  set_test_pin_value RALPH_PIN_PLAN_PROMPT_SHA256 "$(sha256_file "$config/prompts/plan.md")"
  set_test_pin_value RALPH_PIN_BUILD_PROMPT_SHA256 "$(sha256_file "$config/prompts/build.md")"
  cp "$TEST_RUNTIME/assets/global-skill.env" "$config/global-skill.env"
  set_test_pin_value RALPH_PIN_GLOBAL_SKILL_DEFAULTS_SHA256 "$(sha256_file "$config/global-skill.env")"
  set_test_pin_value RALPH_PIN_CONTAINER_DOCKERFILE_SHA256 "$(sha256_file "$config/container/Dockerfile")"
  set_test_pin_value RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256 "$(sha256_file "$config/container/devcontainer.json")"
  set_test_pin_value RALPH_PIN_SAFE_DOCKERFILE_SHA256 "$(sha256_file "$safe_dockerfile")"
  set_test_pin_value RALPH_PIN_SAFE_DEVCONTAINER_SHA256 "$(sha256_file "$TEST_RUNTIME/assets/devcontainer.safe.json")"
}

write_unsafe_prompt() {
  local destination="$1"
  local config_dir

  mkdir -p "$(dirname "$destination")"
  if [[ "$destination" == */prompts/build.md ]]; then
    config_dir="$(dirname "$(dirname "$destination")")"
    cp "$TEST_RUNTIME/assets/global-skill.env" "$config_dir/global-skill.env"
  fi
  printf '%s\n' \
    '# Build Agent' \
    '- If tests unrelated to your work fail, resolve them as part of this increment' \
    '## Finalise' \
    '3. Commit the changes by invoking the **`/commit` skill**.' \
    '4. `git push`' \
    '5. Stop.' > "$destination"
}

write_unsafe_plan_prompt() {
  local destination="$1"
  local config_dir

  mkdir -p "$(dirname "$destination")"
  if [[ "$destination" == */prompts/plan.md ]]; then
    config_dir="$(dirname "$(dirname "$destination")")"
    cp "$TEST_RUNTIME/assets/global-skill.env" "$config_dir/global-skill.env"
  fi
  printf '%s\n' \
    '# Planning Agent' \
    'You are a planning agent in an autonomous loop.' \
    'Create or update `IMPLEMENTATION_PLAN.md`.' \
    '- **Plan only. Do NOT implement anything.**' > "$destination"
}

test_prompt_sanitization() {
  local source="$TEST_ROOT/unsafe.md"
  local output="$TEST_ROOT/safe.md"
  local race_output="$TEST_ROOT/race/PROMPT_build.md"
  local race_bin="$TEST_ROOT/race-bin"
  local real_ln

  write_unsafe_prompt "$source"
  "$PREPARE" "$source" "$output"
  cmp -s "$SAFE_TEMPLATE" "$output" || fail_test "generated prompt differs from the reviewed template"
  grep -Fq 'Do not stage files, create commits' "$output" || fail_test "safe prompt lacks the no-commit boundary"
  grep -Fq 'Do not fix unrelated baseline failures' "$output" || fail_test "safe prompt lacks the scope boundary"
  if grep -Fq '/commit' "$output" || grep -Fq 'Co-Authored-By:' "$output" || grep -Fq 'Conventional Commits' "$output"; then
    fail_test "safe prompt retained Ralph's opinionated commit policy"
  fi
  if "$PREPARE" "$source" "$output" >/dev/null 2>&1; then
    fail_test "prompt generator overwrote an existing file"
  fi
  printf '%s\n' '# changed upstream prompt' > "$source"
  rm -f "$output"
  if "$PREPARE" "$source" "$output" >"$TEST_ROOT/drift.log" 2>&1; then
    fail_test "prompt generator accepted an unknown upstream contract"
  fi
  grep -Fq 'differs from the reviewed pinned contract' "$TEST_ROOT/drift.log" || fail_test "upstream prompt drift failure was not actionable"

  write_unsafe_prompt "$source"
  mkdir -p "$race_bin"
  real_ln="$(command -v ln)"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "concurrent user prompt" > "$2"' \
    'exec "$REAL_LN" "$@"' > "$race_bin/ln"
  chmod +x "$race_bin/ln"
  if PATH="$race_bin:$PATH" REAL_LN="$real_ln" "$PREPARE" "$source" "$race_output" >"$TEST_ROOT/race.log" 2>&1; then
    fail_test "prompt generator overwrote a concurrently created destination"
  fi
  grep -Fqx 'concurrent user prompt' "$race_output" || fail_test "prompt generator did not preserve the concurrent destination"
  grep -Fq 'destination appeared during preparation' "$TEST_ROOT/race.log" || fail_test "prompt publish race failure was not actionable"
  echo "[OK] Ralph build prompt substitution is reviewed and fail-closed"
}

test_getopt_compatibility_is_scoped() {
  local compat="$TEST_RUNTIME/scripts/compat/getopt"
  local delegate="$TEST_ROOT/delegate-getopt"
  local parsed
  local delegated

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "delegated:%s\n" "$*"' > "$delegate"
  chmod +x "$delegate"

  parsed="$(RALPH_SYSTEM_GETOPT="$delegate" "$compat" -o n:g:m:b:vyh --long iterations:,goal:,model:,backend:,skip-push,dry-run,verbose,yes,help -n ralph -- --skip-push -bcodex -n1 --dry-run --yes)"
  [[ "$parsed" == *'--skip-push -b codex -n 1 --dry-run --yes -- '* ]] || fail_test "getopt helper did not parse Ralph's exact option schema"
  delegated="$(RALPH_SYSTEM_GETOPT="$delegate" "$compat" --foreign option)"
  [[ "$delegated" == 'delegated:--foreign option' ]] || fail_test "getopt helper did not delegate an unrelated invocation"
  echo "[OK] Ralph getopt compatibility is narrowly scoped"
}

test_runner_blocks_configured_remote() {
  local repository="$TEST_ROOT/repository"
  local fake_bin="$TEST_ROOT/bin"
  local config="$TEST_ROOT/config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  git -C "$repository" remote add origin https://example.invalid/repository.git
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'mode="$1"; shift' \
    'ARGS=$(getopt -o n:g:m:b:vyh --long iterations:,goal:,model:,backend:,skip-push,dry-run,verbose,yes,help -n ralph -- "$@")' \
    'eval set -- "$ARGS"' \
    'printf "%s %s\n" "$mode" "$*" > "$RALPH_TEST_ROOT/args"' \
    'printf "%s\n" "${GIT_CONFIG_COUNT:-}" > "$RALPH_TEST_ROOT/config-count"' \
    'git config --get remote.origin.pushurl > "$RALPH_TEST_ROOT/pushurl"' \
    'cp PROMPT_build.md "$RALPH_TEST_ROOT/prompt-used"' \
    'if git push origin HEAD >"$RALPH_TEST_ROOT/push-output" 2>&1; then exit 91; fi' \
    'printf "%s\n" blocked > "$RALPH_TEST_ROOT/push-result"' \
    'if git push https://example.invalid/direct.git HEAD >"$RALPH_TEST_ROOT/direct-push-output" 2>&1; then exit 92; fi' \
    'printf "%s\n" blocked > "$RALPH_TEST_ROOT/direct-push-result"' > "$managed_ralph"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" shadowed > "$RALPH_TEST_ROOT/path-shadow"' 'exit 93' > "$fake_bin/ralph"
  chmod +x "$managed_ralph" "$fake_bin/ralph"
  set_test_ralph_pin "$managed_ralph"

  (
    cd "$repository"
    PATH="$fake_bin:$PATH" \
      RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      RALPH_TEST_ROOT="$TEST_ROOT" \
      "$RUN_SAFE" -b codex -n 1
  )

  grep -Fq 'build --skip-push -b codex -n 1' "$TEST_ROOT/args" ||
    fail_test "safe runner did not enforce Ralph skip-push before caller arguments"
  grep -Fqx 'disabled://codex-global-skills/no-remote-write' "$TEST_ROOT/pushurl" || fail_test "safe runner did not override the configured push URL"
  grep -Fqx blocked "$TEST_ROOT/push-result" || fail_test "configured remote write was not blocked"
  grep -Fqx blocked "$TEST_ROOT/direct-push-result" || fail_test "literal-URL Git push was not blocked"
  grep -Fq 'Blocked Git remote-write command' "$TEST_ROOT/direct-push-output" || fail_test "literal-URL push guard was not actionable"
  [[ ! -e "$TEST_ROOT/path-shadow" ]] || fail_test "wrapper executed the PATH-shadowing Ralph binary"
  [[ ! -e "$repository/PROMPT_build.md" ]] || fail_test "temporary safe prompt was not cleaned up"
  cmp -s "$SAFE_TEMPLATE" "$TEST_ROOT/prompt-used" || fail_test "runner supplied an unreviewed prompt"

  if (
    cd "$repository"
    GIT_CONFIG_PARAMETERS="'remote.origin.pushurl=https://example.invalid/bypass.git'" \
      RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      RALPH_TEST_ROOT="$TEST_ROOT" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/config-parameters.log" 2>&1; then
    fail_test "wrapper accepted inherited GIT_CONFIG_PARAMETERS"
  fi
  grep -Fq 'GIT_CONFIG_PARAMETERS would conflict' "$TEST_ROOT/config-parameters.log" || fail_test "GIT_CONFIG_PARAMETERS failure was not actionable"

  for iteration_option in -n2 --iterations=2; do
    if (
      cd "$repository"
      RALPH_BIN_PATH="$managed_ralph" \
        RALPH_CONFIG_DIR="$config" \
        RALPH_TEST_ROOT="$TEST_ROOT" \
        "$RUN_SAFE" "$iteration_option"
    ) >"$TEST_ROOT/iteration.log" 2>&1; then
      fail_test "guarded build accepted multiple iterations via $iteration_option"
    fi
    grep -Fq 'accepts exactly one iteration' "$TEST_ROOT/iteration.log" || fail_test "multiple-iteration failure was not actionable"
  done
  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      RALPH_TEST_ROOT="$TEST_ROOT" \
      "$RUN_SAFE" -b codex -vbclaude
  ) >"$TEST_ROOT/backend-cluster.log" 2>&1; then
    fail_test "guarded build accepted a non-Codex backend hidden in a short-option cluster"
  fi
  grep -Fq 'supports only the pinned Codex backend' "$TEST_ROOT/backend-cluster.log" || fail_test "clustered backend failure was not actionable"
  echo "[OK] Ralph safe runner blocks configured remote writes"
}

test_runner_preserves_existing_prompt() {
  local repository="$TEST_ROOT/existing-prompt"
  local fake_bin="$TEST_ROOT/existing-bin"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  write_unsafe_prompt "$repository/PROMPT_build.md"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 92' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/existing.log" 2>&1; then
    fail_test "safe runner accepted an unsafe project prompt"
  fi
  grep -Fq 'does not exactly match the reviewed guarded prompt' "$TEST_ROOT/existing.log" || fail_test "unsafe prompt failure was not actionable"
  grep -Fq '`git push`' "$repository/PROMPT_build.md" || fail_test "safe runner altered the project prompt"
  echo "[OK] Ralph safe runner preserves existing project prompts"
}

test_runner_leaves_repository_commit_policy_to_supervisor() {
  local repository="$TEST_ROOT/repository-policy"
  local fake_bin="$TEST_ROOT/policy-bin"
  local config="$TEST_ROOT/policy-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local head_before

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  printf '%s\n' 'Commit subjects must start with ABC-123 in uppercase.' 'Do not add generated attribution.' > "$repository/AGENTS.md"
  git -C "$repository" add AGENTS.md
  git -C "$repository" commit -q -m 'ABC-100 INITIAL BASELINE'
  head_before="$(git -C "$repository" rev-parse HEAD)"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cp PROMPT_build.md "$RALPH_TEST_ROOT/policy-prompt-used"' \
    'printf "%s\n" implementation > parser.txt' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      RALPH_TEST_ROOT="$TEST_ROOT" \
      "$RUN_SAFE" -b codex -n 1
  )

  [[ "$(git -C "$repository" rev-parse HEAD)" == "$head_before" ]] || fail_test "Ralph wrapper changed HEAD instead of leaving commit policy to the supervisor"
  [[ -f "$repository/parser.txt" ]] || fail_test "fake build did not leave an implementation result"
  cmp -s "$SAFE_TEMPLATE" "$TEST_ROOT/policy-prompt-used" || fail_test "policy fixture did not receive the reviewed prompt"
  if grep -Fq '/commit' "$TEST_ROOT/policy-prompt-used" || grep -Fq 'Co-Authored-By:' "$TEST_ROOT/policy-prompt-used" || grep -Fq 'Conventional Commits' "$TEST_ROOT/policy-prompt-used"; then
    fail_test "Ralph prompt overrode the repository's commit or attribution policy"
  fi
  echo "[OK] Ralph leaves repository commit and attribution policy to global commit"
}

test_runner_fails_when_backend_changes_head() {
  local repository="$TEST_ROOT/head-invariant"
  local fake_bin="$TEST_ROOT/head-bin"
  local config="$TEST_ROOT/head-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local head_before

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  head_before="$(git -C "$repository" rev-parse HEAD)"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'git commit --allow-empty -q -m "backend policy violation"' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/head.log" 2>&1; then
    fail_test "wrapper accepted a backend-created commit"
  fi

  [[ "$(git -C "$repository" rev-parse HEAD)" != "$head_before" ]] || fail_test "HEAD-invariant fixture did not create its policy-violation commit"
  grep -Fq 'changed HEAD despite the guarded prompt' "$TEST_ROOT/head.log" || fail_test "HEAD-invariant failure was not actionable"
  git -C "$repository" log -1 --format=%s | grep -Fqx 'backend policy violation' || fail_test "wrapper did not preserve the unexpected commit for review"
  echo "[OK] Ralph wrapper enforces HEAD invariance and preserves evidence"
}

test_runner_fails_when_backend_changes_other_refs() {
  local repository="$TEST_ROOT/ref-invariant"
  local fake_bin="$TEST_ROOT/ref-bin"
  local config="$TEST_ROOT/ref-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local head_before

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  head_before="$(git -C "$repository" rev-parse HEAD)"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'git tag backend-policy-violation' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/ref.log" 2>&1; then
    fail_test "wrapper accepted a backend-created tag"
  fi

  [[ "$(git -C "$repository" rev-parse HEAD)" == "$head_before" ]] || fail_test "ref-invariant fixture unexpectedly changed HEAD"
  git -C "$repository" show-ref --verify --quiet refs/tags/backend-policy-violation || fail_test "wrapper did not preserve the unexpected tag for review"
  grep -Fq 'changed local Git refs despite the no-history prompt' "$TEST_ROOT/ref.log" || fail_test "ref-invariant failure was not actionable"
  echo "[OK] Ralph wrapper detects non-HEAD ref changes"
}

test_runner_fails_when_backend_retargets_symbolic_ref() {
  local repository="$TEST_ROOT/symref-invariant"
  local fake_bin="$TEST_ROOT/symref-bin"
  local config="$TEST_ROOT/symref-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  git -C "$repository" update-ref refs/remotes/origin/main HEAD
  git -C "$repository" update-ref refs/remotes/origin/alternate HEAD
  git -C "$repository" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/alternate' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/symref.log" 2>&1; then
    fail_test "wrapper accepted a same-OID symbolic-ref retarget"
  fi

  [[ "$(git -C "$repository" symbolic-ref refs/remotes/origin/HEAD)" == 'refs/remotes/origin/alternate' ]] || fail_test "symbolic-ref evidence was not preserved"
  grep -Fq 'changed local Git refs despite the no-history prompt' "$TEST_ROOT/symref.log" || fail_test "symbolic-ref failure was not actionable"
  echo "[OK] Ralph wrapper detects same-OID symbolic-ref retargeting"
}

test_runner_fails_when_backend_switches_same_commit_branch() {
  local repository="$TEST_ROOT/head-identity"
  local fake_bin="$TEST_ROOT/head-identity-bin"
  local config="$TEST_ROOT/head-identity-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local head_before

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  git -C "$repository" branch alternate
  head_before="$(git -C "$repository" symbolic-ref HEAD)"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'git switch -q alternate' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/head-identity.log" 2>&1; then
    fail_test "wrapper accepted a same-commit branch switch"
  fi

  [[ "$(git -C "$repository" symbolic-ref HEAD)" != "$head_before" ]] || fail_test "HEAD-identity fixture did not switch branches"
  grep -Fq 'changed the symbolic or detached HEAD identity' "$TEST_ROOT/head-identity.log" || fail_test "HEAD-identity failure was not actionable"
  echo "[OK] Ralph wrapper detects same-commit branch identity changes"
}

test_runner_fails_when_backend_changes_repository_config() {
  local repository="$TEST_ROOT/config-invariant"
  local fake_bin="$TEST_ROOT/config-bin"
  local config="$TEST_ROOT/config-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local external_config="$TEST_ROOT/external-git-config"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  git -C "$repository" remote add origin https://example.invalid/original.git
  mv "$repository/.git/config" "$external_config"
  ln -s "$external_config" "$repository/.git/config"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'git remote set-url origin https://example.invalid/attacker.git' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/config-invariant.log" 2>&1; then
    fail_test "wrapper accepted a persistent remote URL change"
  fi

  [[ "$(git -C "$repository" remote get-url origin)" == 'https://example.invalid/attacker.git' ]] || fail_test "repository-config evidence was not preserved"
  grep -Fq 'changed repository Git configuration, hooks, excludes, or alternates' "$TEST_ROOT/config-invariant.log" || fail_test "repository-config failure was not actionable"
  echo "[OK] Ralph wrapper detects persistent Git metadata changes"
}

test_runner_fails_when_backend_changes_effective_hooks() {
  local repository="$TEST_ROOT/hooks-invariant"
  local fake_bin="$TEST_ROOT/hooks-bin"
  local config="$TEST_ROOT/hooks-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local external_hooks="$TEST_ROOT/external-hooks"

  mkdir -p "$repository" "$external_hooks" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" config core.hooksPath .githooks
  git -C "$repository" commit -q --allow-empty -m 'base'
  ln -s "$external_hooks" "$repository/.githooks"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$external_hooks/pre-commit"
  chmod +x "$external_hooks/pre-commit"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "#!/usr/bin/env bash" "exit 99" > .githooks/pre-commit' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/hooks-invariant.log" 2>&1; then
    fail_test "wrapper accepted a change to the effective hooks path"
  fi

  grep -Fqx 'exit 99' "$external_hooks/pre-commit" || fail_test "effective-hook evidence was not preserved"
  grep -Fq 'changed repository Git configuration, hooks, excludes, or alternates' "$TEST_ROOT/hooks-invariant.log" || fail_test "effective-hook failure was not actionable"
  echo "[OK] Ralph wrapper detects effective hooks-path and symlink-referent changes"
}

test_runner_fails_when_backend_retargets_broken_hook_chain() {
  local repository="$TEST_ROOT/broken-hook-invariant"
  local fake_bin="$TEST_ROOT/broken-hook-bin"
  local config="$TEST_ROOT/broken-hook-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" config core.hooksPath .githooks
  git -C "$repository" commit -q --allow-empty -m 'base'
  ln -s hook-target "$repository/.githooks"
  ln -s missing-one "$repository/hook-target"
  write_unsafe_prompt "$config/prompts/build.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'rm hook-target' \
    'ln -s missing-two hook-target' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/broken-hook.log" 2>&1; then
    fail_test "wrapper accepted a retarget inside a broken hook symlink chain"
  fi

  [[ "$(readlink "$repository/hook-target")" == 'missing-two' ]] || fail_test "broken-hook retarget evidence was not preserved"
  grep -Fq 'changed repository Git configuration, hooks, excludes, or alternates' "$TEST_ROOT/broken-hook.log" || fail_test "broken-hook failure was not actionable"
  echo "[OK] Ralph wrapper serializes broken security-symlink chains"
}

test_runner_fails_when_backend_changes_reviewed_prompt() {
  local repository="$TEST_ROOT/prompt-invariant"
  local fake_bin="$TEST_ROOT/prompt-bin"
  local config="$TEST_ROOT/prompt-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  mkdir -p "$config/prompts"
  cp "$TEST_RUNTIME/assets/global-skill.env" "$config/global-skill.env"
  cp "$SAFE_TEMPLATE" "$repository/PROMPT_build.md"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" tampered >> PROMPT_build.md' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" RALPH_CONFIG_DIR="$config" "$RUN_SAFE" -b codex -n 1
  ) >"$TEST_ROOT/prompt-invariant.log" 2>&1; then
    fail_test "wrapper accepted a changed reviewed prompt"
  fi
  grep -Fq 'changed or removed the reviewed PROMPT_build.md' "$TEST_ROOT/prompt-invariant.log" || fail_test "prompt-invariant failure was not actionable"
  grep -Fq tampered "$repository/PROMPT_build.md" || fail_test "wrapper did not preserve the changed prompt as evidence"
  echo "[OK] guarded Ralph detects reviewed-prompt mutation"
}

test_safe_init_preserves_project_git_files() {
  local repository="$TEST_ROOT/safe-init"
  local ignore_hash
  local commit_skill_hash

  mkdir -p "$repository/.claude/skills/commit"
  git -C "$repository" init -q
  printf '%s\n' 'user-owned-ignore' > "$repository/.gitignore"
  printf '%s\n' 'user-owned commit policy' > "$repository/.claude/skills/commit/SKILL.md"
  ignore_hash="$(sha256_file "$repository/.gitignore")"
  commit_skill_hash="$(sha256_file "$repository/.claude/skills/commit/SKILL.md")"

  (
    cd "$repository"
    "$INIT_SAFE" > "$TEST_ROOT/init.log"
    "$INIT_SAFE" > "$TEST_ROOT/init-second.log"
  )

  [[ "$(sha256_file "$repository/.gitignore")" == "$ignore_hash" ]] || fail_test "safe init changed the project .gitignore"
  [[ "$(sha256_file "$repository/.claude/skills/commit/SKILL.md")" == "$commit_skill_hash" ]] || fail_test "safe init changed the project commit skill"
  [[ -f "$repository/IMPLEMENTATION_PLAN.md" && -f "$repository/PROGRESS.md" && -d "$repository/specs" ]] || fail_test "safe init did not create required Ralph artifacts"
  grep -Fq 'Left .gitignore and .claude/ unchanged' "$TEST_ROOT/init.log" || fail_test "safe init did not report its preservation boundary"
  grep -Fq 'Preserved: IMPLEMENTATION_PLAN.md' "$TEST_ROOT/init-second.log" || fail_test "safe init was not idempotent"
  echo "[OK] safe Ralph init preserves Git ignore and commit policy"
}

test_safe_init_preflights_all_artifacts() {
  local repository="$TEST_ROOT/init-preflight"
  local outside="$TEST_ROOT/outside-progress"

  mkdir -p "$repository"
  git -C "$repository" init -q
  printf '%s\n' 'outside' > "$outside"
  ln -s "$outside" "$repository/PROGRESS.md"

  if (
    cd "$repository"
    "$INIT_SAFE"
  ) >"$TEST_ROOT/init-preflight.log" 2>&1; then
    fail_test "safe init accepted a symbolic-link artifact"
  fi
  [[ ! -e "$repository/specs" && ! -e "$repository/IMPLEMENTATION_PLAN.md" ]] || fail_test "safe init mutated before completing artifact preflight"
  grep -Fq 'not a regular file: PROGRESS.md' "$TEST_ROOT/init-preflight.log" || fail_test "safe init preflight failure was not actionable"
  grep -Fqx outside "$outside" || fail_test "safe init changed the symlink target"
  echo "[OK] safe Ralph init preflights every artifact before mutation"
}

test_plan_uses_guarded_managed_runtime() {
  local repository="$TEST_ROOT/safe-plan"
  local fake_bin="$TEST_ROOT/plan-bin"
  local config="$TEST_ROOT/plan-config"
  local managed_ralph="$fake_bin/managed-ralph"
  local head_before

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  (
    cd "$repository"
    "$INIT_SAFE" >/dev/null
  )
  head_before="$(git -C "$repository" rev-parse HEAD)"
  write_unsafe_plan_prompt "$config/prompts/plan.md"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'mode="$1"; shift' \
    'ARGS=$(getopt -o n:g:m:b:vyh --long iterations:,goal:,model:,backend:,skip-push,dry-run,verbose,yes,help -n ralph -- "$@")' \
    'eval set -- "$ARGS"' \
    'printf "%s %s\n" "$mode" "$*" > "$RALPH_TEST_ROOT/plan-args"' \
    'cp PROMPT_plan.md "$RALPH_TEST_ROOT/plan-prompt-used"' \
    'printf "%s\n" "- [ ] Planned item" >> IMPLEMENTATION_PLAN.md' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      RALPH_TEST_ROOT="$TEST_ROOT" \
      "$RUN_PLAN" -b codex -n 1 -g 'Plan the parser'
  )

  [[ "$(git -C "$repository" rev-parse HEAD)" == "$head_before" ]] || fail_test "guarded plan changed HEAD"
  cmp -s "$TEST_RUNTIME/assets/PROMPT_plan.safe.md" "$TEST_ROOT/plan-prompt-used" || fail_test "guarded plan did not use the reviewed prompt"
  grep -Fq 'plan --skip-push -b codex -n 1 -g Plan the parser --' "$TEST_ROOT/plan-args" ||
    fail_test "guarded plan did not enforce the managed option path"
  grep -Fq 'Planned item' "$repository/IMPLEMENTATION_PLAN.md" || fail_test "guarded plan fixture produced no plan result"
  [[ ! -e "$repository/PROMPT_plan.md" ]] || fail_test "guarded plan left its generated prompt"
  echo "[OK] Ralph planning uses the guarded managed runtime"
}

test_plan_rejects_source_mutation() {
  local repository="$TEST_ROOT/plan-scope"
  local fake_bin="$TEST_ROOT/plan-scope-bin"
  local config="$TEST_ROOT/plan-scope-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository/src" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  printf '%s\n' original > "$repository/src/app.ts"
  git -C "$repository" add src/app.ts
  git -C "$repository" commit -q -m 'base'
  (
    cd "$repository"
    "$INIT_SAFE" >/dev/null
  )
  write_unsafe_plan_prompt "$config/prompts/plan.md"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" mutated > src/app.ts' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" RALPH_CONFIG_DIR="$config" "$RUN_PLAN" -b codex -n 1
  ) >"$TEST_ROOT/plan-scope.log" 2>&1; then
    fail_test "guarded plan accepted a source mutation"
  fi
  grep -Fq 'changed Git-visible paths outside IMPLEMENTATION_PLAN.md or specs/' "$TEST_ROOT/plan-scope.log" || fail_test "plan scope failure was not actionable"
  grep -Fqx mutated "$repository/src/app.ts" || fail_test "plan scope guard did not preserve mutation evidence"
  echo "[OK] guarded Ralph planning rejects source mutation"
}

test_plan_rejects_nested_repository_mutation() {
  local repository="$TEST_ROOT/plan-nested"
  local fake_bin="$TEST_ROOT/plan-nested-bin"
  local config="$TEST_ROOT/plan-nested-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  (
    cd "$repository"
    "$INIT_SAFE" >/dev/null
  )
  write_unsafe_plan_prompt "$config/prompts/plan.md"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'mkdir nested' \
    'git -C nested init -q' \
    'printf "%s\n" nested > nested/source.txt' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" RALPH_CONFIG_DIR="$config" "$RUN_PLAN" -b codex -n 1
  ) >"$TEST_ROOT/plan-nested.log" 2>&1; then
    fail_test "guarded plan accepted an out-of-scope nested repository"
  fi
  grep -Fq 'changed Git-visible paths outside IMPLEMENTATION_PLAN.md or specs/' "$TEST_ROOT/plan-nested.log" || fail_test "nested-repository scope failure was not actionable"
  [[ -d "$repository/nested/.git" && -f "$repository/nested/source.txt" ]] || fail_test "nested-repository evidence was not preserved"
  echo "[OK] guarded Ralph planning detects nested repository mutation"
}

test_plan_rejects_dirty_submodule_mutation() {
  local repository="$TEST_ROOT/plan-submodule"
  local child="$TEST_ROOT/plan-submodule-child"
  local fake_bin="$TEST_ROOT/plan-submodule-bin"
  local config="$TEST_ROOT/plan-submodule-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$child" "$fake_bin"
  git -C "$child" init -q
  git -C "$child" config user.name 'Codex Test'
  git -C "$child" config user.email 'codex-test@example.invalid'
  printf '%s\n' original > "$child/source.txt"
  git -C "$child" add source.txt
  git -C "$child" commit -q -m 'child base'

  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" -c protocol.file.allow=always submodule add -q "$child" modules/child
  git -C "$repository" commit -q -am 'parent base'
  printf '%s\n' baseline-dirty > "$repository/modules/child/source.txt"
  (
    cd "$repository"
    "$INIT_SAFE" >/dev/null
  )
  write_unsafe_plan_prompt "$config/prompts/plan.md"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" mutated-by-plan > modules/child/source.txt' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  if (
    cd "$repository"
    RALPH_BIN_PATH="$managed_ralph" RALPH_CONFIG_DIR="$config" "$RUN_PLAN" -b codex -n 1
  ) >"$TEST_ROOT/plan-submodule.log" 2>&1; then
    fail_test "guarded plan accepted a mutation hidden inside an already-dirty submodule"
  fi
  grep -Fq 'changed Git-visible paths outside IMPLEMENTATION_PLAN.md or specs/' "$TEST_ROOT/plan-submodule.log" || fail_test "dirty-submodule scope failure was not actionable"
  grep -Fqx mutated-by-plan "$repository/modules/child/source.txt" || fail_test "dirty-submodule mutation evidence was not preserved"
  echo "[OK] guarded Ralph planning detects changes inside dirty submodules"
}

test_runner_resolves_devcontainer_mount() {
  local repository="$TEST_ROOT/devcontainer"
  local fake_bin="$TEST_ROOT/devcontainer-bin"
  local config="$TEST_ROOT/devcontainer-config"
  local managed_ralph="$fake_bin/managed-ralph"

  mkdir -p "$repository" "$fake_bin"
  git -C "$repository" init -q
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'base'
  mkdir -p "$config/prompts"
  cp "$TEST_RUNTIME/assets/global-skill.env" "$config/global-skill.env"
  cp "$SAFE_TEMPLATE" "$repository/PROMPT_build.md"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" sandbox > "$RALPH_TEST_ROOT/devcontainer-result"' \
    'printf "%s\n" "$*" > "$RALPH_TEST_ROOT/devcontainer-args"' > "$managed_ralph"
  chmod +x "$managed_ralph"
  set_test_ralph_pin "$managed_ralph"

  (
    cd "$repository"
    DEVCONTAINER=true \
      HOME="$TEST_ROOT/container-home" \
      RALPH_SANDBOX_BIN_PATH="$managed_ralph" \
      RALPH_CONFIG_DIR="$config" \
      RALPH_TEST_ROOT="$TEST_ROOT" \
      "$RUN_SAFE"
  )

  grep -Fqx sandbox "$TEST_ROOT/devcontainer-result" || fail_test "guarded runner did not resolve the devcontainer Ralph mount"
  grep -Fq 'build --skip-push --iterations 1 --backend codex' "$TEST_ROOT/devcontainer-args" ||
    fail_test "guarded runner did not enforce one iteration and the pinned Codex backend"
  echo "[OK] guarded Ralph resolves the verified devcontainer mount"
}

test_sandbox_launcher_mounts_verified_ralph() {
  local fake_bin="$TEST_ROOT/sandbox-bin"
  local managed_dir="$fake_bin/managed"
  local managed_ralph="$managed_dir/ralph"
  local config="$TEST_ROOT/sandbox-source-config"
  local state="$TEST_ROOT/sandbox-state"
  local first_config
  local second_config

  mkdir -p "$fake_bin" "$managed_dir" "$config/container"
  managed_dir="$(cd "$managed_dir" && pwd -P)"
  managed_ralph="$managed_dir/ralph"
  write_unsafe_prompt "$config/prompts/build.md"
  write_unsafe_plan_prompt "$config/prompts/plan.md"
  printf '%s\n' 'FROM node:20' 'RUN npm install -g @openai/codex' > "$config/container/Dockerfile"
  printf '%s\n' '{}' > "$config/container/devcontainer.json"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$*" == "sandbox clean" ]]; then printf "%s\n" "$*" > "$RALPH_TEST_ROOT/sandbox-args"; exit 0; fi' \
    'printf "%s\n" "$*" > "$RALPH_TEST_ROOT/sandbox-args"' \
    'printf "%s\n" "$RALPH_CONFIG_DIR" > "$RALPH_TEST_ROOT/sandbox-config-path"' \
    'printf "%s\n" "$HOME" > "$RALPH_TEST_ROOT/sandbox-home"' \
    'printf "%s\n" "$RALPH_GUARDED_SKILL_DIR" > "$RALPH_TEST_ROOT/sandbox-skill-path"' \
    'grep -Eq "npm install -g @openai/codex@[0-9]+\\.[0-9]+\\.[0-9]+" "$RALPH_CONFIG_DIR/container/Dockerfile"' \
    '! grep -Eq "docker\\.sock|network=host" "$RALPH_CONFIG_DIR/container/devcontainer.json"' \
    'grep -Fq "target=/home/node/.codex/skills/ralph,type=bind,readonly" "$RALPH_CONFIG_DIR/container/devcontainer.json"' \
    'command -v ralph > "$RALPH_TEST_ROOT/sandbox-mounted-path"' \
    'if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$(command -v ralph)" | awk "{print \$1}"; else sha256sum "$(command -v ralph)" | awk "{print \$1}"; fi > "$RALPH_TEST_ROOT/sandbox-mounted-hash"' > "$managed_ralph"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" shadowed > "$RALPH_TEST_ROOT/sandbox-shadow"' > "$fake_bin/ralph"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$1" == "ps" ]]; then printf "%s\n" abc123 def456 abc789; exit 0; fi' \
    'if [[ "$1" == "inspect" ]]; then' \
    '  case "${!#}" in' \
    '    abc123) printf "%s\n" "$CODEX_GLOBAL_SKILLS_HOME/ralph-sandbox-configs/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/container/devcontainer.json" ;;' \
    '    def456) printf "%s\n" "$CODEX_GLOBAL_SKILLS_HOME/ralph-sandbox-configs/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/container/devcontainer.json" ;;' \
    '    abc789) printf "%s\n" "$RALPH_TEST_ROOT/unrelated/.devcontainer/devcontainer.json" ;;' \
    '  esac' \
    '  exit 0' \
    'fi' \
    'if [[ "$1" == "rm" && "$2" == "-f" ]]; then printf "%s\n" "$3" >> "$RALPH_TEST_ROOT/sandbox-cleaned"; exit 0; fi' \
    'exit 91' > "$fake_bin/docker"
  chmod +x "$managed_ralph" "$fake_bin/ralph" "$fake_bin/docker"
  set_test_ralph_pin "$managed_ralph"
  set_test_sandbox_pin "$config"

  PATH="$fake_bin:$PATH" \
    RALPH_BIN_PATH="$managed_ralph" \
    RALPH_CONFIG_DIR="$config" \
    CODEX_GLOBAL_SKILLS_HOME="$state" \
    RALPH_TEST_ROOT="$TEST_ROOT" \
    "$RUN_SANDBOX" --rebuild >"$TEST_ROOT/sandbox-launch.log" 2>&1

  grep -Fqx 'sandbox --rebuild' "$TEST_ROOT/sandbox-args" || fail_test "sandbox launcher did not pass the validated option"
  grep -Fq 'run: codex login' "$TEST_ROOT/sandbox-launch.log" || fail_test "sandbox launcher did not explain first-use dedicated authentication"
  [[ ! -e "$TEST_ROOT/sandbox-shadow" ]] || fail_test "sandbox launcher used a PATH-shadowing Ralph"
  [[ "$(cat "$TEST_ROOT/sandbox-mounted-hash")" == "$(sha256_file "$managed_ralph")" ]] || fail_test "sandbox launcher selected an unverified mount binary"
  [[ "$(cat "$TEST_ROOT/sandbox-mounted-path")" == "$(cat "$TEST_ROOT/sandbox-config-path")/bin/ralph" ]] || fail_test "sandbox launcher did not select the contract-scoped mount path"
  [[ -e "$(cat "$TEST_ROOT/sandbox-mounted-path")" ]] || fail_test "sandbox mount source did not survive launcher exit"
  first_config="$(cat "$TEST_ROOT/sandbox-config-path")"
  [[ -f "$first_config/.ready" ]] || fail_test "sandbox launcher did not persist a ready managed configuration"
  [[ "$(cat "$TEST_ROOT/sandbox-home")" == "$state/ralph-sandbox-home" ]] || fail_test "sandbox launcher exposed the caller's host home"
  [[ "$(cat "$TEST_ROOT/sandbox-skill-path")" == "$state/ralph-sandbox-skills/"*'/ralph' ]] || fail_test "sandbox launcher did not supply a contract-scoped skill mount"
  [[ "$(cat "$TEST_ROOT/sandbox-skill-path")" != "$first_config"/* ]] || fail_test "read-only sandbox skill was placed inside the writable Ralph config mount"
  [[ "$(sha256_file "$(cat "$TEST_ROOT/sandbox-skill-path")/scripts/run-guarded.sh")" == "$(sha256_file "$TEST_RUNTIME/scripts/run-guarded.sh")" ]] || fail_test "sandbox skill mount source differs from the reviewed wrapper"
  if grep -Eq 'docker\.sock|network=host|\.ssh|\.config/gh' "$first_config/container/devcontainer.json"; then
    fail_test "guarded devcontainer retained a host escape or host credential mount"
  fi
  PATH="$fake_bin:$PATH" \
    RALPH_BIN_PATH="$managed_ralph" \
    RALPH_CONFIG_DIR="$config" \
    CODEX_GLOBAL_SKILLS_HOME="$state" \
    RALPH_TEST_ROOT="$TEST_ROOT" \
    "$RUN_SANDBOX"
  [[ "$(cat "$TEST_ROOT/sandbox-mounted-path")" == "$first_config/bin/ralph" ]] || fail_test "sandbox reuse changed the stable mount source"
  [[ "$(cat "$TEST_ROOT/sandbox-config-path")" == "$first_config" ]] || fail_test "sandbox reuse changed the managed configuration path"

  set_test_sandbox_pin "$config" 0.144.0
  PATH="$fake_bin:$PATH" \
    RALPH_BIN_PATH="$managed_ralph" \
    RALPH_CONFIG_DIR="$config" \
    CODEX_GLOBAL_SKILLS_HOME="$state" \
    RALPH_TEST_ROOT="$TEST_ROOT" \
    "$RUN_SANDBOX"
  second_config="$(cat "$TEST_ROOT/sandbox-config-path")"
  [[ "$second_config" != "$first_config" ]] || fail_test "sandbox contract upgrade reused stale managed configuration"
  [[ -f "$first_config/.ready" && -f "$second_config/.ready" ]] || fail_test "sandbox contract upgrade did not preserve complete versioned configurations"
  grep -Fq '@openai/codex@0.144.0' "$second_config/container/Dockerfile" || fail_test "sandbox contract upgrade did not apply the new Codex pin"

  mkdir -p "$TEST_ROOT/sandbox-symlink-state/ralph-sandbox-home" "$TEST_ROOT/sandbox-symlink-target"
  ln -s "$TEST_ROOT/sandbox-symlink-target" "$TEST_ROOT/sandbox-symlink-state/ralph-sandbox-home/.codex"
  if PATH="$fake_bin:$PATH" \
    RALPH_BIN_PATH="$managed_ralph" \
    RALPH_CONFIG_DIR="$config" \
    CODEX_GLOBAL_SKILLS_HOME="$TEST_ROOT/sandbox-symlink-state" \
    RALPH_TEST_ROOT="$TEST_ROOT" \
    "$RUN_SANDBOX" >"$TEST_ROOT/sandbox-symlink.log" 2>&1; then
    fail_test "sandbox launcher followed a symlinked dedicated-home component"
  fi
  grep -Fq 'home component is not a regular directory' "$TEST_ROOT/sandbox-symlink.log" || fail_test "sandbox-home symlink failure was not actionable"
  [[ -z "$(find "$TEST_ROOT/sandbox-symlink-target" -mindepth 1 -print -quit)" ]] || fail_test "sandbox launcher wrote through the home symlink"

  printf '%s\n' 'corrupt managed config' > "$second_config/container/devcontainer.json"
  rm -f "$TEST_ROOT/sandbox-args" "$TEST_ROOT/sandbox-cleaned"
  PATH="$fake_bin:$PATH" \
    RALPH_BIN_PATH="$managed_ralph" \
    RALPH_CONFIG_DIR="$config" \
    CODEX_GLOBAL_SKILLS_HOME="$state" \
    RALPH_TEST_ROOT="$TEST_ROOT" \
    "$RUN_SANDBOX" clean
  [[ ! -e "$TEST_ROOT/sandbox-args" ]] || fail_test "sandbox clean delegated to Ralph's single-container cleanup"
  [[ "$(sed -n '1p' "$TEST_ROOT/sandbox-cleaned")" == "abc123" && "$(sed -n '2p' "$TEST_ROOT/sandbox-cleaned")" == "def456" ]] || fail_test "sandbox clean did not remove every matching contract container"
  [[ "$(wc -l < "$TEST_ROOT/sandbox-cleaned" | tr -d '[:space:]')" -eq 2 ]] || fail_test "sandbox clean removed an unrelated same-workspace devcontainer"
  if RALPH_BIN_PATH="$managed_ralph" "$RUN_SANDBOX" --unknown >"$TEST_ROOT/sandbox-option.log" 2>&1; then
    fail_test "sandbox launcher accepted an unknown option"
  fi
  echo "[OK] guarded sandbox launcher mounts only the verified Ralph binary"
}

test_prompt_sanitization
test_getopt_compatibility_is_scoped
test_runner_blocks_configured_remote
test_runner_preserves_existing_prompt
test_runner_leaves_repository_commit_policy_to_supervisor
test_runner_fails_when_backend_changes_head
test_runner_fails_when_backend_changes_other_refs
test_runner_fails_when_backend_retargets_symbolic_ref
test_runner_fails_when_backend_switches_same_commit_branch
test_runner_fails_when_backend_changes_repository_config
test_runner_fails_when_backend_changes_effective_hooks
test_runner_fails_when_backend_retargets_broken_hook_chain
test_runner_fails_when_backend_changes_reviewed_prompt
test_safe_init_preserves_project_git_files
test_safe_init_preflights_all_artifacts
test_plan_uses_guarded_managed_runtime
test_plan_rejects_source_mutation
test_plan_rejects_nested_repository_mutation
test_plan_rejects_dirty_submodule_mutation
test_runner_resolves_devcontainer_mount
test_sandbox_launcher_mounts_verified_ralph
