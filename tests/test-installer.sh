#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-tests.XXXXXX")"
PASSED=0

# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail_test() {
  echo "[FAIL] $1" >&2
  exit 1
}

pass_test() {
  PASSED=$((PASSED + 1))
  echo "[OK] $1"
}

file_mode() {
  local file="$1"

  if stat -f '%Lp' "$file" >/dev/null 2>&1; then
    stat -f '%Lp' "$file"
  else
    stat -c '%a' "$file"
  fi
}

new_fixture() {
  local name="$1"
  local fixture="$TEST_ROOT/$name"

  mkdir -p "$fixture/codex" "$fixture/state"
  printf '# User guidance\n\nKeep this user-owned line.\n' > "$fixture/codex/AGENTS.md"
  printf '%s\n' "$fixture"
}

run_install() {
  local fixture="$1"
  shift
  CODEX_HOME="$fixture/codex" \
    CODEX_GLOBAL_SKILLS_HOME="$fixture/state" \
    "$ROOT/install.sh" "$@"
}

run_doctor() {
  local fixture="$1"
  CODEX_HOME="$fixture/codex" \
    CODEX_GLOBAL_SKILLS_HOME="$fixture/state" \
    "$ROOT/doctor.sh"
}

test_idempotent_install_and_guidance_preservation() {
  local fixture
  local first_agents_hash
  local first_manifest_hash
  local first_agents_mode

  fixture="$(new_fixture idempotent)"
  run_install "$fixture" --pack developer-core >/dev/null
  grep -Fqx 'Keep this user-owned line.' "$fixture/codex/AGENTS.md" || fail_test "installer changed user guidance"
  [[ "$(grep -Fxc '<!-- codex-global-skills:git-safety:start -->' "$fixture/codex/AGENTS.md")" -eq 1 ]] || fail_test "managed guidance start marker is not unique"
  [[ "$(grep -Fxc '<!-- codex-global-skills:git-safety:end -->' "$fixture/codex/AGENTS.md")" -eq 1 ]] || fail_test "managed guidance end marker is not unique"
  first_agents_hash="$(sha256_file "$fixture/codex/AGENTS.md")"
  first_manifest_hash="$(sha256_file "$fixture/codex/.codex-global-skills/manifest")"
  first_agents_mode="$(file_mode "$fixture/codex/AGENTS.md")"

  run_install "$fixture" >/dev/null
  [[ "$(sha256_file "$fixture/codex/AGENTS.md")" == "$first_agents_hash" ]] || fail_test "second install changed AGENTS.md"
  [[ "$(file_mode "$fixture/codex/AGENTS.md")" == "$first_agents_mode" ]] || fail_test "second install changed AGENTS.md permissions"
  [[ "$(sha256_file "$fixture/codex/.codex-global-skills/manifest")" == "$first_manifest_hash" ]] || fail_test "second install changed managed state"
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected an idempotent installation"
  pass_test "idempotent install preserves user guidance"
}

test_pack_switch_removes_only_managed_skills() {
  local fixture

  fixture="$(new_fixture switch)"
  run_install "$fixture" --pack developer-core >/dev/null
  mkdir -p "$fixture/codex/skills/personal-helper"
  printf '%s\n' 'personal content' > "$fixture/codex/skills/personal-helper/notes.txt"

  run_install "$fixture" --pack git >/dev/null
  [[ -d "$fixture/codex/skills/commit" ]] || fail_test "git pack lost commit"
  [[ -d "$fixture/codex/skills/git-workflow" ]] || fail_test "git pack lost git-workflow"
  [[ ! -e "$fixture/codex/skills/repo-map" ]] || fail_test "pack switch retained obsolete managed skill"
  [[ -f "$fixture/codex/skills/personal-helper/notes.txt" ]] || fail_test "pack switch removed unmanaged skill"
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected switched pack state"
  pass_test "pack switch removes only unchanged managed skills"
}

test_modified_managed_skill_blocks_removal() {
  local fixture

  fixture="$(new_fixture modified)"
  run_install "$fixture" --pack developer-core >/dev/null
  printf '\nLocal customization.\n' >> "$fixture/codex/skills/repo-map/SKILL.md"

  if run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    fail_test "installer removed a modified managed skill"
  fi
  grep -Fq 'Refusing to remove locally modified managed skill' "$fixture/install.log" || fail_test "modified-skill failure was not actionable"
  grep -Fq 'Local customization.' "$fixture/codex/skills/repo-map/SKILL.md" || fail_test "installer altered modified managed skill"
  pass_test "modified managed skills block desired-state removal"
}

test_managed_skill_mode_changes_are_detected() {
  local fixture

  fixture="$(new_fixture mode-change)"
  run_install "$fixture" --pack developer-core >/dev/null
  chmod +x "$fixture/codex/skills/repo-map/SKILL.md"

  if run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored a managed skill mode change"
  fi
  grep -Fq 'Refusing to overwrite modified or unmanaged skill' "$fixture/install.log" || fail_test "mode-change failure was not actionable"
  [[ -x "$fixture/codex/skills/repo-map/SKILL.md" ]] || fail_test "installer changed the locally modified mode"
  pass_test "managed hashes include executable modes"
}

