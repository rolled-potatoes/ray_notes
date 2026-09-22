#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
bundle_path="$repo_dir/build/Ray Notes.app"

cd "$repo_dir"
# macOS의 sandbox-exec 제한 환경에서도 SwiftPM 자체의 manifest sandbox와
# 앱의 App Sandbox를 혼동하지 않도록, 이 로컬 빌드에만 비활성화한다.
mise exec -- swift build -c release --disable-sandbox
bin_dir="$(mise exec -- swift build -c release --disable-sandbox --show-bin-path)"
binary_path="$bin_dir/RayNotes"

if [[ ! -x "$binary_path" ]]; then
  echo "빌드된 실행 파일을 찾지 못했습니다: $binary_path" >&2
  exit 1
fi

rm -rf "$bundle_path"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources"
cp "$repo_dir/resources/Info.plist" "$bundle_path/Contents/Info.plist"
cp "$binary_path" "$bundle_path/Contents/MacOS/RayNotes"
/usr/bin/codesign --force --sign - "$bundle_path"
/usr/bin/plutil -lint "$bundle_path/Contents/Info.plist"
echo "앱 번들을 만들었습니다: $bundle_path"
