#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
SKILLS_DEST="${CODEX_HOME:-$HOME/.codex}/skills"
STATE_DIR="${CODEX_GLOBAL_SKILLS_HOME:-$HOME/.local/share/codex-global-skills}"
RALPH_REPO_URL="${RALPH_REPO_URL:-https://github.com/marc0der/ralph.git}"
RALPH_SOURCE_DIR="${RALPH_SOURCE_DIR:-$STATE_DIR/ralph}"
BIN_DIR="${RALPH_BIN_DIR:-$HOME/.local/bin}"

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "Could not find skills directory: $SKILLS_SRC" >&2
  exit 1
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
echo "Done. Restart Codex or start a new chat if newly installed skills are not visible yet."
