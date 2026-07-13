#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
PACKS_DIR="$SCRIPT_DIR/packs"
GUIDANCE_SRC="$SCRIPT_DIR/guidance/git-safety.md"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DEST="$CODEX_CONFIG_DIR/skills"
GLOBAL_AGENTS_FILE="$CODEX_CONFIG_DIR/AGENTS.md"
MANAGED_STATE_DIR="$CODEX_CONFIG_DIR/.codex-global-skills"
MANIFEST_FILE="$MANAGED_STATE_DIR/manifest"
LOCK_DIR="$MANAGED_STATE_DIR/install.lock"
LEGACY_HASH_FILE="$SCRIPT_DIR/migrations/legacy-skill-hashes.tsv"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
RALPH_SOURCE_DIR="${RALPH_SOURCE_DIR:-$STATE_DIR/ralph}"
RALPH_PIN_FILE="$SCRIPT_DIR/skills/ralph/assets/ralph-pin.env"
if [[ ! -f "$RALPH_PIN_FILE" || -L "$RALPH_PIN_FILE" ]]; then
  echo "Reviewed Ralph pin contract is missing or invalid: $RALPH_PIN_FILE" >&2
  exit 1
fi
# shellcheck source=skills/ralph/assets/ralph-pin.env
source "$RALPH_PIN_FILE"
RALPH_REPO_URL="$RALPH_PIN_REPO_URL"
RALPH_REVISION="$RALPH_PIN_REVISION"
RALPH_RUNTIME_DIR="$STATE_DIR/ralph-runtimes/$RALPH_PIN_RUNTIME_ID"
BIN_DIR="${RALPH_BIN_DIR:-$RALPH_RUNTIME_DIR/bin}"
RALPH_CONFIG_DIR="${RALPH_CONFIG_DIR:-$RALPH_RUNTIME_DIR/config}"
CLI_PIN_FILE="$SCRIPT_DIR/pins/cli.env"
if [[ ! -f "$CLI_PIN_FILE" || -L "$CLI_PIN_FILE" ]]; then
  echo "Reviewed CLI pin contract is missing or invalid: $CLI_PIN_FILE" >&2
  exit 1
fi
# shellcheck source=pins/cli.env
source "$CLI_PIN_FILE"
GIT_GUIDANCE_START="<!-- codex-global-skills:git-safety:start -->"
GIT_GUIDANCE_END="<!-- codex-global-skills:git-safety:end -->"
GLOBAL_AGENTS_HEADING="# Global Codex Guidance"
DEFAULT_PACK="developer"
INSTALL_DEPENDENCIES=0
LIST_PACKS=0
EXPLICIT_PACK_SELECTION=0
REQUESTED_PACKS=()
TEMP_PATHS=()
LOCK_HELD=0
ACTIVE_SELECTION_DIR=""
TRANSACTION_COMMITTED=0
RALPH_RUNTIME_CREATED_PATHS=()
RALPH_RUNTIME_CREATED_HASHES=()
RALPH_RUNTIME_CREATED_MODES=()

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --pack <name>             Select a pack; repeat to install a union of packs.
  --install-dependencies    Install missing pinned CLIs and synchronize Ralph.
  --list-packs              List available packs and exit.
  --help                    Show this help.

With no --pack option, the installer reuses the previous managed selection or
installs the developer pack on the first run. Missing external dependencies are
reported unless --install-dependencies is explicitly supplied.
EOF
}

register_temp_path() {
  TEMP_PATHS+=("$1")
}

