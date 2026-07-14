#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUIDANCE_SRC="$SCRIPT_DIR/installer/guidance/git-safety.md"
PACKS_DIR="$SCRIPT_DIR/packs"
status=0
TEMP_DIR=""

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

fail() {
  echo "[FAIL] $1"
  status=1
}

validate_skill_frontmatter() {
  local skill="$1"
  local skill_file="$2"
  local parsed
  local name
  local description

  parsed="$(awk '
    NR == 1 { if ($0 != "---") exit 1; in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { closed = 1; exit }
    in_frontmatter && $0 ~ /^name:[[:space:]]*/ {
      if (++name_count != 1) exit 1
      value = $0; sub(/^name:[[:space:]]*/, "", value); name = value; next
    }
    in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
      if (++description_count != 1) exit 1
      value = $0; sub(/^description:[[:space:]]*/, "", value); description = value; next
    }
    in_frontmatter && $0 !~ /^[[:space:]]*$/ { exit 1 }
    END {
      if (!(closed && name_count == 1 && description_count == 1 && length(name) > 0 && length(description) > 0)) exit 1
      print name
      print description
    }
  ' "$skill_file" 2>/dev/null)" || return 1

  name="$(printf '%s\n' "$parsed" | sed -n '1p')"
  description="$(printf '%s\n' "$parsed" | sed -n '2p')"
  [[ "$name" == "$skill" ]] || return 1
  is_safe_name "$name" || return 1
  [[ "${#name}" -le 64 ]] || return 1
  [[ "${#description}" -le 1024 ]] || return 1
  [[ "$description" != *'<'* && "$description" != *'>'* ]] || return 1
}

validate_skill_metadata() {
  local skill="$1"
  local metadata_file="$2"
  local short_description

  [[ -f "$metadata_file" ]] || return 1
  [[ "$(sed -n '1p' "$metadata_file")" == "interface:" ]] || return 1
  grep -Eq '^  display_name: "[^"]+"$' "$metadata_file" || return 1
  grep -Eq '^  short_description: "[^"]+"$' "$metadata_file" || return 1
  grep -Eq '^  default_prompt: "[^"]+"$' "$metadata_file" || return 1
  grep -Fq "\$$skill" "$metadata_file" || return 1
  short_description="$(sed -n 's/^  short_description: "\(.*\)"$/\1/p' "$metadata_file")"
  [[ "${#short_description}" -ge 25 && "${#short_description}" -le 64 ]] || return 1
}

