#!/usr/bin/env bash
# Validate tracked files against the repository's file allow/forbid policy.
set -euo pipefail

ROOT="."
CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "error: --root needs a value" >&2; exit 2; }
      ROOT="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "error: --config needs a value" >&2; exit 2; }
      CONFIG="$2"
      shift 2
      ;;
    -h|--help)
      echo "usage: validate-files.sh [--root PATH] [--config PATH]"
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT"
CONFIG="${CONFIG:-infra/config/repo.json}"
[[ -s "$CONFIG" ]] || { echo "missing config: $CONFIG" >&2; exit 1; }
jq empty "$CONFIG" >/dev/null || { echo "invalid JSON: $CONFIG" >&2; exit 1; }
jq -e '.files.rules' "$CONFIG" >/dev/null || { echo "missing .files.rules in $CONFIG" >&2; exit 1; }

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors+1)); }
infra_max_mb="$(jq -r '.files.infra_max_file_mb // 1' "$CONFIG")"
sep=$'\x1f'
fs=$'\x1e'

declare -A R_EXT R_NAME R_GLOB R_ALLOW
while IFS="$fs" read -r key exts names globs allow; do
  R_EXT["$key"]="$exts"
  R_NAME["$key"]="$names"
  R_GLOB["$key"]="$globs"
  R_ALLOW["$key"]="$allow"
done < <(jq -r --arg sep "$sep" --arg fs "$fs" '
  .files.rules | to_entries[] |
  [ (if .key == "" then "__root__" else .key end),
    ((.value.allow_extensions // []) | join($sep)),
    ((.value.allow_names // []) | join($sep)),
    ((.value.allow_globs // []) | join($sep)),
    ((.value.allow // []) | join($sep)) ] | join($fs)
' "$CONFIG")

mapfile -t KEYS < <(
  printf '%s\n' "${!R_EXT[@]}" |
  grep -v '^__root__$' |
  awk '{ print length "\t" $0 }' |
  sort -rn |
  cut -f2-
)

F_RE=()
F_REASON=()
F_ALLOW=()
while IFS="$fs" read -r re reason allow; do
  F_RE+=("$re")
  F_REASON+=("$reason")
  F_ALLOW+=("$allow")
done < <(jq -r --arg sep "$sep" --arg fs "$fs" '
  .files.forbid[]? |
  [ .regex, (.reason // "forbidden"), ((.allow // []) | join($sep)) ] | join($fs)
' "$CONFIG")

rule_key() {
  local f="$1" k
  if [[ "$f" != */* ]]; then
    printf '%s' "__root__"
    return 0
  fi
  for k in "${KEYS[@]}"; do
    if [[ "$f" == "$k"* ]]; then
      printf '%s' "$k"
      return 0
    fi
  done
  return 0
}

check_allowed() {
  local key="$1" f="$2" base ext a
  base="${f##*/}"
  ext="${base##*.}"
  [[ "$ext" != "$base" ]] && ext=".$ext" || ext=""

  IFS="$sep" read -r -a arr <<< "${R_ALLOW[$key]:-}"
  for a in "${arr[@]}"; do
    [[ "$a" == "*" ]] && return 0
  done

  IFS="$sep" read -r -a arr <<< "${R_NAME[$key]:-}"
  for a in "${arr[@]}"; do
    [[ -n "$a" ]] || continue
    [[ "$base" == "$a" || "$f" == "$a" ]] && return 0
  done

  IFS="$sep" read -r -a arr <<< "${R_EXT[$key]:-}"
  for a in "${arr[@]}"; do
    [[ "$ext" == "$a" ]] && return 0
  done

  IFS="$sep" read -r -a arr <<< "${R_GLOB[$key]:-}"
  for a in "${arr[@]}"; do
    [[ -n "$a" ]] || continue
    # shellcheck disable=SC2053
    [[ "$base" == $a ]] && return 0
  done

  return 1
}

is_forbidden() {
  local f="$1" i a
  for i in "${!F_RE[@]}"; do
    [[ "${F_RE[$i]}" ]] || continue
    if [[ "$f" =~ ${F_RE[$i]} ]]; then
      IFS="$sep" read -r -a arr <<< "${F_ALLOW[$i]:-}"
      for a in "${arr[@]}"; do
        [[ -n "$a" ]] || continue
        [[ "$f" =~ $a ]] && return 1
      done
      printf '%s\n' "${F_REASON[$i]}"
      return 0
    fi
  done
  return 1
}

while IFS= read -r -d '' f; do
  reason="$(is_forbidden "$f" || true)"
  if [[ -n "$reason" ]]; then
    fail "$f: $reason"
    continue
  fi

  key="$(rule_key "$f")"
  if [[ -z "${R_EXT[$key]+x}${R_NAME[$key]+x}${R_GLOB[$key]+x}${R_ALLOW[$key]+x}" ]]; then
    fail "$f: no allow rule matches this path"
    continue
  fi
  if ! check_allowed "$key" "$f"; then
    fail "$f: file type is not allowed in this path"
    continue
  fi

  if [[ "$f" == infra/* ]]; then
    size="$(stat -c '%s' "$f" 2>/dev/null || echo 0)"
    if (( size > infra_max_mb * 1000000 )); then
      fail "$f: infra file exceeds ${infra_max_mb} MB"
    fi
  fi
done < <(git ls-files -z)

(( errors == 0 )) || exit 1
echo "file policy ok"
