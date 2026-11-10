#!/usr/bin/env bash
# Exercise the CI profile and hub renderers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CI="$ROOT/infra/scripts/render-ci-profile.sh"
HUBS="$ROOT/infra/scripts/render-hubs.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/infra/config"
jq -n '{organization:"templates",name:"example",visibility:"public",ci:{profile:"universal"},hubs:{practice:7,automation:8}}' > "$tmp/infra/config/repo.json"
[[ "$("$CI" --root "$tmp")" == "ci-universal" ]] || { echo "error: universal profile not rendered" >&2; exit 1; }
jq '.ci.profile = "python"' "$tmp/infra/config/repo.json" > "$tmp/infra/config/repo.json.tmp" && mv "$tmp/infra/config/repo.json.tmp" "$tmp/infra/config/repo.json"
[[ "$("$CI" --root "$tmp")" == "ci-python" ]] || { echo "error: python profile not rendered" >&2; exit 1; }
hubs="$("$HUBS" --root "$tmp")"
grep -q '/templates/example/issues/7' <<<"$hubs" || { echo "error: practice link wrong" >&2; exit 1; }
grep -q '/templates/example/issues/8' <<<"$hubs" || { echo "error: automation link wrong" >&2; exit 1; }

echo "render fixtures: ok"
