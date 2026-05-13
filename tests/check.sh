#!/usr/bin/env bash
set -euo pipefail

root="${SKILLS_ROOT:-$(pwd)}"
skills_dir="$root/skills"
errors=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  errors=$((errors + 1))
}

has_frontmatter() {
  local file first
  file="$1"
  IFS= read -r first < "$file" || return 1
  [ "$first" = '---' ]
}

check_skill_file() {
  local file
  file="$1"

  if ! has_frontmatter "$file"; then
    fail "$file must start with YAML frontmatter delimiter ---"
  fi
}

if [ ! -d "$skills_dir" ]; then
  fail "$skills_dir does not exist"
else
  shopt -s nullglob
  declare -A global_seen=()

  skill_count=0

  for entry in "$skills_dir"/*; do
    [ -e "$entry" ] || continue

    if [ ! -d "$entry" ]; then
      case "$(basename "$entry")" in
        .*) continue ;;
      esac
      fail "$entry must be a skill directory containing SKILL.md"
      continue
    fi

    skill_name="$(basename "$entry")"

    if [ ! -f "$entry/SKILL.md" ]; then
      fail "$entry must contain SKILL.md"
      continue
    fi

    check_skill_file "$entry/SKILL.md"

    if [ -n "${global_seen[$skill_name]:-}" ]; then
      fail "duplicate skill name $skill_name; flat exports require globally unique names"
    fi

    global_seen[$skill_name]=1
    skill_count=$((skill_count + 1))
  done

  unset global_seen
fi

if [ "$errors" -gt 0 ]; then
  printf '%s structural error(s) found\n' "$errors" >&2
  exit 1
fi

printf 'skills structure ok\n'
