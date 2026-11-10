#!/usr/bin/env bash
set -euo pipefail
ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) echo "usage: check-size.sh [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"
cfg=infra/config/repo.json
repo_mb=$(jq -r '.limits.repo_mb // 100' "$cfg")
file_mb=$(jq -r '.limits.file_mb // 25' "$cfg")
total=$(git ls-files -z | xargs -0 -r stat -c '%s' | awk '{s+=$1} END {print s+0}')
printf 'tracked size: %s bytes; limit: %s MB\n' "$total" "$repo_mb"
(( total <= repo_mb * 1000000 ))
largest=$(git ls-files -z | xargs -0 -r stat -c '%s %n' | awk 'BEGIN {m=0} $1>m {m=$1; f=$0} END {if (m>0) print f}')
if [[ -n "$largest" ]]; then
  size=${largest%% *}; file=${largest#* }
  printf 'largest file: %s bytes; limit: %s MB: %s\n' "$size" "$file_mb" "$file"
  (( size <= file_mb * 1000000 ))
fi