test_unmanaged_collision_blocks_install() {
  local fixture

  fixture="$(new_fixture collision)"
  mkdir -p "$fixture/codex/skills/commit"
  printf '%s\n' 'user-owned collision' > "$fixture/codex/skills/commit/SKILL.md"

  if run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    fail_test "installer overwrote an unmanaged collision"
  fi
  grep -Fq 'Refusing to overwrite modified or unmanaged skill' "$fixture/install.log" || fail_test "collision failure was not actionable"
  grep -Fqx 'user-owned collision' "$fixture/codex/skills/commit/SKILL.md" || fail_test "collision content was changed"
  pass_test "unmanaged skill collisions fail safely"
}

test_malformed_guidance_fails_before_install() {
  local fixture
  local original_hash

  fixture="$(new_fixture malformed-guidance)"
  printf '%s\n' '<!-- codex-global-skills:git-safety:start -->' >> "$fixture/codex/AGENTS.md"
  original_hash="$(sha256_file "$fixture/codex/AGENTS.md")"

  if run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer accepted malformed guidance markers"
  fi
  [[ "$(sha256_file "$fixture/codex/AGENTS.md")" == "$original_hash" ]] || fail_test "malformed guidance file changed"
  [[ ! -e "$fixture/codex/skills/commit" ]] || fail_test "skills were installed after guidance preflight failure"
  pass_test "malformed guidance fails before installation"
}

test_ralph_worktree_is_never_deleted() {
  local fixture="$TEST_ROOT/ralph-worktree"
  local repository="$fixture/repository"
  local worktree="$fixture/worktree"

  mkdir -p "$fixture"
  git init -q "$repository"
  git -C "$repository" config user.name 'Codex Test'
  git -C "$repository" config user.email 'codex-test@example.invalid'
  git -C "$repository" commit -q --allow-empty -m 'test base'
  git -C "$repository" worktree add -q -b test-worktree "$worktree"
  [[ -f "$worktree/.git" ]] || fail_test "fixture is not a Git worktree"

  if (
    export RALPH_SOURCE_DIR="$worktree"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    preflight_ralph_source
  ) >"$fixture/preflight.log" 2>&1; then
    fail_test "unrecognized Ralph worktree passed preflight"
  fi
  [[ -d "$worktree" && -f "$worktree/.git" ]] || fail_test "Ralph preflight deleted a Git worktree"
  pass_test "Ralph preflight preserves Git worktrees and unknown checkouts"
}

test_reviewed_ralph_runtime_preserves_user_config() {
  local fixture="$TEST_ROOT/ralph-runtime"
  local source="$fixture/source"
  local bin="$fixture/bin"
  local config="$fixture/state/ralph-config"

  mkdir -p "$source/prompts" "$source/container" "$config"
  printf '%s\n' '#!/usr/bin/env bash' 'echo ralph' > "$source/ralph"
  printf '%s\n' 'plan prompt' > "$source/prompts/plan.md"
  printf '%s\n' 'build prompt' > "$source/prompts/build.md"
  printf '%s\n' 'FROM node:20' > "$source/container/Dockerfile"
  printf '%s\n' '{}' > "$source/container/devcontainer.json"
  chmod 755 "$source/ralph"
  printf '%s\n' 'user-owned extra config' > "$config/custom.txt"

  (
    export CODEX_HOME="$fixture/codex"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    export RALPH_SOURCE_DIR="$source"
    export RALPH_BIN_DIR="$bin"
    export RALPH_CONFIG_DIR="$config"
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    RALPH_PIN_CLI_SHA256="$(sha256_file "$source/ralph")"
    RALPH_PIN_PLAN_PROMPT_SHA256="$(sha256_file "$source/prompts/plan.md")"
    RALPH_PIN_BUILD_PROMPT_SHA256="$(sha256_file "$source/prompts/build.md")"
    RALPH_PIN_CONTAINER_DOCKERFILE_SHA256="$(sha256_file "$source/container/Dockerfile")"
    RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256="$(sha256_file "$source/container/devcontainer.json")"
    verify_git_checkout_exact() { return 0; }
    install_reviewed_ralph_runtime
  ) >/dev/null || fail_test "reviewed Ralph runtime could not install into an empty managed destination"

  [[ -x "$bin/ralph" ]] || fail_test "reviewed Ralph CLI was not installed executable"
  [[ -f "$config/prompts/plan.md" && -f "$config/container/devcontainer.json" ]] || fail_test "reviewed Ralph config was incomplete"
  grep -Fqx 'RALPH_GLOBAL_SKILL_BACKEND=codex' "$config/global-skill.env" || fail_test "reviewed Ralph config did not set Codex as the global-skill backend"
  grep -Fqx 'user-owned extra config' "$config/custom.txt" || fail_test "Ralph runtime install changed unrelated config"

  printf '%s\n' 'user customization' > "$config/prompts/plan.md"
  if (
    export CODEX_HOME="$fixture/codex"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    export RALPH_SOURCE_DIR="$source"
    export RALPH_BIN_DIR="$bin"
    export RALPH_CONFIG_DIR="$config"
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    RALPH_PIN_CLI_SHA256="$(sha256_file "$source/ralph")"
    RALPH_PIN_PLAN_PROMPT_SHA256="$(sha256_file "$source/prompts/plan.md")"
    RALPH_PIN_BUILD_PROMPT_SHA256="$(sha256_file "$source/prompts/build.md")"
    RALPH_PIN_CONTAINER_DOCKERFILE_SHA256="$(sha256_file "$source/container/Dockerfile")"
    RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256="$(sha256_file "$source/container/devcontainer.json")"
    verify_git_checkout_exact() { return 0; }
    install_reviewed_ralph_runtime
  ) >"$fixture/install.log" 2>&1; then
    fail_test "reviewed Ralph runtime overwrote a customized managed destination"
  fi
  grep -Fq 'Refusing to overwrite modified or unmanaged Ralph runtime file' "$fixture/install.log" || fail_test "Ralph runtime collision failure was not actionable"
  grep -Fqx 'user customization' "$config/prompts/plan.md" || fail_test "Ralph runtime collision changed user content"
  pass_test "reviewed Ralph runtime isolates and preserves user configuration"
}

