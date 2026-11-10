#!/usr/bin/env bash
# Validate append-only task files in docs/issues.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "error: --root needs a value" >&2; exit 2; }
      ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "usage: validate-local-issues.sh [--root PATH]"
      exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "error: root not found: $ROOT" >&2; exit 2; }
DIR="$ROOT/docs/issues"
if [[ ! -d "$DIR" ]]; then
  echo "local tasks: none"
  exit 0
fi

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
count=0
declare -A seen=()

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  base="$(basename "$file")"
  case "$base" in
    README.md|schema.json|template.json) continue ;;
  esac
  count=$((count + 1))

  if [[ ! "$base" =~ ^([123])\.([0-9]{1,6})-([a-z0-9]+(-[a-z0-9]+)*)\.json$ ]]; then
    fail "$base: filename must match <1|2|3>.<1-6 digits>-<slug>.json"
    continue
  fi
  prefix="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  frac="${BASH_REMATCH[2]}"
  [[ "$frac" != *0 ]] || fail "$base: rank must not end in zero"

  jq empty "$file" >/dev/null 2>&1 || { fail "$base: invalid JSON"; continue; }

  rank="$(jq -r '.rank // empty' "$file")"
  [[ "$rank" == "$prefix" ]] || fail "$base: rank must be $prefix"
  [[ -n "${seen[$rank]:-}" ]] && fail "$base: duplicate rank $rank"
  seen[$rank]=1

  extra="$(jq -r '[keys[] | select(. != "rank" and . != "title" and . != "context" and . != "limits" and . != "spec" and . != "attempts")] | join(", ")' "$file")"
  [[ -z "$extra" ]] || fail "$base: unknown top-level fields: $extra"

  jq -e '.title | type == "string" and length > 0' "$file" >/dev/null || fail "$base: title is required"
  jq -e '.context | type == "string" and length > 0' "$file" >/dev/null || fail "$base: context is required"
  jq -e '.limits | type == "object" and ((keys | sort) == ["max_commits","max_file_changes"])' "$file" >/dev/null || fail "$base: limits must contain only max_commits and max_file_changes"
  jq -e '.limits.max_commits | type == "number" and . >= 1 and floor == .' "$file" >/dev/null || fail "$base: limits.max_commits must be a positive integer"
  jq -e '.limits.max_file_changes | type == "number" and . >= 1 and floor == .' "$file" >/dev/null || fail "$base: limits.max_file_changes must be a positive integer"
  jq -e '.spec | type == "object" and ((keys | sort) == ["acceptance_criteria","expected_outcome","summary"])' "$file" >/dev/null || fail "$base: spec must contain only summary, expected_outcome, and acceptance_criteria"
  jq -e '.spec.summary | type == "string" and length > 0' "$file" >/dev/null || fail "$base: spec.summary is required"
  jq -e '.spec.expected_outcome | type == "string" and length > 0' "$file" >/dev/null || fail "$base: spec.expected_outcome is required"
  jq -e '.spec.acceptance_criteria | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' "$file" >/dev/null || fail "$base: spec.acceptance_criteria must be a non-empty array of strings"
  jq -e 'if has("attempts") then (.attempts | type == "array" and all(.[]; type == "object" and ((keys - ["summary","next_step"]) | length == 0) and (.summary | type == "string" and length > 0))) else true end' "$file" >/dev/null || fail "$base: attempts must be an array of {summary, next_step?}"

  lines="$(wc -l < "$file")"
  (( lines <= 300 )) || fail "$base: file exceeds 300 lines"
done < <(find "$DIR" -maxdepth 1 -type f -name '*.json' | sort)

(( errors == 0 )) || exit 1
echo "local tasks: ok ($count files)"
