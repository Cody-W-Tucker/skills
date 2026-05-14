set -euo pipefail

TEMP_PATHS=()
ACTIVE_IMPORT_ROOT=
ACTIVE_IMPORT_REPO_DIR=

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
  https://github.com/OWNER/REPO
  https://github.com/OWNER/REPO/tree/REF/path/to/skill
  https://github.com/OWNER/REPO/tree/REF/path/to/skills
USAGE
}

die() {
  if [ -n "${ACTIVE_IMPORT_ROOT:-}" ] && [ -n "${ACTIVE_IMPORT_REPO_DIR:-}" ] && [ -d "${ACTIVE_IMPORT_REPO_DIR:-}" ]; then
    preserve_failed_import "$ACTIVE_IMPORT_ROOT" "$ACTIVE_IMPORT_REPO_DIR"
    ACTIVE_IMPORT_ROOT=
    ACTIVE_IMPORT_REPO_DIR=
  fi
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
  local url trimmed rest owner repo kind ref path
  url="$1"

  case "$url" in
    https://github.com/*) ;;
    *) die "expected a https://github.com URL" ;;
  esac

  trimmed="${url#https://github.com/}"
  trimmed="${trimmed%%\?*}"
  trimmed="${trimmed%%#*}"
  trimmed="${trimmed%/}"

  rest="$trimmed"
  owner="${rest%%/*}"
  rest="${rest#*/}"
  repo="${rest%%/*}"

  [ -n "$owner" ] || die "missing GitHub owner"
  [ -n "$repo" ] || die "missing GitHub repo"

  if [ "$trimmed" = "$owner/$repo" ]; then
    KIND=repo
    REF=
    SOURCE_PATH=.
  else
    rest="${rest#*/}"
    kind="${rest%%/*}"
    rest="${rest#*/}"
    ref="${rest%%/*}"

    [ "$kind" = tree ] || die "URL must be a repo URL or contain /tree/"
    [ -n "$ref" ] || die "missing GitHub ref"

    if [ "$rest" = "$ref" ]; then
      path=.
    else
      path="${rest#*/}"
      [ -n "$path" ] || die "missing GitHub path"
    fi

    KIND="$kind"
    REF="$ref"
    SOURCE_PATH="$path"
  fi

  OWNER="$owner"
  REPO="$repo"
}

resolve_ref() {
  if [ "$KIND" = repo ]; then
    REF="$(gh api "repos/$OWNER/$REPO" --jq .default_branch)"
  fi
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

clone_repo_root() {
  local repo_dir
  repo_dir="$1"

  git clone --quiet --depth 1 --branch "$REF" --filter=blob:none "https://github.com/$OWNER/$REPO.git" "$repo_dir"
}

clone_source() {
  local sha repo_dir
  sha="$1"
  repo_dir="$2"

  if [ "$SOURCE_PATH" = . ]; then
    clone_repo_root "$repo_dir"
  else
    clone_sparse_source "$sha" "$repo_dir"
  fi
}

list_skill_paths() {
  local source_dir skill_file skill_path
  source_dir="$1"

  shopt -s dotglob globstar nullglob

  for skill_file in "$source_dir"/**/SKILL.md; do
    [ -f "$skill_file" ] || continue
    skill_path="${skill_file#"$source_dir"/}"
    skill_path="${skill_path%/SKILL.md}"
    printf '%s\n' "$skill_path"
  done

  shopt -u dotglob globstar nullglob
}

skill_destination_exists() {
  local root skill_name
  root="$1"
  skill_name="$2"
  [ -e "$root/skills/$skill_name" ]
}

ensure_unique_skill_names() {
  local skill_name
  declare -A seen=()

  for skill_name in "$@"; do
    [ -n "$skill_name" ] || continue
    [ -z "${seen[$skill_name]:-}" ] || die "duplicate skill name $skill_name within source tree"
    seen[$skill_name]=1
  done
}

flatten_skill_path_name() {
  local skill_path
  skill_path="$1"
  printf '%s\n' "${skill_path//\//--}"
}

normalize_skill_path_key() {
  local skill_path
  skill_path="$1"

  case "$skill_path" in
    .*/skills/*)
      printf '%s\n' "${skill_path#*/}"
      ;;
    *)
      printf '%s\n' "$skill_path"
      ;;
  esac
}

single_skill_name() {
  if [ "$SOURCE_PATH" = . ]; then
    printf '%s\n' "$REPO"
  else
    basename "$SOURCE_PATH"
  fi
}

next_failed_import_dir() {
  local root failures_dir index candidate
  root="$1"
  failures_dir="$root/.skill-import-failures"

  mkdir -p "$failures_dir"
  index=1

  while :; do
    candidate=$(printf '%s/%04d-%s-%s\n' "$failures_dir" "$index" "$OWNER" "$REPO")
    [ ! -e "$candidate" ] && break
    index=$((index + 1))
  done

  printf '%s\n' "$candidate"
}