test_contract_scoped_ralph_runtime_upgrades_without_overwrite() {
  local fixture="$TEST_ROOT/ralph-runtime-upgrade"
  local source="$fixture/source"

  mkdir -p "$source/prompts" "$source/container" "$fixture/state" "$fixture/fake-ln"
  printf '%s\n' '#!/usr/bin/env bash' 'echo version-one' > "$source/ralph"
  printf '%s\n' 'plan one' > "$source/prompts/plan.md"
  printf '%s\n' 'build one' > "$source/prompts/build.md"
  printf '%s\n' 'FROM node:20' > "$source/container/Dockerfile"
  printf '%s\n' '{"version":1}' > "$source/container/devcontainer.json"
  chmod 755 "$source/ralph"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'count=0' \
    '[[ -f "$RALPH_LN_COUNTER" ]] && count="$(cat "$RALPH_LN_COUNTER")"' \
    'count=$((count + 1))' \
    'printf "%s\n" "$count" > "$RALPH_LN_COUNTER"' \
    '[[ "$count" -eq 3 ]] && exit 77' \
    'exec /bin/ln "$@"' > "$fixture/fake-ln/ln"
  chmod +x "$fixture/fake-ln/ln"

  (
    export CODEX_HOME="$fixture/codex"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    export RALPH_SOURCE_DIR="$source"
    unset RALPH_BIN_DIR RALPH_CONFIG_DIR
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    verify_git_checkout_exact() { return 0; }

    select_fake_runtime() {
      RALPH_PIN_RUNTIME_ID="$1"
      RALPH_PIN_CLI_SHA256="$(sha256_file "$source/ralph")"
      RALPH_PIN_PLAN_PROMPT_SHA256="$(sha256_file "$source/prompts/plan.md")"
      RALPH_PIN_BUILD_PROMPT_SHA256="$(sha256_file "$source/prompts/build.md")"
      RALPH_PIN_CONTAINER_DOCKERFILE_SHA256="$(sha256_file "$source/container/Dockerfile")"
      RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256="$(sha256_file "$source/container/devcontainer.json")"
      RALPH_RUNTIME_DIR="$STATE_DIR/ralph-runtimes/$RALPH_PIN_RUNTIME_ID"
      BIN_DIR="$RALPH_RUNTIME_DIR/bin"
      RALPH_CONFIG_DIR="$RALPH_RUNTIME_DIR/config"
    }

    select_fake_runtime aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    install_reviewed_ralph_runtime
    first_runtime="$RALPH_RUNTIME_DIR"

    printf '%s\n' '#!/usr/bin/env bash' 'echo version-two' > "$source/ralph"
    printf '%s\n' 'plan two' > "$source/prompts/plan.md"
    printf '%s\n' 'build two' > "$source/prompts/build.md"
    printf '%s\n' 'FROM node:22' > "$source/container/Dockerfile"
    printf '%s\n' '{"version":2}' > "$source/container/devcontainer.json"
    chmod 755 "$source/ralph"
    select_fake_runtime bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    install_reviewed_ralph_runtime
    second_runtime="$RALPH_RUNTIME_DIR"

    grep -Fq 'version-one' "$first_runtime/bin/ralph"
    grep -Fqx 'RALPH_GLOBAL_SKILL_BACKEND=codex' "$first_runtime/config/global-skill.env"
    grep -Fq 'plan one' "$first_runtime/config/prompts/plan.md"
    grep -Fq 'version-two' "$second_runtime/bin/ralph"
    grep -Fqx 'RALPH_GLOBAL_SKILL_BACKEND=codex' "$second_runtime/config/global-skill.env"
    grep -Fq 'plan two' "$second_runtime/config/prompts/plan.md"

    printf '%s\n' '#!/usr/bin/env bash' 'echo version-three' > "$source/ralph"
    printf '%s\n' 'plan three' > "$source/prompts/plan.md"
    printf '%s\n' 'build three' > "$source/prompts/build.md"
    chmod 755 "$source/ralph"
    select_fake_runtime cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    export RALPH_LN_COUNTER="$fixture/ln-counter"
    if PATH="$fixture/fake-ln:$PATH" install_reviewed_ralph_runtime; then
      exit 91
    fi
    rollback_incomplete_ralph_runtime
    [[ ! -e "$RALPH_RUNTIME_DIR/bin/ralph" ]]
    [[ ! -e "$RALPH_RUNTIME_DIR/config/prompts/plan.md" ]]
  ) >/dev/null 2>&1 || fail_test "contract-scoped Ralph runtime could not install a new pin beside the old pin"

  pass_test "contract-scoped Ralph runtimes make pin upgrades non-destructive"
}

