#!/usr/bin/env bash
# Check repository-tree links in Markdown.
#
# --changed  check only Markdown changed against --base
# --all      check every tracked Markdown file
# --check    exit non-zero on findings
# --report   print findings and exit zero
set -euo pipefail

ROOT="."
BASE="origin/main"
MODE=""
RESULT="check"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed) MODE="changed"; shift ;;
    --all) MODE="all"; shift ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --check) RESULT="check"; shift ;;
    --report) RESULT="report"; shift ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: validate-md-links.sh --changed|--all [--base REF] [--check|--report] [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || { echo "error: choose --changed or --all" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "error: root not found: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

if [[ "$MODE" == "changed" ]]; then
  base="$BASE"
  if ! git -C "$ROOT" rev-parse --verify "$base" >/dev/null 2>&1; then
    if [[ -f "$ROOT/.git/shallow" ]]; then
      git -C "$ROOT" fetch --no-tags --unshallow origin "${base#origin/}" >/dev/null 2>&1 || true
    else
      git -C "$ROOT" fetch --no-tags origin "${base#origin/}" >/dev/null 2>&1 || true
    fi
  fi
  if ! git -C "$ROOT" rev-parse --verify "$base" >/dev/null 2>&1; then
    base="HEAD~1"
  fi
  git -C "$ROOT" rev-parse --verify "$base" >/dev/null 2>&1 || {
    echo "error: cannot resolve base: $BASE" >&2; exit 2;
  }
  mapfile -t files < <(git -C "$ROOT" diff --name-only --diff-filter=ACMR "$base"...HEAD -- '*.md')
else
  mapfile -t files < <(git -C "$ROOT" ls-files '*.md')
fi

errors=0
report() {
  echo "$1"
  errors=$((errors + 1))
}

for path in "${files[@]}"; do
  [[ -n "$path" ]] || continue
  file="$ROOT/$path"
  [[ -f "$file" ]] || continue
  base_dir="$(cd "$(dirname "$file")" && pwd -P)"

  while IFS=$'\t' read -r line target; do
    [[ -n "$line" && -n "$target" ]] || continue
    target="${target#"${target%%[![:space:]]*}"}"
    target="${target%"${target##*[![:space:]]}"}"
    case "$target" in
      ""|"#"*|http:*|https:*|mailto:*|tel:*) continue ;;
    esac
    target="${target%%#*}"
    [[ -n "$target" ]] || continue

    if [[ "${path##*/}" != "README.md" ]]; then
      report "$path:$line:$target: relative link in non-README"
      continue
    fi

    if [[ "$target" == /* ]]; then
      report "$path:$line:$target: absolute path"
      continue
    fi
    if [[ "/$target/" == *"/../"* ]]; then
      report "$path:$line:$target: parent or sibling link"
      continue
    fi

    resolved="$(realpath -m "$base_dir/$target")"
    case "$resolved" in
      "$base_dir"/*) ;;
      *) report "$path:$line:$target: escapes the README subtree"; continue ;;
    esac
    [[ -e "$resolved" ]] || report "$path:$line:$target: missing target"
  done < <(awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      gsub(/!\[[^]]*\]\([^)]*\)/, "", line)
      while (match(line, /\[[^]]*\]\([^)]*\)/)) {
        m = substr(line, RSTART, RLENGTH)
        sub(/^.*\]\(/, "", m)
        sub(/\).*$/, "", m)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", m)
        print NR "\t" m
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$file")
done

if (( errors > 0 )); then
  echo "link check: $errors finding(s)" >&2
  [[ "$RESULT" == "check" ]] && exit 1
fi
echo "link check: ok"