preserve_failed_import() {
  local root repo_dir failure_dir
  root="$1"
  repo_dir="$2"

  [ -d "$repo_dir" ] || return 0

  failure_dir="$(next_failed_import_dir "$root")"
  mv "$repo_dir" "$failure_dir"
  untrack_temp_path "$repo_dir"
  printf 'Preserved failed import at %s\n' "$failure_dir" >&2
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

import_tree_inner() {
  local url sha root repo_dir source_dir skill_name skill_path skill_count total index imported_path normalized_key i skipped_count
  local -a skill_names=() skill_paths=()
  declare -A skill_name_counts=() normalized_paths_seen=()
  url="$1"
  sha="$2"
  root="$3"
  repo_dir="$4"

  printf 'Fetching source tree...\n'
  clone_source "$sha" "$repo_dir"

  if [ "$SOURCE_PATH" = . ]; then
    source_dir="$repo_dir"
  else
    source_dir="$repo_dir/$SOURCE_PATH"
  fi

  [ -d "$source_dir" ] || die "source path $SOURCE_PATH was not found"

  if [ -f "$source_dir/SKILL.md" ]; then
    skill_name="$(single_skill_name)"
    if skill_destination_exists "$root" "$skill_name"; then
      printf 'Skipping duplicate 1/1: %s\n' "$skill_name"
      printf 'Imported 0 skill(s); skipped 1 duplicate(s).\n'
      return
    fi
    printf 'Importing 1/1: %s\n' "$skill_name"
    import_single_skill "$root" "$skill_name" "$source_dir" "$SOURCE_PATH" "$url" "$sha"
    return
  fi

  while IFS= read -r skill_path; do
    [ -n "$skill_path" ] || continue
    normalized_key="$(normalize_skill_path_key "$skill_path")"
    [ -z "${normalized_paths_seen[$normalized_key]:-}" ] || continue
    normalized_paths_seen[$normalized_key]=1
    skill_paths+=("$skill_path")
    skill_name="$(basename "$skill_path")"
    skill_names+=("$skill_name")
    skill_name_counts[$skill_name]=$(( ${skill_name_counts[$skill_name]:-0} + 1 ))
  done < <(list_skill_paths "$source_dir" | sort -u)

  total="${#skill_paths[@]}"
  [ "$total" -gt 0 ] || die "no skill directories found under $SOURCE_PATH"

  for i in "${!skill_paths[@]}"; do
    skill_name="${skill_names[i]}"
    if [ "${skill_name_counts[$skill_name]}" -gt 1 ]; then
      skill_names[i]="$(flatten_skill_path_name "${skill_paths[i]}")"
    fi
  done

  ensure_unique_skill_names "${skill_names[@]}"

  skill_count=0
  skipped_count=0
  for i in "${!skill_paths[@]}"; do
    skill_path="${skill_paths[i]}"
    skill_name="${skill_names[i]}"
    if [ "$SOURCE_PATH" = . ]; then
      imported_path="$skill_path"
    else
      imported_path="$SOURCE_PATH/$skill_path"
    fi
    index=$((skill_count + skipped_count + 1))
    if skill_destination_exists "$root" "$skill_name"; then
      printf 'Skipping duplicate %s/%s: %s\n' "$index" "$total" "$skill_name"
      skipped_count=$((skipped_count + 1))
      continue
    fi
    printf 'Importing %s/%s: %s\n' "$index" "$total" "$skill_name"
    import_single_skill "$root" "$skill_name" "$source_dir/$skill_path" "$imported_path" "$url" "$sha"
    skill_count=$((skill_count + 1))
  done

  printf 'Imported %s skill(s); skipped %s duplicate(s).\n' "$skill_count" "$skipped_count"
}

import_tree() {
  local url sha root repo_dir status
  url="$1"
  sha="$2"
  root="$3"

  repo_dir="$(make_temp_dir "/tmp/opencode/skill-import.XXXXXX")"
  ACTIVE_IMPORT_ROOT="$root"
  ACTIVE_IMPORT_REPO_DIR="$repo_dir"

  if import_tree_inner "$url" "$sha" "$root" "$repo_dir"; then
    ACTIVE_IMPORT_ROOT=
    ACTIVE_IMPORT_REPO_DIR=
    return
  else
    status=$?
    preserve_failed_import "$root" "$repo_dir"
    ACTIVE_IMPORT_ROOT=
    ACTIVE_IMPORT_REPO_DIR=
    return "$status"
  fi
}

import_url() {
  local root url sha
  url="$1"
  root="$(find_root)"
  parse_github_url "$url"
  resolve_ref

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
