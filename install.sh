#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DEST="$CODEX_CONFIG_DIR/skills"
GUIDANCE_SRC="$SCRIPT_DIR/guidance/git-safety.md"
GLOBAL_AGENTS_FILE="$CODEX_CONFIG_DIR/AGENTS.md"
GIT_GUIDANCE_START="<!-- codex-global-skills:git-safety:start -->"
GIT_GUIDANCE_END="<!-- codex-global-skills:git-safety:end -->"
GLOBAL_AGENTS_HEADING="# Global Codex Guidance"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
RALPH_REPO_URL="${RALPH_REPO_URL:-https://github.com/marc0der/ralph.git}"
RALPH_SOURCE_DIR="${RALPH_SOURCE_DIR:-$STATE_DIR/ralph}"
BIN_DIR="${RALPH_BIN_DIR:-$HOME/.local/bin}"
INSTALL_TEMP_FILE=""

cleanup_install_temp() {
  if [[ -n "$INSTALL_TEMP_FILE" ]]; then
    rm -f "$INSTALL_TEMP_FILE"
  fi
}

trap cleanup_install_temp EXIT

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "Could not find skills directory: $SKILLS_SRC" >&2
  exit 1
fi

append_git_guidance_block() {
  local destination="$1"

  printf '%s\n' "$GIT_GUIDANCE_START" >> "$destination"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >> "$destination"
  done < "$GUIDANCE_SRC"
  printf '%s\n' "$GIT_GUIDANCE_END" >> "$destination"
}

install_global_git_guidance() {
  if [[ ! -s "$GUIDANCE_SRC" ]]; then
    echo "Could not find global Git guidance: $GUIDANCE_SRC" >&2
    return 1
  fi

  local agents_dir
  local temp_file
  local begin_count=0
  local end_count=0
  local begin_line
  local end_line
  local last_byte
  agents_dir="$(dirname "$GLOBAL_AGENTS_FILE")"
  mkdir -p "$agents_dir"
  temp_file="$(mktemp "$agents_dir/.AGENTS.md.codex-global-skills.XXXXXX")"
  INSTALL_TEMP_FILE="$temp_file"

  if [[ -L "$GLOBAL_AGENTS_FILE" ]]; then
    rm -f "$temp_file"
    INSTALL_TEMP_FILE=""
    echo "Cannot install global Git guidance: $GLOBAL_AGENTS_FILE is a symbolic link" >&2
    return 1
  elif [[ ! -e "$GLOBAL_AGENTS_FILE" ]]; then
    printf '%s\n\n' "$GLOBAL_AGENTS_HEADING" >> "$temp_file"
    append_git_guidance_block "$temp_file"
  elif [[ ! -f "$GLOBAL_AGENTS_FILE" ]]; then
    rm -f "$temp_file"
    INSTALL_TEMP_FILE=""
    echo "Cannot install global Git guidance: $GLOBAL_AGENTS_FILE is not a regular file" >&2
    return 1
  else
    cp -p "$GLOBAL_AGENTS_FILE" "$temp_file"
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
      append_git_guidance_block "$temp_file"
    elif [[ "$begin_count" -ne 1 || "$end_count" -ne 1 ]]; then
      rm -f "$temp_file"
      INSTALL_TEMP_FILE=""
      echo "Cannot update global Git guidance: expected one matching managed marker pair in $GLOBAL_AGENTS_FILE" >&2
      return 1
    else
      begin_line="$(grep -nFx -- "$GIT_GUIDANCE_START" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
      end_line="$(grep -nFx -- "$GIT_GUIDANCE_END" "$GLOBAL_AGENTS_FILE" | cut -d: -f1)"
      if [[ "$begin_line" -ge "$end_line" ]]; then
        rm -f "$temp_file"
        INSTALL_TEMP_FILE=""
        echo "Cannot update global Git guidance: managed markers are out of order in $GLOBAL_AGENTS_FILE" >&2
        return 1
      fi

      head -n "$begin_line" "$GLOBAL_AGENTS_FILE" > "$temp_file"
      while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line" >> "$temp_file"
      done < "$GUIDANCE_SRC"
      tail -n "+$end_line" "$GLOBAL_AGENTS_FILE" >> "$temp_file"
    fi
  fi

  if [[ -f "$GLOBAL_AGENTS_FILE" ]] && cmp -s "$temp_file" "$GLOBAL_AGENTS_FILE"; then
    rm -f "$temp_file"
    echo "  Current:     $GLOBAL_AGENTS_FILE"
  else
    mv "$temp_file" "$GLOBAL_AGENTS_FILE"
    echo "  Installed:   $GLOBAL_AGENTS_FILE"
  fi
  INSTALL_TEMP_FILE=""
}

