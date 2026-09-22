#!/bin/bash
set -euo pipefail

# 이 스크립트는 사용자가 수동으로 실행할 때만 ~/Applications에 복사합니다.
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
source_bundle="$repo_dir/build/Ray Notes.app"
target_dir="$HOME/Applications"
target_bundle="$target_dir/Ray Notes.app"

if [[ ! -d "$source_bundle" ]]; then
  echo "먼저 scripts/build-app.sh를 실행하세요." >&2
  exit 1
fi

mkdir -p "$target_dir"
rm -rf "$target_bundle"
/usr/bin/ditto "$source_bundle" "$target_bundle"
echo "설치했습니다: $target_bundle"