test_doctor_rejects_wrong_toolkit_link() {
  local fixture

  fixture="$(new_fixture toolkit-link)"
  run_install "$fixture" --pack equal-experts >/dev/null
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected a clean EE installation"
  mkdir -p "$fixture/wrong-toolkit"
  rm "$fixture/codex/skills/ee-clarify/toolkit"
  ln -s "$fixture/wrong-toolkit" "$fixture/codex/skills/ee-clarify/toolkit"

  if run_doctor "$fixture" >"$fixture/doctor.log" 2>&1; then
    fail_test "doctor accepted a wrong EE toolkit link"
  fi
  grep -Fq 'points elsewhere for ee-clarify' "$fixture/doctor.log" || fail_test "wrong-link failure was not actionable"
  pass_test "doctor rejects wrong EE toolkit links"
}

test_managed_ee_links_relocate_with_source_clone() {
  local fixture
  local old_target
  local old_target_hash
  local manifest
  local next_manifest
  local state_hash
  local skill

  fixture="$(new_fixture ee-relocation)"
  run_install "$fixture" --pack equal-experts >/dev/null
  old_target="$fixture/old-clone/vendor/equalexperts/llm-toolkit"
  mkdir -p "$old_target"
  for skill in ee-control-plane ee-clarify ee-breakdown equal-experts-workflow; do
    rm "$fixture/codex/skills/$skill/toolkit"
    ln -s "$old_target" "$fixture/codex/skills/$skill/toolkit"
  done
  manifest="$fixture/codex/.codex-global-skills/manifest"
  next_manifest="$fixture/manifest.relocated"
  old_target_hash="$(printf '%s' "$old_target" | sha256_stream)"
  awk -v target_hash="$old_target_hash" '
    $1 == "ee-toolkit-target-sha256" { print "ee-toolkit-target-sha256 " target_hash; next }
    $1 != "state-sha256" { print }
  ' "$manifest" > "$next_manifest"
  state_hash="$(state_manifest_records_digest "$next_manifest")"
  printf 'state-sha256 %s\n' "$state_hash" >> "$next_manifest"
  mv "$next_manifest" "$manifest"

  run_install "$fixture" --pack equal-experts >/dev/null || fail_test "installer could not relocate its recorded EE links"
  for skill in ee-control-plane ee-clarify ee-breakdown equal-experts-workflow; do
    [[ "$(readlink "$fixture/codex/skills/$skill/toolkit")" == "$ROOT/vendor/equalexperts/llm-toolkit" ]] || fail_test "installer did not relocate $skill toolkit link"
  done
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected relocated EE links"
  pass_test "managed EE links relocate safely with the source clone"
}

test_legacy_installations_are_adopted() {
  local revision
  local full_revision
  local fixture
  local skill

  for revision in 92981ea 7d3b9bf 7580790 03a81e7; do
    full_revision="$(git -C "$ROOT" rev-parse "$revision^{commit}")"
    fixture="$(new_fixture "legacy-$revision")"
    git -C "$ROOT" archive "$full_revision" skills | tar -x -C "$fixture/codex"
    for skill in ee-control-plane ee-clarify ee-breakdown equal-experts-workflow; do
      [[ -d "$fixture/codex/skills/$skill" ]] || continue
      ln -s "$ROOT/vendor/equalexperts/llm-toolkit" "$fixture/codex/skills/$skill/toolkit"
    done
    run_install "$fixture" --pack git --pack equal-experts >/dev/null || fail_test "could not adopt legacy skills from $revision"
  done
  pass_test "all published pre-manifest skill versions are safely adopted"
}

test_legacy_mode_changes_are_not_adopted() {
  local fixture
  local revision

  revision="$(git -C "$ROOT" rev-parse '03a81e7^{commit}')"
  fixture="$(new_fixture legacy-mode-change)"
  git -C "$ROOT" archive "$revision" skills/commit skills/git-workflow | tar -x -C "$fixture/codex"
  chmod 600 "$fixture/codex/skills/commit/SKILL.md"

  if run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    fail_test "installer adopted a legacy skill with a mode-only modification"
  fi
  grep -Fq 'Refusing to overwrite modified or unmanaged skill' "$fixture/install.log" || fail_test "legacy mode-change failure was not actionable"
  [[ "$(file_mode "$fixture/codex/skills/commit/SKILL.md")" == "600" ]] || fail_test "legacy mode-change was overwritten"
  pass_test "legacy adoption rejects mode-only modifications"
}

test_legacy_ee_links_relocate_after_clone_move() {
  local fixture
  local revision
  local old_target
  local skill

  revision="$(git -C "$ROOT" rev-parse '92981ea^{commit}')"
  fixture="$(new_fixture legacy-ee-relocation)"
  old_target="$fixture/deleted-old-clone/vendor/equalexperts/llm-toolkit"
  git -C "$ROOT" archive "$revision" \
    skills/ee-control-plane skills/ee-clarify skills/ee-breakdown skills/equal-experts-workflow | tar -x -C "$fixture/codex"
  for skill in ee-control-plane ee-clarify ee-breakdown equal-experts-workflow; do
    ln -s "$old_target" "$fixture/codex/skills/$skill/toolkit"
  done

  run_install "$fixture" --pack equal-experts >/dev/null || fail_test "installer could not relocate an approved pre-manifest EE install"
  for skill in ee-control-plane ee-clarify ee-breakdown equal-experts-workflow; do
    [[ "$(readlink "$fixture/codex/skills/$skill/toolkit")" == "$ROOT/vendor/equalexperts/llm-toolkit" ]] || fail_test "legacy relocation did not repair $skill"
  done
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected relocated pre-manifest EE skills"
  pass_test "approved pre-manifest EE links relocate after a source-clone move"
}

