#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0

ok() {
  echo "[OK] $1"
}

fail() {
  echo "[FAIL] $1"
  status=1
}

echo "Codex global skills source validation"
echo ""

for script in install.sh update.sh doctor.sh validate.sh; do
  if bash -n "$SCRIPT_DIR/$script"; then
    ok "shell syntax: $script"
  else
    fail "shell syntax: $script"
  fi
done

echo ""
skill_count=0
for skill_dir in "$SCRIPT_DIR/skills"/*; do
  [[ -d "$skill_dir" ]] || continue

  skill="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"
  metadata_file="$skill_dir/agents/openai.yaml"
  docs_file="$SCRIPT_DIR/docs/$skill.md"
  skill_count=$((skill_count + 1))

  if [[ -f "$skill_file" ]] && awk -v expected="$skill" '
    NR == 1 {
      if ($0 != "---") {
        exit 1
      }
      in_frontmatter = 1
      next
    }
    in_frontmatter && $0 == "---" {
      closed = 1
      exit
    }
    in_frontmatter && $0 ~ /^name:[[:space:]]*/ {
      value = $0
      sub(/^name:[[:space:]]*/, "", value)
      name = value
    }
    in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
      value = $0
      sub(/^description:[[:space:]]*/, "", value)
      if (length(value) > 0) {
        has_description = 1
      }
    }
    END {
      if (!(closed && name == expected && has_description)) {
        exit 1
      }
    }
  ' "$skill_file"; then
    ok "skill frontmatter: $skill"
  else
    fail "invalid SKILL.md frontmatter for $skill"
  fi

  if [[ -f "$metadata_file" ]] &&
    grep -Fq "display_name:" "$metadata_file" &&
    grep -Fq "short_description:" "$metadata_file" &&
    grep -Fq "default_prompt:" "$metadata_file" &&
    grep -Fq "\$$skill" "$metadata_file"; then
    ok "skill UI metadata: $skill"
  else
    fail "invalid or incomplete agents/openai.yaml for $skill"
  fi

  if [[ -f "$docs_file" ]]; then
    ok "developer guide: docs/$skill.md"
  else
    fail "missing developer guide: docs/$skill.md"
  fi

  catalog_entry='`'"$skill"'`'
  if grep -Fq "$catalog_entry" "$SCRIPT_DIR/README.md"; then
    ok "README catalog entry: $skill"
  else
    fail "missing README catalog entry: $skill"
  fi
done

if [[ "$skill_count" -eq 0 ]]; then
  fail "no skill directories found under $SCRIPT_DIR/skills"
fi

echo ""
if grep -R -n -E 'TODO|\[TODO' "$SCRIPT_DIR/skills"; then
  fail "skill templates still contain TODO markers"
else
  ok "no skill TODO markers"
fi

if grep -R -n -E '[[:blank:]]+$' "$SCRIPT_DIR/AGENTS.md" "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/docs" "$SCRIPT_DIR/skills" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/update.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/validate.sh"; then
  fail "trailing whitespace found"
else
  ok "no trailing whitespace"
fi

if git -C "$SCRIPT_DIR" diff --check; then
  ok "tracked diff whitespace"
else
  fail "tracked diff whitespace"
fi

exit "$status"