if [[ "${CODEX_GLOBAL_SKILLS_GUIDANCE_ONLY:-0}" == "1" ]]; then
  install_global_git_guidance
  exit
fi

ensure_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    echo "$install_hint" >&2
    exit 1
  fi
}

ensure_npm_package() {
  local command_name="$1"
  local package_name="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    echo "  Found:       $command_name"
    return
  fi

  ensure_command npm "Install Node.js/npm first, then rerun this installer."
  echo "  Installing:  $package_name"
  npm install -g "$package_name"
}

install_or_update_ralph() {
  ensure_command git "Install git first, then rerun this installer."
  mkdir -p "$STATE_DIR"

  if [[ -d "$RALPH_SOURCE_DIR/.git" ]]; then
    echo "Updating Ralph..."
    git -C "$RALPH_SOURCE_DIR" pull --ff-only
  else
    rm -rf "$RALPH_SOURCE_DIR"
    echo "Cloning Ralph..."
    git clone "$RALPH_REPO_URL" "$RALPH_SOURCE_DIR"
  fi

  echo "Installing Ralph..."
  RALPH_BIN_DIR="$BIN_DIR" "$RALPH_SOURCE_DIR/install.sh"
}

ensure_path_hint() {
  mkdir -p "$BIN_DIR"
  if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
    return
  fi

  local profile_file="$HOME/.zshrc"
  local path_line="export PATH=\"$BIN_DIR:\$PATH\""

  if [[ -f "$profile_file" ]] && grep -Fq "$path_line" "$profile_file"; then
    return
  fi

  echo "" >> "$profile_file"
  echo "# Added by codex-global-skills installer" >> "$profile_file"
  echo "$path_line" >> "$profile_file"
  export PATH="$BIN_DIR:$PATH"
  echo "  Updated:     $profile_file with $BIN_DIR"
}

ensure_command git "Install git first, then rerun this installer."

if [[ -f "$SCRIPT_DIR/.gitmodules" ]]; then
  echo "Initializing external toolkits..."
  git -C "$SCRIPT_DIR" submodule update --init --recursive
fi

echo "Installing required CLIs..."
ensure_npm_package codex @openai/codex
ensure_npm_package devcontainer @devcontainers/cli
install_or_update_ralph
ensure_path_hint

mkdir -p "$SKILLS_DEST"

echo "Installing Codex global skills..."
echo "  Source:      $SKILLS_SRC"
echo "  Destination: $SKILLS_DEST"

for skill_dir in "$SKILLS_SRC"/*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  rm -rf "$SKILLS_DEST/$skill_name"
  cp -R "$skill_dir" "$SKILLS_DEST/$skill_name"
  if [[ -d "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" && ( "$skill_name" == "equal-experts-workflow" || "$skill_name" == ee-* ) ]]; then
    rm -rf "$SKILLS_DEST/$skill_name/toolkit"
    ln -s "$SCRIPT_DIR/vendor/equalexperts/llm-toolkit" "$SKILLS_DEST/$skill_name/toolkit"
  fi
  echo "  Installed:   $skill_name"
done

if [[ -d "$SKILLS_DEST/ralph-workflow" ]]; then
  rm -rf "$SKILLS_DEST/ralph-workflow"
  echo "  Removed:     legacy ralph-workflow"
fi

echo ""
echo "Installing global Git safety guidance..."
install_global_git_guidance

echo ""
echo "Done. Restart Codex or start a new chat if newly installed skills are not visible yet."
