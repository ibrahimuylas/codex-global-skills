#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIN_FILE="$SCRIPT_DIR/../assets/ralph-pin.env"
SAFE_DOCKERFILE="$SCRIPT_DIR/../assets/Dockerfile.safe"
SAFE_DEVCONTAINER="$SCRIPT_DIR/../assets/devcontainer.safe.json"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
SANDBOX_CONFIG_PARENT="$STATE_DIR/ralph-sandbox-configs"
SANDBOX_SKILL_PARENT="$STATE_DIR/ralph-sandbox-skills"
SANDBOX_HOST_HOME="$STATE_DIR/ralph-sandbox-home"
LOCK_DIR="$SANDBOX_CONFIG_PARENT/install.lock"
LOCK_HELD=0
CREATED_CONFIG=0
CREATED_SKILL=0

cleanup() {
  if [[ "$CREATED_CONFIG" -eq 1 && -d "${SANDBOX_CONFIG_DIR:-}" && ! -f "$SANDBOX_CONFIG_DIR/.ready" ]]; then
    rm -rf "$SANDBOX_CONFIG_DIR"
  fi
  if [[ "$CREATED_SKILL" -eq 1 && -d "${SANDBOX_SKILL_CONTRACT_DIR:-}" && ! -f "$SANDBOX_SKILL_CONTRACT_DIR/.ready" ]]; then
    rm -rf "$SANDBOX_SKILL_CONTRACT_DIR"
  fi
  if [[ "$LOCK_HELD" -eq 1 && -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
    rm -rf "$LOCK_DIR"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM

case "$#:${1:-}" in
  0:|1:--rebuild|1:clean) ;;
  *)
    echo "Usage: run-sandbox-guarded.sh [--rebuild|clean]" >&2
    exit 2
    ;;
esac
if [[ "${DEVCONTAINER:-}" == "true" ]]; then
  echo "Run the guarded sandbox launcher on the host, not from inside the devcontainer" >&2
  exit 1
fi
if [[ ! -f "$PIN_FILE" || -L "$PIN_FILE" ]]; then
  echo "Reviewed Ralph pin contract is missing or invalid: $PIN_FILE" >&2
  exit 1
fi
# shellcheck source=../assets/ralph-pin.env
source "$PIN_FILE"
RALPH_RUNTIME_DIR="$STATE_DIR/ralph-runtimes/$RALPH_PIN_RUNTIME_ID"
HOST_RALPH_CONFIG_DIR="${RALPH_CONFIG_DIR:-$RALPH_RUNTIME_DIR/config}"

if [[ -n "${RALPH_BIN_PATH+x}" ]]; then
  RALPH_BINARY="$RALPH_BIN_PATH"
elif [[ -n "${RALPH_BIN_DIR+x}" ]]; then
  RALPH_BINARY="$RALPH_BIN_DIR/ralph"
else
  RALPH_BINARY="$RALPH_RUNTIME_DIR/bin/ralph"
fi

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

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

hash_directory_tree() {
  local directory="$1"

  [[ -d "$directory" && ! -L "$directory" ]] || return 1
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

verify_source_config() {
  [[ -d "$HOST_RALPH_CONFIG_DIR" && ! -L "$HOST_RALPH_CONFIG_DIR" ]] &&
    [[ -f "$HOST_RALPH_CONFIG_DIR/prompts/plan.md" && ! -L "$HOST_RALPH_CONFIG_DIR/prompts/plan.md" ]] &&
    [[ -f "$HOST_RALPH_CONFIG_DIR/prompts/build.md" && ! -L "$HOST_RALPH_CONFIG_DIR/prompts/build.md" ]] &&
    [[ -f "$HOST_RALPH_CONFIG_DIR/container/Dockerfile" && ! -L "$HOST_RALPH_CONFIG_DIR/container/Dockerfile" ]] &&
    [[ -f "$HOST_RALPH_CONFIG_DIR/container/devcontainer.json" && ! -L "$HOST_RALPH_CONFIG_DIR/container/devcontainer.json" ]] &&
    [[ "$(sha256_file "$HOST_RALPH_CONFIG_DIR/prompts/plan.md")" == "$RALPH_PIN_PLAN_PROMPT_SHA256" ]] &&
    [[ "$(sha256_file "$HOST_RALPH_CONFIG_DIR/prompts/build.md")" == "$RALPH_PIN_BUILD_PROMPT_SHA256" ]] &&
    [[ "$(sha256_file "$HOST_RALPH_CONFIG_DIR/container/Dockerfile")" == "$RALPH_PIN_CONTAINER_DOCKERFILE_SHA256" ]] &&
    [[ "$(sha256_file "$HOST_RALPH_CONFIG_DIR/container/devcontainer.json")" == "$RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256" ]]
}

verify_safe_assets() {
  [[ -f "$SAFE_DOCKERFILE" && ! -L "$SAFE_DOCKERFILE" ]] &&
    [[ -f "$SAFE_DEVCONTAINER" && ! -L "$SAFE_DEVCONTAINER" ]] &&
    [[ "$(sha256_file "$SAFE_DOCKERFILE")" == "$RALPH_PIN_SAFE_DOCKERFILE_SHA256" ]] &&
    [[ "$(sha256_file "$SAFE_DEVCONTAINER")" == "$RALPH_PIN_SAFE_DEVCONTAINER_SHA256" ]]
}

verify_sandbox_payload() {
  [[ -d "$SANDBOX_CONFIG_DIR" && ! -L "$SANDBOX_CONFIG_DIR" ]] &&
    [[ -f "$SANDBOX_CONFIG_DIR/.managed" && ! -L "$SANDBOX_CONFIG_DIR/.managed" ]] &&
    [[ -f "$SANDBOX_CONFIG_DIR/prompts/plan.md" && ! -L "$SANDBOX_CONFIG_DIR/prompts/plan.md" ]] &&
    [[ -f "$SANDBOX_CONFIG_DIR/prompts/build.md" && ! -L "$SANDBOX_CONFIG_DIR/prompts/build.md" ]] &&
    [[ -f "$SANDBOX_CONFIG_DIR/container/devcontainer.json" && ! -L "$SANDBOX_CONFIG_DIR/container/devcontainer.json" ]] &&
    [[ -f "$SANDBOX_CONFIG_DIR/container/Dockerfile" && ! -L "$SANDBOX_CONFIG_DIR/container/Dockerfile" ]] &&
    [[ -f "$SANDBOX_CONFIG_DIR/bin/ralph" && ! -L "$SANDBOX_CONFIG_DIR/bin/ralph" && -x "$SANDBOX_CONFIG_DIR/bin/ralph" ]] &&
    [[ "$(sed -n '1p' "$SANDBOX_CONFIG_DIR/.managed")" == "$SANDBOX_CONTRACT_ID" ]] &&
    [[ "$(sha256_file "$SANDBOX_CONFIG_DIR/prompts/plan.md")" == "$RALPH_PIN_PLAN_PROMPT_SHA256" ]] &&
    [[ "$(sha256_file "$SANDBOX_CONFIG_DIR/prompts/build.md")" == "$RALPH_PIN_BUILD_PROMPT_SHA256" ]] &&
    [[ "$(sha256_file "$SANDBOX_CONFIG_DIR/container/devcontainer.json")" == "$RALPH_PIN_SAFE_DEVCONTAINER_SHA256" ]] &&
    [[ "$(sha256_file "$SANDBOX_CONFIG_DIR/container/Dockerfile")" == "$RALPH_PIN_SAFE_DOCKERFILE_SHA256" ]] &&
    [[ "$(sha256_file "$SANDBOX_CONFIG_DIR/bin/ralph")" == "$RALPH_PIN_CLI_SHA256" ]]
}

verify_sandbox_config() {
  verify_sandbox_payload &&
    [[ -f "$SANDBOX_CONFIG_DIR/.ready" && ! -L "$SANDBOX_CONFIG_DIR/.ready" ]]
}

verify_sandbox_skill() {
  [[ -d "$SANDBOX_SKILL_CONTRACT_DIR" && ! -L "$SANDBOX_SKILL_CONTRACT_DIR" ]] &&
    [[ -f "$SANDBOX_SKILL_CONTRACT_DIR/.managed" && ! -L "$SANDBOX_SKILL_CONTRACT_DIR/.managed" ]] &&
    [[ -f "$SANDBOX_SKILL_CONTRACT_DIR/.ready" && ! -L "$SANDBOX_SKILL_CONTRACT_DIR/.ready" ]] &&
    [[ -d "$SANDBOX_SKILL_DIR" && ! -L "$SANDBOX_SKILL_DIR" ]] &&
    [[ "$(sed -n '1p' "$SANDBOX_SKILL_CONTRACT_DIR/.managed")" == "$SANDBOX_CONTRACT_ID" ]] &&
    [[ "$(hash_directory_tree "$SANDBOX_SKILL_DIR")" == "$SOURCE_SKILL_HASH" ]]
}

prepare_sandbox_skill() {
  if [[ -e "$SANDBOX_SKILL_CONTRACT_DIR" || -L "$SANDBOX_SKILL_CONTRACT_DIR" ]]; then
    if verify_sandbox_skill; then
      return
    fi
    echo "Managed read-only Ralph sandbox skill is incomplete or modified: $SANDBOX_SKILL_CONTRACT_DIR" >&2
    return 1
  fi
  mkdir "$SANDBOX_SKILL_CONTRACT_DIR"
  CREATED_SKILL=1
  printf '%s\n' "$SANDBOX_CONTRACT_ID" > "$SANDBOX_SKILL_CONTRACT_DIR/.managed"
  mkdir "$SANDBOX_SKILL_DIR"
  cp -R "$SKILL_DIR/." "$SANDBOX_SKILL_DIR/"
  if [[ "$(hash_directory_tree "$SANDBOX_SKILL_DIR")" != "$SOURCE_SKILL_HASH" ]]; then
    echo "Generated read-only Ralph sandbox skill failed verification" >&2
    return 1
  fi
  : > "$SANDBOX_SKILL_CONTRACT_DIR/.ready"
  verify_sandbox_skill || {
    rm -f "$SANDBOX_SKILL_CONTRACT_DIR/.ready"
    echo "Generated read-only Ralph sandbox skill failed final verification" >&2
    return 1
  }
}

prepare_sandbox_config() {
  if [[ -e "$SANDBOX_CONFIG_DIR" || -L "$SANDBOX_CONFIG_DIR" ]]; then
    if verify_sandbox_config; then
      return
    fi
    echo "Managed Ralph sandbox configuration is incomplete or modified: $SANDBOX_CONFIG_DIR" >&2
    return 1
  fi
  if ! verify_source_config; then
    echo "Managed Ralph source configuration differs from the reviewed pin: $HOST_RALPH_CONFIG_DIR" >&2
    return 1
  fi
  if ! verify_safe_assets; then
    echo "Bundled guarded Ralph container assets differ from the reviewed pin" >&2
    return 1
  fi

  mkdir "$SANDBOX_CONFIG_DIR"
  CREATED_CONFIG=1
  printf '%s\n' "$SANDBOX_CONTRACT_ID" > "$SANDBOX_CONFIG_DIR/.managed"
  mkdir "$SANDBOX_CONFIG_DIR/prompts" "$SANDBOX_CONFIG_DIR/container" "$SANDBOX_CONFIG_DIR/bin"
  cp "$HOST_RALPH_CONFIG_DIR/prompts/plan.md" "$SANDBOX_CONFIG_DIR/prompts/plan.md"
  cp "$HOST_RALPH_CONFIG_DIR/prompts/build.md" "$SANDBOX_CONFIG_DIR/prompts/build.md"
  cp "$SAFE_DEVCONTAINER" "$SANDBOX_CONFIG_DIR/container/devcontainer.json"
  cp "$SAFE_DOCKERFILE" "$SANDBOX_CONFIG_DIR/container/Dockerfile"
  cp "$RALPH_BINARY" "$SANDBOX_CONFIG_DIR/bin/ralph"
  chmod 0555 "$SANDBOX_CONFIG_DIR/bin/ralph"
  if ! verify_sandbox_payload; then
    echo "Generated Ralph sandbox payload failed verification" >&2
    return 1
  fi
  : > "$SANDBOX_CONFIG_DIR/.ready"
  if ! verify_sandbox_config; then
    rm -f "$SANDBOX_CONFIG_DIR/.ready"
    echo "Generated Ralph sandbox configuration failed final verification" >&2
    return 1
  fi
}

prepare_sandbox_home() {
  local skills_parent="$SANDBOX_HOST_HOME/.codex/skills"
  local destination="$skills_parent/ralph"
  local directory

  for directory in "$SANDBOX_HOST_HOME" "$SANDBOX_HOST_HOME/.codex" "$skills_parent"; do
    if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
      echo "Dedicated Ralph sandbox home component is not a regular directory: $directory" >&2
      return 1
    fi
    [[ -d "$directory" ]] || mkdir "$directory"
  done
  chmod 0700 "$SANDBOX_HOST_HOME" "$SANDBOX_HOST_HOME/.codex"
  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ -L "$destination" || ! -d "$destination" ]]; then
      echo "Dedicated sandbox Ralph skill mountpoint is not a regular directory: $destination" >&2
      return 1
    fi
    if { { [[ ! -f "$destination/.readonly-mountpoint" ]] || [[ -L "$destination/.readonly-mountpoint" ]]; } &&
      { [[ ! -f "$destination/.sandbox-managed-copy" ]] || [[ -L "$destination/.sandbox-managed-copy" ]]; }; } &&
      [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      echo "Dedicated sandbox Ralph skill mountpoint contains unrecognized content: $destination" >&2
      return 1
    fi
  else
    mkdir "$destination"
  fi
  : > "$destination/.readonly-mountpoint"
}

clean_sandbox_containers() {
  local container_ids
  local container_id
  local config_file
  local relative_config
  local contract_id
  local removed=0

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required to clean Ralph sandbox containers" >&2
    return 1
  fi
  if ! container_ids="$(docker ps -a --filter "label=devcontainer.local_folder=$PWD" --format '{{.ID}}')"; then
    echo "Could not list Ralph sandbox containers for $PWD" >&2
    return 1
  fi
  while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    if [[ ! "$container_id" =~ ^[0-9a-fA-F]+$ ]]; then
      echo "Docker returned an invalid container ID while cleaning: $container_id" >&2
      return 1
    fi
    if ! config_file="$(docker inspect --format '{{ index .Config.Labels "devcontainer.config_file" }}' "$container_id")"; then
      echo "Could not inspect sandbox container $container_id" >&2
      return 1
    fi
    if [[ "$config_file" != "$SANDBOX_CONFIG_PARENT/"* ]]; then
      continue
    fi
    relative_config="${config_file#"$SANDBOX_CONFIG_PARENT/"}"
    contract_id="${relative_config%%/*}"
    if [[ ! "$contract_id" =~ ^[0-9a-f]{64}$ ]] ||
      [[ "$relative_config" != "$contract_id/container/devcontainer.json" ]]; then
      continue
    fi
    docker rm -f "$container_id" >/dev/null
    removed=$((removed + 1))
  done <<< "$container_ids"
  if [[ "$removed" -eq 0 ]]; then
    echo "No sandbox container found for $PWD"
  else
    echo "Removed $removed sandbox container(s) for $PWD"
  fi
}

if [[ ! -f "$RALPH_BINARY" || -L "$RALPH_BINARY" || ! -x "$RALPH_BINARY" ]] ||
  [[ "$(sha256_file "$RALPH_BINARY")" != "$RALPH_PIN_CLI_SHA256" ]]; then
  echo "Managed Ralph executable is missing or differs from the reviewed pin: $RALPH_BINARY" >&2
  exit 1
fi
RALPH_BINARY_DIR="$(cd "$(dirname "$RALPH_BINARY")" && pwd -P)"
RALPH_BINARY="$RALPH_BINARY_DIR/$(basename "$RALPH_BINARY")"
if [[ "$(basename "$RALPH_BINARY")" != "ralph" ]]; then
  echo "Managed Ralph sandbox binary must have the stable filename 'ralph': $RALPH_BINARY" >&2
  exit 1
fi
resolved_ralph="$(PATH="$RALPH_BINARY_DIR:${PATH:-}" command -v ralph 2>/dev/null || true)"
if [[ "$resolved_ralph" != "$RALPH_BINARY" ]]; then
  echo "Could not resolve the verified stable Ralph binary for the sandbox launcher" >&2
  exit 1
fi

if [[ "${1:-}" == "clean" ]]; then
  clean_sandbox_containers
  exit $?
fi

if ! command -v devcontainer >/dev/null 2>&1; then
  echo "Pinned devcontainer CLI is missing; guarded sandbox requires $RALPH_PIN_DEVCONTAINER_VERSION" >&2
  exit 1
fi
DEVCONTAINER_VERSION="$(devcontainer --version 2>/dev/null | sed -n '1p')"
if [[ "$DEVCONTAINER_VERSION" != "$RALPH_PIN_DEVCONTAINER_VERSION" ]]; then
  echo "devcontainer CLI version is ${DEVCONTAINER_VERSION:-unknown}; guarded sandbox requires $RALPH_PIN_DEVCONTAINER_VERSION" >&2
  exit 1
fi

if [[ -L "$STATE_DIR" || ( -e "$STATE_DIR" && ! -d "$STATE_DIR" ) ]]; then
  echo "Ralph managed state path is not a regular directory: $STATE_DIR" >&2
  exit 1
fi
mkdir -p "$STATE_DIR"
for managed_directory in "$SANDBOX_CONFIG_PARENT" "$SANDBOX_SKILL_PARENT" "$SANDBOX_HOST_HOME"; do
  if [[ -L "$managed_directory" || ( -e "$managed_directory" && ! -d "$managed_directory" ) ]]; then
    echo "Ralph sandbox state path is not a regular directory: $managed_directory" >&2
    exit 1
  fi
done
mkdir -p "$SANDBOX_CONFIG_PARENT" "$SANDBOX_SKILL_PARENT"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another Ralph sandbox configuration operation may be active: $LOCK_DIR" >&2
  exit 1
fi
LOCK_HELD=1
SOURCE_SKILL_HASH="$(hash_directory_tree "$SKILL_DIR")"
SANDBOX_CONTRACT_ID="$({
  printf '%s\n' "$RALPH_PIN_REPO_URL" "$RALPH_PIN_REVISION" "$RALPH_PIN_CLI_SHA256"
  printf '%s\n' "$RALPH_PIN_CODEX_VERSION" "$RALPH_PIN_DEVCONTAINER_VERSION"
  printf '%s\n' "$RALPH_PIN_PLAN_PROMPT_SHA256" "$RALPH_PIN_BUILD_PROMPT_SHA256"
  printf '%s\n' "$RALPH_PIN_CONTAINER_DOCKERFILE_SHA256" "$RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256"
  printf '%s\n' "$RALPH_PIN_SAFE_DOCKERFILE_SHA256" "$RALPH_PIN_SAFE_DEVCONTAINER_SHA256"
  printf '%s\n' "$SOURCE_SKILL_HASH"
} | sha256_stream)"
SANDBOX_CONFIG_DIR="$SANDBOX_CONFIG_PARENT/$SANDBOX_CONTRACT_ID"
SANDBOX_SKILL_CONTRACT_DIR="$SANDBOX_SKILL_PARENT/$SANDBOX_CONTRACT_ID"
SANDBOX_SKILL_DIR="$SANDBOX_SKILL_CONTRACT_DIR/ralph"
prepare_sandbox_config
prepare_sandbox_skill
prepare_sandbox_home
rm -rf "$LOCK_DIR"
LOCK_HELD=0

