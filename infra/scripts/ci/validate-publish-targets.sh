#!/usr/bin/env bash
# Validate that every declared publish target has the required manifest.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "error: --root needs a value" >&2; exit 2; }
      ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "usage: validate-publish-targets.sh [--root PATH]"
      exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "error: root not found: $ROOT" >&2; exit 2; }
cd "$ROOT"
CONFIG="infra/config/repo.json"
[[ -s "$CONFIG" ]] || { echo "error: missing $CONFIG" >&2; exit 1; }

mapfile -t targets < <(jq -r '.publish // [] | .[]' "$CONFIG")
errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

for target in "${targets[@]}"; do
  case "$target" in
    npm)
      [[ -s package.json ]] || fail "publish npm requires package.json"
      ;;
    pypi)
      [[ -s pyproject.toml ]] || fail "publish pypi requires pyproject.toml"
      ;;
    crates)
      [[ -s Cargo.toml ]] || fail "publish crates requires Cargo.toml"
      ;;
    docker)
      compgen -G "infra/docker/*.dockerfile" >/dev/null || fail "publish docker requires infra/docker/*.dockerfile"
      ;;
    nuget)
      compgen -G "*.csproj" >/dev/null || fail "publish nuget requires a *.csproj"
      ;;
    go)
      [[ -s go.mod ]] || fail "publish go requires go.mod"
      ;;
    maven)
      [[ -s pom.xml ]] || fail "publish maven requires pom.xml"
      ;;
    gem)
      compgen -G "*.gemspec" >/dev/null || fail "publish gem requires a *.gemspec"
      ;;
    composer)
      [[ -s composer.json ]] || fail "publish composer requires composer.json"
      ;;
    *)
      fail "unknown publish target: $target"
      ;;
  esac
done

(( errors == 0 )) || exit 1
if (( ${#targets[@]} == 0 )); then
  echo "publish targets: none"
else
  echo "publish targets: ${targets[*]}"
fi
