#!/usr/bin/env bash
# Review-load budget check for CI. Runs only on pull_request events.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: validate-pr-size.sh [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  echo "pr size: skipped (not a pull request)"
  exit 0
fi

base="${GITHUB_BASE_REF:-main}"
repo="${GITHUB_REPOSITORY:-local/repo}"
pr=""
event="${GITHUB_EVENT_PATH:-}"

if [[ -n "$event" && -r "$event" ]]; then
  pr="$(jq -r '.pull_request.number // .number // empty' "$event" 2>/dev/null || true)"
  event_base="$(jq -r '.pull_request.base.ref // empty' "$event" 2>/dev/null || true)"
  [[ -n "$event_base" ]] && base="$event_base"
fi
if [[ -z "$pr" && "${GITHUB_REF:-}" =~ ^refs/pull/([0-9]+)/ ]]; then
  pr="${BASH_REMATCH[1]}"
fi
if [[ -z "$pr" ]]; then
  echo "pr size: skipped (no pull request number)"
  exit 0
fi

base_ref="origin/$base"
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  if [[ -f .git/shallow ]]; then
    git fetch --no-tags --unshallow origin "$base" >/dev/null 2>&1 || true
  else
    git fetch --no-tags origin "$base" >/dev/null 2>&1 || true
  fi
fi
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  base_ref="$base"
fi
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "pr size: cannot resolve base ref: $base" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
base_cfg="$tmpdir/repo.json"
if ! git show "$base_ref:infra/config/repo.json" > "$base_cfg" 2>/dev/null; then
  printf '{}\n' > "$base_cfg"
fi

check="infra/scripts/ci/pr-size-check.sh"
if [[ ! -r "$check" ]]; then
  echo "pr size: missing $check" >&2
  exit 2
fi

if ! bash "$check" --repo "$repo" --base "$base_ref" --head HEAD --root . --repo-config "$base_cfg"; then
  exit 1
fi
