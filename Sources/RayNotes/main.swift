import AppKit
import RayNotesCore

final class NotesTableView: NSTableView {
    var openSelection: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { openSelection?(); return }
        super.keyDown(with: event)
    }
}

final class NotesRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let color = isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.selectedControlColor.withAlphaComponent(0.35)
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    private var store: NoteStore!
    private var window: NSWindow!
    private var editor: NSTextView!
    private var sidebarButton: NSButton!
    private var pinButton: NSButton!
    private var split: NSSplitView!
    private var sidebar: NSView!
    private var list: NSTableView!
    private var status: NSTextField!
    private var notes: [Note] = []
    private var current: Note?
    private var dirty = false
    private var saving = false
    private var isLoading = false
    private var searchField: NSSearchField!
    private var debounce: Timer?
    private var pendingRoutes: [NoteRoute] = []
    private var pendingRouteErrors: [String] = []
    private var receivedRoute = false
    private var isSelectingProgrammatically = false
    private var showingTrash = false
    private var sidebarVisible = false
    func applicationDidFinishLaunching(_ notification: Notification) { do { store = try NoteStore(); buildWindow(); refresh(); let routes = pendingRoutes; pendingRoutes.removeAll(); routes.forEach(handle); if let message = pendingRouteErrors.first { status.stringValue = message }; DispatchQueue.main.async { [weak self] in guard let self, !self.receivedRoute, self.current == nil, let recent = try? self.store.all().first else { return }; self.show(recent) } } catch { showFatal(error) } }
    func application(_ application: NSApplication, open urls: [URL]) { receivedRoute = true; for url in urls { do { let route = try RouteParser.parse(url); if store == nil { pendingRoutes.append(route) } else { handle(route) } } catch { let message = "지원하지 않는 Ray Notes 요청입니다: \(url.absoluteString)"; if store == nil { pendingRouteErrors.append(message) } else { status.stringValue = message; window.makeKeyAndOrderFront(nil) } } } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { flush(); return dirty ? .terminateCancel : .terminateNow }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flush(); guard !dirty else { return false }; sender.orderOut(nil); return false }
    private func buildWindow() {
        let fallback: NSRect = { let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800); return NSRect(x: screen.maxX - 430, y: screen.midY - 280, width: 430, height: 560) }()
        let frame = UserDefaults.standard.string(forKey: "compactWindowFrameV2").map(NSRectFromString) ?? fallback
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false); window.title = "Ray Notes"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.backgroundColor = .textBackgroundColor; window.delegate = self; window.minSize = NSSize(width: 400, height: 400)
        split = NSSplitView(frame: window.contentView!.bounds); split.autoresizingMask = [.width, .height]; split.isVertical = true; split.dividerStyle = .thin; window.contentView!.addSubview(split)
        sidebar = NSView(); sidebar.wantsLayer = true; sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; let detail = NSView(); detail.wantsLayer = true; detail.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor; split.addArrangedSubview(sidebar); split.addArrangedSubview(detail); split.adjustSubviews(); split.setPosition(230, ofDividerAt: 0); sidebar.isHidden = true; split.adjustSubviews()
        let sidebarTitle = NSTextField(labelWithString: "메모"); sidebarTitle.font = .systemFont(ofSize: 15, weight: .semibold); sidebarTitle.frame = NSRect(x: 14, y: sidebar.bounds.height - 27, width: 170, height: 18); sidebarTitle.autoresizingMask = [.minYMargin]; sidebar.addSubview(sidebarTitle)
        searchField = NSSearchField(frame: NSRect(x: 12, y: sidebar.bounds.height - 58, width: 246, height: 26)); searchField.autoresizingMask = [.width, .minYMargin]; searchField.placeholderString = "메모 검색"; searchField.target = self; searchField.action = #selector(searchChanged); sidebar.addSubview(searchField)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: sidebar.bounds.width, height: sidebar.bounds.height - 68)); scroll.drawsBackground = false; scroll.autoresizingMask = [.width, .height]; let noteList = NotesTableView(frame: NSRect(origin: .zero, size: scroll.contentSize)); noteList.autoresizingMask = [.width]; noteList.rowHeight = 48; noteList.intercellSpacing = NSSize(width: 0, height: 3); noteList.selectionHighlightStyle = .none; noteList.openSelection = { [weak self] in self?.openSelectedFromList() }; list = noteList; let col = NSTableColumn(identifier: .init("title")); col.title = "최근 노트"; col.width = 260; col.minWidth = 100; col.resizingMask = .autoresizingMask; list.addTableColumn(col); list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; list.headerView = nil; list.delegate = self; list.dataSource = self; list.target = self; list.doubleAction = #selector(selectRow); scroll.documentView = list; scroll.hasVerticalScroller = true; sidebar.addSubview(scroll)
        let toolbar = NSView(frame: NSRect(x: 12, y: detail.bounds.height - 38, width: detail.bounds.width - 24, height: 28)); toolbar.autoresizingMask = [.width, .minYMargin]; detail.addSubview(toolbar)
        let toggle = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "목록 열기")!, target: self, action: #selector(toggleSidebar)); toggle.toolTip = "목록 열기"; sidebarButton = toggle; toggle.frame = NSRect(x: 0, y: 0, width: 28, height: 28); toggle.bezelStyle = .texturedRounded; toolbar.addSubview(toggle)
        let add = NSButton(image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "새 메모")!, target: self, action: #selector(newNote)); add.frame = NSRect(x: 34, y: 0, width: 28, height: 28); add.bezelStyle = .texturedRounded; toolbar.addSubview(add)
        let pin = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: "항상 위 켜기")!, target: self, action: #selector(toggleFloating)); pin.toolTip = "항상 위 켜기"; pinButton = pin; pin.frame = NSRect(x: 68, y: 0, width: 28, height: 28); pin.bezelStyle = .texturedRounded; toolbar.addSubview(pin)
        let editScroll = NSScrollView(frame: NSRect(x: 0, y: 25, width: detail.bounds.width, height: detail.bounds.height - 70)); editScroll.drawsBackground = false; editScroll.autoresizingMask = [.width, .height]; editor = MarkdownTextView(frame: NSRect(origin: .zero, size: editScroll.contentSize)); editor.autoresizingMask = [.width]; editor.minSize = NSSize(width: 0, height: editScroll.contentSize.height); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.textContainer?.widthTracksTextView = true; editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.font = .systemFont(ofSize: 16); editor.textColor = .labelColor; editor.backgroundColor = .textBackgroundColor; editor.delegate = self; editor.allowsUndo = true; editor.textContainerInset = NSSize(width: 26, height: 20); editScroll.documentView = editor; editScroll.hasVerticalScroller = true; detail.addSubview(editScroll)
        status = NSTextField(labelWithString: "준비됨"); status.font = .systemFont(ofSize: 11); status.frame = NSRect(x: 26, y: 7, width: detail.bounds.width - 52, height: 16); status.autoresizingMask = [.width, .maxYMargin]; status.textColor = .secondaryLabelColor; detail.addSubview(status)
        let menu = NSMenu()
        let app = NSMenuItem(title: "Ray Notes", action: nil, keyEquivalent: ""); let appMenu = NSMenu(); appMenu.addItem(withTitle: "Ray Notes 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""); appMenu.addItem(NSMenuItem.separator()); appMenu.addItem(withTitle: "Ray Notes 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"); appMenu.addItem(withTitle: "기타 항목 숨기기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]; appMenu.addItem(withTitle: "모두 표시", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""); appMenu.addItem(NSMenuItem.separator()); appMenu.addItem(withTitle: "Ray Notes 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); app.submenu = appMenu; menu.addItem(app)
        let file = NSMenuItem(title: "파일", action: nil, keyEquivalent: ""); let submenu = NSMenu(); submenu.addItem(withTitle: "새 노트", action: #selector(newNote), keyEquivalent: "n"); let meeting = NSMenuItem(title: "회의 노트", action: #selector(newMeeting), keyEquivalent: "N"); meeting.keyEquivalentModifierMask = [.command, .shift]; submenu.addItem(meeting); submenu.addItem(withTitle: "내보내기", action: #selector(export), keyEquivalent: "e"); submenu.addItem(withTitle: "저장 재시도", action: #selector(retry), keyEquivalent: "s"); submenu.addItem(NSMenuItem.separator()); let trash = NSMenuItem(title: "휴지통으로 이동", action: #selector(moveToTrash), keyEquivalent: "\u{8}"); trash.keyEquivalentModifierMask = [.command]; submenu.addItem(trash); submenu.addItem(withTitle: "휴지통에서 복원", action: #selector(restoreCurrent), keyEquivalent: ""); file.submenu = submenu; menu.addItem(file)
        let edit = NSMenuItem(title: "편집", action: nil, keyEquivalent: ""); let editMenu = NSMenu(); editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z"); editMenu.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "Z").keyEquivalentModifierMask = [.command, .shift]; editMenu.addItem(NSMenuItem.separator()); editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x"); editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c"); editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"); edit.submenu = editMenu; menu.addItem(edit)
        let view = NSMenuItem(title: "보기", action: nil, keyEquivalent: ""); let viewMenu = NSMenu(); viewMenu.addItem(withTitle: "검색", action: #selector(focusSearch), keyEquivalent: "f"); viewMenu.addItem(withTitle: "목록으로 이동", action: #selector(focusList), keyEquivalent: "l"); let sidebarItem = NSMenuItem(title: "목록 표시 전환", action: #selector(toggleSidebar), keyEquivalent: "L"); sidebarItem.keyEquivalentModifierMask = [.command, .shift]; viewMenu.addItem(sidebarItem); viewMenu.addItem(withTitle: "휴지통 보기", action: #selector(toggleTrash), keyEquivalent: "t"); view.submenu = viewMenu; menu.addItem(view); NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowDidResize(_ notification: Notification) { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "compactWindowFrameV2") }
    func windowDidMove(_ notification: Notification) { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "compactWindowFrameV2") }
    func textDidChange(_ notification: Notification) { guard !isLoading else { return }; markDirty(); applyMarkdownStyling() }
    private func markDirty() { guard current != nil else { return }; dirty = true; status.stringValue = "저장 대기 중"; debounce?.invalidate(); debounce = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in self?.flush() } }
    private func flush() { guard dirty, !saving, let existing = current else { return }; if editor.hasMarkedText() { status.stringValue = "한글 입력을 마친 뒤 저장합니다"; return }; saving = true; status.textColor = .secondaryLabelColor; status.stringValue = "저장 중…"; var note = existing; note.applyEditedMarkdown(editor.string); note.updatedAt = Date(); do { try store.save(note); current = note; dirty = false; status.stringValue = "저장됨"; refresh(keeping: note.id) } catch { status.textColor = .systemRed; status.stringValue = "저장 실패 — ⌘S로 재시도" } ; saving = false }
    private func refresh(keeping: UUID? = nil) { do { let query = searchField?.stringValue ?? ""; notes = try (showingTrash ? store.all(includeTrashed: true).filter { $0.isTrashed && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)) } : store.search(query)); list?.reloadData(); if let id = keeping { selectInList(id) } } catch { status?.stringValue = "노트 파일을 읽지 못했습니다: \(error.localizedDescription)" } }
    private func selectInList(_ id: UUID) { guard let index = notes.firstIndex(where: { $0.id == id }) else { return }; isSelectingProgrammatically = true; list.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); isSelectingProgrammatically = false }
    private func show(_ note: Note) { if current?.id != note.id { flush(); guard !dirty else { if let current { selectInList(current.id) }; return } }; current = note; selectInList(note.id); isLoading = true; editor.string = note.editorMarkdown; applyMarkdownStyling(); editor.undoManager?.removeAllActions(); isLoading = false; status.stringValue = note.isTrashed ? "휴지통의 노트" : "저장됨"; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.makeFirstResponder(editor); editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0)) }
    private func handle(_ route: NoteRoute) { switch route { case .new(let meeting): create(meeting: meeting); case .recent: do { if let note = try store.all().first { show(note) } else { create(meeting: false) } } catch { status.stringValue = "최근 노트를 열지 못했습니다: \(error.localizedDescription)"; window.makeKeyAndOrderFront(nil) }; case .search(let q): setSidebarVisible(true); window.makeKeyAndOrderFront(nil); searchField.stringValue = q; refresh(); window.makeFirstResponder(searchField); case .open(let id): do { let note = try store.load(id); if !note.isTrashed { show(note) } } catch { status.stringValue = "노트를 열지 못했습니다: \(error.localizedDescription)" } } }
    private func create(meeting: Bool) { flush(); guard !dirty else { return }; let note = meeting ? Note.meeting() : Note(); do { try store.save(note); refresh(keeping: note.id); show(note) } catch { status.stringValue = "새 노트를 만들지 못했습니다: \(error.localizedDescription)" } }
    @objc private func newNote() { create(meeting: false) }
    @objc private func newMeeting() { create(meeting: true) }
    @objc private func selectRow() { let row = list.selectedRow; if notes.indices.contains(row) { show(notes[row]) } }
    private func openSelectedFromList() { selectRow() }
    @objc private func searchChanged() { refresh() }
    @objc private func focusSearch() { setSidebarVisible(true); window.makeFirstResponder(searchField) }
    @objc private func focusList() { setSidebarVisible(true); window.makeFirstResponder(list) }
    @objc private func toggleSidebar() { setSidebarVisible(!sidebarVisible) }
    private func setSidebarVisible(_ visible: Bool) { guard sidebarVisible != visible else { return }; let old = window.frame; let delta: CGFloat = 230; let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? old; let targetWidth = visible ? min(old.width + delta, screen.width) : max(430, old.width - delta); let target = NSRect(x: old.maxX - targetWidth, y: old.origin.y, width: targetWidth, height: old.height); window.setFrame(target, display: true, animate: true); sidebarVisible = visible; sidebar.isHidden = !visible; split.adjustSubviews(); if visible { split.setPosition(230, ofDividerAt: 0) } else { window.makeFirstResponder(editor) }; let label = visible ? "목록 닫기" : "목록 열기"; sidebarButton.setAccessibilityLabel(label); sidebarButton.toolTip = label; UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "compactWindowFrameV2") }
    @objc private func toggleFloating() { let floating = window.level != .floating; window.level = floating ? .floating : .normal; let label = floating ? "항상 위 끄기" : "항상 위 켜기"; pinButton.setAccessibilityLabel(label); pinButton.toolTip = label; status.stringValue = floating ? "항상 위" : "일반 창" }
    private func applyMarkdownStyling() { MarkdownStyler.apply(to: editor) }
    @objc private func retry() { flush() }
    @objc private func moveToTrash() { flush(); guard !dirty, let note = current else { return }; do { try store.trash(note.id); current = nil; refresh(); if let first = notes.first { show(first) } else { editor.string = ""; status.stringValue = "휴지통으로 이동했습니다" } } catch { status.stringValue = "휴지통 이동 실패: \(error.localizedDescription)" } }
    @objc private func restoreCurrent() { flush(); guard !dirty, let note = current, note.isTrashed else { status.stringValue = "휴지통의 노트를 선택하세요"; return }; do { try store.restore(note.id); showingTrash = false; if let restored = try? store.load(note.id) { refresh(keeping: note.id); show(restored) } } catch { status.stringValue = "복원 실패: \(error.localizedDescription)" } }
    @objc private func toggleTrash() { flush(); guard !dirty else { return }; showingTrash.toggle(); refresh(); status.stringValue = showingTrash ? "휴지통 — 선택한 노트는 파일 메뉴에서 복구할 수 있습니다" : "최근 노트" }
    @objc private func export() { guard let existing = current else { return }; flush(); var snapshot = existing; snapshot.applyEditedMarkdown(editor.string); let panel = NSSavePanel(); panel.nameFieldStringValue = "\(snapshot.title).md"; panel.allowedContentTypes = [.plainText]; if panel.runModal() == .OK, let url = panel.url { do { try store.export(snapshot, to: url); status.stringValue = dirty ? "저장되지 않은 현재 내용을 내보냈습니다" : "내보냈습니다" } catch { status.stringValue = "내보내기 실패: \(error.localizedDescription)" } } }
    private func showFatal(_ error: Error) { let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil) }
}
extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { NotesRowView() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { let id = NSUserInterfaceItemIdentifier("cell"); let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView(); cell.identifier = id; if cell.textField == nil { let text = NSTextField(labelWithString: ""); text.font = .systemFont(ofSize: 13, weight: .semibold); text.frame = NSRect(x: 12, y: 25, width: 220, height: 16); text.lineBreakMode = .byTruncatingTail; cell.addSubview(text); cell.textField = text; let preview = NSTextField(labelWithString: ""); preview.identifier = NSUserInterfaceItemIdentifier("preview"); preview.font = .systemFont(ofSize: 11); preview.textColor = .secondaryLabelColor; preview.frame = NSRect(x: 12, y: 8, width: 220, height: 14); preview.lineBreakMode = .byTruncatingTail; cell.addSubview(preview) }; cell.textField?.stringValue = notes[row].title; let preview = cell.subviews.first { $0.identifier == NSUserInterfaceItemIdentifier("preview") } as? NSTextField; preview?.stringValue = notes[row].body.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces); return cell }
    func tableViewSelectionDidChange(_ notification: Notification) { guard !isSelectingProgrammatically else { return }; let row = list.selectedRow; if notes.indices.contains(row) { show(notes[row]) } }
}
let delegate = AppDelegate(); NSApplication.shared.delegate = delegate; NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.run()
