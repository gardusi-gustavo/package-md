#!/usr/bin/env bash
# Exercise the contract validator with valid and invalid fixtures.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="$ROOT/infra/scripts/ci/validate-repo-contract.sh"
FIXTURES="$ROOT/tests/fixtures/repo"

[[ -x "$HELPER" ]] || { echo "error: missing $HELPER" >&2; exit 2; }
[[ -d "$FIXTURES" ]] || { echo "error: missing $FIXTURES" >&2; exit 2; }

"$HELPER" --config "$FIXTURES/contract-valid.json" >/dev/null

if "$HELPER" --config "$FIXTURES/contract-invalid-missing.json" >/dev/null 2>&1; then
  echo "error: missing identity fixture passed" >&2
  exit 1
fi

if "$HELPER" --config "$FIXTURES/contract-invalid-type.json" >/dev/null 2>&1; then
  echo "error: bad type fixture passed" >&2
  exit 1
fi

echo "contract fixtures: ok"