test_historical_manifest_state_uses_mode_digest_lookup() {
  local fixture
  local revision
  local commit_digest
  local workflow_digest
  local manifest

  fixture="$(new_fixture historical-state-mode-digest)"
  revision="$(git -C "$ROOT" rev-parse '03a81e7^{commit}')"
  commit_digest="$(awk -F '\t' -v revision="$revision" '$1 == "commit" && $4 == revision { print $3; exit }' "$ROOT/migrations/legacy-skill-hashes.tsv")"
  workflow_digest="$(awk -F '\t' -v revision="$revision" '$1 == "git-workflow" && $4 == revision { print $3; exit }' "$ROOT/migrations/legacy-skill-hashes.tsv")"
  manifest="$fixture/codex/.codex-global-skills/manifest"
  mkdir -p "$(dirname "$manifest")" "$fixture/empty-source-skills"
  printf '%s\n' \
    'version 1' \
    'pack git' \
    'dependency git' \
    'guidance git-safety' \
    "skill commit $commit_digest" \
    "skill git-workflow $workflow_digest" > "$manifest"

  if ! (
    export CODEX_HOME="$fixture/codex"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    SKILLS_SRC="$fixture/empty-source-skills"
    validate_state_manifest
  ) >"$fixture/validate.log" 2>&1; then
    fail_test "validator did not recognize historical mode-aware manifest hashes"
  fi
  pass_test "historical removed-skill state uses mode-aware migration hashes"
}

test_state_write_failure_precedes_skill_mutation() {
  local fixture
  local manifest_hash

  fixture="$(new_fixture state-write)"
  run_install "$fixture" --pack developer-core >/dev/null
  manifest_hash="$(sha256_file "$fixture/codex/.codex-global-skills/manifest")"
  chmod 500 "$fixture/codex/.codex-global-skills"

  if run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    chmod 700 "$fixture/codex/.codex-global-skills"
    fail_test "installer succeeded without a writable managed-state directory"
  fi
  chmod 700 "$fixture/codex/.codex-global-skills"
  [[ -d "$fixture/codex/skills/repo-map" ]] || fail_test "state failure removed a previously managed skill"
  [[ "$(sha256_file "$fixture/codex/.codex-global-skills/manifest")" == "$manifest_hash" ]] || fail_test "state failure changed the previous manifest"
  pass_test "managed-state write failures occur before skill mutation"
}

test_non_ee_toolkit_content_is_not_ignored() {
  local fixture

  fixture="$(new_fixture non-ee-toolkit)"
  run_install "$fixture" --pack developer-core >/dev/null
  mkdir -p "$fixture/codex/skills/repo-map/toolkit"
  printf '%s\n' 'user-owned' > "$fixture/codex/skills/repo-map/toolkit/notes.txt"

  if run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored user content named toolkit in a non-EE skill"
  fi
  grep -Fq 'Refusing to overwrite modified or unmanaged skill' "$fixture/install.log" || fail_test "non-EE toolkit conflict was not actionable"
  [[ -f "$fixture/codex/skills/repo-map/toolkit/notes.txt" ]] || fail_test "non-EE toolkit content was removed"
  pass_test "non-EE toolkit paths remain part of managed hashes"
}

test_missing_dependencies_fail_without_installing() {
  local fixture

  fixture="$(new_fixture missing-dependencies)"
  if PATH="/usr/bin:/bin" \
    RALPH_BIN_DIR="$fixture/bin" \
    CODEX_HOME="$fixture/codex" \
    CODEX_GLOBAL_SKILLS_HOME="$fixture/state" \
    "$ROOT/install.sh" --pack ralph >"$fixture/install.log" 2>&1; then
    fail_test "installer accepted missing Ralph-pack dependencies"
  fi
  grep -Fq 'Missing dependency: codex' "$fixture/install.log" || fail_test "missing dependency failure was not actionable"
  [[ ! -e "$fixture/codex/skills/ralph" ]] || fail_test "skills changed after dependency preflight failure"
  [[ ! -e "$fixture/codex/.codex-global-skills/manifest" ]] || fail_test "dependency failure committed managed state"
  pass_test "missing dependencies fail without implicit installation"
}

test_dependency_version_mismatch_fails_without_installing() {
  local fixture
  local fake_bin

  fixture="$(new_fixture dependency-version)"
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-cli 0.1.0"' > "$fake_bin/codex"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "0.2.0"' > "$fake_bin/devcontainer"
  chmod +x "$fake_bin/codex" "$fake_bin/devcontainer"

  if PATH="$fake_bin:/usr/bin:/bin" \
    RALPH_BIN_DIR="$fixture/bin" \
    CODEX_HOME="$fixture/codex" \
    CODEX_GLOBAL_SKILLS_HOME="$fixture/state" \
    "$ROOT/install.sh" --pack ralph >"$fixture/install.log" 2>&1; then
    fail_test "installer accepted an unpinned selected CLI"
  fi
  grep -Fq 'Dependency version mismatch: codex 0.1.0 (required 0.143.0)' "$fixture/install.log" || fail_test "dependency version failure was not actionable"
  [[ ! -e "$fixture/codex/skills/ralph" ]] || fail_test "version mismatch changed installed skills"
  pass_test "selected CLI versions are enforced"
}

