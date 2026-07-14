#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "Usage: run-guarded.sh <plan|build> [ralph options]" >&2
  exit 2
fi

MODE="$1"
shift
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
RALPH_PIN_FILE="$SCRIPT_DIR/../assets/ralph-pin.env"
GETOPT_COMPAT_DIR="$SCRIPT_DIR/compat"
SYSTEM_GETOPT="$(command -v getopt 2>/dev/null || true)"
SYSTEM_GIT="$(command -v git 2>/dev/null || true)"
CREATED_PROMPT=0
CREATED_PROMPT_HASH=""
NORMALIZED_RALPH_ARGUMENTS=()
MODEL_ARGUMENT_SUPPLIED=0

if [[ ! -f "$RALPH_PIN_FILE" || -L "$RALPH_PIN_FILE" ]]; then
  echo "Reviewed Ralph pin contract is missing or invalid: $RALPH_PIN_FILE" >&2
  exit 1
fi
# shellcheck source=../assets/ralph-pin.env
source "$RALPH_PIN_FILE"
RALPH_RUNTIME_DIR="$STATE_DIR/ralph-runtimes/$RALPH_PIN_RUNTIME_ID"
if [[ -z "${RALPH_CONFIG_DIR+x}" ]]; then
  if [[ "${DEVCONTAINER:-}" == "true" ]]; then
    RALPH_CONFIG_DIR="/home/node/.config/ralph"
  else
    RALPH_CONFIG_DIR="$RALPH_RUNTIME_DIR/config"
  fi
fi
RALPH_GLOBAL_SKILL_DEFAULTS_FILE="$RALPH_CONFIG_DIR/global-skill.env"

if [[ -n "${RALPH_BIN_PATH+x}" ]]; then
  RALPH_BINARY="$RALPH_BIN_PATH"
elif [[ -n "${RALPH_BIN_DIR+x}" ]]; then
  RALPH_BINARY="$RALPH_BIN_DIR/ralph"
elif [[ "${DEVCONTAINER:-}" == "true" ]]; then
  RALPH_BINARY="${RALPH_SANDBOX_BIN_PATH:-/usr/local/bin/ralph}"
else
  RALPH_BINARY="$RALPH_RUNTIME_DIR/bin/ralph"
fi

case "$MODE" in
  build)
    LOCAL_PROMPT="PROMPT_build.md"
    DEFAULT_PROMPT="$RALPH_CONFIG_DIR/prompts/build.md"
    SAFE_TEMPLATE="$SCRIPT_DIR/../assets/PROMPT_build.safe.md"
    PREPARE_PROMPT="$SCRIPT_DIR/prepare-safe-build-prompt.sh"
    ;;
  plan)
    LOCAL_PROMPT="PROMPT_plan.md"
    DEFAULT_PROMPT="$RALPH_CONFIG_DIR/prompts/plan.md"
    SAFE_TEMPLATE="$SCRIPT_DIR/../assets/PROMPT_plan.safe.md"
    PREPARE_PROMPT="$SCRIPT_DIR/prepare-safe-plan-prompt.sh"
    ;;
  *)
    echo "Unsupported guarded Ralph mode: $MODE" >&2
    exit 2
    ;;
esac

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "Missing SHA-256 command: install shasum or sha256sum" >&2
    return 1
  fi
}

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    echo "Missing SHA-256 command: install shasum or sha256sum" >&2
    return 1
  fi
}

snapshot_refs() {
  "$SYSTEM_GIT" for-each-ref --format='%(refname)%09%(objectname)%09%(symref)' | LC_ALL=C sort | sha256_stream
}

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

hash_untracked_directory() {
  local directory="$1"

  (
    cd "$directory"
    find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r relative_path; do
      if [[ -L "$relative_path" ]]; then
        printf 'link\t%s\t%s\n' "$relative_path" "$(readlink "$relative_path")"
      else
        printf 'file\t%s\t%s\t%s\n' "$relative_path" "$(file_mode "$relative_path")" "$(sha256_file "$relative_path")"
      fi
    done
  ) | sha256_stream
}

