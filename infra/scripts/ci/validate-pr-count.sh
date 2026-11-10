#!/usr/bin/env bash
# Per-repository open-PR cap. The repository may have at most N open pull
# requests; the oldest-PR-only serialization is intentionally removed.
set -euo pipefail

REPO=""
PR=""
TOKEN=""
API="${GITEA_URL:-${GITHUB_SERVER_URL:-http://gitea.localhost:3001}}"
FIXTURE=""
POLICY="${GITEA_POLICY:-infra/config/policy.json}"
MAX_OPEN="${GITEA_MAX_OPEN_PRS:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --api) API="${2:-}"; shift 2 ;;
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: validate-pr-count.sh --repo OWNER/REPO [--pr N] [--token TOKEN] [--fixture FILE] [--policy FILE]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" && -z "$FIXTURE" ]]; then
  echo "pr count: skipped (not a pull request)"
  exit 0
fi
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || { echo "error: --repo must be OWNER/REPO" >&2; exit 2; }

if [[ -z "$MAX_OPEN" && -s "$POLICY" ]]; then
  MAX_OPEN="$(jq -r '.pull_requests.max_open_per_repo // 3' "$POLICY")"
fi
MAX_OPEN="${MAX_OPEN:-3}"
[[ "$MAX_OPEN" =~ ^[0-9]+$ ]] || { echo "error: invalid PR cap: $MAX_OPEN" >&2; exit 2; }
(( MAX_OPEN > 0 )) || { echo "error: PR cap must be positive" >&2; exit 2; }

if [[ -n "$FIXTURE" ]]; then
  [[ -r "$FIXTURE" ]] || { echo "error: cannot read fixture: $FIXTURE" >&2; exit 2; }
  prs="$(cat "$FIXTURE")"
else
  if [[ -z "$TOKEN" ]]; then
    echo "warning: no API token; PR cap check skipped" >&2
    exit 0
  fi
  prs="$(curl -fsS -H "Authorization: token $TOKEN" \
    "${API%/}/api/v1/repos/$REPO/pulls?state=open&limit=100")" || {
    echo "error: cannot list open PRs for $REPO" >&2
    exit 2
  }
fi

jq -e 'type == "array"' <<<"$prs" >/dev/null 2>&1 || {
  echo "error: invalid pull request response for $REPO" >&2
  exit 2
}

count="$(jq 'length' <<<"$prs")"
if (( count > MAX_OPEN )); then
  echo "pr count: FAILED ($count/$MAX_OPEN open PRs in $REPO)" >&2
  jq -r '.[] | "  #\(.number) [\(.user.login)] \(.head.ref): \(.title)"' <<<"$prs" >&2
  echo "  merge or close a PR before adding another" >&2
  exit 1
fi

echo "pr count: ok ($count/$MAX_OPEN open PRs${PR:+; current #$PR})"
