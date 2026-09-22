#!/bin/bash

# Raycast Script Command가 source하는 공통 함수입니다.
raynotes_repo_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

raynotes_app_path() {
  local repo_dir installed_app built_app
  repo_dir="$(raynotes_repo_dir)"
  installed_app="$HOME/Applications/Ray Notes.app"
  built_app="$repo_dir/build/Ray Notes.app"

  if [[ -n "${RAY_NOTES_APP:-}" ]]; then
    printf '%s\n' "$RAY_NOTES_APP"
  elif [[ -d "$installed_app" ]]; then
    printf '%s\n' "$installed_app"
  else
    printf '%s\n' "$built_app"
  fi
}

raynotes_require_app() {
  local app_path
  app_path="$(raynotes_app_path)"
  if [[ ! -d "$app_path" ]]; then
    echo "Ray Notes 앱을 찾지 못했습니다: $app_path" >&2
    echo "scripts/build-app.sh를 실행하거나 RAY_NOTES_APP에 앱 번들 경로를 지정하세요." >&2
    return 1
  fi
  printf '%s\n' "$app_path"
}

raynotes_open_url() {
  local url="$1" app_path
  app_path="$(raynotes_require_app)" || return 1
  /usr/bin/open -a "$app_path" "$url"
}

# 외부 런타임에 의존하지 않고 UTF-8 바이트를 percent-encode합니다.
raynotes_urlencode() {
  local input="$1" byte value character output=""
  while read -r byte; do
    value=$((10#$byte))
    if (( (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122) || value == 45 || value == 46 || value == 95 || value == 126 )); then
      printf -v character "\\$(printf '%03o' "$value")"
      output+="$character"
    else
      printf -v output '%s%%%02X' "$output" "$value"
    fi
  done < <(LC_ALL=C /usr/bin/printf '%s' "$input" | /usr/bin/od -An -v -tu1 | /usr/bin/tr -s ' ' '\n' | /usr/bin/sed '/^$/d')
  printf '%s' "$output"
}
