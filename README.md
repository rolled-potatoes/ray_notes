# Ray Notes

Raycast에서 호출해 바로 쓰고, 로컬에 자동 저장한 개인 메모를 다음 호출에서 이어 쓰는 macOS 앱입니다. 앱이 노트 개수에 인위적인 제한을 두지 않으며 로그인·서버·구독이 필요하지 않습니다.

## 선택한 구조

Swift/AppKit을 선택했습니다. AppKit의 `NSTextView`는 macOS 창 수명, URL 열기, 키보드 포커스와 한글 IME 조합을 직접 제어할 수 있어 이 앱의 작고 오래 유지할 수 있는 범위에 맞습니다. SwiftUI에 AppKit 브리지를 더하는 방식은 화면 구성에는 편하지만 IME·텍스트 편집의 세밀한 제어를 위해 브리지 경계가 생깁니다. Tauri는 WebView와 Rust, Electron은 Chromium과 Node 런타임·번들·업데이트 관리가 더해집니다. 이는 구조와 유지보수 범위의 비교이며 런타임별 속도·메모리 벤치마크는 수행하지 않았습니다.

`RayNotesCore`는 Markdown 노트와 파일 저장을, `RayNotes`는 AppKit 창과 `raynotes://` URL 라우팅을 담당합니다. Raycast Script Command는 URL만 열고, 앱이 꺼져 있으면 macOS가 앱을 시작하며 이미 실행 중이면 기존 프로세스가 URL을 받아 해당 노트를 활성화합니다. 새 메모·최근 메모·검색·UUID 열기를 구분하므로 재호출로 빈 노트를 중복 만들지 않습니다.

## 디자인 방향