validate_routing_evals() {
  local routing="$SCRIPT_DIR/installer/evals/routing.tsv"
  local skill
  local expected
  local excluded
  local case_id
  local prompt

  if [[ ! -f "$routing" ]] || [[ "$(sed -n '1p' "$routing")" != $'case_id\texpected_skill\texcluded_skills\tprompt' ]]; then
    fail "missing or invalid installer/evals/routing.tsv header"
    return
  fi
  if ! awk -F '\t' 'NR > 1 && (NF != 4 || $1 !~ /^[a-z0-9-]+$/ || $2 == "" || $3 == "" || $4 == "") { exit 1 } END { if (NR < 2) exit 1 }' "$routing"; then
    fail "invalid routing evaluation row"
    return
  fi
  if [[ -n "$(tail -n +2 "$routing" | cut -f1 | LC_ALL=C sort | uniq -d)" ]]; then
    fail "duplicate routing evaluation case IDs"
    return
  fi

  while IFS=$'\t' read -r case_id expected excluded prompt; do
    [[ "$case_id" == "case_id" ]] && continue
    if [[ "$expected" != "none" && ! -d "$SCRIPT_DIR/skills/$expected" ]]; then
      fail "routing case $case_id references missing expected skill: $expected"
    fi
    while IFS= read -r skill; do
      if [[ ! -d "$SCRIPT_DIR/skills/$skill" ]]; then
        fail "routing case $case_id references missing excluded skill: $skill"
      fi
      if [[ "$skill" == "$expected" ]]; then
        fail "routing case $case_id both expects and excludes $skill"
      fi
    done < <(printf '%s\n' "$excluded" | tr ',' '\n')
  done < "$routing"

  for skill in "$SCRIPT_DIR/skills"/*; do
    [[ -d "$skill" ]] || continue
    skill="$(basename "$skill")"
    if ! awk -F '\t' -v expected="$skill" 'NR > 1 && $2 == expected { found = 1 } END { exit(found ? 0 : 1) }' "$routing"; then
      fail "routing evaluations lack a positive case for $skill"
    fi
    if ! tail -n +2 "$routing" | cut -f3 | tr ',' '\n' | grep -Fqx -- "$skill"; then
      fail "routing evaluations lack adjacent-negative coverage for $skill"
    fi
  done
  ok "routing evaluation schema, references, and coverage"
}

validate_safety_evals() {
  local safety="$SCRIPT_DIR/installer/evals/workflow-safety.tsv"
  local case_id
  local skill
  local prompt
  local required
  local forbidden

  if [[ ! -f "$safety" ]] || [[ "$(sed -n '1p' "$safety")" != $'case_id\tskill\tprompt\trequired_behaviors\tforbidden_behaviors' ]]; then
    fail "missing or invalid installer/evals/workflow-safety.tsv header"
    return
  fi
  if ! awk -F '\t' 'NR > 1 && (NF != 5 || $1 !~ /^[a-z0-9-]+$/ || $2 == "" || $3 == "" || $4 == "" || $5 == "") { exit 1 } END { if (NR < 2) exit 1 }' "$safety"; then
    fail "invalid workflow safety evaluation row"
    return
  fi
  if [[ -n "$(tail -n +2 "$safety" | cut -f1 | LC_ALL=C sort | uniq -d)" ]]; then
    fail "duplicate workflow safety evaluation case IDs"
    return
  fi
  while IFS=$'\t' read -r case_id skill prompt required forbidden; do
    [[ "$case_id" == "case_id" ]] && continue
    [[ -d "$SCRIPT_DIR/skills/$skill" ]] || fail "safety case $case_id references missing skill: $skill"
  done < "$safety"
  for skill in ee-control-plane equal-experts-workflow ralph commit git-workflow decision-record dependency-maintenance quality-gate; do
    if ! awk -F '\t' -v expected="$skill" 'NR > 1 && $2 == expected { found = 1 } END { exit(found ? 0 : 1) }' "$safety"; then
      fail "workflow safety evaluations lack coverage for $skill"
    fi
  done
  ok "workflow safety evaluation schema, references, and coverage"
}

validate_legacy_hashes() {
  local hashes="$SCRIPT_DIR/installer/migrations/legacy-skill-hashes.tsv"
  local skill
  local digest
  local mode_digest
  local source_commit

  if [[ ! -f "$hashes" ]] || [[ "$(sed -n '1p' "$hashes")" != $'skill\tdigest\tmode_digest\tsource_commit' ]]; then
    fail "missing or invalid installer/migrations/legacy-skill-hashes.tsv header"
    return
  fi
  if ! awk -F '\t' 'NR > 1 && (NF != 4 || $1 !~ /^[a-z0-9-]+$/ || $2 !~ /^[0-9a-f]+$/ || length($2) != 64 || $3 !~ /^[0-9a-f]+$/ || length($3) != 64 || $4 !~ /^[0-9a-f]+$/ || length($4) != 40) { exit 1 } END { if (NR < 2) exit 1 }' "$hashes"; then
    fail "invalid legacy skill hash row"
    return
  fi
  if [[ -n "$(tail -n +2 "$hashes" | cut -f1,2,3 | LC_ALL=C sort | uniq -d)" ]]; then
    fail "duplicate legacy skill hash rows"
    return
  fi
  while IFS=$'\t' read -r skill digest mode_digest source_commit; do
    [[ "$skill" == "skill" ]] && continue
    [[ -d "$SCRIPT_DIR/skills/$skill" ]] || fail "legacy hash references missing skill: $skill"
    git -C "$SCRIPT_DIR" cat-file -e "$source_commit^{commit}" 2>/dev/null || fail "legacy hash references missing commit: $source_commit"
  done < "$hashes"
  ok "legacy skill hash migration table"
}

validate_ralph_pin() {
  local pin_file="$SCRIPT_DIR/skills/ralph/assets/ralph-pin.env"
  local assignment_count
  local revision
  local cli_hash
  local global_skill_defaults_hash
  local codex_version
  local devcontainer_version
  local plan_prompt_hash
  local prompt_hash
  local container_hash
  local devcontainer_hash
  local safe_container_hash
  local safe_devcontainer_hash
  local runtime_id
  local computed_runtime_id

  if [[ ! -f "$pin_file" || -L "$pin_file" ]]; then
    fail "missing regular Ralph pin contract"
    return
  fi
  assignment_count="$(grep -Ec '^[A-Z0-9_]+=' "$pin_file" || true)"
  if [[ "$assignment_count" -ne 14 ]] ||
    ! grep -Eq '^RALPH_PIN_REPO_URL=https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_REVISION=[0-9a-f]{40}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_CLI_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_GLOBAL_SKILL_DEFAULTS_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_CODEX_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_UPSTREAM_CODEX_DEFAULT_MODEL=[A-Za-z0-9._-]+$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_DEVCONTAINER_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_PLAN_PROMPT_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_BUILD_PROMPT_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_CONTAINER_DOCKERFILE_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_SAFE_DOCKERFILE_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_SAFE_DEVCONTAINER_SHA256=[0-9a-f]{64}$' "$pin_file" ||
    ! grep -Eq '^RALPH_PIN_RUNTIME_ID=[0-9a-f]{64}$' "$pin_file"; then
    fail "invalid Ralph pin contract"
    return
  fi

  revision="$(sed -n 's/^RALPH_PIN_REVISION=//p' "$pin_file")"
  cli_hash="$(sed -n 's/^RALPH_PIN_CLI_SHA256=//p' "$pin_file")"
  global_skill_defaults_hash="$(sed -n 's/^RALPH_PIN_GLOBAL_SKILL_DEFAULTS_SHA256=//p' "$pin_file")"
  codex_version="$(sed -n 's/^RALPH_PIN_CODEX_VERSION=//p' "$pin_file")"
  devcontainer_version="$(sed -n 's/^RALPH_PIN_DEVCONTAINER_VERSION=//p' "$pin_file")"
  plan_prompt_hash="$(sed -n 's/^RALPH_PIN_PLAN_PROMPT_SHA256=//p' "$pin_file")"
  prompt_hash="$(sed -n 's/^RALPH_PIN_BUILD_PROMPT_SHA256=//p' "$pin_file")"
  container_hash="$(sed -n 's/^RALPH_PIN_CONTAINER_DOCKERFILE_SHA256=//p' "$pin_file")"
  devcontainer_hash="$(sed -n 's/^RALPH_PIN_CONTAINER_DEVCONTAINER_SHA256=//p' "$pin_file")"
  safe_container_hash="$(sed -n 's/^RALPH_PIN_SAFE_DOCKERFILE_SHA256=//p' "$pin_file")"
  safe_devcontainer_hash="$(sed -n 's/^RALPH_PIN_SAFE_DEVCONTAINER_SHA256=//p' "$pin_file")"
  runtime_id="$(sed -n 's/^RALPH_PIN_RUNTIME_ID=//p' "$pin_file")"
  computed_runtime_id="$({
    sed -n 's/^RALPH_PIN_REPO_URL=//p' "$pin_file"
    printf '%s\n' "$revision" "$cli_hash" "$global_skill_defaults_hash" "$plan_prompt_hash" "$prompt_hash" "$container_hash" "$devcontainer_hash"
  } | sha256_stream)"
  [[ "$runtime_id" == "$computed_runtime_id" ]] || fail "Ralph runtime ID does not match its source/CLI/config contract"
  grep -Fq "$revision" "$SCRIPT_DIR/docs/install.md" || fail "docs/install.md does not document the Ralph pin revision"
  grep -Fqx "CODEX_REQUIRED_VERSION=$codex_version" "$SCRIPT_DIR/installer/pins/cli.env" || fail "Ralph and global Codex CLI pins differ"
  grep -Fqx "DEVCONTAINER_REQUIRED_VERSION=$devcontainer_version" "$SCRIPT_DIR/installer/pins/cli.env" || fail "Ralph and global devcontainer CLI pins differ"
  verify_regular_file_sha256 "$SCRIPT_DIR/skills/ralph/assets/Dockerfile.safe" "$safe_container_hash" || fail "guarded Ralph Dockerfile differs from its pin"
  verify_regular_file_sha256 "$SCRIPT_DIR/skills/ralph/assets/devcontainer.safe.json" "$safe_devcontainer_hash" || fail "guarded Ralph devcontainer config differs from its pin"
  verify_regular_file_sha256 "$SCRIPT_DIR/skills/ralph/assets/global-skill.env" "$global_skill_defaults_hash" ||
    fail "guarded Ralph global-skill defaults differ from their pin"
  grep -Fqx 'RALPH_GLOBAL_SKILL_BACKEND=codex' "$SCRIPT_DIR/skills/ralph/assets/global-skill.env" ||
    fail "guarded Ralph global-skill defaults do not select Codex"
  if grep -Eq '^RALPH_GLOBAL_SKILL_MODEL=' "$SCRIPT_DIR/skills/ralph/assets/global-skill.env"; then
    fail "guarded Ralph global-skill defaults must not force a Codex model"
  fi
  grep -Fq 'MODEL_ARGUMENT_SUPPLIED=1' "$SCRIPT_DIR/skills/ralph/scripts/run-guarded.sh" ||
    fail "Ralph guarded runner does not preserve explicit model requests"
  grep -Fq -- '&& -n "${RALPH_GLOBAL_SKILL_MODEL:-}"' "$SCRIPT_DIR/skills/ralph/scripts/run-guarded.sh" ||
    fail "Ralph guarded runner does not keep model override optional"
  [[ -x "$SCRIPT_DIR/skills/ralph/scripts/codex-shim/codex" && ! -L "$SCRIPT_DIR/skills/ralph/scripts/codex-shim/codex" ]] ||
    fail "Ralph guarded runner is missing its Codex model-deferral shim"
  grep -Fq 'RALPH_CODEX_DEFER_MODEL=$CODEX_DEFER_MODEL' "$SCRIPT_DIR/skills/ralph/scripts/run-guarded.sh" ||
    fail "Ralph guarded runner does not scope Codex model deferral"
  grep -Fq 'CODEX_HOME=$BACKEND_CODEX_HOME' "$SCRIPT_DIR/skills/ralph/scripts/run-guarded.sh" ||
    fail "Ralph guarded runner does not isolate its backend Codex home"
  grep -Fq 'arguments=(exec --ephemeral --disable plugins)' "$SCRIPT_DIR/skills/ralph/scripts/codex-shim/codex" ||
    fail "Ralph Codex shim does not isolate backend sessions and plugins"
  grep -Fq 'managed Ralph backend Codex home isolates global skills' "$SCRIPT_DIR/doctor.sh" ||
    fail "doctor does not verify the managed Ralph backend Codex home"
  grep -Fq "@openai/codex@$codex_version" "$SCRIPT_DIR/skills/ralph/assets/Dockerfile.safe" || fail "guarded Ralph Dockerfile does not use the Codex pin"
  if grep -Eq 'docker\.sock|network=host|localEnv:HOME|/home/node/\.ssh|/home/node/\.config/gh' "$SCRIPT_DIR/skills/ralph/assets/devcontainer.safe.json"; then
    fail "guarded Ralph devcontainer exposes a host escape or host credential mount"
  fi
  grep -Fq '"RALPH_CONFIG_DIR": "/home/node/.config/ralph"' "$SCRIPT_DIR/skills/ralph/assets/devcontainer.safe.json" ||
    fail "guarded Ralph devcontainer does not export its mounted config path"
  grep -Fq 'target=/home/node/.codex/skills/ralph,type=bind,readonly' "$SCRIPT_DIR/skills/ralph/assets/devcontainer.safe.json" ||
    fail "guarded Ralph devcontainer does not mount the enforcement skill read-only"
  grep -Fq 'source "$RALPH_PIN_FILE"' "$SCRIPT_DIR/install.sh" || fail "installer does not load the shared Ralph pin contract"
  grep -Fq 'source "$RALPH_PIN_FILE"' "$SCRIPT_DIR/doctor.sh" || fail "doctor does not load the shared Ralph pin contract"
  grep -Fq 'source "$RALPH_PIN_FILE"' "$SCRIPT_DIR/skills/ralph/scripts/run-guarded.sh" || fail "Ralph guarded runner does not load the shared pin contract"
  if grep -RFq "$cli_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$plan_prompt_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$prompt_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$container_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$devcontainer_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$global_skill_defaults_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$safe_container_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts" ||
    grep -RFq "$safe_devcontainer_hash" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/skills/ralph/scripts"; then
    fail "Ralph hashes are duplicated outside the shared pin contract"
    return
  fi
  ok "shared Ralph runtime pin contract"
}

validate_cli_pins() {
  local pin_file="$SCRIPT_DIR/installer/pins/cli.env"
  local codex_version
  local devcontainer_version

  if [[ ! -f "$pin_file" || -L "$pin_file" ]]; then
    fail "missing regular CLI pin contract"
    return
  fi
  if [[ "$(grep -Ec '^[A-Z0-9_]+=' "$pin_file" || true)" -ne 4 ]] ||
    ! grep -Eq '^CODEX_REQUIRED_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$pin_file" ||
    ! grep -Eq '^CODEX_NPM_PACKAGE=@openai/codex@[0-9]+\.[0-9]+\.[0-9]+$' "$pin_file" ||
    ! grep -Eq '^DEVCONTAINER_REQUIRED_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$pin_file" ||
    ! grep -Eq '^DEVCONTAINER_NPM_PACKAGE=@devcontainers/cli@[0-9]+\.[0-9]+\.[0-9]+$' "$pin_file"; then
    fail "invalid CLI pin contract"
    return
  fi
  codex_version="$(sed -n 's/^CODEX_REQUIRED_VERSION=//p' "$pin_file")"
  devcontainer_version="$(sed -n 's/^DEVCONTAINER_REQUIRED_VERSION=//p' "$pin_file")"
  grep -Fqx "CODEX_NPM_PACKAGE=@openai/codex@$codex_version" "$pin_file" || fail "Codex package and required version differ"
  grep -Fqx "DEVCONTAINER_NPM_PACKAGE=@devcontainers/cli@$devcontainer_version" "$pin_file" || fail "devcontainer package and required version differ"
  grep -Fq "Codex CLI \`$codex_version\`" "$SCRIPT_DIR/docs/install.md" || fail "docs/install.md does not document the Codex CLI pin"
  grep -Fq "devcontainer CLI \`$devcontainer_version\`" "$SCRIPT_DIR/docs/install.md" || fail "docs/install.md does not document the devcontainer CLI pin"
  grep -Fq 'source "$CLI_PIN_FILE"' "$SCRIPT_DIR/install.sh" || fail "installer does not load the shared CLI pin contract"
  grep -Fq 'source "$CLI_PIN_FILE"' "$SCRIPT_DIR/doctor.sh" || fail "doctor does not load the shared CLI pin contract"
  ok "shared CLI dependency pin contract"
}

echo "Codex global skills source validation"
echo ""

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-global-skills-validate.XXXXXX")"

for script in install.sh update.sh doctor.sh validate.sh installer/lib/common.sh tests/*.sh; do
  [[ -e "$SCRIPT_DIR/$script" ]] || continue
  if bash -n "$SCRIPT_DIR/$script"; then
    ok "shell syntax: $script"
  else
    fail "shell syntax: $script"
  fi
done
for script in "$SCRIPT_DIR"/tests/*.sh; do
  [[ -x "$script" ]] || fail "test script is not executable: ${script#"$SCRIPT_DIR/"}"
done
while IFS= read -r script; do
  [[ -n "$script" ]] || continue
  if bash -n "$script"; then
    ok "shell syntax: ${script#"$SCRIPT_DIR/"}"
  else
    fail "shell syntax: ${script#"$SCRIPT_DIR/"}"
  fi
  [[ -x "$script" ]] || fail "skill helper is not executable: ${script#"$SCRIPT_DIR/"}"
done < <(find "$SCRIPT_DIR/skills" -path '*/scripts/*' -type f -print | LC_ALL=C sort)

echo ""
if [[ -s "$GUIDANCE_SRC" ]] &&
  grep -Fqx "## Git safety and working agreements" "$GUIDANCE_SRC" &&
  grep -Eq '^- ' "$GUIDANCE_SRC" &&
  ! grep -Fq '<!-- codex-global-skills:git-safety:' "$GUIDANCE_SRC"; then
  ok "global Git guidance source"
else
  fail "missing or invalid installer/guidance/git-safety.md"
fi

echo ""
skill_count=0
: > "$TEMP_DIR/skill-names"
for skill_dir in "$SCRIPT_DIR/skills"/*; do
  [[ -d "$skill_dir" ]] || continue

  skill="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"
  metadata_file="$skill_dir/agents/openai.yaml"
  docs_file="$SCRIPT_DIR/docs/$skill.md"
  skill_count=$((skill_count + 1))
  printf '%s\n' "$skill" >> "$TEMP_DIR/skill-names"

  if [[ -f "$skill_file" ]] && validate_skill_frontmatter "$skill" "$skill_file"; then
    ok "skill frontmatter: $skill"
  else
    fail "invalid SKILL.md frontmatter for $skill"
  fi
  if validate_skill_metadata "$skill" "$metadata_file"; then
    ok "skill UI metadata: $skill"
  else
    fail "invalid or incomplete agents/openai.yaml for $skill"
  fi
  [[ -f "$docs_file" ]] && ok "developer guide: docs/$skill.md" || fail "missing developer guide: docs/$skill.md"
  if grep -Eq '^\| `?'"$skill"'`? \|' "$SCRIPT_DIR/README.md"; then
    ok "README catalog entry: $skill"
  else
    fail "missing README catalog table entry: $skill"
  fi
done

[[ "$skill_count" -gt 0 ]] || fail "no skill directories found under $SCRIPT_DIR/skills"

echo ""
pack_count=0
for manifest in "$PACKS_DIR"/*.pack; do
  [[ -f "$manifest" ]] || continue
  pack="$(basename "$manifest" .pack)"
  pack_count=$((pack_count + 1))
  : > "$TEMP_DIR/pack-skills"
  : > "$TEMP_DIR/pack-dependencies"
  : > "$TEMP_DIR/pack-guidance"
  if ! is_safe_name "$pack" || ! load_pack_manifest "$manifest" "$TEMP_DIR/pack-skills" "$TEMP_DIR/pack-dependencies" "$TEMP_DIR/pack-guidance"; then
    fail "invalid pack manifest: $pack"
    continue
  fi
  if [[ ! -s "$TEMP_DIR/pack-skills" ]]; then
    fail "pack contains no skills: $pack"
  fi
  if ! grep -Fqx git-safety "$TEMP_DIR/pack-guidance"; then
    fail "pack must include global git-safety guidance: $pack"
  fi
  if [[ -n "$(grep -v '^#' "$manifest" | sed '/^$/d' | LC_ALL=C sort | uniq -d)" ]]; then
    fail "pack contains duplicate entries: $pack"
  fi
  while IFS= read -r skill; do
    [[ -d "$SCRIPT_DIR/skills/$skill" ]] || fail "pack $pack references missing skill: $skill"
  done < "$TEMP_DIR/pack-skills"
  ok "pack manifest: $pack"
done
[[ "$pack_count" -gt 0 ]] || fail "no pack manifests found"

: > "$TEMP_DIR/all-skills"
: > "$TEMP_DIR/all-dependencies"
: > "$TEMP_DIR/all-guidance"
if load_pack_manifest "$PACKS_DIR/all.pack" "$TEMP_DIR/all-skills" "$TEMP_DIR/all-dependencies" "$TEMP_DIR/all-guidance"; then
  LC_ALL=C sort -u "$TEMP_DIR/all-skills" > "$TEMP_DIR/all-sorted"
  LC_ALL=C sort -u "$TEMP_DIR/skill-names" > "$TEMP_DIR/source-sorted"
  cmp -s "$TEMP_DIR/all-sorted" "$TEMP_DIR/source-sorted" && ok "all pack covers every source skill" || fail "all pack does not exactly cover source skills"
  : > "$TEMP_DIR/other-pack-skills"
  : > "$TEMP_DIR/other-pack-dependencies"
  : > "$TEMP_DIR/other-pack-guidance"
  for manifest in "$PACKS_DIR"/*.pack; do
    [[ "$(basename "$manifest")" == "all.pack" ]] && continue
    load_pack_manifest "$manifest" "$TEMP_DIR/other-pack-skills" "$TEMP_DIR/other-pack-dependencies" "$TEMP_DIR/other-pack-guidance" ||
      fail "cannot load pack while checking all-pack union: $(basename "$manifest" .pack)"
  done
  for kind in dependencies guidance; do
    LC_ALL=C sort -u "$TEMP_DIR/all-$kind" > "$TEMP_DIR/all-$kind-sorted"
    LC_ALL=C sort -u "$TEMP_DIR/other-pack-$kind" > "$TEMP_DIR/other-pack-$kind-sorted"
    cmp -s "$TEMP_DIR/all-$kind-sorted" "$TEMP_DIR/other-pack-$kind-sorted" &&
      ok "all pack covers every pack $kind entry" || fail "all pack does not cover the complete $kind union"
  done
else
  fail "all pack cannot be loaded"
fi

: > "$TEMP_DIR/ralph-skills"
: > "$TEMP_DIR/ralph-dependencies"
: > "$TEMP_DIR/ralph-guidance"
if load_pack_manifest "$PACKS_DIR/ralph.pack" "$TEMP_DIR/ralph-skills" "$TEMP_DIR/ralph-dependencies" "$TEMP_DIR/ralph-guidance"; then
  for skill in ralph quality-gate local-review commit git-workflow; do
    grep -Fqx "$skill" "$TEMP_DIR/ralph-skills" || fail "ralph pack lacks required handoff skill: $skill"
  done
else
  fail "ralph pack cannot be loaded"
fi

: > "$TEMP_DIR/ee-skills"
: > "$TEMP_DIR/ee-dependencies"
: > "$TEMP_DIR/ee-guidance"
if load_pack_manifest "$PACKS_DIR/equal-experts.pack" "$TEMP_DIR/ee-skills" "$TEMP_DIR/ee-dependencies" "$TEMP_DIR/ee-guidance"; then
  grep -Fqx decision-record "$TEMP_DIR/ee-skills" || fail "equal-experts pack lacks decision-record handoff"
else
  fail "equal-experts pack cannot be loaded"
fi

echo ""
validate_routing_evals
validate_safety_evals
validate_legacy_hashes
validate_ralph_pin
validate_cli_pins

for required_doc in docs/packs.md docs/evaluations.md docs/skills.md docs/lifecycle.md docs/install.md docs/global-git-guidance.md docs/repository-layout.md docs/adding-a-skill.md; do
  [[ -f "$SCRIPT_DIR/$required_doc" ]] && ok "developer guide: $required_doc" || fail "missing developer guide: $required_doc"
done

echo ""
if grep -R -n -E 'TODO|\[TODO' "$SCRIPT_DIR/skills" "$SCRIPT_DIR/installer/guidance" "$SCRIPT_DIR/packs" "$SCRIPT_DIR/installer/evals" "$SCRIPT_DIR/installer/migrations" "$SCRIPT_DIR/installer/pins"; then
  fail "skill, guidance, pack, or evaluation files still contain TODO markers"
else
  ok "no managed-content TODO markers"
fi

if grep -R -n -E '[[:blank:]]+$' "$SCRIPT_DIR/AGENTS.md" "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/docs" "$SCRIPT_DIR/skills" "$SCRIPT_DIR/installer" "$SCRIPT_DIR/packs" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/update.sh" "$SCRIPT_DIR/doctor.sh" "$SCRIPT_DIR/validate.sh" "$SCRIPT_DIR/tests" 2>/dev/null; then
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
