#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title 노트 ID로 열기
# @raycast.mode compact
# @raycast.packageName Ray Notes
# @raycast.icon 🔖
# @raycast.argument1 { "type": "text", "placeholder": "UUID" }

set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/raynotes.sh"
note_id="${1:-}"
if [[ ! "$note_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "UUID 형식의 노트 ID를 입력하세요." >&2
  exit 2
fi
raynotes_open_url "raynotes://open?id=$note_id"
