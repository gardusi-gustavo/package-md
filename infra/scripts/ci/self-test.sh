#!/usr/bin/env bash
# Self-tests for the shell-bash repository.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
find infra/scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
bash infra/scripts/ci/test-repo-contract.sh
bash infra/scripts/ci/test-publish-targets.sh
bash infra/scripts/ci/test-render.sh
bash infra/scripts/ci/test-local-issues.sh
bash infra/scripts/ci/validate-local-issues.sh --root "$ROOT"
echo "self-test: ok"
