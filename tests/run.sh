#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/test-installer.sh"
"$SCRIPT_DIR/test-ee-toolkit.sh"
"$SCRIPT_DIR/test-ralph-safety.sh"
"$SCRIPT_DIR/test-ralph-pinned-integration.sh"