test_manifest_commit_failure_rolls_back_skills() {
  local fixture
  local manifest_hash
  local fake_bin

  fixture="$(new_fixture manifest-rollback)"
  run_install "$fixture" --pack developer-core >/dev/null
  manifest_hash="$(sha256_file "$fixture/codex/.codex-global-skills/manifest")"
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$*" == *"/.codex-global-skills/manifest"* ]]; then exit 77; fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored a managed-state commit failure"
  fi
  [[ -d "$fixture/codex/skills/repo-map" ]] || fail_test "manifest failure did not restore removed skill"
  [[ -d "$fixture/codex/skills/quality-gate" ]] || fail_test "manifest failure did not restore previous pack"
  [[ "$(sha256_file "$fixture/codex/.codex-global-skills/manifest")" == "$manifest_hash" ]] || fail_test "manifest failure changed committed state"
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected state after transaction rollback"
  pass_test "manifest commit failures roll back skill changes"
}

test_manifest_commit_failure_rolls_back_first_install() {
  local fixture
  local fake_bin

  fixture="$(new_fixture first-manifest-rollback)"
  rm "$fixture/codex/AGENTS.md"
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$*" == *"/.codex-global-skills/manifest"* ]]; then exit 77; fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    fail_test "first install ignored a managed-state commit failure"
  fi
  [[ ! -e "$fixture/codex/skills/commit" ]] || fail_test "first-install rollback retained a skill"
  [[ ! -e "$fixture/codex/.codex-global-skills/manifest" ]] || fail_test "first-install rollback committed state"
  [[ ! -e "$fixture/codex/AGENTS.md" ]] || fail_test "first-install rollback retained managed guidance"
  pass_test "first-install manifest failure rolls back skills and guidance"
}

test_corrupt_state_cannot_claim_unmanaged_skill() {
  local fixture
  local digest

  fixture="$(new_fixture corrupt-claim)"
  run_install "$fixture" --pack git >/dev/null
  mkdir -p "$fixture/codex/skills/personal-helper"
  printf '%s\n' 'user-owned sentinel' > "$fixture/codex/skills/personal-helper/notes.txt"
  digest="$(hash_skill_directory "$fixture/codex/skills/personal-helper")"
  printf 'skill personal-helper %s\n' "$digest" >> "$fixture/codex/.codex-global-skills/manifest"

  if run_install "$fixture" >"$fixture/install.log" 2>&1; then
    fail_test "installer trusted a corrupt state claim for an unmanaged skill"
  fi
  grep -Fq 'Managed state claims an unknown skill' "$fixture/install.log" || fail_test "corrupt state claim failure was not actionable"
  [[ -f "$fixture/codex/skills/personal-helper/notes.txt" ]] || fail_test "corrupt state removed unmanaged content"
  pass_test "corrupt state cannot claim or delete unmanaged skills"
}

test_truncated_state_never_expands_default_pack() {
  local fixture

  fixture="$(new_fixture truncated-state)"
  run_install "$fixture" --pack git >/dev/null
  printf 'version 1\n' > "$fixture/codex/.codex-global-skills/manifest"

  if run_install "$fixture" >"$fixture/install.log" 2>&1; then
    fail_test "installer accepted a version-only state manifest"
  fi
  grep -Fq 'must contain at least one pack and one skill' "$fixture/install.log" || fail_test "truncated state failure was not actionable"
  [[ ! -e "$fixture/codex/skills/repo-map" ]] || fail_test "truncated state expanded to the default pack"
  [[ -d "$fixture/codex/skills/commit" ]] || fail_test "truncated state altered the existing installation"
  pass_test "truncated state fails without default-pack expansion"
}

test_invalid_dependency_state_is_actionable() {
  local fixture

  fixture="$(new_fixture invalid-dependency)"
  run_install "$fixture" --pack git >/dev/null
  sed 's/^dependency git$/dependency bogus/' "$fixture/codex/.codex-global-skills/manifest" > "$fixture/manifest.invalid"
  mv "$fixture/manifest.invalid" "$fixture/codex/.codex-global-skills/manifest"

  if run_install "$fixture" >"$fixture/install.log" 2>&1; then
    fail_test "installer accepted an invalid dependency state"
  fi
  grep -Fq 'Invalid dependency state' "$fixture/install.log" || fail_test "invalid dependency state had no actionable error"
  pass_test "invalid dependency state reports its cause"
}

test_pack_line_corruption_cannot_change_desired_state() {
  local fixture

  fixture="$(new_fixture corrupt-pack-selection)"
  run_install "$fixture" --pack developer-core >/dev/null
  sed 's/^pack developer-core /pack git /' "$fixture/codex/.codex-global-skills/manifest" > "$fixture/manifest.invalid"
  mv "$fixture/manifest.invalid" "$fixture/codex/.codex-global-skills/manifest"

  if run_install "$fixture" >"$fixture/install.log" 2>&1; then
    fail_test "installer trusted a corrupt pack line as a new desired state"
  fi
  grep -Fq 'state checksum does not match' "$fixture/install.log" || fail_test "pack-corruption failure was not actionable"
  [[ -d "$fixture/codex/skills/repo-map" ]] || fail_test "pack corruption removed a previously managed skill"
  [[ -d "$fixture/codex/skills/quality-gate" ]] || fail_test "pack corruption changed the installed selection"
  pass_test "manifest checksum prevents pack-line desired-state corruption"
}

test_install_lock_blocks_concurrent_installer() {
  local fixture

  fixture="$(new_fixture install-lock)"
  mkdir -p "$fixture/codex/.codex-global-skills/install.lock"
  printf '%s\n' '99999' > "$fixture/codex/.codex-global-skills/install.lock/pid"

  if run_install "$fixture" --pack git >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored an existing install lock"
  fi
  grep -Fq 'Another install may be active' "$fixture/install.log" || fail_test "install-lock failure was not actionable"
  [[ ! -e "$fixture/codex/skills/commit" ]] || fail_test "locked installer changed skills"
  pass_test "install lock blocks concurrent profile mutation"
}

