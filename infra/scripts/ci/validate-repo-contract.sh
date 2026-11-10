#!/usr/bin/env bash
# Validate the required repository contract fields.
set -euo pipefail

CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config needs a value" >&2; exit 2; }
      CONFIG="$2"; shift 2 ;;
    -h|--help)
      echo "usage: validate-repo-contract.sh --config PATH"
      exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$CONFIG" ]] || { echo "error: --config is required" >&2; exit 2; }
[[ -s "$CONFIG" ]] || { echo "error: missing $CONFIG" >&2; exit 1; }
jq empty "$CONFIG" >/dev/null || { echo "error: invalid JSON: $CONFIG" >&2; exit 1; }

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
check() {
  local expr="$1" message="$2"
  jq -e "$expr" "$CONFIG" >/dev/null || fail "$message"
}

check '.schema == 1' 'schema must be 1'
check '.name | type == "string" and test("^[a-z0-9][a-z0-9-]*$")' 'name must be the repository name'
check '.organization | type == "string" and test("^[a-z0-9][a-z0-9-]*$")' 'organization must be an org name'
check '.layer | type == "number" and . == floor and . >= 0 and . <= 4' 'layer must be an integer from 0 to 4'
check '.depends_on | type == "array" and all(.[]; type == "string" and test("^[a-z0-9-]+/[a-z0-9-]+$"))' 'depends_on must be owner/repo strings'
check '.consumers | type == "array" and all(.[]; type == "string" and length > 0)' 'consumers must be non-empty strings'
check '.data_classification | IN("public", "private", "personal", "secret")' 'data_classification is invalid'
check '.visibility | IN("public", "limited", "private")' 'visibility is invalid'
check '.dependencies | type == "object" and (keys | all(.[]; test("^[a-z0-9-]+/[a-z0-9-]+$"))) and ([.[] | type == "string" and test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")] | all)' 'dependencies must map owner/repo to vX.Y.Z'

if jq -e 'has("publish")' "$CONFIG" >/dev/null; then
  check '.publish | type == "array" and all(.[]; IN("npm", "pypi", "crates", "docker", "nuget", "go", "maven", "gem", "composer"))' 'publish targets are invalid'
fi

if jq -e 'has("hubs")' "$CONFIG" >/dev/null; then
  check '.hubs | type == "object"' 'hubs must be an object'
  if jq -e '.hubs | has("practice")' "$CONFIG" >/dev/null; then
    check '.hubs.practice | type == "number" and . == floor and . >= 1' 'hubs.practice must be an issue number'
  fi
  if jq -e '.hubs | has("automation")' "$CONFIG" >/dev/null; then
    check '.hubs.automation | type == "number" and . == floor and . >= 1' 'hubs.automation must be an issue number'
  fi
fi

if jq -e '.ci | has("profile")' "$CONFIG" >/dev/null; then
  check '.ci.profile | IN("universal", "base", "python", "node", "go", "rust", "cpp", "java", "media", "dotnet", "ruby", "php")' 'ci.profile is invalid'
fi

(( errors == 0 )) || exit 1
echo "contract ok: $CONFIG"