cleanup_temp_paths() {
  local exit_status="$?"
  local path

  trap - EXIT INT TERM
  rollback_incomplete_ralph_runtime || true
  if [[ -n "$ACTIVE_SELECTION_DIR" && -f "$ACTIVE_SELECTION_DIR/active-rollback" ]]; then
    if [[ "$TRANSACTION_COMMITTED" -eq 1 ]]; then
      finalize_skill_transaction "$ACTIVE_SELECTION_DIR" || true
      finalize_global_git_guidance "$ACTIVE_SELECTION_DIR" || true
    else
      rollback_skill_transaction "$ACTIVE_SELECTION_DIR" || true
      rollback_global_git_guidance "$ACTIVE_SELECTION_DIR" || true
    fi
  fi
  if [[ "${#TEMP_PATHS[@]}" -gt 0 ]]; then
    for path in "${TEMP_PATHS[@]}"; do
      if [[ -e "$path" || -L "$path" ]]; then
        rm -rf "$path"
      fi
    done
  fi
  if [[ "$LOCK_HELD" -eq 1 && -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
    rm -rf "$LOCK_DIR"
  fi
  exit "$exit_status"
}

rollback_incomplete_ralph_runtime() {
  local index
  local path
  local expected_hash
  local expected_mode

  if [[ "${#RALPH_RUNTIME_CREATED_PATHS[@]}" -eq 0 ]]; then
    return
  fi
  for ((index = 0; index < ${#RALPH_RUNTIME_CREATED_PATHS[@]}; index++)); do
    path="${RALPH_RUNTIME_CREATED_PATHS[$index]}"
    expected_hash="${RALPH_RUNTIME_CREATED_HASHES[$index]}"
    expected_mode="${RALPH_RUNTIME_CREATED_MODES[$index]}"
    if [[ -f "$path" && ! -L "$path" ]] &&
      [[ "$(sha256_file "$path")" == "$expected_hash" ]] &&
      [[ "$(file_mode "$path")" == "$expected_mode" ]]; then
      rm -f "$path"
    elif [[ -e "$path" || -L "$path" ]]; then
      echo "Preserving concurrently changed Ralph runtime path during rollback: $path" >&2
    fi
  done
  RALPH_RUNTIME_CREATED_PATHS=()
  RALPH_RUNTIME_CREATED_HASHES=()
  RALPH_RUNTIME_CREATED_MODES=()
}

trap cleanup_temp_paths EXIT
trap 'exit 130' INT TERM

list_packs() {
  local manifest

  for manifest in "$PACKS_DIR"/*.pack; do
    [[ -f "$manifest" ]] || continue
    basename "$manifest" .pack
  done | LC_ALL=C sort
}

append_git_guidance_block() {
  local destination="$1"

  printf '%s\n' "$GIT_GUIDANCE_START" >> "$destination"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >> "$destination"
  done < "$GUIDANCE_SRC"
  printf '%s\n' "$GIT_GUIDANCE_END" >> "$destination"
}

preflight_global_git_guidance() {
  local begin_count=0
  local end_count=0
  local begin_line
  local end_line

  if [[ ! -s "$GUIDANCE_SRC" ]]; then
    echo "Could not find global Git guidance: $GUIDANCE_SRC" >&2
    return 1
  fi

  if [[ -L "$GLOBAL_AGENTS_FILE" ]]; then
    echo "Cannot install global Git guidance: $GLOBAL_AGENTS_FILE is a symbolic link" >&2
    return 1
  fi
  if [[ -e "$GLOBAL_AGENTS_FILE" && ! -f "$GLOBAL_AGENTS_FILE" ]]; then
    echo "Cannot install global Git guidance: $GLOBAL_AGENTS_FILE is not a regular file" >&2
    return 1
  fi
  if [[ ! -e "$GLOBAL_AGENTS_FILE" ]]; then
    return
  fi

  begin_count="$(grep -Fxc -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" || true)"
  end_count="$(grep -Fxc -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" || true)"
  if [[ "$begin_count" -eq 0 && "$end_count" -eq 0 ]]; then
    return
  fi
  if [[ "$begin_count" -ne 1 || "$end_count" -ne 1 ]]; then
    echo "Cannot update global Git guidance: expected one matching managed marker pair in $GLOBAL_AGENTS_FILE" >&2
    return 1
  fi

  begin_line="$(grep -nFx -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
  end_line="$(grep -nFx -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
  if [[ "$begin_line" -ge "$end_line" ]]; then
    echo "Cannot update global Git guidance: managed markers are out of order in $GLOBAL_AGENTS_FILE" >&2
    return 1
  fi
}

install_global_git_guidance() {
  local selection_dir="$1"
  local agents_dir
  local temp_file
  local backup_file=""
  local begin_count=0
  local end_count=0
  local begin_line
  local end_line
  local last_byte
  local preimage_hash

  preflight_global_git_guidance || return 1
  agents_dir="$(dirname "$GLOBAL_AGENTS_FILE")"
  mkdir -p "$agents_dir" || return 1
  temp_file="$(mktemp "$agents_dir/.AGENTS.md.codex-global-skills.XXXXXX")" || return 1
  register_temp_path "$temp_file"

  if [[ ! -e "$GLOBAL_AGENTS_FILE" ]]; then
    : > "$selection_dir/AGENTS.was-absent"
    printf '%s\n\n' "$GLOBAL_AGENTS_HEADING" >> "$temp_file"
    append_git_guidance_block "$temp_file" || return 1
  else
    cp -p "$GLOBAL_AGENTS_FILE" "$temp_file" || return 1
    cp -p "$temp_file" "$selection_dir/AGENTS.before" || return 1
    preimage_hash="$(sha256_file "$temp_file")"
    printf '%s\n' "$preimage_hash" > "$selection_dir/AGENTS.preimage-hash"
    begin_count="$(grep -Fxc -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" || true)"
    end_count="$(grep -Fxc -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" || true)"
    if [[ "$begin_count" -eq 0 && "$end_count" -eq 0 ]]; then
      if [[ -s "$temp_file" ]]; then
        last_byte="$(tail -c 1 "$temp_file" | od -An -t x1 | tr -d '[:space:]')"
        if [[ "$last_byte" == "0a" ]]; then
          printf '\n' >> "$temp_file"
        else
          printf '\n\n' >> "$temp_file"
        fi
      else
        printf '%s\n\n' "$GLOBAL_AGENTS_HEADING" >> "$temp_file"
      fi
      append_git_guidance_block "$temp_file" || return 1
    else
      begin_line="$(grep -nFx -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
      end_line="$(grep -nFx -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
      head -n "$begin_line" "$GLOBAL_AGENTS_FILE" > "$temp_file" || return 1
      while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line" >> "$temp_file"
      done < "$GUIDANCE_SRC"
      tail -n "+$end_line" "$GLOBAL_AGENTS_FILE" >> "$temp_file" || return 1
    fi
  fi

  if [[ -f "$selection_dir/AGENTS.was-absent" ]]; then
    if [[ -e "$GLOBAL_AGENTS_FILE" || -L "$GLOBAL_AGENTS_FILE" ]]; then
      echo "Global AGENTS.md appeared during installation; preserving it and stopping" >&2
      return 1
    fi
  else
    if [[ -L "$GLOBAL_AGENTS_FILE" || ! -f "$GLOBAL_AGENTS_FILE" ]] ||
      [[ "$(sha256_file "$GLOBAL_AGENTS_FILE")" != "$preimage_hash" ]]; then
      echo "Global AGENTS.md changed during installation; preserving the concurrent edit and stopping" >&2
      return 1
    fi
  fi

  if [[ -f "$GLOBAL_AGENTS_FILE" ]] && cmp -s "$temp_file" "$GLOBAL_AGENTS_FILE"; then
    rm -f "$temp_file"
    echo "  Current:     $GLOBAL_AGENTS_FILE"
    return
  fi

  if [[ -f "$selection_dir/AGENTS.was-absent" ]]; then
    if ! ln "$temp_file" "$GLOBAL_AGENTS_FILE" 2>/dev/null; then
      echo "Could not atomically create global Git guidance" >&2
      return 1
    fi
  else
    backup_file="$(mktemp "$agents_dir/.AGENTS.md.codex-global-skills-backup.XXXXXX")" || return 1
    rm -f "$backup_file"
    if ! mv "$GLOBAL_AGENTS_FILE" "$backup_file"; then
      echo "Could not stage the existing global Git guidance for update" >&2
      return 1
    fi
    printf '%s\n' "$backup_file" > "$selection_dir/AGENTS.backup-path"
    if [[ -L "$backup_file" || ! -f "$backup_file" ]] ||
      [[ "$(sha256_file "$backup_file")" != "$preimage_hash" ]]; then
      if [[ ! -e "$GLOBAL_AGENTS_FILE" && ! -L "$GLOBAL_AGENTS_FILE" ]]; then
        mv "$backup_file" "$GLOBAL_AGENTS_FILE" || true
      fi
      echo "Global AGENTS.md changed while the transaction was starting; preserving the concurrent edit and stopping" >&2
      return 1
    fi
    if ! ln "$temp_file" "$GLOBAL_AGENTS_FILE" 2>/dev/null; then
      if [[ ! -e "$GLOBAL_AGENTS_FILE" && ! -L "$GLOBAL_AGENTS_FILE" ]]; then
        mv "$backup_file" "$GLOBAL_AGENTS_FILE" || true
      fi
      echo "Could not atomically update global Git guidance" >&2
      return 1
    fi
  fi
  rm -f "$temp_file"
  echo "  Installed:   $GLOBAL_AGENTS_FILE"
  if [[ -f "$GLOBAL_AGENTS_FILE" && ! -L "$GLOBAL_AGENTS_FILE" ]]; then
    sha256_file "$GLOBAL_AGENTS_FILE" > "$selection_dir/AGENTS.installed-hash"
  fi
}

rollback_global_git_guidance() {
  local selection_dir="$1"
  local installed_hash
  local current_hash
  local backup_file=""
  local recovery_file

  [[ -f "$selection_dir/AGENTS.installed-hash" ]] || return
  installed_hash="$(sed -n '1p' "$selection_dir/AGENTS.installed-hash")"
  if [[ -f "$selection_dir/AGENTS.backup-path" ]]; then
    backup_file="$(sed -n '1p' "$selection_dir/AGENTS.backup-path")"
  fi
  if [[ -f "$GLOBAL_AGENTS_FILE" && ! -L "$GLOBAL_AGENTS_FILE" ]]; then
    current_hash="$(sha256_file "$GLOBAL_AGENTS_FILE")"
    if [[ "$current_hash" == "$installed_hash" ]]; then
      rm -f "$GLOBAL_AGENTS_FILE"
    else
      recovery_file="$MANAGED_STATE_DIR/AGENTS.md.pre-install-recovery"
      if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        cp -p "$backup_file" "$recovery_file"
        echo "AGENTS.md changed concurrently; preserved the pre-install copy at $recovery_file" >&2
      fi
      return 1
    fi
  elif [[ -e "$GLOBAL_AGENTS_FILE" || -L "$GLOBAL_AGENTS_FILE" ]]; then
    echo "Could not roll back global guidance because AGENTS.md changed concurrently" >&2
    return 1
  fi

  if [[ -f "$selection_dir/AGENTS.was-absent" ]]; then
    return
  fi

  if [[ -n "$backup_file" && -f "$backup_file" ]]; then
    mv "$backup_file" "$GLOBAL_AGENTS_FILE"
  elif [[ -f "$selection_dir/AGENTS.before" ]]; then
    recovery_file="$MANAGED_STATE_DIR/AGENTS.md.pre-install-recovery"
    cp -p "$selection_dir/AGENTS.before" "$recovery_file"
    echo "AGENTS.md rollback backup was missing; preserved the pre-install copy at $recovery_file" >&2
    return 1
  fi
}

finalize_global_git_guidance() {
  local selection_dir="$1"
  local backup_file

  [[ -f "$selection_dir/AGENTS.backup-path" ]] || return 0
  backup_file="$(sed -n '1p' "$selection_dir/AGENTS.backup-path")"
  if [[ -n "$backup_file" && ( -e "$backup_file" || -L "$backup_file" ) ]]; then
    rm -f "$backup_file"
  fi
  rm -f "$selection_dir/AGENTS.backup-path"
}

preflight_managed_state() {
  if [[ -L "$MANAGED_STATE_DIR" || ( -e "$MANAGED_STATE_DIR" && ! -d "$MANAGED_STATE_DIR" ) ]]; then
    echo "Managed state directory is not a regular directory: $MANAGED_STATE_DIR" >&2
    return 1
  fi
  if [[ -L "$MANIFEST_FILE" || ( -e "$MANIFEST_FILE" && ! -f "$MANIFEST_FILE" ) ]]; then
    echo "Managed install state is not a regular file: $MANIFEST_FILE" >&2
    return 1
  fi
}

acquire_install_lock() {
  mkdir -p "$MANAGED_STATE_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another install may be active, or a stale lock exists: $LOCK_DIR" >&2
    return 1
  fi
  LOCK_HELD=1
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

validate_state_manifest() {
  local line_number=0
  local line
  local kind
  local value
  local detail
  local extra
  local state_version=""
  local state_hash=""
  local state_hash_count=0
  local ee_toolkit_target_count=0
  local pack_count=0
  local skill_count=0
  local pack_hashes_current=1
  local validation_dir
  local pack
  local recorded_pack_hash
  local pack_path

  if [[ ! -e "$MANIFEST_FILE" ]]; then
    return
  fi
  if [[ -L "$MANIFEST_FILE" || ! -f "$MANIFEST_FILE" ]]; then
    echo "Managed install state is not a regular file: $MANIFEST_FILE" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    IFS=' ' read -r kind value detail extra <<< "$line"
    if [[ "$line_number" -eq 1 ]]; then
      if [[ "$kind" != "version" || ( "$value" != "1" && "$value" != "2" ) || -n "$detail" ]]; then
        echo "Unsupported managed install state: $MANIFEST_FILE" >&2
        return 1
      fi
      state_version="$value"
      continue
    fi

    case "$kind" in
      state-sha256)
        if [[ "$state_version" != "2" || ! "$value" =~ ^[0-9a-f]{64}$ || -n "$detail" ]]; then
          echo "Invalid state checksum at $MANIFEST_FILE:$line_number" >&2
          return 1
        fi
        state_hash="$value"
        state_hash_count=$((state_hash_count + 1))
        ;;
      ee-toolkit-target-sha256)
        if [[ "$state_version" != "2" || ! "$value" =~ ^[0-9a-f]{64}$ || -n "$detail" ]]; then
          echo "Invalid EE toolkit target state at $MANIFEST_FILE:$line_number" >&2
          return 1
        fi
        ee_toolkit_target_count=$((ee_toolkit_target_count + 1))
        ;;
      pack)
        if [[ -z "$value" ]] || ! is_safe_name "$value" || [[ ! -f "$(pack_manifest_path "$PACKS_DIR" "$value")" ]] ||
          { [[ "$state_version" == "1" ]] && [[ -n "$detail" ]]; } ||
          { [[ "$state_version" == "2" ]] && { [[ ! "$detail" =~ ^[0-9a-f]{64}$ ]] || [[ -n "$extra" ]]; }; }; then
          echo "Invalid pack state at $MANIFEST_FILE:$line_number" >&2
          return 1
        fi
        pack_count=$((pack_count + 1))
        ;;
      dependency)
        if [[ -z "$value" || -n "$detail" ]]; then
          echo "Invalid dependency state at $MANIFEST_FILE:$line_number" >&2
          return 1
        fi
        case "$value" in
          git|codex|devcontainer|ralph|ee-toolkit) ;;
          *)
            echo "Invalid dependency state at $MANIFEST_FILE:$line_number" >&2
            return 1
            ;;
        esac
        ;;
      guidance)
        if [[ "$value" != "git-safety" || -n "$detail" ]]; then
          echo "Invalid guidance state at $MANIFEST_FILE:$line_number" >&2
          return 1
        fi
        ;;
      skill)
        if [[ -z "$value" || -z "$detail" || -n "$extra" ]] || ! is_safe_name "$value" || [[ ! "$detail" =~ ^[0-9a-f]{64}$ ]]; then
          echo "Invalid skill state at $MANIFEST_FILE:$line_number" >&2
          return 1
        fi
        if [[ ! -d "$SKILLS_SRC/$value" ]] && ! legacy_mode_hash_is_known "$value" "$detail"; then
          echo "Managed state claims an unknown skill at $MANIFEST_FILE:$line_number: $value" >&2
          return 1
        fi
        skill_count=$((skill_count + 1))
        ;;
      *)
        echo "Invalid managed state entry at $MANIFEST_FILE:$line_number" >&2
        return 1
        ;;
    esac
  done < "$MANIFEST_FILE"

  if [[ "$line_number" -eq 0 ]]; then
    echo "Managed install state is empty: $MANIFEST_FILE" >&2
    return 1
  fi
  if [[ "$pack_count" -eq 0 || "$skill_count" -eq 0 ]]; then
    echo "Managed install state must contain at least one pack and one skill: $MANIFEST_FILE" >&2
    return 1
  fi
  if [[ -n "$(awk 'NR > 1 && ($1 == "pack" || $1 == "dependency" || $1 == "guidance" || $1 == "skill") { print $1, $2 }' "$MANIFEST_FILE" | LC_ALL=C sort | uniq -d)" ]]; then
    echo "Managed install state contains duplicate entries: $MANIFEST_FILE" >&2
    return 1
  fi
  if [[ "$state_version" == "2" ]]; then
    if [[ "$state_hash_count" -ne 1 ]] || [[ "$ee_toolkit_target_count" -gt 1 ]] ||
      [[ "$(state_manifest_records_digest "$MANIFEST_FILE")" != "$state_hash" ]]; then
      echo "Managed install state checksum does not match its recorded selection: $MANIFEST_FILE" >&2
      return 1
    fi
    if awk '$1 == "skill" && ($2 == "equal-experts-workflow" || $2 ~ /^ee-/) { found = 1 } END { exit(found ? 0 : 1) }' "$MANIFEST_FILE"; then
      if [[ "$ee_toolkit_target_count" -ne 1 ]]; then
        echo "Managed EE skill state lacks one toolkit-target fingerprint: $MANIFEST_FILE" >&2
        return 1
      fi
    elif [[ "$ee_toolkit_target_count" -ne 0 ]]; then
      echo "Managed non-EE state contains an unexpected toolkit-target fingerprint: $MANIFEST_FILE" >&2
      return 1
    fi
    while read -r _ pack recorded_pack_hash _; do
      pack_path="$(pack_manifest_path "$PACKS_DIR" "$pack")"
      if [[ "$(sha256_file "$pack_path")" != "$recorded_pack_hash" ]]; then
        pack_hashes_current=0
      fi
    done < <(awk '$1 == "pack" { print }' "$MANIFEST_FILE")
  fi

  if [[ "$state_version" == "1" || "$pack_hashes_current" -eq 1 ]]; then
    validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-state-validation.XXXXXX")"
    register_temp_path "$validation_dir"
    : > "$validation_dir/skills"
    : > "$validation_dir/dependencies"
    : > "$validation_dir/guidance"
    while read -r _ pack _ _; do
      load_pack_manifest "$(pack_manifest_path "$PACKS_DIR" "$pack")" \
        "$validation_dir/skills" "$validation_dir/dependencies" "$validation_dir/guidance"
    done < <(awk '$1 == "pack" { print }' "$MANIFEST_FILE")
    awk '$1 == "skill" { print $2 }' "$MANIFEST_FILE" | LC_ALL=C sort -u > "$validation_dir/state-skills"
    awk '$1 == "dependency" { print $2 }' "$MANIFEST_FILE" | LC_ALL=C sort -u > "$validation_dir/state-dependencies"
    awk '$1 == "guidance" { print $2 }' "$MANIFEST_FILE" | LC_ALL=C sort -u > "$validation_dir/state-guidance"
    LC_ALL=C sort -u "$validation_dir/skills" > "$validation_dir/expected-skills"
    LC_ALL=C sort -u "$validation_dir/dependencies" > "$validation_dir/expected-dependencies"
    LC_ALL=C sort -u "$validation_dir/guidance" > "$validation_dir/expected-guidance"
    if ! cmp -s "$validation_dir/state-skills" "$validation_dir/expected-skills" ||
      ! cmp -s "$validation_dir/state-dependencies" "$validation_dir/expected-dependencies" ||
      ! cmp -s "$validation_dir/state-guidance" "$validation_dir/expected-guidance"; then
      echo "Managed install state does not match its recorded pack selection: $MANIFEST_FILE" >&2
      return 1
    fi
  fi
}

parse_arguments() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --pack)
        if [[ "$#" -lt 2 ]] || ! is_safe_name "$2"; then
          echo "--pack requires a lowercase hyphenated pack name" >&2
          exit 2
        fi
        REQUESTED_PACKS+=("$2")
        EXPLICIT_PACK_SELECTION=1
        shift 2
        ;;
      --install-dependencies)
        INSTALL_DEPENDENCIES=1
        shift
        ;;
      --list-packs)
        LIST_PACKS=1
        shift
        ;;
      --help|-h)
        usage
        exit
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
}

prepare_selection() {
  local selection_dir="$1"
  local packs_output="$selection_dir/packs"
  local skills_output="$selection_dir/skills"
  local dependencies_output="$selection_dir/dependencies"
  local guidance_output="$selection_dir/guidance"
  local pack
  local manifest

  : > "$packs_output"
  : > "$skills_output"
  : > "$dependencies_output"
  : > "$guidance_output"

  if [[ "$EXPLICIT_PACK_SELECTION" -eq 0 && -f "$MANIFEST_FILE" ]]; then
    while IFS= read -r pack; do
      [[ -n "$pack" ]] && REQUESTED_PACKS+=("$pack")
    done < <(awk '$1 == "pack" { print $2 }' "$MANIFEST_FILE")
  fi
  if [[ "${#REQUESTED_PACKS[@]}" -eq 0 ]]; then
    REQUESTED_PACKS+=("$DEFAULT_PACK")
  fi

  for pack in "${REQUESTED_PACKS[@]}"; do
    manifest="$(pack_manifest_path "$PACKS_DIR" "$pack")"
    if [[ ! -f "$manifest" || -L "$manifest" ]]; then
      echo "Unknown pack: $pack" >&2
      return 1
    fi
    append_unique_line "$pack" "$packs_output"
    load_pack_manifest "$manifest" "$skills_output" "$dependencies_output" "$guidance_output"
  done

  if [[ ! -s "$skills_output" ]]; then
    echo "Selected packs contain no skills" >&2
    return 1
  fi
}

preflight_ralph_source() {
  local actual_remote
  local dirty

  if [[ ! "$RALPH_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
    echo "RALPH_REVISION must be a pinned 40-character commit" >&2
    return 1
  fi
  if [[ ! -e "$RALPH_SOURCE_DIR" ]]; then
    return
  fi
  if [[ -L "$RALPH_SOURCE_DIR" || ! -d "$RALPH_SOURCE_DIR" ]]; then
    echo "Refusing to replace unknown Ralph path: $RALPH_SOURCE_DIR" >&2
    return 1
  fi
  if ! git -C "$RALPH_SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Refusing to replace non-Git Ralph path: $RALPH_SOURCE_DIR" >&2
    return 1
  fi
  actual_remote="$(git -C "$RALPH_SOURCE_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$actual_remote" || "$actual_remote" != "$RALPH_REPO_URL" ]]; then
    echo "Refusing to update Ralph because its origin does not match the configured repository" >&2
    return 1
  fi
  dirty="$(git -C "$RALPH_SOURCE_DIR" status --porcelain --untracked-files=all)"
  if [[ -n "$dirty" ]]; then
    echo "Refusing to update a modified Ralph checkout: $RALPH_SOURCE_DIR" >&2
    return 1
  fi
}

verify_pinned_ralph_install() {
  verify_regular_file_sha256 "$BIN_DIR/ralph" "$RALPH_PIN_CLI_SHA256" &&
    [[ -x "$BIN_DIR/ralph" ]] &&
    verify_regular_file_sha256 "$RALPH_CONFIG_DIR/prompts/plan.md" "$RALPH_PIN_PLAN_PROMPT_SHA256" &&
    verify_regular_file_sha256 "$RALPH_CONFIG_DIR/prompts/build.md" "$RALPH_PIN_BUILD_PROMPT_SHA256" &&
    verify_regular_file_sha256 "$RALPH_CONFIG_DIR/container/Dockerfile" "$RALPH_PIN_CONTAINER_DOCKERFILE_SHA256" &&
    verify_regular_file_sha256 "$RALPH_CONFIG_DIR/container/devcontainer.json" "$RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256" &&
    verify_git_checkout_exact "$RALPH_SOURCE_DIR" "$RALPH_REPO_URL" "$RALPH_REVISION"
}

preflight_ralph_runtime_directory() {
  local directory="$1"

  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    echo "Refusing to use a non-regular Ralph runtime directory: $directory" >&2
    return 1
  fi
}

preflight_ralph_runtime_file() {
  local source="$1"
  local destination="$2"
  local expected_hash="$3"
  local expected_mode="$4"

  if ! verify_regular_file_sha256 "$source" "$expected_hash"; then
    echo "Pinned Ralph source file differs from the reviewed contract: $source" >&2
    return 1
  fi
  if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
    echo "Refusing to replace a non-regular Ralph runtime path: $destination" >&2
    return 1
  fi
  if [[ -f "$destination" ]] &&
    { [[ "$(sha256_file "$destination")" != "$expected_hash" ]] || [[ "$(file_mode "$destination")" != "$expected_mode" ]]; }; then
    echo "Refusing to overwrite modified or unmanaged Ralph runtime file: $destination" >&2
    return 1
  fi
}

publish_ralph_runtime_file() {
  local source="$1"
  local destination="$2"
  local expected_hash="$3"
  local expected_mode="$4"
  local parent
  local staged

  if [[ -f "$destination" && ! -L "$destination" ]]; then
    return
  fi
  parent="$(dirname "$destination")"
  mkdir -p "$parent"
  preflight_ralph_runtime_directory "$parent"
  staged="$(mktemp "$parent/.ralph-runtime.XXXXXX")"
  register_temp_path "$staged"
  cp "$source" "$staged"
  chmod "$expected_mode" "$staged"
  if ! verify_regular_file_sha256 "$staged" "$expected_hash" || [[ "$(file_mode "$staged")" != "$expected_mode" ]]; then
    echo "Staged Ralph runtime file failed verification: $destination" >&2
    return 1
  fi
  if ! ln "$staged" "$destination" 2>/dev/null; then
    echo "Ralph runtime path appeared during installation; preserving it and stopping: $destination" >&2
    return 1
  fi
  RALPH_RUNTIME_CREATED_PATHS+=("$destination")
  RALPH_RUNTIME_CREATED_HASHES+=("$expected_hash")
  RALPH_RUNTIME_CREATED_MODES+=("$expected_mode")
  rm -f "$staged"
  echo "  Installed:   $destination"
}

install_reviewed_ralph_runtime() {
  local cli_source="$RALPH_SOURCE_DIR/ralph"
  local plan_source="$RALPH_SOURCE_DIR/prompts/plan.md"
  local build_source="$RALPH_SOURCE_DIR/prompts/build.md"
  local docker_source="$RALPH_SOURCE_DIR/container/Dockerfile"
  local devcontainer_source="$RALPH_SOURCE_DIR/container/devcontainer.json"

  preflight_ralph_runtime_directory "$STATE_DIR" || return 1
  preflight_ralph_runtime_directory "$BIN_DIR" || return 1
  preflight_ralph_runtime_directory "$RALPH_CONFIG_DIR" || return 1
  preflight_ralph_runtime_directory "$RALPH_CONFIG_DIR/prompts" || return 1
  preflight_ralph_runtime_directory "$RALPH_CONFIG_DIR/container" || return 1
  preflight_ralph_runtime_file "$cli_source" "$BIN_DIR/ralph" "$RALPH_PIN_CLI_SHA256" 755 || return 1
  preflight_ralph_runtime_file "$plan_source" "$RALPH_CONFIG_DIR/prompts/plan.md" "$RALPH_PIN_PLAN_PROMPT_SHA256" 644 || return 1
  preflight_ralph_runtime_file "$build_source" "$RALPH_CONFIG_DIR/prompts/build.md" "$RALPH_PIN_BUILD_PROMPT_SHA256" 644 || return 1
  preflight_ralph_runtime_file "$docker_source" "$RALPH_CONFIG_DIR/container/Dockerfile" "$RALPH_PIN_CONTAINER_DOCKERFILE_SHA256" 644 || return 1
  preflight_ralph_runtime_file "$devcontainer_source" "$RALPH_CONFIG_DIR/container/devcontainer.json" "$RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256" 644 || return 1

  publish_ralph_runtime_file "$cli_source" "$BIN_DIR/ralph" "$RALPH_PIN_CLI_SHA256" 755 || return 1
  publish_ralph_runtime_file "$plan_source" "$RALPH_CONFIG_DIR/prompts/plan.md" "$RALPH_PIN_PLAN_PROMPT_SHA256" 644 || return 1
  publish_ralph_runtime_file "$build_source" "$RALPH_CONFIG_DIR/prompts/build.md" "$RALPH_PIN_BUILD_PROMPT_SHA256" 644 || return 1
  publish_ralph_runtime_file "$docker_source" "$RALPH_CONFIG_DIR/container/Dockerfile" "$RALPH_PIN_CONTAINER_DOCKERFILE_SHA256" 644 || return 1
  publish_ralph_runtime_file "$devcontainer_source" "$RALPH_CONFIG_DIR/container/devcontainer.json" "$RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256" 644 || return 1

  if ! verify_pinned_ralph_install; then
    echo "Ralph installation does not match the reviewed pinned runtime contract" >&2
    return 1
  fi
  RALPH_RUNTIME_CREATED_PATHS=()
  RALPH_RUNTIME_CREATED_HASHES=()
  RALPH_RUNTIME_CREATED_MODES=()
}

install_or_update_ralph() {
  local clone_parent
  local clone_temp
  local checkout="$RALPH_SOURCE_DIR"
  local actual_revision

  preflight_ralph_source
  mkdir -p "$STATE_DIR" "$BIN_DIR"

  if [[ ! -e "$RALPH_SOURCE_DIR" ]]; then
    clone_parent="$(dirname "$RALPH_SOURCE_DIR")"
    mkdir -p "$clone_parent"
    clone_temp="$(mktemp -d "$clone_parent/.ralph.clone.XXXXXX")"
    register_temp_path "$clone_temp"
    echo "Cloning pinned Ralph source..."
    git clone --filter=blob:none --no-checkout "$RALPH_REPO_URL" "$clone_temp"
    checkout="$clone_temp"
  else
    echo "Refreshing pinned Ralph source..."
  fi

  git -C "$checkout" fetch --force --tags origin
  if ! git -C "$checkout" cat-file -e "$RALPH_REVISION^{commit}" 2>/dev/null; then
    git -C "$checkout" fetch origin "$RALPH_REVISION"
  fi
  git -C "$checkout" checkout --detach "$RALPH_REVISION"
  actual_revision="$(git -C "$checkout" rev-parse HEAD)"
  if [[ "$actual_revision" != "$RALPH_REVISION" ]]; then
    echo "Ralph checkout did not resolve to the pinned revision" >&2
    return 1
  fi

  if [[ "$checkout" != "$RALPH_SOURCE_DIR" ]]; then
    mv "$checkout" "$RALPH_SOURCE_DIR"
  fi

  echo "Installing reviewed Ralph runtime files from $RALPH_REVISION..."
  install_reviewed_ralph_runtime
}

installed_command_version() {
  local command_name="$1"

  case "$command_name" in
    codex)
      codex --version 2>/dev/null | sed -n '1s/.* //p'
      ;;
    devcontainer)
      devcontainer --version 2>/dev/null | sed -n '1p'
      ;;
  esac
}

ensure_npm_package() {
  local command_name="$1"
  local package_name="$2"
  local required_version="$3"
  local actual_version=""

  if command -v "$command_name" >/dev/null 2>&1; then
    actual_version="$(installed_command_version "$command_name" || true)"
    if [[ "$actual_version" == "$required_version" ]]; then
      echo "  Found:       $command_name $actual_version"
      return
    fi
    if [[ "$INSTALL_DEPENDENCIES" -ne 1 ]]; then
      echo "Dependency version mismatch: $command_name ${actual_version:-unknown} (required $required_version)" >&2
      echo "Rerun with --install-dependencies to install $package_name." >&2
      return 1
    fi
  fi
  if [[ "$INSTALL_DEPENDENCIES" -ne 1 ]]; then
    echo "Missing dependency: $command_name" >&2
    echo "Rerun with --install-dependencies to install the pinned package $package_name." >&2
    return 1
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "Missing npm; install Node.js/npm before installing $package_name" >&2
    return 1
  fi

  echo "  Installing:  $package_name"
  npm install -g "$package_name"
  actual_version="$(installed_command_version "$command_name" || true)"
  if [[ "$actual_version" != "$required_version" ]]; then
    echo "Installed $command_name did not resolve to required version $required_version (found ${actual_version:-unknown})" >&2
    return 1
  fi
}

ensure_ee_toolkit() {
  local toolkit="$SCRIPT_DIR/vendor/equalexperts/llm-toolkit"

  if [[ "$INSTALL_DEPENDENCIES" -ne 1 ]]; then
    if verify_ee_toolkit_exact "$SCRIPT_DIR"; then
      echo "  Found:       ee-toolkit (clean and pinned)"
      return
    fi
    echo "EE toolkit is missing, modified, or not at the pinned gitlink" >&2
    echo "Rerun with --install-dependencies to synchronize the pinned submodule." >&2
    return 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "Missing git; install it before initializing the EE toolkit" >&2
    return 1
  fi

  echo "Synchronizing pinned EE toolkit..."
  git -C "$SCRIPT_DIR" submodule sync -- vendor/equalexperts/llm-toolkit
  git -C "$SCRIPT_DIR" submodule update --init --recursive -- vendor/equalexperts/llm-toolkit
  if ! verify_ee_toolkit_exact "$SCRIPT_DIR"; then
    echo "EE toolkit synchronization did not produce the clean pinned gitlink" >&2
    return 1
  fi
}

preflight_ee_toolkit() {
  local toolkit="$SCRIPT_DIR/vendor/equalexperts/llm-toolkit"

  if [[ ! -e "$toolkit" ]]; then
    return
  fi
  if [[ -L "$toolkit" || ! -d "$toolkit" ]]; then
    echo "EE toolkit path is not a regular directory: $toolkit" >&2
    return 1
  fi
  if [[ -e "$toolkit/.git" ]]; then
    if ! git -C "$toolkit" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "EE toolkit path is not a valid Git checkout: $toolkit" >&2
      return 1
    fi
    if [[ -n "$(git -C "$toolkit" status --porcelain --untracked-files=all)" ]]; then
      echo "Refusing to synchronize a modified EE toolkit checkout: $toolkit" >&2
      return 1
    fi
    local expected_url
    local actual_url
    expected_url="$(git -C "$SCRIPT_DIR" config -f .gitmodules --get submodule.vendor/equalexperts/llm-toolkit.url 2>/dev/null || true)"
    actual_url="$(git -C "$toolkit" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$expected_url" || "$actual_url" != "$expected_url" ]]; then
      echo "Refusing to synchronize an EE toolkit checkout with an unexpected origin" >&2
      return 1
    fi
  elif [[ -n "$(find "$toolkit" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Refusing to replace an unrecognized EE toolkit directory: $toolkit" >&2
    return 1
  fi
}

ensure_dependencies() {
  local dependencies_file="$1"
  local dependency

  if grep -Fqx ralph "$dependencies_file" && [[ "$INSTALL_DEPENDENCIES" -eq 1 ]]; then
    if ! command -v git >/dev/null 2>&1; then
      echo "Missing git; install it before installing Ralph" >&2
      return 1
    fi
    preflight_ralph_source
  fi
  if grep -Fqx ee-toolkit "$dependencies_file" && [[ "$INSTALL_DEPENDENCIES" -eq 1 ]]; then
    if ! command -v git >/dev/null 2>&1; then
      echo "Missing git; install it before synchronizing the EE toolkit" >&2
      return 1
    fi
    preflight_ee_toolkit
  fi
  if [[ "$INSTALL_DEPENDENCIES" -eq 1 ]] &&
    { { grep -Fqx codex "$dependencies_file" && ! command -v codex >/dev/null 2>&1; } ||
      { grep -Fqx devcontainer "$dependencies_file" && ! command -v devcontainer >/dev/null 2>&1; }; } &&
    ! command -v npm >/dev/null 2>&1; then
    echo "Missing npm; install Node.js/npm before installing selected CLI dependencies" >&2
    return 1
  fi

  while IFS= read -r dependency; do
    case "$dependency" in
      git)
        if command -v git >/dev/null 2>&1; then
          echo "  Found:       git"
        else
          echo "Missing dependency: git (install it manually and rerun)" >&2
          return 1
        fi
        ;;
      codex)
        ensure_npm_package codex "$CODEX_NPM_PACKAGE" "$CODEX_REQUIRED_VERSION"
        ;;
      devcontainer)
        ensure_npm_package devcontainer "$DEVCONTAINER_NPM_PACKAGE" "$DEVCONTAINER_REQUIRED_VERSION"
        ;;
      ralph)
        if [[ "$INSTALL_DEPENDENCIES" -eq 1 ]]; then
          install_or_update_ralph
        elif verify_pinned_ralph_install; then
          echo "  Found:       pinned Ralph at $BIN_DIR/ralph"
        else
          echo "Pinned Ralph is missing or inconsistent (CLI, prompt, source, revision, origin, or cleanliness)" >&2
          echo "Rerun with --install-dependencies to synchronize the reviewed Ralph installation." >&2
          return 1
        fi
        ;;
      ee-toolkit)
        ensure_ee_toolkit
        ;;
    esac
  done < "$dependencies_file"
}

legacy_hash_is_known() {
  local skill="$1"
  local digest="$2"

  [[ -f "$LEGACY_HASH_FILE" ]] || return 1
  awk -F '\t' -v expected_skill="$skill" -v expected_digest="$digest" '
    $1 == expected_skill && $2 == expected_digest { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$LEGACY_HASH_FILE"
}

legacy_mode_hash_is_known() {
  local skill="$1"
  local mode_digest="$2"

  [[ -f "$LEGACY_HASH_FILE" ]] || return 1
  awk -F '\t' -v expected_skill="$skill" -v expected_mode_digest="$mode_digest" '
    $1 == expected_skill && $3 == expected_mode_digest { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$LEGACY_HASH_FILE"
}

legacy_install_is_known() {
  local skill="$1"
  local digest="$2"
  local mode_digest="$3"

  [[ -f "$LEGACY_HASH_FILE" ]] || return 1
  awk -F '\t' -v expected_skill="$skill" -v expected_digest="$digest" -v expected_mode_digest="$mode_digest" '
    $1 == expected_skill && $2 == expected_digest && $3 == expected_mode_digest { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$LEGACY_HASH_FILE"
}

installed_toolkit_link_is_exact() {
  local skill_directory="$1"

  [[ -L "$skill_directory/toolkit" ]] &&
    [[ "$(readlink "$skill_directory/toolkit")" == "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" ]]
}

installed_toolkit_link_matches_recorded_target() {
  local skill_directory="$1"
  local recorded_hash
  local link_target

  [[ -f "$MANIFEST_FILE" && -L "$skill_directory/toolkit" ]] || return 1
  recorded_hash="$(awk '$1 == "ee-toolkit-target-sha256" { print $2; found = 1; exit } END { if (!found) exit 1 }' "$MANIFEST_FILE")" || return 1
  link_target="$(readlink "$skill_directory/toolkit")"
  [[ "$link_target" == /* ]] || return 1
  [[ "$(printf '%s' "$link_target" | sha256_stream)" == "$recorded_hash" ]]
}

legacy_ee_toolkit_target() {
  local skill_directory="$1"
  local target

  [[ -L "$skill_directory/toolkit" ]] || return 1
  target="$(readlink "$skill_directory/toolkit")"
  [[ "$target" == /*/vendor/equalexperts/llm-toolkit ]] || return 1
  printf '%s\n' "$target"
}

hash_installed_skill() {
  local skill="$1"
  local directory="$2"

  if is_ee_skill "$skill"; then
    hash_skill_directory "$directory" 1
  else
    hash_skill_directory "$directory"
  fi
}

hash_installed_skill_legacy() {
  local skill="$1"
  local directory="$2"

  if is_ee_skill "$skill"; then
    hash_skill_directory_legacy "$directory" 1
  else
    hash_skill_directory_legacy "$directory"
  fi
}

preflight_skill_destinations() {
  local selection_dir="$1"
  local skills_file="$selection_dir/skills"
  local records_file="$selection_dir/skill-records"
  local obsolete_file="$selection_dir/obsolete-skills"
  local destinations_file="$selection_dir/destination-records"
  local toolkit_targets_file="$selection_dir/toolkit-target-records"
  local skill
  local source_dir
  local destination
  local source_hash
  local installed_hash
  local legacy_installed_hash
  local expected_hash
  local old_hash
  local state_owned
  local legacy_owned
  local legacy_ee_target=""
  local toolkit_target

  : > "$records_file"
  : > "$obsolete_file"
  : > "$destinations_file"
  : > "$toolkit_targets_file"
  if [[ -L "$SKILLS_DEST" || ( -e "$SKILLS_DEST" && ! -d "$SKILLS_DEST" ) ]]; then
    echo "Skills destination must be a regular directory: $SKILLS_DEST" >&2
    return 1
  fi

  while IFS= read -r skill; do
    source_dir="$SKILLS_SRC/$skill"
    destination="$SKILLS_DEST/$skill"
    if [[ ! -f "$source_dir/SKILL.md" || ! -f "$source_dir/agents/openai.yaml" || -L "$source_dir" ]]; then
      echo "Incomplete source skill: $source_dir" >&2
      return 1
    fi
    source_hash="$(hash_skill_directory "$source_dir")"
    printf '%s %s\n' "$skill" "$source_hash" >> "$records_file"

    if [[ -e "$destination" || -L "$destination" ]]; then
      if [[ -L "$destination" || ! -d "$destination" ]]; then
        echo "Refusing to replace non-directory installed skill: $destination" >&2
        return 1
      fi
      installed_hash="$(hash_installed_skill "$skill" "$destination")"
      state_owned=0
      legacy_owned=0
      if old_hash="$(state_skill_hash "$MANIFEST_FILE" "$skill" 2>/dev/null)"; then
        expected_hash="$old_hash"
        state_owned=1
      else
        legacy_installed_hash="$(hash_installed_skill_legacy "$skill" "$destination")"
        if legacy_install_is_known "$skill" "$legacy_installed_hash" "$installed_hash"; then
          expected_hash="$installed_hash"
          legacy_owned=1
          echo "  Adopting:    legacy managed skill $skill"
        else
          expected_hash="$source_hash"
        fi
      fi
      if [[ "$installed_hash" != "$expected_hash" ]]; then
        echo "Refusing to overwrite modified or unmanaged skill: $destination" >&2
        return 1
      fi
      if is_ee_skill "$skill" && ! installed_toolkit_link_is_exact "$destination"; then
        if [[ "$state_owned" -eq 1 ]] && installed_toolkit_link_matches_recorded_target "$destination"; then
          echo "  Relocating:  managed EE toolkit link for $skill"
        elif [[ "$legacy_owned" -eq 1 ]] && toolkit_target="$(legacy_ee_toolkit_target "$destination")"; then
          if [[ -n "$legacy_ee_target" && "$toolkit_target" != "$legacy_ee_target" ]]; then
            echo "Refusing to relocate legacy EE skills with inconsistent toolkit targets" >&2
            return 1
          fi
          legacy_ee_target="$toolkit_target"
          echo "  Relocating:  approved legacy EE toolkit link for $skill"
        else
          echo "Refusing to replace an EE skill with an unexpected toolkit path: $destination" >&2
          return 1
        fi
      fi
      if is_ee_skill "$skill"; then
        printf '%s %s\n' "$skill" "$(printf '%s' "$(readlink "$destination/toolkit")" | sha256_stream)" >> "$toolkit_targets_file"
      fi
      printf '%s %s\n' "$skill" "$installed_hash" >> "$destinations_file"
    else
      printf '%s absent\n' "$skill" >> "$destinations_file"
    fi
  done < "$skills_file"

  if [[ -f "$MANIFEST_FILE" ]]; then
    while read -r _ skill old_hash _; do
      [[ -n "$skill" ]] || continue
      if grep -Fqx -- "$skill" "$skills_file"; then
        continue
      fi
      append_unique_line "$skill" "$obsolete_file"
      destination="$SKILLS_DEST/$skill"
      if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        printf '%s absent\n' "$skill" >> "$destinations_file"
        continue
      fi
      if [[ -L "$destination" || ! -d "$destination" ]]; then
        echo "Refusing to remove non-directory managed skill: $destination" >&2
        return 1
      fi
      if is_ee_skill "$skill" && ! installed_toolkit_link_is_exact "$destination" &&
        ! installed_toolkit_link_matches_recorded_target "$destination"; then
        echo "Refusing to remove an EE skill with an unexpected toolkit path: $destination" >&2
        return 1
      fi
      installed_hash="$(hash_installed_skill "$skill" "$destination")"
      if [[ "$installed_hash" != "$old_hash" ]]; then
        echo "Refusing to remove locally modified managed skill: $destination" >&2
        return 1
      fi
      if is_ee_skill "$skill"; then
        printf '%s %s\n' "$skill" "$(printf '%s' "$(readlink "$destination/toolkit")" | sha256_stream)" >> "$toolkit_targets_file"
      fi
      printf '%s %s\n' "$skill" "$installed_hash" >> "$destinations_file"
    done < <(awk '$1 == "skill" { print }' "$MANIFEST_FILE")
  fi
}

revalidate_skill_destinations() {
  local selection_dir="$1"
  local skill
  local expected_hash
  local destination
  local actual_hash
  local expected_toolkit_hash
  local actual_toolkit_hash

  while read -r skill expected_hash; do
    destination="$SKILLS_DEST/$skill"
    if [[ "$expected_hash" == "absent" ]]; then
      if [[ -e "$destination" || -L "$destination" ]]; then
        echo "Installed skill appeared after preflight; refusing to replace it: $destination" >&2
        return 1
      fi
      continue
    fi
    if [[ -L "$destination" || ! -d "$destination" ]]; then
      echo "Installed skill changed after preflight: $destination" >&2
      return 1
    fi
    if is_ee_skill "$skill"; then
      expected_toolkit_hash="$(awk -v expected="$skill" '$1 == expected { print $2; exit }' "$selection_dir/toolkit-target-records")"
      if [[ -z "$expected_toolkit_hash" || ! -L "$destination/toolkit" ]]; then
        echo "EE toolkit link changed after preflight: $destination" >&2
        return 1
      fi
      actual_toolkit_hash="$(printf '%s' "$(readlink "$destination/toolkit")" | sha256_stream)"
      if [[ "$actual_toolkit_hash" != "$expected_toolkit_hash" ]]; then
        echo "EE toolkit link changed after preflight: $destination" >&2
        return 1
      fi
    fi
    actual_hash="$(hash_installed_skill "$skill" "$destination")"
    if [[ "$actual_hash" != "$expected_hash" ]]; then
      echo "Installed skill changed after preflight; preserving concurrent edits: $destination" >&2
      return 1
    fi
  done < "$selection_dir/destination-records"
}

stage_selected_skills() {
  local selection_dir="$1"
  local records_file="$selection_dir/skill-records"
  local staging_dir="$2"
  local skill
  local expected_hash
  local staged_hash

  while read -r skill expected_hash; do
    mkdir -p "$staging_dir/$skill"
    cp -R "$SKILLS_SRC/$skill/." "$staging_dir/$skill/"
    if is_ee_skill "$skill"; then
      ln -s "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" "$staging_dir/$skill/toolkit"
    fi
    if is_ee_skill "$skill"; then
      staged_hash="$(hash_skill_directory "$staging_dir/$skill" 1)"
    else
      staged_hash="$(hash_skill_directory "$staging_dir/$skill")"
    fi
    if [[ "$staged_hash" != "$expected_hash" ]]; then
      echo "Staged skill hash mismatch: $skill" >&2
      return 1
    fi
  done < "$records_file"
}

verify_moved_skill_preimage() {
  local selection_dir="$1"
  local skill="$2"
  local moved_path="$3"
  local expected_hash
  local actual_hash
  local expected_toolkit_hash
  local actual_toolkit_hash

  expected_hash="$(awk -v expected="$skill" '$1 == expected { print $2; exit }' "$selection_dir/destination-records")"
  if [[ -z "$expected_hash" || "$expected_hash" == "absent" ]] || [[ -L "$moved_path" || ! -d "$moved_path" ]]; then
    echo "Installed skill changed while the transaction was starting: $SKILLS_DEST/$skill" >&2
    return 1
  fi
  actual_hash="$(hash_installed_skill "$skill" "$moved_path")"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "Installed skill changed while the transaction was starting; preserving the edit: $SKILLS_DEST/$skill" >&2
    return 1
  fi
  if is_ee_skill "$skill"; then
    expected_toolkit_hash="$(awk -v expected="$skill" '$1 == expected { print $2; exit }' "$selection_dir/toolkit-target-records")"
    if [[ -z "$expected_toolkit_hash" || ! -L "$moved_path/toolkit" ]]; then
      echo "EE toolkit link changed while the transaction was starting: $SKILLS_DEST/$skill" >&2
      return 1
    fi
    actual_toolkit_hash="$(printf '%s' "$(readlink "$moved_path/toolkit")" | sha256_stream)"
    if [[ "$actual_toolkit_hash" != "$expected_toolkit_hash" ]]; then
      echo "EE toolkit link changed while the transaction was starting: $SKILLS_DEST/$skill" >&2
      return 1
    fi
  fi
}

apply_skill_transaction() {
  local selection_dir="$1"
  local staging_dir="$2"
  local records_file="$selection_dir/skill-records"
  local obsolete_file="$selection_dir/obsolete-skills"
  local affected_file="$selection_dir/affected-skills"
  local moved_file="$selection_dir/moved-skills"
  local installed_file="$selection_dir/installed-skills"
  local rollback_dir
  local skill
  local operation_failed=0

  : > "$affected_file"
  : > "$moved_file"
  : > "$installed_file"
  while read -r skill _; do append_unique_line "$skill" "$affected_file"; done < "$records_file"
  while IFS= read -r skill; do append_unique_line "$skill" "$affected_file"; done < "$obsolete_file"

  rollback_dir="$(mktemp -d "$SKILLS_DEST/.codex-global-skills-rollback.XXXXXX")"
  printf '%s\n' "$rollback_dir" > "$selection_dir/active-rollback"
  ACTIVE_SELECTION_DIR="$selection_dir"

  while IFS= read -r skill; do
    if [[ -e "$SKILLS_DEST/$skill" || -L "$SKILLS_DEST/$skill" ]]; then
      if ! mv "$SKILLS_DEST/$skill" "$rollback_dir/$skill"; then
        operation_failed=1
        break
      fi
      printf '%s\n' "$skill" >> "$moved_file"
      if ! verify_moved_skill_preimage "$selection_dir" "$skill" "$rollback_dir/$skill"; then
        operation_failed=1
        break
      fi
    fi
  done < "$affected_file"

  if [[ "$operation_failed" -eq 0 ]]; then
    while IFS= read -r skill; do
      if ! verify_moved_skill_preimage "$selection_dir" "$skill" "$rollback_dir/$skill"; then
        operation_failed=1
        break
      fi
    done < "$moved_file"
  fi

  if [[ "$operation_failed" -eq 0 ]]; then
    while read -r skill _; do
      printf '%s\n' "$skill" >> "$installed_file"
      if ! mv "$staging_dir/$skill" "$SKILLS_DEST/$skill"; then
        operation_failed=1
        break
      fi
    done < "$records_file"
  fi

  if [[ "$operation_failed" -ne 0 ]]; then
    rollback_skill_transaction "$selection_dir" || true
    echo "Skill installation failed; restored the previous managed installation" >&2
    return 1
  fi

  while IFS= read -r skill; do
    [[ -n "$skill" ]] && echo "  Removed:     $skill"
  done < "$obsolete_file"
  while read -r skill _; do
    echo "  Installed:   $skill"
  done < "$records_file"
  rm -rf "$staging_dir"
}

rollback_skill_transaction() {
  local selection_dir="$1"
  local rollback_dir
  local skill
  local expected_hash
  local actual_hash
  local conflict=0

  [[ -f "$selection_dir/active-rollback" ]] || return
  rollback_dir="$(sed -n '1p' "$selection_dir/active-rollback")"
  while IFS= read -r skill; do
    if [[ -e "$SKILLS_DEST/$skill" || -L "$SKILLS_DEST/$skill" ]]; then
      expected_hash="$(awk -v expected="$skill" '$1 == expected { print $2; exit }' "$selection_dir/skill-records")"
      if [[ -L "$SKILLS_DEST/$skill" || ! -d "$SKILLS_DEST/$skill" ]]; then
        conflict=1
        continue
      fi
      if is_ee_skill "$skill" && ! installed_toolkit_link_is_exact "$SKILLS_DEST/$skill"; then
        echo "Rollback preserved concurrently changed EE toolkit link: $SKILLS_DEST/$skill" >&2
        conflict=1
        continue
      fi
      actual_hash="$(hash_installed_skill "$skill" "$SKILLS_DEST/$skill")"
      if [[ "$actual_hash" == "$expected_hash" ]]; then
        rm -rf "$SKILLS_DEST/$skill"
      else
        echo "Rollback preserved concurrently changed skill: $SKILLS_DEST/$skill" >&2
        conflict=1
      fi
    fi
  done < "$selection_dir/installed-skills"
  if [[ -d "$rollback_dir" ]]; then
    for skill in "$rollback_dir"/*; do
      [[ -e "$skill" || -L "$skill" ]] || continue
      if [[ -e "$SKILLS_DEST/$(basename "$skill")" || -L "$SKILLS_DEST/$(basename "$skill")" ]]; then
        echo "Rollback backup preserved for manual recovery: $skill" >&2
        conflict=1
      else
        mv "$skill" "$SKILLS_DEST/$(basename "$skill")"
      fi
    done
    if [[ "$conflict" -eq 0 ]]; then
      rm -rf "$rollback_dir"
    fi
  fi
  if [[ "$conflict" -eq 0 ]]; then
    rm -f "$selection_dir/active-rollback"
    ACTIVE_SELECTION_DIR=""
  else
    echo "Rollback needs manual recovery from $rollback_dir" >&2
    return 1
  fi
}

finalize_skill_transaction() {
  local selection_dir="$1"
  local rollback_dir

  [[ -f "$selection_dir/active-rollback" ]] || return
  rollback_dir="$(sed -n '1p' "$selection_dir/active-rollback")"
  rm -rf "$rollback_dir"
  rm -f "$selection_dir/active-rollback"
  ACTIVE_SELECTION_DIR=""
}

prepare_state_manifest() {
  local selection_dir="$1"
  local state_temp
  local value
  local pack_path
  local state_hash
  local skill
  local digest

  if [[ -L "$MANAGED_STATE_DIR" || ( -e "$MANAGED_STATE_DIR" && ! -d "$MANAGED_STATE_DIR" ) ]]; then
    echo "Managed state directory is not a regular directory: $MANAGED_STATE_DIR" >&2
    return 1
  fi
  mkdir -p "$MANAGED_STATE_DIR"
  state_temp="$(mktemp "$MANAGED_STATE_DIR/.manifest.XXXXXX")"
  register_temp_path "$state_temp"

  printf 'version 2\n' >> "$state_temp"
  while IFS= read -r value; do
    pack_path="$(pack_manifest_path "$PACKS_DIR" "$value")"
    printf 'pack %s %s\n' "$value" "$(sha256_file "$pack_path")" >> "$state_temp"
  done < "$selection_dir/packs"
  while IFS= read -r value; do printf 'dependency %s\n' "$value" >> "$state_temp"; done < "$selection_dir/dependencies"
  while IFS= read -r value; do printf 'guidance %s\n' "$value" >> "$state_temp"; done < "$selection_dir/guidance"
  while read -r skill digest; do printf 'skill %s %s\n' "$skill" "$digest" >> "$state_temp"; done < "$selection_dir/skill-records"
  if grep -Eq '^(equal-experts-workflow|ee-[a-z0-9-]+)$' "$selection_dir/skills"; then
    printf 'ee-toolkit-target-sha256 %s\n' \
      "$(printf '%s' "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" | sha256_stream)" >> "$state_temp"
  fi
  state_hash="$(state_manifest_records_digest "$state_temp")"
  printf 'state-sha256 %s\n' "$state_hash" >> "$state_temp"
  printf '%s\n' "$state_temp" > "$selection_dir/prepared-manifest"
}

commit_state_manifest() {
  local selection_dir="$1"
  local state_temp
  local expected_manifest_hash
  local interrupted=0

  state_temp="$(sed -n '1p' "$selection_dir/prepared-manifest")"
  expected_manifest_hash="$(sha256_file "$state_temp")"
  trap 'interrupted=1' INT TERM
  if ! mv "$state_temp" "$MANIFEST_FILE"; then
    if [[ ! -e "$state_temp" && ! -L "$MANIFEST_FILE" && -f "$MANIFEST_FILE" ]] &&
      [[ "$(sha256_file "$MANIFEST_FILE")" == "$expected_manifest_hash" ]]; then
      TRANSACTION_COMMITTED=1
      rm -f "$selection_dir/prepared-manifest"
      trap 'exit 130' INT TERM
      echo "Managed install state was published even though mv reported failure; preserving the complete committed selection" >&2
      if [[ "$interrupted" -eq 1 ]]; then
        return 130
      fi
      return 1
    fi
    trap 'exit 130' INT TERM
    echo "Could not atomically commit managed install state" >&2
    return 1
  fi
  TRANSACTION_COMMITTED=1
  rm -f "$selection_dir/prepared-manifest"
  trap 'exit 130' INT TERM
  if [[ "$interrupted" -eq 1 ]]; then
    return 130
  fi
}

main() {
  local selection_dir
  local staging_dir
  local commit_status=0

  parse_arguments "$@"
  if [[ "$LIST_PACKS" -eq 1 ]]; then
    list_packs
    return
  fi
  if [[ ! -d "$SKILLS_SRC" || ! -d "$PACKS_DIR" ]]; then
    echo "Could not find repository skills or packs" >&2
    return 1
  fi

  preflight_managed_state
  acquire_install_lock
  validate_state_manifest
  selection_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-selection.XXXXXX")"
  register_temp_path "$selection_dir"
  prepare_selection "$selection_dir"
  preflight_skill_destinations "$selection_dir"
  prepare_state_manifest "$selection_dir"
  if grep -Fqx git-safety "$selection_dir/guidance"; then
    preflight_global_git_guidance
  fi

  echo "Checking selected pack dependencies..."
  ensure_dependencies "$selection_dir/dependencies"

  mkdir -p "$CODEX_CONFIG_DIR" "$SKILLS_DEST"
  staging_dir="$(mktemp -d "$SKILLS_DEST/.codex-global-skills-stage.XXXXXX")"
  register_temp_path "$staging_dir"
  stage_selected_skills "$selection_dir" "$staging_dir"
  revalidate_skill_destinations "$selection_dir" || return 1

  echo "Installing Codex global skills..."
  echo "  Packs:       $(tr '\n' ' ' < "$selection_dir/packs" | sed 's/[[:space:]]*$//')"
  echo "  Destination: $SKILLS_DEST"
  apply_skill_transaction "$selection_dir" "$staging_dir"

  if grep -Fqx git-safety "$selection_dir/guidance"; then
    echo "Installing global Git safety guidance..."
    if ! install_global_git_guidance "$selection_dir"; then
      rollback_skill_transaction "$selection_dir"
      rollback_global_git_guidance "$selection_dir" || true
      return 1
    fi
  fi
  commit_state_manifest "$selection_dir" || commit_status=$?
  if [[ "$commit_status" -ne 0 ]]; then
    if [[ "$TRANSACTION_COMMITTED" -eq 1 ]]; then
      finalize_skill_transaction "$selection_dir"
      finalize_global_git_guidance "$selection_dir"
    else
      rollback_skill_transaction "$selection_dir"
      rollback_global_git_guidance "$selection_dir" || true
    fi
    return "$commit_status"
  fi
  finalize_skill_transaction "$selection_dir"
  finalize_global_git_guidance "$selection_dir"

  if [[ -d "$SKILLS_DEST/ralph-workflow" ]]; then
    echo "Warning: legacy unmanaged skill remains at $SKILLS_DEST/ralph-workflow; review it manually."
  fi
  echo "Done. Start a new Codex task if newly installed skills are not visible yet."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