test_concurrent_skill_edit_is_revalidated() {
  local fixture

  fixture="$(new_fixture concurrent-skill)"
  run_install "$fixture" --pack developer-core >/dev/null

  if (
    export CODEX_HOME="$fixture/codex"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    ensure_dependencies() {
      printf '\nConcurrent user edit.\n' >> "$fixture/codex/skills/repo-map/SKILL.md"
    }
    main --pack developer-core
  ) >"$fixture/install.log" 2>&1; then
    fail_test "installer overwrote a skill edited after preflight"
  fi
  grep -Fq 'preserving concurrent edits' "$fixture/install.log" || fail_test "concurrent skill failure was not actionable"
  grep -Fq 'Concurrent user edit.' "$fixture/codex/skills/repo-map/SKILL.md" || fail_test "concurrent skill edit was lost"
  [[ ! -d "$fixture/codex/.codex-global-skills/install.lock" ]] || fail_test "failed install left its lock behind"
  pass_test "destinations are revalidated immediately before replacement"
}

test_concurrent_skill_edit_during_move_is_revalidated() {
  local fixture
  local fake_bin
  local manifest_hash_before

  fixture="$(new_fixture concurrent-skill-move)"
  run_install "$fixture" --pack developer-core >/dev/null
  manifest_hash_before="$(sha256_file "$fixture/codex/.codex-global-skills/manifest")"
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "if [[ \"\$1\" == \"$fixture/codex/skills/repo-map\" && \"\$2\" == *\"/.codex-global-skills-rollback.\"*\"/repo-map\" ]]; then" \
    "  printf '%s\n' 'Concurrent move-time skill edit.' >> \"$fixture/codex/skills/repo-map/SKILL.md\"" \
    'fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer overwrote a skill edited while it was being moved"
  fi
  grep -Fq 'changed while the transaction was starting' "$fixture/install.log" || fail_test "move-time skill failure was not actionable"
  grep -Fq 'Concurrent move-time skill edit.' "$fixture/codex/skills/repo-map/SKILL.md" || fail_test "move-time skill edit was lost"
  [[ "$(sha256_file "$fixture/codex/.codex-global-skills/manifest")" == "$manifest_hash_before" ]] || fail_test "move-time skill failure changed managed state"
  pass_test "moved skills are revalidated before replacement"
}

test_guidance_rollback_preserves_dependency_time_edit() {
  local fixture
  local fake_bin

  fixture="$(new_fixture concurrent-guidance)"
  run_install "$fixture" --pack developer-core >/dev/null
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$*" == *"/.codex-global-skills/manifest"* ]]; then exit 77; fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if (
    export PATH="$fake_bin:$PATH"
    export CODEX_HOME="$fixture/codex"
    export CODEX_GLOBAL_SKILLS_HOME="$fixture/state"
    # shellcheck source=../install.sh
    source "$ROOT/install.sh"
    ensure_dependencies() {
      printf '%s\n' 'Concurrent user guidance edit.' >> "$fixture/codex/AGENTS.md"
    }
    main --pack git
  ) >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored the injected manifest failure"
  fi
  grep -Fqx 'Concurrent user guidance edit.' "$fixture/codex/AGENTS.md" || fail_test "guidance rollback lost a dependency-time user edit"
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected state after concurrent-guidance rollback"
  pass_test "guidance rollback snapshots the final preimage"
}

test_concurrent_guidance_edit_during_move_is_revalidated() {
  local fixture
  local fake_bin

  fixture="$(new_fixture concurrent-guidance-move)"
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "if [[ \"\$1\" == \"$fixture/codex/AGENTS.md\" && \"\$2\" == *\"/.AGENTS.md.codex-global-skills-backup.\"* ]]; then" \
    "  printf '%s\n' 'Concurrent move-time guidance edit.' >> \"$fixture/codex/AGENTS.md\"" \
    'fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer overwrote guidance edited while it was being moved"
  fi
  grep -Fq 'Global AGENTS.md changed while the transaction was starting' "$fixture/install.log" || fail_test "move-time guidance failure was not actionable"
  grep -Fqx 'Concurrent move-time guidance edit.' "$fixture/codex/AGENTS.md" || fail_test "move-time guidance edit was lost"
  [[ ! -e "$fixture/codex/.codex-global-skills/manifest" ]] || fail_test "guidance move failure committed managed state"
  [[ ! -e "$fixture/codex/skills/repo-map" ]] || fail_test "guidance move failure did not roll back first-install skills"
  pass_test "moved global guidance is revalidated before replacement"
}

