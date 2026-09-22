#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title 최근 노트 이어쓰기
# @raycast.mode compact
# @raycast.packageName Ray Notes
# @raycast.icon ⏱️

set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/raynotes.sh"
raynotes_open_url "raynotes://recent"
