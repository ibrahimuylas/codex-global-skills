#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
PACKS_DIR="$SCRIPT_DIR/packs"
GUIDANCE_SRC="$SCRIPT_DIR/installer/guidance/git-safety.md"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DEST="$CODEX_CONFIG_DIR/skills"
GLOBAL_AGENTS_FILE="$CODEX_CONFIG_DIR/AGENTS.md"
MANIFEST_FILE="$CODEX_CONFIG_DIR/.codex-global-skills/manifest"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
RALPH_SOURCE_DIR="${RALPH_SOURCE_DIR:-$STATE_DIR/ralph}"
RALPH_PIN_FILE="$SCRIPT_DIR/skills/ralph/assets/ralph-pin.env"
if [[ ! -f "$RALPH_PIN_FILE" || -L "$RALPH_PIN_FILE" ]]; then
  echo "[FAIL] Reviewed Ralph pin contract is missing or invalid: $RALPH_PIN_FILE"
  exit 1
fi
# shellcheck source=skills/ralph/assets/ralph-pin.env
source "$RALPH_PIN_FILE"
RALPH_REPO_URL="$RALPH_PIN_REPO_URL"
RALPH_REVISION="$RALPH_PIN_REVISION"
RALPH_RUNTIME_DIR="$STATE_DIR/ralph-runtimes/$RALPH_PIN_RUNTIME_ID"
BIN_DIR="${RALPH_BIN_DIR:-$RALPH_RUNTIME_DIR/bin}"
RALPH_CONFIG_DIR="${RALPH_CONFIG_DIR:-$RALPH_RUNTIME_DIR/config}"
RALPH_DEFAULTS_FILE="$RALPH_CONFIG_DIR/global-skill.env"
RALPH_BACKEND_CODEX_HOME="$STATE_DIR/ralph-backend-home"
CLI_PIN_FILE="$SCRIPT_DIR/installer/pins/cli.env"
if [[ ! -f "$CLI_PIN_FILE" || -L "$CLI_PIN_FILE" ]]; then
  echo "[FAIL] Reviewed CLI pin contract is missing or invalid: $CLI_PIN_FILE"
  exit 1
fi
# shellcheck source=installer/pins/cli.env
source "$CLI_PIN_FILE"
GIT_GUIDANCE_START="<!-- codex-global-skills:git-safety:start -->"
GIT_GUIDANCE_END="<!-- codex-global-skills:git-safety:end -->"
status=0
TEMP_DIR=""
HAS_MANAGED_STATE=0

# shellcheck source=installer/lib/common.sh
source "$SCRIPT_DIR/installer/lib/common.sh"

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

ok() {
  echo "[OK] $1"
}

warn() {
  echo "[WARN] $1"
}

fail() {
  echo "[FAIL] $1"
  status=1
}

check_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "command: $command_name ($(command -v "$command_name"))"
  else
    fail "command missing: $command_name"
  fi
}

check_versioned_command() {
  local command_name="$1"
  local required_version="$2"
  local actual_version=""

  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "command missing: $command_name"
    return
  fi
  case "$command_name" in
    codex) actual_version="$(codex --version 2>/dev/null | sed -n '1s/.* //p')" ;;
    devcontainer) actual_version="$(devcontainer --version 2>/dev/null | sed -n '1p')" ;;
  esac
  if [[ "$actual_version" == "$required_version" ]]; then
    ok "command: $command_name $actual_version ($(command -v "$command_name"))"
  else
    fail "$command_name version is ${actual_version:-unknown}; required $required_version"
  fi
}

ralph_backend_skills_are_isolated() {
  local skills_dir="$RALPH_BACKEND_CODEX_HOME/skills"
  local entry

  if [[ ! -e "$skills_dir" && ! -L "$skills_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$skills_dir" || -L "$skills_dir" ]]; then
    return 1
  fi
  while IFS= read -r -d '' entry; do
    if [[ "$(basename "$entry")" != ".system" || ! -d "$entry" || -L "$entry" ]]; then
      return 1
    fi
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -print0)
}

