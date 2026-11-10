#!/usr/bin/env bash
# Risk gate for sensitive and elevated paths. Uses the pull_request event
# payload for labels and body; no API token required.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --event) GITHUB_EVENT_PATH="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: validate-risk.sh [--root PATH] [--event FILE]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"

event="${GITHUB_EVENT_PATH:-}"
if [[ -z "$event" || ! -r "$event" ]]; then
  echo "risk: skipped (no pull_request event)"
  exit 0
fi

base="${GITHUB_BASE_REF:-}"
if [[ -z "$base" ]]; then
  base="$(jq -r '.pull_request.base.ref // empty' "$event" 2>/dev/null || true)"
fi
[[ -n "$base" ]] || base="main"

body="$(jq -r '.pull_request.body // ""' "$event" 2>/dev/null || true)"
labels="$(jq -r '[.pull_request.labels[]?.name] | join(",")' "$event" 2>/dev/null || true)"

base_ref="origin/$base"
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  if [[ -f .git/shallow ]]; then
    git fetch --no-tags --unshallow origin "$base" >/dev/null 2>&1 || true
  else
    git fetch --no-tags origin "$base" >/dev/null 2>&1 || true
  fi
fi
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "risk: cannot resolve base ref: $base" >&2
  exit 2
fi
merge_base="$(git merge-base "$base_ref" HEAD)" || {
  echo "risk: cannot find a merge base with $base" >&2
  exit 2
}
mapfile -t changed < <(git diff --name-only "$merge_base" HEAD)

sensitive_patterns=(
  'auth/**' '**/auth/**' 'auth*' '**/auth*'
  'security/**' '**/security/**' '**/secrets*' '**/payment*'
  '**/permissions*' '**/authorization*'
  'migrations/**' '**/migrations/**'
  'infra/config/policy.json' 'infra/config/repos.json'
  '.gitea/workflows/**' 'infra/scripts/agent/**'
  'AGENTS.md' 'CODEOWNERS'
)
elevated_patterns=(
  'package.json' 'package-lock.json' 'npm-shrinkwrap.json' 'yarn.lock'
  'pnpm-lock.yaml' 'Cargo.toml' 'Cargo.lock' 'pyproject.toml' 'poetry.lock'
  'requirements*.txt' 'go.mod' 'go.sum' 'composer.json' 'Gemfile'
  'infra/docker/**' 'src/data/**' '*.csv' '*.jsonl'
)

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

sensitive=()
elevated=()
for path in "${changed[@]}"; do
  [[ -n "$path" ]] || continue
  if matches "$path" "${sensitive_patterns[@]}"; then
    sensitive+=("$path")
  elif matches "$path" "${elevated_patterns[@]}"; then
    elevated+=("$path")
  fi
done

has_section() {
  local heading="$1"
  awk -v h="$heading" '
    $0 == h { found = 1; next }
    /^## / { found = 0 }
    found && NF { print "yes"; exit }
  ' <<<"$body"
}

reasons=()
if (( ${#sensitive[@]} > 0 )); then
  printf 'risk: sensitive paths:\n'
  printf '  %s\n' "${sensitive[@]}"
  if [[ ",$labels," != *",security-review,"* ]]; then
    reasons+=("missing security-review label")
  fi
  [[ -n "$(has_section '## Security')" ]] || reasons+=("missing ## Security section")
fi

if (( ${#elevated[@]} > 0 )); then
  printf 'risk: elevated paths:\n'
  printf '  %s\n' "${elevated[@]}"
  [[ -n "$(has_section '## Risk')" ]] || reasons+=("missing ## Risk section")
fi

if (( ${#reasons[@]} > 0 )); then
  echo "risk: FAILED" >&2
  printf '  %s\n' "${reasons[@]}" >&2
  echo "  sensitive changes need security-review and ## Security" >&2
  echo "  elevated changes need ## Risk" >&2
  exit 1
fi
echo "risk: ok"