snapshot_submodule_worktree() {
  local display_path="$1"
  local absolute_path="$2"
  local path
  local head
  local head_identity
  local index_tree
  local refs
  local security

  (
    cd "$absolute_path"
    head="$("$SYSTEM_GIT" rev-parse HEAD)" || exit 1
    head_identity="$(snapshot_head_identity)" || exit 1
    index_tree="$("$SYSTEM_GIT" write-tree)" || exit 1
    refs="$(snapshot_refs)" || exit 1
    security="$(snapshot_repository_security_metadata)" || exit 1
    printf 'submodule\t%s\n' "$display_path"
    printf 'head\t%s\n' "$head"
    printf 'head-identity\t%s\n' "$head_identity"
    printf 'index\t%s\n' "$index_tree"
    printf 'refs\t%s\n' "$refs"
    printf 'security\t%s\n' "$security"
    "$SYSTEM_GIT" diff --binary HEAD -- . || exit 1
    while IFS= read -r -d '' path; do
      if [[ -L "$path" ]]; then
        printf 'untracked-link\t%s\t%s\n' "$path" "$(readlink "$path")"
      elif [[ -f "$path" ]]; then
        printf 'untracked-file\t%s\t%s\t%s\n' "$path" "$(file_mode "$path")" "$(sha256_file "$path")"
      elif [[ -d "$path" ]]; then
        printf 'untracked-directory\t%s\t%s\n' "$path" "$(hash_untracked_directory "$path")"
      else
        printf 'untracked-other\t%s\t%s\n' "$path" "$(file_mode "$path")"
      fi
    done < <("$SYSTEM_GIT" ls-files --others --exclude-standard -z)
  )
}

snapshot_initialized_submodules() {
  local display_path
  local absolute_path
  local listing

  listing="$("$SYSTEM_GIT" submodule foreach --quiet --recursive 'printf "%s\t%s\n" "$displaypath" "$PWD"')" || return 1
  while IFS=$'\t' read -r display_path absolute_path; do
    [[ -n "$display_path" && -n "$absolute_path" ]] || continue
    snapshot_submodule_worktree "$display_path" "$absolute_path" || return 1
  done <<< "$listing"
}

snapshot_plan_out_of_scope() {
  {
    "$SYSTEM_GIT" diff --binary HEAD -- . \
      ':(exclude)IMPLEMENTATION_PLAN.md' \
      ':(exclude)specs/**' \
      ':(exclude)PROMPT_plan.md' || exit 1
    while IFS= read -r -d '' path; do
      if [[ -L "$path" ]]; then
        printf 'untracked-link\t%s\t%s\n' "$path" "$(readlink "$path")"
      elif [[ -f "$path" ]]; then
        printf 'untracked-file\t%s\t%s\t%s\n' "$path" "$(file_mode "$path")" "$(sha256_file "$path")"
      elif [[ -d "$path" ]]; then
        printf 'untracked-directory\t%s\t%s\n' "$path" "$(hash_untracked_directory "$path")"
      else
        printf 'untracked-other\t%s\t%s\n' "$path" "$(file_mode "$path")"
      fi
    done < <("$SYSTEM_GIT" ls-files --others --exclude-standard -z -- . \
      ':(exclude)IMPLEMENTATION_PLAN.md' \
      ':(exclude)specs/**' \
      ':(exclude)PROMPT_plan.md')
    snapshot_initialized_submodules || exit 1
  } | sha256_stream
}

normalize_ralph_arguments() {
  local normalized
  local argument

  for argument in "$@"; do
    if [[ "$argument" == "--" ]]; then
      echo "Guarded Ralph does not accept an option terminator" >&2
      return 2
    fi
  done
  if ! normalized="$(RALPH_SYSTEM_GETOPT="$SYSTEM_GETOPT" "$GETOPT_COMPAT_DIR/getopt" \
    -o n:g:m:b:vyh \
    --long iterations:,goal:,model:,backend:,skip-push,dry-run,verbose,yes,help \
    -n ralph -- "$@")"; then
    echo "Guarded Ralph received invalid options" >&2
    return 2
  fi

  eval "set -- $normalized"
  NORMALIZED_RALPH_ARGUMENTS=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -n|--iterations)
        if [[ "$MODE" == "build" && "$2" != "1" ]]; then
          echo "Guarded Ralph build accepts exactly one iteration; received $2" >&2
          return 2
        fi
        NORMALIZED_RALPH_ARGUMENTS+=("$1" "$2")
        shift 2
        ;;
      -b|--backend)
        if [[ "$2" != "codex" ]]; then
          echo "Guarded Ralph supports only the pinned Codex backend" >&2
          return 2
        fi
        NORMALIZED_RALPH_ARGUMENTS+=("$1" "$2")
        shift 2
        ;;
      -g|--goal)
        NORMALIZED_RALPH_ARGUMENTS+=("$1" "$2")
        shift 2
        ;;
      -m|--model)
        MODEL_ARGUMENT_SUPPLIED=1
        NORMALIZED_RALPH_ARGUMENTS+=("$1" "$2")
        shift 2
        ;;
      --skip-push|--dry-run|-v|--verbose|-y|--yes|-h|--help)
        NORMALIZED_RALPH_ARGUMENTS+=("$1")
        shift
        ;;
      --)
        shift
        if [[ "$#" -ne 0 ]]; then
          echo "Guarded Ralph does not accept positional arguments" >&2
          return 2
        fi
        break
        ;;
      *)
        echo "Guarded Ralph received an unsupported normalized option: $1" >&2
        return 2
        ;;
    esac
  done
}