check_global_git_guidance() {
  local begin_count
  local end_count
  local begin_line
  local end_line
  local installed_guidance

  if [[ ! -s "$GUIDANCE_SRC" ]]; then
    fail "missing or empty source Git guidance: $GUIDANCE_SRC"
    return
  fi
  if [[ -L "$GLOBAL_AGENTS_FILE" ]]; then
    fail "global AGENTS.md must not be a symbolic link: $GLOBAL_AGENTS_FILE"
    return
  fi
  if [[ ! -f "$GLOBAL_AGENTS_FILE" ]]; then
    fail "missing global AGENTS.md: $GLOBAL_AGENTS_FILE"
    return
  fi

  begin_count="$(grep -Fxc -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" || true)"
  end_count="$(grep -Fxc -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" || true)"
  if [[ "$begin_count" -ne 1 || "$end_count" -ne 1 ]]; then
    fail "expected one managed Git guidance marker pair in $GLOBAL_AGENTS_FILE"
    return
  fi
  begin_line="$(grep -nFx -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
  end_line="$(grep -nFx -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
  if [[ "$begin_line" -ge "$end_line" ]]; then
    fail "managed Git guidance markers are out of order in $GLOBAL_AGENTS_FILE"
    return
  fi

  installed_guidance="$TEMP_DIR/installed-guidance"
  awk -v start="$GIT_GUIDANCE_START" -v finish="$GIT_GUIDANCE_END" '
    $0 == start { managed = 1; next }
    $0 == finish { managed = 0; found_end = 1; exit }
    managed { print }
    END { if (!found_end) exit 1 }
  ' "$GLOBAL_AGENTS_FILE" > "$installed_guidance"
  if cmp -s "$GUIDANCE_SRC" "$installed_guidance"; then
    ok "installed Git guidance matches source"
  else
    fail "installed Git guidance differs from $GUIDANCE_SRC"
  fi
}

