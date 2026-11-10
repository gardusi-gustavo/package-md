#!/usr/bin/env bash
# Review-load budget check. Classifies changed files into reviewable, generated,
# binary, and data content, then applies the limits from policy.json and the
# repository's repo.json.
set -euo pipefail

REPO=""
BASE="origin/main"
HEAD="HEAD"
ROOT="."
REPO_CONFIG=""
POLICY=""
FIXTURE=""

usage() {
  cat <<'USAGE'
usage: pr-size-check.sh --repo OWNER/REPO [options]

Options:
  --base REF             base ref (default: origin/main)
  --head REF             head SHA or ref (default: HEAD)
  --root PATH            repository root (default: .)
  --repo-config FILE     repo.json with pull_request_limits
  --policy FILE          policy.json with pull_requests.size
  --fixture FILE         JSON fixture; no git required
  -h, --help             show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --head) HEAD="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --repo-config) REPO_CONFIG="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || { echo "error: --repo must be OWNER/REPO" >&2; exit 2; }

defaults='{
  "max_reviewable_lines": 500,
  "max_reviewable_lines_per_file": 250,
  "max_files_changed": 50,
  "max_commits": 10,
  "max_generated_files": 10,
  "max_generated_bytes": 10485760,
  "max_generated_file_bytes": 5242880,
  "max_binary_files": 20,
  "max_binary_file_bytes": 10485760,
  "max_binary_bytes": 52428800,
  "max_combined_bytes": 57671680,
  "max_added_bytes": 62914560,
  "max_data_files": 10,
  "max_data_bytes": 5242880,
  "generated_patterns": [
    "package-lock.json",
    "npm-shrinkwrap.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "bun.lockb",
    "Cargo.lock",
    "poetry.lock",
    "Pipfile.lock",
    "uv.lock",
    "go.sum",
    "composer.lock",
    "Gemfile.lock",
    "mix.lock",
    "pubspec.lock",
    "*.min.js",
    "*.min.css",
    "*.map",
    "*.snap",
    "**/__snapshots__/**",
    "**/dist/**",
    "**/build/**",
    "**/vendor/**",
    "**/generated/**",
    "*.generated.*",
    "dist/**",
    "build/**",
    "vendor/**",
    "generated/**",
    "__snapshots__/**"
  ],
  "data_patterns": []
}'

policy_size='{}'
if [[ -n "$POLICY" && -s "$POLICY" ]]; then
  policy_size="$(jq -c '.pull_requests.size // {}' "$POLICY")"
fi
repo_limits='{}'
if [[ -n "$REPO_CONFIG" && -s "$REPO_CONFIG" ]]; then
  repo_limits="$(jq -c '.pull_request_limits // {}' "$REPO_CONFIG")"
fi
limits="$(jq -cn --argjson d "$defaults" --argjson p "$policy_size" --argjson r "$repo_limits" \
  '$d * $p * $r')"

get() { jq -r ".$1" <<<"$limits"; }
max_reviewable="$(get max_reviewable_lines)"
max_per_file="$(get max_reviewable_lines_per_file)"
max_files="$(get max_files_changed)"
max_commits="$(get max_commits)"
max_generated_files="$(get max_generated_files)"
max_generated_bytes="$(get max_generated_bytes)"
max_generated_file_bytes="$(get max_generated_file_bytes)"
max_binary_files="$(get max_binary_files)"
max_binary_file_bytes="$(get max_binary_file_bytes)"
max_binary_bytes="$(get max_binary_bytes)"
max_combined="$(get max_combined_bytes)"
max_added="$(get max_added_bytes)"
max_data_files="$(get max_data_files)"
max_data_bytes="$(get max_data_bytes)"
mapfile -t generated_patterns < <(jq -r '.generated_patterns[]?' <<<"$limits")
mapfile -t data_patterns < <(jq -r '.data_patterns[]?' <<<"$limits")

