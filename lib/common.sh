#!/usr/bin/env bash

# Shared, side-effect-free helpers for the installer, doctor, and validator.

append_unique_line() {
  local value="$1"
  local destination="$2"

  if ! grep -Fqx -- "$value" "$destination" 2>/dev/null; then
    printf '%s\n' "$value" >> "$destination"
  fi
}

is_safe_name() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
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

sha256_file() {
  local file="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo "Missing SHA-256 command: install shasum or sha256sum" >&2
    return 1
  fi
}

verify_regular_file_sha256() {
  local file="$1"
  local expected="$2"

  [[ -f "$file" && ! -L "$file" ]] || return 1
  [[ "$(sha256_file "$file")" == "$expected" ]]
}

verify_git_checkout_exact() {
  local directory="$1"
  local expected_url="$2"
  local expected_revision="$3"
  local actual_url
  local actual_revision

  [[ -d "$directory" && ! -L "$directory" ]] || return 1
  git -C "$directory" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  actual_url="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  actual_revision="$(git -C "$directory" rev-parse HEAD 2>/dev/null || true)"
  [[ "$actual_url" == "$expected_url" && "$actual_revision" == "$expected_revision" ]] || return 1
  [[ -z "$(git -C "$directory" status --porcelain --untracked-files=all 2>/dev/null)" ]]
}

file_mode() {
  local file="$1"

  if stat -f '%Lp' "$file" >/dev/null 2>&1; then
    stat -f '%Lp' "$file"
  else
    stat -c '%a' "$file"
  fi
}

hash_skill_directory_legacy() {
  local directory="$1"
  local ignore_toolkit="${2:-0}"
  local find_arguments=(.)

  if [[ ! -d "$directory" || -L "$directory" ]]; then
    echo "Cannot hash non-directory skill path: $directory" >&2
    return 1
  fi

  if [[ "$ignore_toolkit" == "1" ]]; then
    find_arguments+=(\( -type f -o -type l \) ! -path './toolkit' ! -path './toolkit/*' -print)
  else
    find_arguments+=(\( -type f -o -type l \) -print)
  fi

  (
    cd "$directory"
    find "${find_arguments[@]}" | LC_ALL=C sort | while IFS= read -r relative_path; do
        if [[ -L "$relative_path" ]]; then
          printf 'link\t%s\t%s\n' "$relative_path" "$(readlink "$relative_path")"
        else
          printf 'file\t%s\t%s\n' "$relative_path" "$(sha256_file "$relative_path")"
        fi
      done
  ) | sha256_stream
}

hash_skill_directory() {
  local directory="$1"
  local ignore_toolkit="${2:-0}"
  local find_arguments=(.)

  if [[ ! -d "$directory" || -L "$directory" ]]; then
    echo "Cannot hash non-directory skill path: $directory" >&2
    return 1
  fi

  if [[ "$ignore_toolkit" == "1" ]]; then
    find_arguments+=(\( -type f -o -type l \) ! -path './toolkit' ! -path './toolkit/*' -print)
  else
    find_arguments+=(\( -type f -o -type l \) -print)
  fi

  (
    cd "$directory"
    find "${find_arguments[@]}" | LC_ALL=C sort | while IFS= read -r relative_path; do
        if [[ -L "$relative_path" ]]; then
          printf 'link\t%s\t%s\n' "$relative_path" "$(readlink "$relative_path")"
        else
          printf 'file\t%s\t%s\t%s\n' "$relative_path" "$(file_mode "$relative_path")" "$(sha256_file "$relative_path")"
        fi
      done
  ) | sha256_stream
}

is_ee_skill() {
  [[ "$1" == "equal-experts-workflow" || "$1" == ee-* ]]
}

pack_manifest_path() {
  local packs_dir="$1"
  local pack="$2"

  printf '%s/%s.pack\n' "$packs_dir" "$pack"
}