resolve_git_path() {
  local path

  path="$("$SYSTEM_GIT" rev-parse --git-path "$1")"
  if [[ "$path" != /* ]]; then
    path="$PWD/$path"
  fi
  printf '%s\n' "$path"
}

hash_symlink_referent_state() {
  local current="$1"
  local depth="$2"
  local target
  local link_depth=0
  local referent_hash

  while [[ -L "$current" ]]; do
    link_depth=$((link_depth + 1))
    if [[ "$link_depth" -gt 20 ]]; then
      printf 'link-chain-too-deep\n'
      return
    fi
    target="$(readlink "$current")"
    printf 'level-%s=%s\t' "$link_depth" "$target"
    if [[ "$target" == /* ]]; then
      current="$target"
    else
      current="$(dirname "$current")/$target"
    fi
  done
  if [[ ! -e "$current" ]]; then
    printf 'broken\n'
    return
  fi
  if [[ -f "$current" ]]; then
    printf 'referent-file\t%s\t%s\n' "$(file_mode "$current")" "$(sha256_file "$current")"
  elif [[ -d "$current" ]]; then
    referent_hash="$(hash_security_directory "$current" $((depth + 1)))" || return 1
    printf 'referent-directory\t%s\n' "$referent_hash"
  else
    printf 'referent-other\t%s\n' "$(file_mode "$current")"
  fi
}

hash_security_directory() {
  local directory="$1"
  local depth="$2"
  local relative_path

  if [[ "$depth" -gt 10 ]]; then
    echo "Repository security path nesting is too deep: $directory" >&2
    return 1
  fi
  {
    printf 'directory-mode\t%s\n' "$(file_mode "$directory")"
    while IFS= read -r relative_path; do
      hash_path_state "$relative_path" "$directory/${relative_path#./}" "$depth" || exit 1
    done < <(cd "$directory" && find . \( -type f -o -type l \) -print | LC_ALL=C sort)
  } | sha256_stream
}

hash_path_state() {
  local label="$1"
  local path="$2"
  local depth="${3:-0}"
  local directory_hash

  if [[ -L "$path" ]]; then
    printf 'link\t%s\t%s\t' "$label" "$(readlink "$path")"
    hash_symlink_referent_state "$path" "$depth" || return 1
  elif [[ -f "$path" ]]; then
    printf 'file\t%s\t%s\t%s\n' "$label" "$(file_mode "$path")" "$(sha256_file "$path")"
  elif [[ -d "$path" ]]; then
    directory_hash="$(hash_security_directory "$path" $((depth + 1)))" || return 1
    printf 'directory\t%s\t%s\n' "$label" "$directory_hash"
  elif [[ -e "$path" ]]; then
    printf 'other\t%s\t%s\n' "$label" "$(file_mode "$path")"
  else
    printf 'missing\t%s\n' "$label"
  fi
}

snapshot_head_identity() {
  local symbolic_head

  if symbolic_head="$("$SYSTEM_GIT" symbolic-ref -q HEAD 2>/dev/null)"; then
    printf 'symbolic:%s\n' "$symbolic_head"
  else
    printf 'detached:%s\n' "$("$SYSTEM_GIT" rev-parse HEAD)"
  fi
}

snapshot_repository_security_metadata() {
  local config_path
  local worktree_config_path
  local hooks_path
  local info_path
  local alternates_path
  local http_alternates_path

  config_path="$(resolve_git_path config)" || return 1
  worktree_config_path="$(resolve_git_path config.worktree)" || return 1
  hooks_path="$(resolve_git_path hooks)" || return 1
  info_path="$(resolve_git_path info)" || return 1
  alternates_path="$(resolve_git_path objects/info/alternates)" || return 1
  http_alternates_path="$(resolve_git_path objects/info/http-alternates)" || return 1

  {
    hash_path_state config "$config_path" || exit 1
    hash_path_state config-worktree "$worktree_config_path" || exit 1
    hash_path_state hooks "$hooks_path" || exit 1
    hash_path_state info "$info_path" || exit 1
    hash_path_state alternates "$alternates_path" || exit 1
    hash_path_state http-alternates "$http_alternates_path" || exit 1
  } | sha256_stream
}

cleanup() {
  if [[ "$CREATED_PROMPT" -eq 1 && -f "$LOCAL_PROMPT" && ! -L "$LOCAL_PROMPT" ]]; then
    if [[ "$(sha256_file "$LOCAL_PROMPT")" == "$CREATED_PROMPT_HASH" ]]; then
      rm -f "$LOCAL_PROMPT"
    else
      echo "Generated $LOCAL_PROMPT changed during the run; preserving it for review" >&2
    fi
  fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM

if [[ ! -f "$RALPH_BINARY" || -L "$RALPH_BINARY" || ! -x "$RALPH_BINARY" ]]; then
  echo "Pinned Ralph executable is missing or invalid: $RALPH_BINARY" >&2
  exit 1
fi
if [[ "$(sha256_file "$RALPH_BINARY")" != "$RALPH_PIN_CLI_SHA256" ]]; then
  echo "Ralph executable does not match the reviewed pinned CLI: $RALPH_BINARY" >&2
  exit 1
fi
if ! command -v codex >/dev/null 2>&1; then
  echo "Pinned Codex CLI is missing; guarded Ralph requires Codex $RALPH_PIN_CODEX_VERSION" >&2
  exit 1
fi
CODEX_VERSION="$(codex --version 2>/dev/null | sed -n '1s/.* //p')"
if [[ "$CODEX_VERSION" != "$RALPH_PIN_CODEX_VERSION" ]]; then
  echo "Codex CLI version is ${CODEX_VERSION:-unknown}; guarded Ralph requires $RALPH_PIN_CODEX_VERSION" >&2
  exit 1
fi
for helper in "$GETOPT_COMPAT_DIR/getopt" "$GETOPT_COMPAT_DIR/git"; do
  if [[ ! -x "$helper" || -L "$helper" ]]; then
    echo "Ralph compatibility helper is missing or invalid: $helper" >&2
    exit 1
  fi
done
if [[ -z "$SYSTEM_GIT" || ! -x "$SYSTEM_GIT" ]] || ! "$SYSTEM_GIT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Run the guarded Ralph $MODE wrapper inside a Git worktree" >&2
  exit 1
fi
if [[ -n "${GIT_CONFIG_COUNT:-}" ]]; then
  echo "Existing GIT_CONFIG_COUNT would conflict with remote-write protection" >&2
  exit 1
fi
if [[ -n "${GIT_CONFIG_PARAMETERS:-}" ]]; then
  echo "Existing GIT_CONFIG_PARAMETERS would conflict with remote-write protection" >&2
  exit 1
fi
if [[ ! -f "$SAFE_TEMPLATE" || -L "$SAFE_TEMPLATE" || ! -x "$PREPARE_PROMPT" || -L "$PREPARE_PROMPT" ]]; then
  echo "Bundled guarded $MODE prompt resources are missing or invalid" >&2
  exit 1
fi
if [[ ! -f "$RALPH_GLOBAL_SKILL_DEFAULTS_FILE" || -L "$RALPH_GLOBAL_SKILL_DEFAULTS_FILE" ]] ||
  [[ "$(sha256_file "$RALPH_GLOBAL_SKILL_DEFAULTS_FILE")" != "$RALPH_PIN_GLOBAL_SKILL_DEFAULTS_SHA256" ]]; then
  echo "Managed Ralph global-skill defaults are missing or modified: $RALPH_GLOBAL_SKILL_DEFAULTS_FILE" >&2
  exit 1
fi
# shellcheck source=../assets/global-skill.env
source "$RALPH_GLOBAL_SKILL_DEFAULTS_FILE"
if [[ "${RALPH_GLOBAL_SKILL_BACKEND:-}" != "codex" ]]; then
  echo "Managed Ralph global skill must use the Codex backend" >&2
  exit 1
fi
if [[ -z "${RALPH_GLOBAL_SKILL_MODEL:-}" || ! "$RALPH_GLOBAL_SKILL_MODEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Managed Ralph global skill model is missing or invalid" >&2
  exit 1
fi
normalize_ralph_arguments "$@"

if [[ -e "$LOCAL_PROMPT" || -L "$LOCAL_PROMPT" ]]; then
  if [[ -L "$LOCAL_PROMPT" || ! -f "$LOCAL_PROMPT" ]]; then
    echo "Project-local $MODE prompt is not a regular file: $LOCAL_PROMPT" >&2
    exit 1
  fi
  if ! cmp -s "$SAFE_TEMPLATE" "$LOCAL_PROMPT"; then
    echo "Existing $LOCAL_PROMPT does not exactly match the reviewed guarded prompt; preserve it and stop" >&2
    exit 1
  fi
else
  "$PREPARE_PROMPT" "$DEFAULT_PROMPT" "$LOCAL_PROMPT"
  CREATED_PROMPT=1
  CREATED_PROMPT_HASH="$(sha256_file "$LOCAL_PROMPT")"
fi
PROMPT_HASH_BEFORE="$(sha256_file "$LOCAL_PROMPT")"

remotes=()
while IFS= read -r remote; do
  [[ -n "$remote" ]] && remotes+=("$remote")
done < <("$SYSTEM_GIT" remote)

environment=(
  "GIT_CONFIG_COUNT=${#remotes[@]}"
  "PATH=$GETOPT_COMPAT_DIR:${PATH:-}"
  "RALPH_SYSTEM_GETOPT=$SYSTEM_GETOPT"
  "RALPH_SYSTEM_GIT=$SYSTEM_GIT"
)
index=0
if [[ "${#remotes[@]}" -gt 0 ]]; then
  for remote in "${remotes[@]}"; do
    environment+=("GIT_CONFIG_KEY_$index=remote.$remote.pushurl")
    environment+=("GIT_CONFIG_VALUE_$index=disabled://codex-global-skills/no-remote-write")
    index=$((index + 1))
  done
fi

head_before="$("$SYSTEM_GIT" rev-parse HEAD)"
head_identity_before="$(snapshot_head_identity)"
index_before="$("$SYSTEM_GIT" write-tree)"
refs_before="$(snapshot_refs)"
repository_security_before="$(snapshot_repository_security_metadata)"
if [[ "$MODE" == "plan" ]]; then
  plan_scope_before="$(snapshot_plan_out_of_scope)"
fi
ralph_status=0
ralph_arguments=(--skip-push)
if [[ "$MODEL_ARGUMENT_SUPPLIED" -eq 0 ]]; then
  ralph_arguments+=(--model "$RALPH_GLOBAL_SKILL_MODEL")
fi
if [[ "${#NORMALIZED_RALPH_ARGUMENTS[@]}" -gt 0 ]]; then
  ralph_arguments+=("${NORMALIZED_RALPH_ARGUMENTS[@]}")
fi
if [[ "$MODE" == "build" ]]; then
  ralph_arguments+=(--iterations 1)
fi
ralph_arguments+=(--backend "$RALPH_GLOBAL_SKILL_BACKEND")
env "${environment[@]}" "$RALPH_BINARY" "$MODE" "${ralph_arguments[@]}" || ralph_status=$?
head_identity_after="$(snapshot_head_identity)"
repository_security_after="$(snapshot_repository_security_metadata)"
head_after="$("$SYSTEM_GIT" rev-parse HEAD)"
if ! index_after="$("$SYSTEM_GIT" write-tree 2>/dev/null)"; then
  echo "Ralph left an unreadable or conflicted Git index; preserving it for review and failing" >&2
  exit 1
fi
refs_after="$(snapshot_refs)"

if [[ ! -f "$LOCAL_PROMPT" || -L "$LOCAL_PROMPT" ]] || [[ "$(sha256_file "$LOCAL_PROMPT")" != "$PROMPT_HASH_BEFORE" ]]; then
  echo "Ralph changed or removed the reviewed $LOCAL_PROMPT; preserving available evidence and failing" >&2
  exit 1
fi

if [[ "$head_after" != "$head_before" ]]; then
  echo "Ralph changed HEAD despite the guarded prompt; preserving the commit for review and failing" >&2
  exit 1
fi
if [[ "$head_identity_after" != "$head_identity_before" ]]; then
  echo "Ralph changed the symbolic or detached HEAD identity; preserving the branch state for review and failing" >&2
  exit 1
fi
if [[ "$index_after" != "$index_before" ]]; then
  echo "Ralph changed the Git index despite the no-stage prompt; preserving it for review and failing" >&2
  exit 1
fi
if [[ "$refs_after" != "$refs_before" ]]; then
  echo "Ralph changed local Git refs despite the no-history prompt; preserving them for review and failing" >&2
  exit 1
fi
if [[ "$repository_security_after" != "$repository_security_before" ]]; then
  echo "Ralph changed repository Git configuration, hooks, excludes, or alternates; preserving the metadata for review and failing" >&2
  exit 1
fi
if [[ "$MODE" == "plan" ]]; then
  plan_scope_after="$(snapshot_plan_out_of_scope)"
  if [[ "$plan_scope_after" != "$plan_scope_before" ]]; then
    echo "Ralph plan changed Git-visible paths outside IMPLEMENTATION_PLAN.md or specs/; preserving evidence and failing" >&2
    exit 1
  fi
fi

exit "$ralph_status"