parse_managed_state() {
  local packs_output="$TEMP_DIR/packs"
  local skills_output="$TEMP_DIR/skills"
  local dependencies_output="$TEMP_DIR/dependencies"
  local guidance_output="$TEMP_DIR/guidance"
  local manifest
  local pack
  local first_line
  local state_version
  local state_hash=""
  local state_hash_count=0
  local ee_toolkit_target_count=0
  local line_number=0
  local line
  local kind
  local value
  local detail
  local extra

  : > "$packs_output"
  : > "$skills_output"
  : > "$dependencies_output"
  : > "$guidance_output"

  if [[ ! -e "$MANIFEST_FILE" ]]; then
    warn "managed install state is missing; comparing every repository skill directly"
    find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort > "$skills_output"
    printf '%s\n' git codex devcontainer ralph ee-toolkit > "$dependencies_output"
    printf '%s\n' git-safety > "$guidance_output"
    return
  fi
  if [[ -L "$MANIFEST_FILE" || ! -f "$MANIFEST_FILE" ]]; then
    fail "managed install state is not a regular file: $MANIFEST_FILE"
    return
  fi

  HAS_MANAGED_STATE=1
  IFS= read -r first_line < "$MANIFEST_FILE"
  case "$first_line" in
    'version 1') state_version=1 ;;
    'version 2') state_version=2 ;;
    *) fail "unsupported managed install state: $MANIFEST_FILE"; return ;;
  esac

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    [[ "$line_number" -eq 1 ]] && continue
    IFS=' ' read -r kind value detail extra <<< "$line"
    case "$kind" in
      state-sha256)
        if [[ "$state_version" == "2" && "$value" =~ ^[0-9a-f]{64}$ && -z "$detail" ]]; then
          state_hash="$value"
          state_hash_count=$((state_hash_count + 1))
        else
          fail "invalid state checksum at $MANIFEST_FILE:$line_number"
        fi
        ;;
      ee-toolkit-target-sha256)
        if [[ "$state_version" == "2" && "$value" =~ ^[0-9a-f]{64}$ && -z "$detail" ]]; then
          ee_toolkit_target_count=$((ee_toolkit_target_count + 1))
        else
          fail "invalid EE toolkit target state at $MANIFEST_FILE:$line_number"
        fi
        ;;
      pack)
        if [[ -z "$value" ]] || ! is_safe_name "$value" ||
          { [[ "$state_version" == "1" ]] && [[ -n "$detail" ]]; } ||
          { [[ "$state_version" == "2" ]] && { [[ ! "$detail" =~ ^[0-9a-f]{64}$ ]] || [[ -n "$extra" ]]; }; }; then
          fail "invalid pack state at $MANIFEST_FILE:$line_number"
        else
          append_unique_line "$value" "$packs_output"
          if [[ "$state_version" == "2" ]]; then
            manifest="$(pack_manifest_path "$PACKS_DIR" "$value")"
            if [[ ! -f "$manifest" || -L "$manifest" ]] || [[ "$(sha256_file "$manifest")" != "$detail" ]]; then
              fail "recorded pack contract changed for $value; rerun the installer after reviewing the pack diff"
            fi
          fi
        fi
        ;;
      dependency)
        case "$value" in
          git|codex|devcontainer|ralph|ee-toolkit)
            [[ -z "$detail" ]] && append_unique_line "$value" "$dependencies_output" || fail "invalid dependency state at $MANIFEST_FILE:$line_number"
            ;;
          *) fail "invalid dependency state at $MANIFEST_FILE:$line_number" ;;
        esac
        ;;
      guidance)
        if [[ "$value" == "git-safety" && -z "$detail" ]]; then
          append_unique_line "$value" "$guidance_output"
        else
          fail "invalid guidance state at $MANIFEST_FILE:$line_number"
        fi
        ;;
      skill)
        if [[ -z "$value" || -z "$detail" || -n "$extra" ]] || ! is_safe_name "$value" || [[ ! "$detail" =~ ^[0-9a-f]{64}$ ]]; then
          fail "invalid skill state at $MANIFEST_FILE:$line_number"
        else
          printf '%s %s\n' "$value" "$detail" >> "$skills_output"
        fi
        ;;
      *) fail "invalid managed state entry at $MANIFEST_FILE:$line_number" ;;
    esac
  done < "$MANIFEST_FILE"

  if [[ ! -s "$packs_output" || ! -s "$skills_output" ]]; then
    fail "managed install state has no selected packs or skills"
    return
  fi
  if [[ -n "$(awk 'NR > 1 && ($1 == "pack" || $1 == "dependency" || $1 == "guidance" || $1 == "skill") { print $1, $2 }' "$MANIFEST_FILE" | LC_ALL=C sort | uniq -d)" ]]; then
    fail "managed install state contains duplicate entries"
  fi
  if [[ "$state_version" == "2" ]] &&
    { [[ "$state_hash_count" -ne 1 ]] || [[ "$ee_toolkit_target_count" -gt 1 ]] || [[ "$(state_manifest_records_digest "$MANIFEST_FILE")" != "$state_hash" ]]; }; then
    fail "managed install state checksum does not match its recorded selection"
  fi
  if [[ "$state_version" == "2" ]]; then
    if grep -Eq '^(equal-experts-workflow|ee-[a-z0-9-]+) ' "$skills_output"; then
      [[ "$ee_toolkit_target_count" -eq 1 ]] || fail "managed EE skill state lacks one toolkit-target fingerprint"
      if [[ "$ee_toolkit_target_count" -eq 1 ]] &&
        [[ "$(awk '$1 == "ee-toolkit-target-sha256" { print $2; exit }' "$MANIFEST_FILE")" != "$(printf '%s' "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" | sha256_stream)" ]]; then
        fail "managed EE toolkit target fingerprint belongs to a different source clone; rerun the installer"
      fi
    elif [[ "$ee_toolkit_target_count" -ne 0 ]]; then
      fail "managed non-EE state contains an unexpected toolkit-target fingerprint"
    fi
  fi

  : > "$TEMP_DIR/expected-skills"
  : > "$TEMP_DIR/expected-dependencies"
  : > "$TEMP_DIR/expected-guidance"
  while IFS= read -r pack; do
    manifest="$(pack_manifest_path "$PACKS_DIR" "$pack")"
    if [[ ! -f "$manifest" || -L "$manifest" ]]; then
      fail "selected pack is missing: $pack"
      continue
    fi
    load_pack_manifest "$manifest" "$TEMP_DIR/expected-skills" "$TEMP_DIR/expected-dependencies" "$TEMP_DIR/expected-guidance" || fail "cannot load selected pack: $pack"
  done < "$packs_output"

  cut -d' ' -f1 "$skills_output" | LC_ALL=C sort -u > "$TEMP_DIR/state-skill-names"
  LC_ALL=C sort -u "$TEMP_DIR/expected-skills" > "$TEMP_DIR/expected-skill-names"
  if cmp -s "$TEMP_DIR/state-skill-names" "$TEMP_DIR/expected-skill-names"; then
    ok "managed skill selection matches pack manifests"
  else
    fail "managed skill selection differs from selected pack manifests"
  fi
  for kind in dependencies guidance; do
    LC_ALL=C sort -u "$TEMP_DIR/$kind" > "$TEMP_DIR/state-$kind"
    LC_ALL=C sort -u "$TEMP_DIR/expected-$kind" > "$TEMP_DIR/pack-$kind"
    if ! cmp -s "$TEMP_DIR/state-$kind" "$TEMP_DIR/pack-$kind"; then
      fail "managed $kind differ from selected pack manifests"
    fi
  done
}

