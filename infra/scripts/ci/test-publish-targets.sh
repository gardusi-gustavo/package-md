#!/usr/bin/env bash
# Exercise the publish-target validator with one fixture per target.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="$ROOT/infra/scripts/ci/validate-publish-targets.sh"
FIXTURES="$ROOT/tests/fixtures/repo"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check_ok() {
  local fixture="$1" manifest="$2"
  local dir
  dir="$tmp/$(basename "$fixture" .json)"
  mkdir -p "$dir/infra/config" "$dir/infra/docker"
  cp "$FIXTURES/$fixture" "$dir/infra/config/repo.json"
  case "$manifest" in
    package.json)
      echo '{"version":"1.0.0"}' > "$dir/package.json" ;;
    pyproject.toml)
      printf '[project]\nversion = "1.0.0"\n' > "$dir/pyproject.toml" ;;
    Cargo.toml)
      printf '[package]\nversion = "1.0.0"\n' > "$dir/Cargo.toml" ;;
    docker)
      printf 'FROM scratch\n' > "$dir/infra/docker/base.dockerfile" ;;
    csproj)
      printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$dir/Example.csproj" ;;
    go.mod)
      printf 'module example.com/kit\n' > "$dir/go.mod" ;;
    pom.xml)
      printf '<project></project>\n' > "$dir/pom.xml" ;;
    gemspec)
      printf 'Gem::Specification.new do |s|\nend\n' > "$dir/example.gemspec" ;;
    composer.json)
      printf '{"name":"gardusi-gustavo/kit"}\n' > "$dir/composer.json" ;;
  esac
  "$HELPER" --root "$dir" >/dev/null
}

check_ok publish-npm.json package.json
check_ok publish-pypi.json pyproject.toml
check_ok publish-crates.json Cargo.toml
check_ok publish-docker.json docker
check_ok publish-nuget.json csproj
check_ok publish-go.json go.mod
check_ok publish-maven.json pom.xml
check_ok publish-gem.json gemspec
check_ok publish-composer.json composer.json

missing="$tmp/missing"
mkdir -p "$missing/infra/config"
cp "$FIXTURES/publish-npm.json" "$missing/infra/config/repo.json"
if "$HELPER" --root "$missing" >/dev/null 2>&1; then
  echo "error: missing npm manifest passed" >&2
  exit 1
fi

echo "publish fixtures: ok"
