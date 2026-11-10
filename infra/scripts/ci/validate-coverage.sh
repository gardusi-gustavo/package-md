#!/usr/bin/env bash
# Read-only validation for repository coverage maps.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) echo "usage: validate-coverage.sh [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors+1)); }

check_map() {
  local file="$1" quiet="${2:-0}" err=0
  errf() {
    if [[ "$quiet" != "1" ]]; then
      echo "ERROR: $file: $*" >&2
    fi
    err=$((err + 1))
  }

  [[ -s "$file" ]] || { errf "missing or empty"; return 1; }
  jq empty "$file" >/dev/null 2>&1 || { errf "invalid JSON"; return 1; }

  [[ "$(jq -r '.schema // empty' "$file")" == "1" ]] || errf "schema must be 1"
  jq -e '.domain | type == "string" and length > 0' "$file" >/dev/null ||
    errf "domain must be a non-empty string"
  jq -e '(.updated // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")' "$file" >/dev/null ||
    errf "updated must be YYYY-MM-DD"
  if ! jq -e '.rows | type == "array"' "$file" >/dev/null; then
    errf "rows must be an array"
    return 1
  fi
  jq -e '.rows | length > 0' "$file" >/dev/null ||
    errf "rows must be a non-empty array"

  local extra
  extra="$(jq -r 'keys - ["schema", "domain", "updated", "rows"] | join(",")' "$file")"
  [[ -z "$extra" ]] || errf "unknown top-level keys: $extra"

  jq -e 'all(.rows[]; (.topic | type == "string" and length > 0) and (.status | IN("covered", "partial", "missing", "stale")))' "$file" >/dev/null ||
    errf "each row needs a topic and a valid status"

  extra="$(jq -r '[.rows[] | keys - ["topic", "status", "ref", "owner", "notes"]] | flatten | unique | join(",")' "$file")"
  [[ -z "$extra" ]] || errf "unknown row keys: $extra"

  local dup
  dup="$(jq -r '[.rows[].topic] | group_by(.) | map(select(length > 1) | .[0]) | join(",")' "$file")"
  [[ -z "$dup" ]] || errf "duplicate topics: $dup"

  local refs topic ref
  refs="$(jq -r '.rows[] | select(.status == "covered" or .status == "partial") | "\(.topic)\t\(.ref // "")"' "$file")"
  if [[ -n "$refs" ]]; then
    while IFS=$'\t' read -r topic ref; do
      [[ -n "$ref" ]] || { errf "$topic: status requires a ref"; continue; }
      case "$ref" in
        /*|*..*) errf "$topic: ref must be a relative path without ..: $ref"; continue ;;
      esac
      [[ -f "$ROOT/$ref" ]] || errf "$topic: ref not found: $ref"
    done <<< "$refs"
  fi

  (( err == 0 ))
}

if [[ -f src/data/coverage.json ]]; then
  check_map src/data/coverage.json || errors=$((errors + 1))
fi

for f in src/tests/coverage/valid-*.json; do
  [[ -f "$f" ]] || continue
  check_map "$f" || errors=$((errors + 1))
done

for f in src/tests/coverage/invalid-*.json; do
  [[ -f "$f" ]] || continue
  if check_map "$f" 1; then
    fail "invalid fixture passed: $f"
  fi
done

(( errors == 0 )) || exit 1
echo "coverage ok"