mounted_ralph="$SANDBOX_CONFIG_DIR/bin/ralph"
resolved_ralph="$(PATH="$SANDBOX_CONFIG_DIR/bin:$RALPH_BINARY_DIR:${PATH:-}" command -v ralph 2>/dev/null || true)"
if [[ "$resolved_ralph" != "$mounted_ralph" ]] || ! verify_sandbox_config || ! verify_sandbox_skill; then
  echo "Could not resolve the verified contract-scoped Ralph binary for the sandbox mount" >&2
  exit 1
fi

if [[ ! -s "$SANDBOX_HOST_HOME/.codex/auth.json" ]]; then
  echo "Sandbox Codex authentication is not configured. After the container opens, run: codex login" >&2
  echo "The dedicated credential will remain under $SANDBOX_HOST_HOME/.codex; host credentials are not forwarded." >&2
fi

(
  export HOME="$SANDBOX_HOST_HOME"
  unset SSH_AUTH_SOCK GNUPGHOME OPENAI_API_KEY OPENROUTER_API_KEY GEMINI_API_KEY
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
  unset GH_TOKEN GITHUB_TOKEN
  export RALPH_GUARDED_SKILL_DIR="$SANDBOX_SKILL_DIR"
  PATH="$SANDBOX_CONFIG_DIR/bin:$RALPH_BINARY_DIR:${PATH:-}" \
    RALPH_CONFIG_DIR="$SANDBOX_CONFIG_DIR" \
    "$RALPH_BINARY" sandbox "$@"
)
