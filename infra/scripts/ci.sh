#!/usr/bin/env bash
set -euo pipefail
ROOT="${CI_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
cd "$ROOT"
"$ROOT/infra/scripts/ci/validate-repo.sh" --root "$ROOT"
"$ROOT/infra/scripts/ci/check-size.sh" --root "$ROOT"
"$ROOT/infra/scripts/ci/validate-local-issues.sh" --root "$ROOT"
shopt -s nullglob
for f in templates/*.md standards/*.md diagrams/*.mmd diagrams/*.md; do
  [[ -s "$f" ]] || { echo "missing $f" >&2; exit 1; }
done
for f in infra/scripts/*.sh; do bash -n "$f"; done
echo "package-md checks ok"