test_signal_rolls_back_active_transaction() {
  local fixture
  local skill_hash_before
  local manifest_hash_before
  local guidance_hash_before

  fixture="$(new_fixture signal-rollback)"
  run_install "$fixture" --pack developer-core >/dev/null
  skill_hash_before="$(hash_skill_directory "$fixture/codex/skills/repo-map")"
  manifest_hash_before="$(sha256_file "$fixture/codex/.codex-global-skills/manifest")"
  guidance_hash_before="$(sha256_file "$fixture/codex/AGENTS.md")"

  if CODEX_HOME="$fixture/codex" \
    CODEX_GLOBAL_SKILLS_HOME="$fixture/state" \
    ROOT_UNDER_TEST="$ROOT" \
    /bin/bash -c '
      source "$ROOT_UNDER_TEST/install.sh"
      install_global_git_guidance() {
        kill -TERM "$$"
      }
      main --pack git
    ' >"$fixture/install.log" 2>&1; then
    fail_test "installer survived an injected termination signal"
  fi

  [[ "$(hash_skill_directory "$fixture/codex/skills/repo-map")" == "$skill_hash_before" ]] || fail_test "signal rollback did not restore replaced skills"
  [[ "$(sha256_file "$fixture/codex/.codex-global-skills/manifest")" == "$manifest_hash_before" ]] || fail_test "signal rollback changed managed state"
  [[ "$(sha256_file "$fixture/codex/AGENTS.md")" == "$guidance_hash_before" ]] || fail_test "signal rollback changed global guidance"
  [[ ! -d "$fixture/codex/.codex-global-skills/install.lock" ]] || fail_test "signal rollback left the install lock"
  if find "$fixture/codex/skills" -maxdepth 1 \( -name '.codex-global-skills-stage.*' -o -name '.codex-global-skills-rollback.*' \) -print -quit | grep -q .; then
    fail_test "signal rollback left transaction directories"
  fi
  run_doctor "$fixture" >/dev/null || fail_test "doctor rejected state after signal rollback"
  pass_test "termination signals roll back active skill transactions"
}

test_signal_after_manifest_move_keeps_committed_state_consistent() {
  local fixture
  local fake_bin

  fixture="$(new_fixture signal-after-manifest)"
  run_install "$fixture" --pack git >/dev/null
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$*" == *"/.codex-global-skills/manifest"* ]]; then' \
    '  /bin/mv "$@"' \
    '  kill -TERM "$PPID"' \
    '  exit 0' \
    'fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored a termination immediately after manifest publication"
  fi
  grep -Fq 'pack developer-core ' "$fixture/codex/.codex-global-skills/manifest" || fail_test "post-manifest signal did not retain the committed selection"
  [[ -d "$fixture/codex/skills/repo-map" && -d "$fixture/codex/skills/release-readiness" ]] || fail_test "post-manifest signal rolled back committed skills"
  run_doctor "$fixture" >/dev/null || fail_test "doctor found inconsistent state after post-manifest signal"
  pass_test "termination after manifest publication preserves a consistent commit"
}

test_mv_failure_after_manifest_publication_keeps_state_consistent() {
  local fixture
  local fake_bin

  fixture="$(new_fixture mv-fails-after-manifest)"
  run_install "$fixture" --pack git >/dev/null
  fake_bin="$fixture/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$*" == *"/.codex-global-skills/manifest"* ]]; then' \
    '  /bin/mv "$@"' \
    '  exit 77' \
    'fi' \
    'exec /bin/mv "$@"' > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" run_install "$fixture" --pack developer-core >"$fixture/install.log" 2>&1; then
    fail_test "installer ignored mv failure after manifest publication"
  fi
  grep -Fq 'state was published even though mv reported failure' "$fixture/install.log" || fail_test "post-publication mv failure was not actionable"
  grep -Fq 'pack developer-core ' "$fixture/codex/.codex-global-skills/manifest" || fail_test "post-publication mv failure did not retain the new manifest"
  [[ -d "$fixture/codex/skills/repo-map" && -d "$fixture/codex/skills/release-readiness" ]] || fail_test "post-publication mv failure rolled back committed skills"
  run_doctor "$fixture" >/dev/null || fail_test "doctor found inconsistent state after post-publication mv failure"
  pass_test "mv failure after manifest publication preserves a consistent commit"
}

test_idempotent_install_and_guidance_preservation
test_pack_switch_removes_only_managed_skills
test_modified_managed_skill_blocks_removal
test_managed_skill_mode_changes_are_detected
test_unmanaged_collision_blocks_install
test_malformed_guidance_fails_before_install
test_ralph_worktree_is_never_deleted
test_reviewed_ralph_runtime_preserves_user_config
test_contract_scoped_ralph_runtime_upgrades_without_overwrite
test_doctor_rejects_wrong_toolkit_link
test_managed_ee_links_relocate_with_source_clone
test_legacy_installations_are_adopted
test_legacy_mode_changes_are_not_adopted
test_legacy_ee_links_relocate_after_clone_move
test_historical_manifest_state_uses_mode_digest_lookup
test_state_write_failure_precedes_skill_mutation
test_non_ee_toolkit_content_is_not_ignored
test_missing_dependencies_fail_without_installing
test_dependency_version_mismatch_fails_without_installing
test_manifest_commit_failure_rolls_back_skills
test_manifest_commit_failure_rolls_back_first_install
test_corrupt_state_cannot_claim_unmanaged_skill
test_truncated_state_never_expands_default_pack
test_invalid_dependency_state_is_actionable
test_pack_line_corruption_cannot_change_desired_state
test_install_lock_blocks_concurrent_installer
test_concurrent_skill_edit_is_revalidated
test_concurrent_skill_edit_during_move_is_revalidated
test_guidance_rollback_preserves_dependency_time_edit
test_concurrent_guidance_edit_during_move_is_revalidated
test_signal_rolls_back_active_transaction
test_signal_after_manifest_move_keeps_committed_state_consistent
test_mv_failure_after_manifest_publication_keeps_state_consistent

echo "Installer regression tests passed: $PASSED"
