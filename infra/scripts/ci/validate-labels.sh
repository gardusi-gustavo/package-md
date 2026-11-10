#!/usr/bin/env bash
# Validate that issue templates use only the three core labels.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) echo "usage: validate-labels.sh [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"

allowed=" bug documentation enhancement imported "
errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

dir=".gitea/issue_template"
if [[ -d "$dir" ]]; then
  [[ -s "$dir/config.yaml" || -s "$dir/config.yml" ]] || fail "missing $dir/config.yaml"
  found=0
  for f in "$dir"/*.md; do
    [[ -e "$f" ]] || continue
    found=1
    labels="$(awk '
      BEGIN { front = 0; inlabels = 0 }
      /^---[[:space:]]*$/ { front++; next }
      front == 1 {
        if (inlabels) {
          if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
            sub(/^[[:space:]]*-[[:space:]]*/, "")
            print
            next
          }
          if ($0 ~ /^[^[:space:]]/) inlabels = 0
        }
        if ($0 ~ /^labels:[[:space:]]*/) {
          v = $0
          sub(/^labels:[[:space:]]*/, "", v)
          if (v != "") print v
          else inlabels = 1
        }
      }
    ' "$f")"
    [[ -n "$labels" ]] || fail "$f: missing labels in front matter"
    while IFS= read -r label; do
      [[ -n "$label" ]] || continue
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
      case " $allowed " in
        *" $label "*) ;;
        *) fail "$f: unsupported label: $label" ;;
      esac
    done <<< "$labels"
  done
  (( found > 0 )) || fail "$dir: no issue templates found"
fi

(( errors == 0 )) || exit 1
echo "labels ok"