state_manifest_records_digest() {
  local manifest="$1"

  awk '
    $1 == "pack" { print "pack " $2 " " $3 }
    $1 == "dependency" { print "dependency " $2 }
    $1 == "guidance" { print "guidance " $2 }
    $1 == "skill" { print "skill " $2 " " $3 }
    $1 == "ee-toolkit-target-sha256" { print "ee-toolkit-target-sha256 " $2 }
  ' "$manifest" | LC_ALL=C sort | sha256_stream
}

load_pack_manifest() {
  local manifest="$1"
  local skills_output="$2"
  local dependencies_output="$3"
  local guidance_output="$4"
  local line_number=0
  local line
  local kind
  local value
  local extra

  if [[ ! -f "$manifest" || -L "$manifest" ]]; then
    echo "Missing regular pack manifest: $manifest" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    case "$line" in
      ''|'#'*)
        continue
        ;;
    esac

    IFS=' ' read -r kind value extra <<< "$line"
    if [[ -z "$kind" || -z "$value" || -n "$extra" ]]; then
      echo "Invalid pack entry at $manifest:$line_number" >&2
      return 1
    fi

    case "$kind" in
      skill)
        if ! is_safe_name "$value"; then
          echo "Invalid skill name at $manifest:$line_number: $value" >&2
          return 1
        fi
        append_unique_line "$value" "$skills_output"
        ;;
      dependency)
        case "$value" in
          git|codex|devcontainer|ralph|ee-toolkit)
            append_unique_line "$value" "$dependencies_output"
            ;;
          *)
            echo "Unsupported dependency at $manifest:$line_number: $value" >&2
            return 1
            ;;
        esac
        ;;
      guidance)
        if [[ "$value" != "git-safety" ]]; then
          echo "Unsupported guidance at $manifest:$line_number: $value" >&2
          return 1
        fi
        append_unique_line "$value" "$guidance_output"
        ;;
      *)
        echo "Unsupported pack entry at $manifest:$line_number: $kind" >&2
        return 1
        ;;
    esac
  done < "$manifest"
}

state_skill_hash() {
  local manifest="$1"
  local skill="$2"

  [[ -f "$manifest" ]] || return 1
  awk -v expected="$skill" '$1 == "skill" && $2 == expected { print $3; found = 1; exit } END { if (!found) exit 1 }' "$manifest"
}

resolve_directory() {
  local path="$1"

  (cd "$path" 2>/dev/null && pwd -P)
}

resolve_symlink_directory() {
  local link="$1"
  local target

  [[ -L "$link" ]] || return 1
  target="$(readlink "$link")"
  if [[ "$target" != /* ]]; then
    target="$(dirname "$link")/$target"
  fi
  resolve_directory "$target"
}

verify_ee_toolkit_exact() {
  local repository_root="$1"
  local toolkit_relative="vendor/equalexperts/llm-toolkit"
  local toolkit="$repository_root/$toolkit_relative"
  local expected_revision
  local actual_revision
  local expected_url
  local actual_url

  [[ -d "$toolkit" && ! -L "$toolkit" ]] || return 1
  git -C "$repository_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  expected_revision="$(git -C "$repository_root" ls-files -s -- "$toolkit_relative" | awk '$1 == "160000" { print $2; exit }')"
  [[ "$expected_revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  git -C "$toolkit" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  actual_revision="$(git -C "$toolkit" rev-parse HEAD 2>/dev/null || true)"
  [[ "$actual_revision" == "$expected_revision" ]] || return 1
  [[ -z "$(git -C "$toolkit" status --porcelain --untracked-files=all 2>/dev/null)" ]] || return 1
  expected_url="$(git -C "$repository_root" config -f .gitmodules --get submodule.vendor/equalexperts/llm-toolkit.url 2>/dev/null || true)"
  actual_url="$(git -C "$toolkit" remote get-url origin 2>/dev/null || true)"
  [[ -n "$expected_url" && "$actual_url" == "$expected_url" ]]
}
