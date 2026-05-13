set -euo pipefail

TEMP_PATHS=()

cleanup() {
  local path
  for path in "${TEMP_PATHS[@]:-}"; do
    [ -n "$path" ] || continue
    [ -e "$path" ] && rm -rf "$path"
  done
}

trap cleanup EXIT INT TERM

usage() {
  cat <<'USAGE'
Usage:
  skill <github-url>
  skill list

Imports always go to:
  skills/<skill-name>

Supported GitHub URLs:
  https://github.com/OWNER/REPO/tree/REF/path/to/skill
  https://github.com/OWNER/REPO/tree/REF/path/to/skills
USAGE
}

die() {
  printf 'skill: %s\n' "$*" >&2
  exit 1
}

track_temp_path() {
  TEMP_PATHS+=("$1")
}

untrack_temp_path() {
  local keep new_paths path
  keep="$1"
  new_paths=()

  for path in "${TEMP_PATHS[@]:-}"; do
    [ "$path" = "$keep" ] || new_paths+=("$path")
  done

  TEMP_PATHS=("${new_paths[@]:-}")
}

make_temp_dir() {
  local dir
  dir="$(mktemp -d "$1")"
  track_temp_path "$dir"
  printf '%s\n' "$dir"
}

find_root() {
  local dir
  dir="$PWD"

  while [ "$dir" != / ]; do
    if [ -f "$dir/flake.nix" ] && [ -d "$dir/skills" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  die "could not find repo root with flake.nix and skills/"
}

list_skills() {
  local root entry name found_skill
  root="$(find_root)"

  found_skill=0
  for entry in "$root"/skills/*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in
      .*) continue ;;
    esac

    if [ -d "$entry" ] && [ -f "$entry/SKILL.md" ]; then
      name="$(basename "$entry")"
    else
      continue
    fi

    found_skill=1
    printf '%s\n' "$name"
  done

  if [ "$found_skill" -eq 0 ]; then
    printf '%s\n' 'No skills yet. Import one with: skill <github-url>'
  fi
}

parse_github_url() {
  local url rest owner repo kind ref path
  url="$1"

  case "$url" in
    https://github.com/*) ;;
    *) die "expected a https://github.com URL" ;;
  esac

  rest="${url#https://github.com/}"
  owner="${rest%%/*}"
  rest="${rest#*/}"
  repo="${rest%%/*}"
  rest="${rest#*/}"
  kind="${rest%%/*}"
  rest="${rest#*/}"
  ref="${rest%%/*}"
  path="${rest#*/}"

  [ -n "$owner" ] || die "missing GitHub owner"
  [ -n "$repo" ] || die "missing GitHub repo"
  [ "$kind" = tree ] || die "URL must contain /tree/"
  [ -n "$ref" ] || die "missing GitHub ref"
  [ -n "$path" ] || die "missing GitHub path"

  OWNER="$owner"
  REPO="$repo"
  KIND="$kind"
  REF="$ref"
  SOURCE_PATH="$path"
}

write_source_file() {
  local dest sha url source_path
  dest="$1"
  sha="$2"
  url="$3"
  source_path="$4"

  cat > "$dest/.source" <<EOF
url=$url
repo=$OWNER/$REPO
kind=$KIND
path=$source_path
ref=$sha
originalRef=$REF
EOF
}

clone_sparse_source() {
  local sha repo_dir
  sha="$1"
  repo_dir="$2"

  git clone --quiet --no-checkout --filter=blob:none --sparse "https://github.com/$OWNER/$REPO.git" "$repo_dir"
  git -C "$repo_dir" sparse-checkout init --cone >/dev/null
  git -C "$repo_dir" sparse-checkout set "$SOURCE_PATH" >/dev/null
  git -C "$repo_dir" fetch --quiet --depth 1 origin "$sha"
  git -C "$repo_dir" checkout --quiet FETCH_HEAD
}

list_skill_names() {
  local source_dir skill_dir skill_name
  source_dir="$1"

  for skill_dir in "$source_dir"/*; do
    [ -d "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    printf '%s\n' "$skill_name"
  done
}

ensure_destinations_free() {
  local root skill_name
  root="$1"
  shift

  for skill_name in "$@"; do
    [ ! -e "$root/skills/$skill_name" ] || die "$skill_name already exists; rename or remove it manually first"
  done
}

import_single_skill() {
  local root skill_name source_dir source_path url sha dest temp_dest
  root="$1"
  skill_name="$2"
  source_dir="$3"
  source_path="$4"
  url="$5"
  sha="$6"

  dest="$root/skills/$skill_name"
  temp_dest="$(make_temp_dir "$root/skills/.${skill_name}.tmp.XXXXXX")"

  cp -R "$source_dir/." "$temp_dest/"
  [ -f "$temp_dest/SKILL.md" ] || die "$skill_name did not import a top-level SKILL.md"
  write_source_file "$temp_dest" "$sha" "$url" "$source_path"
  mv "$temp_dest" "$dest"
  untrack_temp_path "$temp_dest"
  printf 'Imported %s\n' "$skill_name"
}

import_tree() {
  local url sha root repo_dir source_dir skill_name skill_count total index
  local -a skill_names=()
  url="$1"
  sha="$2"
  root="$3"

  repo_dir="$(make_temp_dir "/tmp/opencode/skill-import.XXXXXX")"

  printf 'Fetching source tree...\n'
  clone_sparse_source "$sha" "$repo_dir"
  source_dir="$repo_dir/$SOURCE_PATH"
  [ -d "$source_dir" ] || die "source path $SOURCE_PATH was not found"

  if [ -f "$source_dir/SKILL.md" ]; then
    skill_name="$(basename "$SOURCE_PATH")"
    ensure_destinations_free "$root" "$skill_name"
    printf 'Importing 1/1: %s\n' "$skill_name"
    import_single_skill "$root" "$skill_name" "$source_dir" "$SOURCE_PATH" "$url" "$sha"
    return
  fi

  while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    skill_names+=("$skill_name")
  done < <(list_skill_names "$source_dir" | sort -u)

  total="${#skill_names[@]}"
  [ "$total" -gt 0 ] || die "no skill directories found under $SOURCE_PATH"
  ensure_destinations_free "$root" "${skill_names[@]}"

  skill_count=0
  for skill_name in "${skill_names[@]}"; do
    index=$((skill_count + 1))
    printf 'Importing %s/%s: %s\n' "$index" "$total" "$skill_name"
    import_single_skill "$root" "$skill_name" "$source_dir/$skill_name" "$SOURCE_PATH/$skill_name" "$url" "$sha"
    skill_count=$((skill_count + 1))
  done

  printf 'Imported %s skill(s).\n' "$skill_count"
}

import_url() {
  local root url sha
  url="$1"
  root="$(find_root)"
  parse_github_url "$url"

  sha="$(gh api "repos/$OWNER/$REPO/commits/$REF" --jq .sha)"

  import_tree "$url" "$sha" "$root"
}

main() {
  if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
  fi

  case "$1" in
    -h|--help|help)
      usage
      ;;
    list)
      list_skills
      ;;
    https://github.com/*)
      import_url "$1"
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
