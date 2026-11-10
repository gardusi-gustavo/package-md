#!/usr/bin/env bash
# Dry-run every workflow step. No writes are allowed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STEP="$ROOT/infra/scripts/workflow/step.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/store/video" "$tmp/store/ready/video" "$tmp/card/video" "$tmp/dump" "$tmp/dest" "$tmp/out"
printf 'x' >"$tmp/store/video/test.mkv"
printf 'x' >"$tmp/store/ready/video/test.mkv"
printf 'x' >"$tmp/card/video/test.mkv"
printf 'x' >"$tmp/dump/gitea.db"
printf 'x' >"$tmp/archive.7z"
printf 'x' >"$tmp/temp.7z"
printf '%s\n' \
  "{\"primary_dir\":\"$tmp/dest\",\"mirror_dirs\":[\"$tmp/card\"],\"retention\":{\"reserve_bytes\":0}}" \
  >"$tmp/policy.json"

run() {
  local name="$1" input="$2"
  printf '%s\n' "$input" >"$tmp/in.json"
  local out
  out="$(SB_SCRIPT_NAME="$name" bash "$STEP" --root "$ROOT" --dry-run --json --input "$tmp/in.json")"
  jq -e . >/dev/null <<<"$out" || {
    echo "error: $name did not emit JSON" >&2
    exit 1
  }
}

item='{"id":"item-12345678","title":"Test","domain":"video","stage":"input","status":"yellow","size_bytes":1,"presence":{"store":true,"card":false},"ticket_id":null,"relpath":"video/test.mkv"}'

run vault.scan "{\"store_root\":\"$tmp/store\"}"
run vault.classify "{\"store_root\":\"$tmp/store\",\"items\":[$item]}"
run vault.plan "{\"items\":[$item]}"
run vault.reconcile "{\"store_root\":\"$tmp/store\",\"card_root\":\"$tmp/card\"}"
run vault.render '{"store_items":1,"card_items":1,"missing_on_card":[],"extra_on_card":[]}'
run vault.fetch "{\"relpath\":\"video/test.mkv\",\"store_root\":\"$tmp/store\",\"card_root\":\"$tmp/card\"}"
run vault.transform "{\"relpath\":\"video/test.mkv\",\"store_root\":\"$tmp/store\"}"
run vault.verify "{\"relpath\":\"video/test.mkv\",\"store_root\":\"$tmp/store\"}"
run vault.publish "{\"relpath\":\"video/test.mkv\",\"store_root\":\"$tmp/store\",\"card_root\":\"$tmp/card\"}"
run vault.cleanup "{\"relpath\":\"video/test.mkv\",\"store_root\":\"$tmp/store\",\"card_root\":\"$tmp/card\"}"

run backup.lock "{\"lock_file\":\"$tmp/lock\",\"mode\":\"manual\"}"
run backup.preflight "{\"policy_path\":\"$tmp/policy.json\"}"
run backup.quiesce '{"name":"gitea","data_dir":"/tmp"}'
run backup.dump '{"data_dir":"/tmp","out_dir":"/tmp/out"}'
run backup.validate "{\"dump_dir\":\"$tmp/dump\"}"
run backup.manifest "{\"dump_dir\":\"$tmp/dump\"}"
run backup.archive "{\"manifest_path\":\"$tmp/dump/manifest.json\",\"archive_path\":\"$tmp/new.7z\"}"
run backup.test "{\"archive_path\":\"$tmp/archive.7z\"}"
run backup.copy "{\"archive_path\":\"$tmp/archive.7z\",\"sha256\":\"deadbeef\",\"final_path\":\"$tmp/dest/archive.7z\"}"
run backup.verify_copy "{\"temp_path\":\"$tmp/temp.7z\",\"sha256\":\"deadbeef\"}"
run backup.publish_copy "{\"temp_path\":\"$tmp/temp.7z\",\"final_path\":\"$tmp/dest/final.7z\"}"
run backup.reconcile "{\"archive_path\":\"$tmp/archive.7z\",\"mirror\":\"$tmp/dest\"}"
run backup.prune "{\"destination\":\"$tmp/dest\",\"archive_path\":\"$tmp/archive.7z\",\"retention\":{\"max_bytes\":1000,\"reserve_bytes\":0,\"minimum_valid_archives\":1}}"
run backup.status "{\"result\":\"pass\",\"mode\":\"manual\",\"archive\":\"$tmp/archive.7z\"}"
run backup.resume '{"name":"gitea"}'
run backup.unlock "{\"lock_file\":\"$tmp/lock\"}"

echo "workflow: 26 dry-run steps ok"
