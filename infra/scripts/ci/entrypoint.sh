#!/usr/bin/env bash
# Platform-neutral CI entrypoint. Runs in the consuming repository.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CI_PROJECT_DIR:-$PWD}"
cd "$ROOT"

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" && -x "$SCRIPT_DIR/validate-md-links.sh" ]]; then
  bash "$SCRIPT_DIR/validate-md-links.sh" \
    --root "$ROOT" --changed --base "origin/${GITHUB_BASE_REF:-main}" --check
fi

if [[ -x "$SCRIPT_DIR/validate-risk.sh" ]]; then
  bash "$SCRIPT_DIR/validate-risk.sh" --root "$ROOT"
fi

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" && -n "${GITEA_TOKEN:-}" && -r "${GITHUB_EVENT_PATH:-}" ]]; then
  pr_number="$(jq -r '.pull_request.number // .number // empty' "$GITHUB_EVENT_PATH")"
  if [[ -n "$pr_number" ]]; then
    bash "$SCRIPT_DIR/validate-pr-count.sh" \
      --repo "${GITHUB_REPOSITORY:?}" --pr "$pr_number" \
      --token "$GITEA_TOKEN" --api "${GITEA_URL:-${GITHUB_SERVER_URL:-http://gitea.localhost:3001}}"
  fi
fi

if command -v ci-lint >/dev/null 2>&1; then
  ci-lint
fi

bash "$SCRIPT_DIR/../ci.sh"
