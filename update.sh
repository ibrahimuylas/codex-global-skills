#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git -C "$SCRIPT_DIR" pull --ff-only
git -C "$SCRIPT_DIR" submodule update --init --recursive
"$SCRIPT_DIR/install.sh"