matches() {
  local path="$1" pat
  shift
  for pat in "$@"; do
    if [[ "$pat" == */* ]]; then
      # shellcheck disable=SC2053
      [[ "$path" == $pat ]] && return 0
    else
      # shellcheck disable=SC2053
      [[ "${path##*/}" == $pat ]] && return 0
    fi
  done
  return 1
}

files=0 reviewable_lines=0 max_reviewable_file=0
generated_files=0 generated_bytes=0 generated_file_max=0
binary_files=0 binary_bytes=0 binary_file_max=0
data_files=0 data_bytes=0
added_bytes=0 commits=0
reasons=()

classify() {
  local path="$1" lines="$2" size="$3" binary="$4"
  files=$((files + 1))
  added_bytes=$((added_bytes + size))
  if (( binary )); then
    binary_files=$((binary_files + 1))
    binary_bytes=$((binary_bytes + size))
    (( size > binary_file_max )) && binary_file_max=$size
    return 0
  fi
  if matches "$path" ${generated_patterns[@]+"${generated_patterns[@]}"}; then
    generated_files=$((generated_files + 1))
    generated_bytes=$((generated_bytes + size))
    (( size > generated_file_max )) && generated_file_max=$size
    return 0
  fi
  if matches "$path" ${data_patterns[@]+"${data_patterns[@]}"}; then
    data_files=$((data_files + 1))
    data_bytes=$((data_bytes + size))
    return 0
  fi
  reviewable_lines=$((reviewable_lines + lines))
  (( lines > max_reviewable_file )) && max_reviewable_file=$lines
  return 0
}

if [[ -n "$FIXTURE" ]]; then
  [[ -r "$FIXTURE" ]] || { echo "error: cannot read fixture: $FIXTURE" >&2; exit 2; }
  commits="$(jq -r '.commits // 0' "$FIXTURE")"
  while IFS=$'\t' read -r path added deleted size; do
    [[ -n "$path" ]] || continue
    if [[ "$added" == "-" ]]; then
      classify "$path" 0 "$size" 1
    else
      classify "$path" $((added + deleted)) "$size" 0
    fi
  done < <(jq -r '.files[]? | [.path, (.added|tostring), (.deleted|tostring), (.size|tostring)] | @tsv' "$FIXTURE")
else
  cd "$ROOT"
  base_ref="$BASE"
  if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    base_ref="main"
  fi
  git rev-parse --verify "$base_ref" >/dev/null 2>&1 || {
    echo "error: cannot resolve base ref: $BASE" >&2; exit 2;
  }
  merge_base="$(git merge-base "$base_ref" "$HEAD")"
  commits="$(git rev-list --count "$merge_base..$HEAD")"
  while IFS=$'\t' read -r added deleted path; do
    [[ -n "$path" ]] || continue
    size="$(git cat-file -s "$HEAD:$path" 2>/dev/null || echo 0)"
    if [[ "$added" == "-" ]]; then
      classify "$path" 0 "$size" 1
    else
      classify "$path" $((added + deleted)) "$size" 0
    fi
  done < <(git diff --numstat "$merge_base" "$HEAD")
fi

combined=$((generated_bytes + binary_bytes))

check() {
  local label="$1" value="$2" limit="$3"
  (( value > limit )) && reasons+=("$label: $value > $limit")
  return 0
}
check "files" "$files" "$max_files"
check "reviewable lines" "$reviewable_lines" "$max_reviewable"
check "largest reviewable file" "$max_reviewable_file" "$max_per_file"
check "generated files" "$generated_files" "$max_generated_files"
check "generated bytes" "$generated_bytes" "$max_generated_bytes"
check "largest generated file" "$generated_file_max" "$max_generated_file_bytes"
check "binary files" "$binary_files" "$max_binary_files"
check "binary bytes" "$binary_bytes" "$max_binary_bytes"
check "largest binary file" "$binary_file_max" "$max_binary_file_bytes"
check "generated + binary bytes" "$combined" "$max_combined"
check "added bytes" "$added_bytes" "$max_added"
check "data files" "$data_files" "$max_data_files"
check "data bytes" "$data_bytes" "$max_data_bytes"
check "commits" "$commits" "$max_commits"

human() {
  if command -v numfmt >/dev/null 2>&1; then numfmt --to=iec --suffix=B "$1"; else printf '%sB' "$1"; fi
}
printf 'files: %s / %s\n' "$files" "$max_files"
printf 'reviewable lines: %s / %s\n' "$reviewable_lines" "$max_reviewable"
printf 'largest reviewable file: %s / %s\n' "$max_reviewable_file" "$max_per_file"
printf 'generated: %s files, %s / %s; largest %s / %s\n' \
  "$generated_files" "$(human "$generated_bytes")" "$(human "$max_generated_bytes")" \
  "$(human "$generated_file_max")" "$(human "$max_generated_file_bytes")"
printf 'binary: %s files, %s / %s; largest %s / %s\n' \
  "$binary_files" "$(human "$binary_bytes")" "$(human "$max_binary_bytes")" \
  "$(human "$binary_file_max")" "$(human "$max_binary_file_bytes")"
printf 'data: %s files, %s / %s\n' "$data_files" "$(human "$data_bytes")" "$(human "$max_data_bytes")"
printf 'generated + binary: %s / %s\n' "$(human "$combined")" "$(human "$max_combined")"
printf 'added bytes: %s / %s\n' "$(human "$added_bytes")" "$(human "$max_added")"
printf 'commits: %s / %s\n' "$commits" "$max_commits"

if (( ${#reasons[@]} > 0 )); then
  echo "pr size: FAILED" >&2
  printf '  %s\n' "${reasons[@]}" >&2
  echo "  split the change into follow-up issues; do not append to this PR" >&2
  exit 1
fi
echo "pr size: ok"