check_dependencies() {
  local dependency
  local path_ralph
  local managed_ralph="$BIN_DIR/ralph"
  local source_codex_home

  while IFS= read -r dependency; do
    case "$dependency" in
      git)
        check_command git
        ;;
      codex)
        check_versioned_command codex "$CODEX_REQUIRED_VERSION"
        ;;
      devcontainer)
        check_versioned_command devcontainer "$DEVCONTAINER_REQUIRED_VERSION"
        ;;
      ralph)
        if verify_regular_file_sha256 "$managed_ralph" "$RALPH_PIN_CLI_SHA256" && [[ -x "$managed_ralph" ]]; then
          ok "pinned Ralph CLI: $managed_ralph"
        else
          fail "managed Ralph CLI is missing, non-executable, or differs from the reviewed pin"
        fi
        if verify_regular_file_sha256 "$RALPH_DEFAULTS_FILE" "$RALPH_PIN_GLOBAL_SKILL_DEFAULTS_SHA256" &&
          grep -Fxq 'RALPH_GLOBAL_SKILL_BACKEND=codex' "$RALPH_DEFAULTS_FILE" &&
          ! grep -Eq '^RALPH_GLOBAL_SKILL_MODEL=' "$RALPH_DEFAULTS_FILE"; then
          ok "managed Ralph global-skill defaults use Codex without forcing a model"
        else
          fail "managed Ralph global-skill defaults are missing, modified, forcing a model, or not set to Codex"
        fi
        if verify_regular_file_sha256 "$RALPH_CONFIG_DIR/prompts/build.md" "$RALPH_PIN_BUILD_PROMPT_SHA256"; then
          ok "pinned Ralph build prompt"
        else
          fail "managed Ralph build prompt is missing or differs from the reviewed pin"
        fi
        if verify_regular_file_sha256 "$RALPH_CONFIG_DIR/prompts/plan.md" "$RALPH_PIN_PLAN_PROMPT_SHA256"; then
          ok "pinned Ralph plan prompt"
        else
          fail "managed Ralph plan prompt is missing or differs from the reviewed pin"
        fi
        if verify_regular_file_sha256 "$RALPH_CONFIG_DIR/container/Dockerfile" "$RALPH_PIN_CONTAINER_DOCKERFILE_SHA256" &&
          verify_regular_file_sha256 "$RALPH_CONFIG_DIR/container/devcontainer.json" "$RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256"; then
          ok "pinned Ralph container configuration"
        else
          fail "managed Ralph container configuration is missing or differs from the reviewed pin"
        fi
        if verify_git_checkout_exact "$RALPH_SOURCE_DIR" "$RALPH_REPO_URL" "$RALPH_REVISION"; then
          ok "managed Ralph source is clean and pinned"
        else
          fail "managed Ralph source is missing, modified, has an unexpected origin, or differs from the pinned revision"
        fi
        if [[ -e "$RALPH_BACKEND_CODEX_HOME" || -L "$RALPH_BACKEND_CODEX_HOME" ]]; then
          source_codex_home="$(cd "$CODEX_CONFIG_DIR" 2>/dev/null && pwd -P)"
          if [[ -n "$source_codex_home" && -d "$RALPH_BACKEND_CODEX_HOME" && ! -L "$RALPH_BACKEND_CODEX_HOME" ]] &&
            ralph_backend_skills_are_isolated &&
            [[ ! -e "$RALPH_BACKEND_CODEX_HOME/AGENTS.md" && ! -L "$RALPH_BACKEND_CODEX_HOME/AGENTS.md" ]] &&
            { [[ ! -f "$source_codex_home/auth.json" && ! -e "$RALPH_BACKEND_CODEX_HOME/auth.json" && ! -L "$RALPH_BACKEND_CODEX_HOME/auth.json" ]] ||
              [[ -L "$RALPH_BACKEND_CODEX_HOME/auth.json" && "$(readlink "$RALPH_BACKEND_CODEX_HOME/auth.json")" == "$source_codex_home/auth.json" ]]; } &&
            { [[ ! -f "$source_codex_home/config.toml" && ! -e "$RALPH_BACKEND_CODEX_HOME/config.toml" && ! -L "$RALPH_BACKEND_CODEX_HOME/config.toml" ]] ||
              [[ -L "$RALPH_BACKEND_CODEX_HOME/config.toml" && "$(readlink "$RALPH_BACKEND_CODEX_HOME/config.toml")" == "$source_codex_home/config.toml" ]]; }; then
            ok "managed Ralph backend Codex home isolates global skills and reuses supervising auth/config"
          else
            fail "managed Ralph backend Codex home is invalid, stale, or exposes global skills/guidance"
          fi
        fi
        path_ralph="$(command -v ralph 2>/dev/null || true)"
        if [[ -n "$path_ralph" && "$path_ralph" != "$managed_ralph" ]]; then
          warn "PATH resolves ralph to $path_ralph; the global skill uses the verified managed CLI at $managed_ralph"
        elif [[ -z "$path_ralph" ]]; then
          warn "managed Ralph is not on PATH; the global skill still uses $managed_ralph directly"
        fi
        ;;
      ee-toolkit)
        if verify_ee_toolkit_exact "$SCRIPT_DIR"; then
          ok "EE toolkit is clean and matches the pinned gitlink"
        else
          fail "EE toolkit is missing, modified, has an unexpected origin, or differs from the pinned gitlink"
        fi
        ;;
    esac
  done < "$TEMP_DIR/dependencies"

  if grep -Fqx ralph "$TEMP_DIR/dependencies" || grep -Fqx devcontainer "$TEMP_DIR/dependencies"; then
    if command -v docker >/dev/null 2>&1; then
      if docker info >/dev/null 2>&1; then
        ok "Docker daemon is reachable"
      else
        warn "docker exists but the daemon is not reachable"
      fi
    else
      warn "docker command is missing; Ralph sandbox needs Docker"
    fi
  fi
}

