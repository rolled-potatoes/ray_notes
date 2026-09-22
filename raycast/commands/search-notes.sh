#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title 노트 찾기
# @raycast.mode compact
# @raycast.packageName Ray Notes
# @raycast.icon 🔎
# @raycast.argument1 { "type": "text", "placeholder": "제목 또는 본문" }

set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/raynotes.sh"
query="${1:-}"
encoded_query="$(raynotes_urlencode "$query")"
raynotes_open_url "raynotes://search?q=$encoded_query"
