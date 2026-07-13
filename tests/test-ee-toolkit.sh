#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-ee.XXXXXX")"

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

expect_rejected() {
  local message="$1"
  local repository="$2"

  if verify_ee_toolkit_exact "$repository"; then
    fail_test "$message"
  fi
}

upstream="$TEST_ROOT/toolkit-upstream"
repository="$TEST_ROOT/repository"
toolkit="$repository/vendor/equalexperts/llm-toolkit"

git init -q "$upstream"
git -C "$upstream" config user.name 'Codex Test'
git -C "$upstream" config user.email 'codex-test@example.invalid'
printf '%s\n' 'version one' > "$upstream/rules.md"
git -C "$upstream" add rules.md
git -C "$upstream" commit -q -m 'initial toolkit'

git init -q "$repository"
git -C "$repository" config user.name 'Codex Test'
git -C "$repository" config user.email 'codex-test@example.invalid'
git -C "$repository" -c protocol.file.allow=always submodule add -q "$upstream" vendor/equalexperts/llm-toolkit
git -C "$repository" commit -q -m 'add toolkit'
expected_revision="$(git -C "$toolkit" rev-parse HEAD)"

verify_ee_toolkit_exact "$repository" || fail_test "exact clean EE toolkit was rejected"

printf '%s\n' 'local edit' >> "$toolkit/rules.md"
expect_rejected "dirty EE toolkit was accepted" "$repository"
printf '%s\n' 'version one' > "$toolkit/rules.md"
verify_ee_toolkit_exact "$repository" || fail_test "restored EE toolkit was rejected"

printf '%s\n' 'version two' > "$upstream/rules.md"
git -C "$upstream" add rules.md
git -C "$upstream" commit -q -m 'advance toolkit'
advanced_revision="$(git -C "$upstream" rev-parse HEAD)"
git -C "$toolkit" fetch -q origin
git -C "$toolkit" switch -q --detach "$advanced_revision"
expect_rejected "EE toolkit at a revision other than the gitlink was accepted" "$repository"
git -C "$toolkit" switch -q --detach "$expected_revision"

git -C "$toolkit" remote set-url origin "$TEST_ROOT/wrong-origin"
expect_rejected "EE toolkit with the wrong origin was accepted" "$repository"
git -C "$toolkit" remote set-url origin "$upstream"
verify_ee_toolkit_exact "$repository" || fail_test "restored EE toolkit origin was rejected"

printf '%s\n' 'untracked' > "$toolkit/untracked.md"
expect_rejected "EE toolkit with an untracked file was accepted" "$repository"

echo "[OK] EE toolkit verification enforces gitlink, cleanliness, and origin"
