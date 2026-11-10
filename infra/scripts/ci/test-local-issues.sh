#!/usr/bin/env bash
# Exercise the append-only task validator.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="$ROOT/infra/scripts/ci/validate-local-issues.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_task() {
  local dir="$1" file="$2" rank="$3"
  mkdir -p "$dir/docs/issues"
  jq -n --arg rank "$rank" \
    '{rank:$rank,title:"Example task",context:"Example context",limits:{max_commits:5,max_file_changes:4},spec:{summary:"Example summary",expected_outcome:"Example outcome",acceptance_criteria:["Done"]},attempts:[]}' \
    > "$dir/docs/issues/$file"
}

ok="$tmp/ok"; make_task "$ok" 3.9-fix-auth.json 3.9; make_task "$ok" 1.4-add-docs.json 1.4
"$HELPER" --root "$ok" >/dev/null

bad_name="$tmp/bad-name"; make_task "$bad_name" 3.9_fix.json 3.9
if "$HELPER" --root "$bad_name" >/dev/null 2>&1; then echo "error: bad filename passed" >&2; exit 1; fi

trailing="$tmp/trailing"; make_task "$trailing" 3.10-fix.json 3.10
if "$HELPER" --root "$trailing" >/dev/null 2>&1; then echo "error: trailing-zero rank passed" >&2; exit 1; fi

dup="$tmp/dup"; make_task "$dup" 3.9-a.json 3.9; make_task "$dup" 3.9-b.json 3.9
if "$HELPER" --root "$dup" >/dev/null 2>&1; then echo "error: duplicate rank passed" >&2; exit 1; fi

mismatch="$tmp/mismatch"; make_task "$mismatch" 3.9-a.json 3.8
if "$HELPER" --root "$mismatch" >/dev/null 2>&1; then echo "error: rank mismatch passed" >&2; exit 1; fi

context="$tmp/context"; make_task "$context" 3.9-a.json 3.9; jq 'del(.context)' "$context/docs/issues/3.9-a.json" > "$tmp/x" && mv "$tmp/x" "$context/docs/issues/3.9-a.json"
if "$HELPER" --root "$context" >/dev/null 2>&1; then echo "error: missing context passed" >&2; exit 1; fi

legacy="$tmp/legacy"; make_task "$legacy" 3.9-a.json 3.9; jq '.author="bot-event" | .status="backlog"' "$legacy/docs/issues/3.9-a.json" > "$tmp/x" && mv "$tmp/x" "$legacy/docs/issues/3.9-a.json"
if "$HELPER" --root "$legacy" >/dev/null 2>&1; then echo "error: legacy fields passed" >&2; exit 1; fi

attempt="$tmp/attempt"; make_task "$attempt" 3.9-a.json 3.9; jq '.attempts=[{summary:"Tried it",next_step:"Retry"}]' "$attempt/docs/issues/3.9-a.json" > "$tmp/x" && mv "$tmp/x" "$attempt/docs/issues/3.9-a.json"
"$HELPER" --root "$attempt" >/dev/null

bad_attempt="$tmp/bad-attempt"; make_task "$bad_attempt" 3.9-a.json 3.9; jq '.attempts=[{summary:"Tried it",owner:"bot"}]' "$bad_attempt/docs/issues/3.9-a.json" > "$tmp/x" && mv "$tmp/x" "$bad_attempt/docs/issues/3.9-a.json"
if "$HELPER" --root "$bad_attempt" >/dev/null 2>&1; then echo "error: unknown attempt field passed" >&2; exit 1; fi

echo "local task fixtures: ok"