[Things](https://culturedcode.com/things/)와 [기능 소개](https://culturedcode.com/things/features/)에서 보이는 여백의 리듬, 중립적인 사이드바, 선택된 항목의 파란 강조를 참고했습니다. 이는 현재의 단일 Markdown 빠른 메모 화면을 더 차분하게 만드는 시각적 판단입니다. 일정·마감일·프로젝트·태그·동기화 같은 작업 관리자 기능은 추가하지 않습니다.

## 빌드와 실행

필수 도구는 Xcode Command Line Tools와 `mise`입니다. 의존성 다운로드는 하지 않습니다.

```bash
cd /Users/goorm/Documents/ChatGPT/ray-notes
./scripts/build-app.sh
open "build/Ray Notes.app"
```

빌드 스크립트는 `mise exec -- swift build -c release`로 실행 파일을 만들고 `build/Ray Notes.app` 번들을 구성한 뒤 ad-hoc 서명합니다. 설치 없이 이 번들을 바로 실행할 수 있습니다.

원하면 사용자가 직접 다음을 실행해 사용자 전용 Applications 폴더로 복사할 수 있습니다. 이 저장소의 스크립트는 자동 설치나 로그인 항목 등록을 하지 않습니다.

```bash
./scripts/install-local.sh
```

## Raycast 등록

1. Raycast Root Search에서 **Search Script Commands**를 실행합니다. 아직 폴더가 없을 때 보이는 **Add Script Command Folder** 버튼을 누릅니다. Settings의 왼쪽에서 **Script Commands**가 자동 선택됩니다.
2. **Script Folders** 영역의 `+`를 선택하고 `/Users/goorm/Documents/ChatGPT/ray-notes/raycast/commands`를 등록합니다. 이 흐름은 Raycast의 [Script Commands 안내](https://github.com/raycast/script-commands)와 입력 인수 [공식 안내](https://www.raycast.com/blog/inputs-for-script-commands)를 따릅니다.
3. Raycast에서 아래 명령을 찾아 원하는 단축키를 각각 지정합니다. 기본 키 조합은 Raycast와 충돌을 피하기 위해 강제하지 않습니다.

| Raycast 명령 | 동작 |
| --- | --- |
| 새 빈 노트 | `# 메모`로 시작하는 새 메모를 만들고 본문 끝에 포커스 |
| 새 회의 노트 | 필요할 때만 날짜·참석자·안건·논의 내용·결정 사항·액션 아이템 템플릿으로 생성 |
| 최근 노트 이어쓰기 | 가장 최근 수정 노트를 열기 |
| 노트 찾기 | 제목·본문 검색 화면 열기 |
| 노트 ID로 열기 | UUID로 기존 노트 열기 |

명령은 먼저 `~/Applications/Ray Notes.app`을 찾고, 없으면 이 저장소의 `build/Ray Notes.app`을 사용합니다. 다른 위치의 번들을 시험할 때는 Raycast Script Command 환경에 `RAY_NOTES_APP`을 해당 `.app` 경로로 설정할 수 있습니다. 앱을 찾지 못하면 명확한 오류로 끝나며 빈 앱 인스턴스를 만들지 않습니다.

## 데이터, 백업, 복구

기본 저장 위치는 `~/Library/Application Support/Ray Notes/notes`입니다. 각 노트는 UUID를 파일명으로 하는 JSON이며 Markdown 문서·생성·수정 시각을 보존합니다. 새 문서는 `formatVersion: 2`를 사용합니다. 테스트는 `RAY_NOTES_DATA_DIR`로 별도 디렉터리를 지정할 수 있습니다.

저장은 문서 변경 뒤 자동으로 수행됩니다. 저장 중·완료·실패 상태는 창에 표시됩니다. 원자적 임시 파일 교체로 기존 파일을 보존하고, 기존 파일이 있을 때는 최신 직전본을 `<UUID>.json.bak`으로 둡니다. 기본 JSON을 읽지 못하면 이 백업을 읽습니다. 실패한 경우 현재 편집 내용은 메모리에 남아 재시도할 수 있습니다.

기존 형식의 노트(`formatVersion` 없음)는 처음 열 때 파일을 바꾸지 않고 `# 기존 제목`과 본문을 한 문서로 보여 줍니다. 사용자가 편집한 시점에만 제목을 첫 H1에서 다시 읽어 `formatVersion: 2` 문서로 저장합니다. 이때 기존 파일은 `.json.bak`으로 남습니다. 자동 일괄 마이그레이션은 하지 않습니다.

- 삭제한 노트는 같은 JSON의 `isTrashed` 상태로 휴지통에 보관하며 앱의 휴지통에서 복구할 수 있습니다.
- 앱의 내보내기 메뉴로 노트를 일반 텍스트 또는 Markdown 파일로 저장할 수 있습니다.
- 전체 백업은 앱을 종료한 뒤 `~/Library/Application Support/Ray Notes` 폴더를 안전한 위치로 복사합니다. 복구는 현재 폴더를 먼저 백업한 후 복사본으로 교체합니다.

창은 메모에 집중할 수 있도록 작은 크기로 시작하며, 목록은 기본으로 접혀 있습니다. 도구 모음의 목록 버튼이나 단축키로 목록을 열고 닫을 수 있습니다. 창을 닫으면 편집 내용을 저장하고 창만 닫습니다. 앱 종료 전에도 저장을 시도하며, 앱을 직접 다시 열면 최근 노트를 복원합니다. 다음 Raycast 호출은 그 명령이 지정한 새·최근·검색·UUID 노트를 엽니다. 창 크기와 위치 복원은 구현되어 있으나 실제 UI 검증은 아직 수행하지 않았습니다.

## 키보드

제목은 편집기 첫 줄의 H1(`# 제목`)입니다. 본문은 같은 편집기에서 계속 입력합니다. H1의 `# ` 접두사는 화면에서 숨기지만 원문은 그대로 유지합니다. 굵게·기울임·취소선·글머리표·체크리스트·인라인 코드·인용문 표기를 읽기 쉽게 표시합니다. 체크리스트의 원문 표기(`- [ ]`, `- [x]`)는 숨긴 원형 토글로 표시하며, 원을 클릭하면 원문도 그 상태로 바뀝니다. Markdown 원문을 그대로 저장·내보내며 전체 CommonMark 렌더러나 별도 미리보기는 제공하지 않습니다.

Enter는 글머리표·체크리스트·번호 목록을 다음 줄에 이어 쓰고 중첩 들여쓰기를 유지합니다. 빈 목록 항목에서 Enter를 누르면 목록을 끝냅니다. 코드 펜스 안에서는 목록을 만들지 않고 들여쓰기만 유지합니다.

- `⌘N`: 새 메모
- `⌘⇧N`: 회의 노트
- `⌘F`: 목록을 열고 검색에 포커스
- `⌘L`: 목록 열기
- `⌘⇧L`: 목록 열기/닫기
- `Tab`: 현재 목록 항목 전체를 두 칸 들여쓰기
- `⇧Tab`: 현재 목록 항목 전체를 두 칸 내어쓰기

도구 모음에서도 목록 열기/닫기, 새 메모, 고정을 사용할 수 있습니다. 텍스트 입력 중에는 IME 조합을 단축키나 저장으로 강제로 확정하지 않습니다. 전역 단축키와 항상 위 표시는 기본 흐름에 필요하지 않아 접근성 권한을 요청하지 않습니다.

목록의 원문 들여쓰기는 Markdown 호환 두 칸 공백이며, 일반 탭 표시는 14pt 간격으로 설정했습니다.

## 검증 상태와 제한

현재 검증 기록은 [docs/verification.md](docs/verification.md)에 있습니다. 개인 메모 UI, Markdown 표시·내보내기, Raycast 재호출, 저장 실패 주입 결과를 포함합니다. live IME 조합 검증과 여러 앱·Space 사이의 고정 상태 검증은 아직 대기 상태입니다.

앱은 AppKit의 URL 열기 위임 경로로 요청을 받습니다. 이 동작의 공개 API는 Apple의 [application(_:open:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)) 문서에서 확인할 수 있습니다.

초기 범위에는 Raycast Notes 데이터 이전, AI 요약, 녹음·전사, 협업, 계정, 모바일 앱, 클라우드 동기화가 포함되지 않습니다.