check_skills() {
  local skill
  local recorded_hash
  local source_hash
  local installed_hash
  local installed="$SKILLS_DEST"
  local expected_toolkit
  local actual_toolkit
  local source_skill

  expected_toolkit="$(resolve_directory "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" 2>/dev/null || true)"
  while read -r skill recorded_hash; do
    if [[ "$HAS_MANAGED_STATE" -eq 0 ]]; then
      recorded_hash="$(hash_skill_directory "$SKILLS_SRC/$skill" 2>/dev/null || true)"
    fi
    source_skill="$SKILLS_SRC/$skill"
    if [[ ! -f "$source_skill/SKILL.md" || ! -f "$source_skill/agents/openai.yaml" ]]; then
      fail "source skill is incomplete: $skill"
      continue
    fi
    source_hash="$(hash_skill_directory "$source_skill" 2>/dev/null || true)"
    if [[ -z "$source_hash" || "$source_hash" != "$recorded_hash" ]]; then
      fail "source skill changed since installation: $skill"
    fi
    if [[ -L "$installed/$skill" || ! -d "$installed/$skill" ]]; then
      fail "installed skill is missing or not a regular directory: $skill"
      continue
    fi
    if is_ee_skill "$skill"; then
      installed_hash="$(hash_skill_directory "$installed/$skill" 1 2>/dev/null || true)"
    else
      installed_hash="$(hash_skill_directory "$installed/$skill" 2>/dev/null || true)"
    fi
    if [[ -n "$installed_hash" && "$installed_hash" == "$recorded_hash" ]]; then
      ok "installed skill matches managed source: $skill"
    else
      fail "installed skill differs from managed source: $skill"
    fi

    if is_ee_skill "$skill"; then
      actual_toolkit="$(resolve_symlink_directory "$installed/$skill/toolkit" 2>/dev/null || true)"
      if [[ -n "$expected_toolkit" && "$actual_toolkit" == "$expected_toolkit" ]]; then
        ok "EE toolkit link is exact for $skill"
      else
        fail "EE toolkit link is missing, broken, or points elsewhere for $skill"
      fi
    fi
  done < "$TEMP_DIR/skills"

  if [[ "$HAS_MANAGED_STATE" -eq 1 ]]; then
    for source_skill in "$SKILLS_SRC"/*; do
      [[ -d "$source_skill" ]] || continue
      skill="$(basename "$source_skill")"
      if [[ -d "$SKILLS_DEST/$skill" ]] && ! awk -v expected="$skill" '$1 == expected { found = 1 } END { exit(found ? 0 : 1) }' "$TEMP_DIR/skills"; then
        warn "repository skill is installed but not managed by the selected packs: $skill"
      fi
    done
  fi
  if [[ -d "$SKILLS_DEST/ralph-workflow" ]]; then
    warn "legacy unmanaged skill is still installed: ralph-workflow"
  fi
}

echo "Codex global skills doctor"
echo ""

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-doctor.XXXXXX")"
if [[ -d "$CODEX_CONFIG_DIR/.codex-global-skills/install.lock" ]]; then
  fail "installer lock is present: $CODEX_CONFIG_DIR/.codex-global-skills/install.lock"
fi
parse_managed_state

echo ""
check_dependencies

echo ""
if grep -Fqx git-safety "$TEMP_DIR/guidance"; then
  check_global_git_guidance
fi

echo ""
check_skills

exit "$status"
