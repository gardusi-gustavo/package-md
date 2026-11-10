#!/usr/bin/env bash
# Validate a repository against its infra/config/repo.json contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) echo "usage: validate-repo.sh [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"
CONFIG="infra/config/repo.json"
errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors+1)); }

[[ -s "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
jq empty "$CONFIG" >/dev/null || { echo "invalid JSON: $CONFIG" >&2; exit 1; }

visibility="$(jq -r '.visibility' "$CONFIG")"
pages="$(jq -r '.features.pages // false' "$CONFIG")"
[[ "$visibility" == "public" || "$visibility" == "private" ]] || fail "visibility must be public or private"
[[ "$(jq -r '.schema' "$CONFIG")" == "1" ]] || fail "unsupported schema"

if ! "$SCRIPT_DIR/validate-repo-contract.sh" --config "$CONFIG"; then
  errors=$((errors + 1))
fi

if ! "$SCRIPT_DIR/validate-publish-targets.sh" --root .; then
  errors=$((errors + 1))
fi

knowledge_mode="$(jq -r '.knowledge_mode // empty' "$CONFIG")"
if [[ -n "$knowledge_mode" ]]; then
  case "$knowledge_mode" in
    observer|instrument|domain-audit|mirror) ;;
    *) fail "knowledge_mode must be observer, instrument, domain-audit, or mirror" ;;
  esac

  case "$knowledge_mode" in
    observer)
      jq -e '.sources | ((type == "string" and length > 0) or (type == "array" and length > 0))' "$CONFIG" >/dev/null ||
        fail "observer requires a non-empty sources value"
      ;;
    instrument)
      jq -e '.sources | ((type == "string" and length > 0) or (type == "array" and length > 0))' "$CONFIG" >/dev/null ||
        fail "instrument requires a non-empty sources value"
      jq -e '.freshness | type == "string" and length > 0' "$CONFIG" >/dev/null ||
        fail "instrument requires freshness"
      if jq -e '.ai_loop.data_path == true' "$CONFIG" >/dev/null; then
        fail "instrument must not put AI in the data path"
      fi
      ;;
    domain-audit)
      coverage_path="$(jq -r '.coverage // empty' "$CONFIG")"
      [[ -n "$coverage_path" ]] || fail "domain-audit requires coverage"
      if [[ -n "$coverage_path" ]]; then
        case "$coverage_path" in
          /*|*..*) fail "coverage must be a relative path without ..: $coverage_path" ;;
        esac
        [[ -f "$coverage_path" ]] || fail "coverage file not found: $coverage_path"
      fi
      jq -e '.ai_loop.cadence | type == "string" and length > 0' "$CONFIG" >/dev/null ||
        fail "domain-audit requires ai_loop.cadence"
      jq -e '.ai_loop.max_issues | type == "number" and . >= 1 and . <= 20' "$CONFIG" >/dev/null ||
        fail "ai_loop.max_issues must be between 1 and 20"
      ;;
    mirror)
      jq -e '.upstream | type == "string" and length > 0' "$CONFIG" >/dev/null ||
        fail "mirror requires upstream"
      ;;
  esac

  if jq -e '.data_classification | IN("private","personal","secret")' "$CONFIG" >/dev/null; then
    if jq -e 'has("ai_loop")' "$CONFIG" >/dev/null; then
      jq -e '.ai_loop.local_only == true' "$CONFIG" >/dev/null ||
        fail "private repositories require ai_loop.local_only: true"
    fi
  fi
fi

for f in README.md .gitattributes .gitignore "$CONFIG" docs/README.md; do
  [[ -s "$f" ]] || fail "missing required file: $f"
done

if [[ "$pages" == "true" ]]; then
  for f in infra/docker/pages.dockerfile infra/scripts/pages.sh; do
    [[ -s "$f" ]] || fail "pages enabled but missing: $f"
  done
fi

while IFS= read -r f; do
  case "$f" in
    infra/scripts/*.sh|templates/base/infra/scripts/*.sh) ;;
    *) fail "shell script outside infra/scripts/: $f" ;;
  esac
done < <(git ls-files '*.sh')

while IFS= read -r f; do
  case "$f" in infra/docker/*.dockerfile|templates/base/infra/docker/*.dockerfile) ;; *) fail "Dockerfile outside infra/docker/: $f" ;; esac
done < <(git ls-files | grep -E '(^|/)Dockerfile$|\.Dockerfile$|\.dockerfile$' || true)

while IFS= read -r f; do
  case "$f" in
    .vscode/*|.idea/*|.devcontainer/*|.editorconfig|*/.*) fail "editor/container file must not be tracked: $f" ;;
  esac
done < <(git ls-files | grep -E '(^|/)(\.vscode|\.idea|\.devcontainer)/|(^|/)\.editorconfig$' || true)

while IFS= read -r f; do
  case "$f" in *.json) ;; *) fail "infra/config/ must contain only JSON: $f" ;; esac
done < <(git ls-files 'infra/config/**' || true)

while IFS= read -r f; do
  case "$f" in *.md|docs/issues/*.json) ;; *) fail "docs/ must contain only Markdown or docs/issues JSON: $f" ;; esac
done < <(git ls-files 'docs/**' || true)

"$SCRIPT_DIR/validate-files.sh" --root . --config "$CONFIG"

max_repo="$(jq -r '.limits.repo_mb // 100' "$CONFIG")"
max_file="$(jq -r '.limits.file_mb // 25' "$CONFIG")"
total="$(git ls-files -z | xargs -0 -r stat -c '%s' | awk '{s+=$1} END {print s+0}')"
if (( total > max_repo * 1000000 )); then fail "repo size ${total} exceeds ${max_repo} MB"; fi
largest=$(git ls-files -z | xargs -0 -r stat -c '%s %n' | awk 'BEGIN {m=0} $1>m {m=$1; f=$0} END {if (m>0) print f}')
if [[ -n "$largest" ]]; then
  size=${largest%% *}; file=${largest#* }
  if (( size > max_file * 1000000 )); then fail "file ${file} exceeds ${max_file} MB"; fi
fi

readme_max="$(jq -r '.readme.max_lines // 80' "$CONFIG")"
lines="$(wc -l < README.md)"
(( lines <= readme_max )) || fail "README.md is ${lines} lines; max ${readme_max}"

(( errors == 0 )) || exit 1
if [[ -x "$SCRIPT_DIR/../check-layout.sh" ]]; then
  "$SCRIPT_DIR/../check-layout.sh" --root .
fi
echo "repo contract ok: $visibility"
