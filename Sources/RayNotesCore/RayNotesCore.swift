import Foundation

public struct Note: Codable, Identifiable, Equatable, Sendable {
    public static let markdownFormatVersion = 2
    public var id: UUID
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isTrashed: Bool
    public var isPinned: Bool
    /// Missing in pre-markdown files. Reading such a note never changes it on disk.
    public var formatVersion: Int?

    public init(id: UUID = UUID(), title: String = "메모", body: String = "# 메모\n\n", createdAt: Date = Date(), updatedAt: Date = Date(), isTrashed: Bool = false, isPinned: Bool = false, formatVersion: Int? = Note.markdownFormatVersion) {
        self.id = id; self.title = title; self.body = body; self.createdAt = createdAt; self.updatedAt = updatedAt; self.isTrashed = isTrashed; self.isPinned = isPinned; self.formatVersion = formatVersion
    }

    public var isMarkdownDocument: Bool { (formatVersion ?? 0) >= Self.markdownFormatVersion }
    public static func title(fromMarkdown markdown: String) -> String {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") { let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty { return title } }
        }
        return "제목 없음"
    }
    /// View-only conversion for old title/body JSON. It is persisted only after editing.
    public var editorMarkdown: String {
        guard !isMarkdownDocument else { return body }
        let first = body.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if first.trimmingCharacters(in: .whitespaces).hasPrefix("# ") { return body }
        return "# \(title)\n\n\(body)"
    }
    public mutating func applyEditedMarkdown(_ markdown: String) { body = markdown; title = Self.title(fromMarkdown: markdown); formatVersion = max(formatVersion ?? 0, Self.markdownFormatVersion) }

    public static func meeting(now: Date = Date()) -> Note {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "yyyy년 M월 d일"
        return Note(title: "회의 노트", body: "# 회의\n\n- 날짜: \(formatter.string(from: now))\n- 참석자: \n\n## 안건\n\n\n## 논의 내용\n\n\n## 결정 사항\n\n\n## 액션 아이템\n\n")
    }
}

public enum NoteRoute: Equatable, Sendable {
    case new(meeting: Bool), recent, search(String), open(UUID)
}

public enum RouteError: Error, Equatable { case unsupported, invalidIdentifier }

public enum RouteParser {
    public static func parse(_ url: URL) throws -> NoteRoute {
        guard url.scheme?.lowercased() == "raynotes" else { throw RouteError.unsupported }
        let host = url.host?.lowercased() ?? ""
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch host {
        case "new": return .new(meeting: items.first(where: { $0.name == "template" })?.value == "meeting")
        case "recent": return .recent
        case "search": return .search(items.first(where: { $0.name == "q" })?.value ?? "")
        case "open":
            guard let value = items.first(where: { $0.name == "id" })?.value, let id = UUID(uuidString: value) else { throw RouteError.invalidIdentifier }
            return .open(id)
        default: throw RouteError.unsupported
        }
    }
}

public enum NoteStoreError: Error, LocalizedError, Equatable {
    case cannotCreateDirectory(String), invalidData(String), writeFailed(String), noteNotFound
    public var errorDescription: String? { switch self { case .cannotCreateDirectory(let s), .invalidData(let s), .writeFailed(let s): return s; case .noteNotFound: return "노트를 찾을 수 없습니다." } }
}

public final class NoteStore: @unchecked Sendable {
    public let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory { self.directory = directory }
        else if let overridden = ProcessInfo.processInfo.environment["RAY_NOTES_DATA_DIR"], !overridden.isEmpty { self.directory = URL(fileURLWithPath: overridden, isDirectory: true) }
        else { self.directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Ray Notes/notes", isDirectory: true) }
        self.encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        do { try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true) } catch { throw NoteStoreError.cannotCreateDirectory(error.localizedDescription) }
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private func backup(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json.bak") }
    public func save(_ note: Note) throws {
        let target = file(note.id); let backup = backup(note.id)
        do {
            let data = try encoder.encode(note)
            if fileManager.fileExists(atPath: target.path) {
                // A recovered backup must never be replaced by bytes from a corrupt primary.
                guard (try? decoder.decode(Note.self, from: Data(contentsOf: target))) != nil else {
                    throw NoteStoreError.invalidData("원본 노트 파일이 손상되어 자동 저장을 중단했습니다. 현재 내용을 내보내고 원본을 복구하세요.")
                }
                let temporaryBackup = directory.appendingPathComponent(".\(note.id.uuidString).backup-\(UUID().uuidString)")
                try fileManager.copyItem(at: target, to: temporaryBackup)
                do {
                    if fileManager.fileExists(atPath: backup.path) { _ = try fileManager.replaceItemAt(backup, withItemAt: temporaryBackup) }
                    else { try fileManager.moveItem(at: temporaryBackup, to: backup) }
                } catch { try? fileManager.removeItem(at: temporaryBackup); throw error }
            }
            try data.write(to: target, options: .atomic)
        } catch let error as NoteStoreError { throw error }
        catch { throw NoteStoreError.writeFailed(error.localizedDescription) }
    }
    public func load(_ id: UUID) throws -> Note {
        let target = file(id)
        guard fileManager.fileExists(atPath: target.path) else { throw NoteStoreError.noteNotFound }
        do { return try decoder.decode(Note.self, from: Data(contentsOf: target)) }
        catch {
            let backup = backup(id)
            guard fileManager.fileExists(atPath: backup.path) else { throw NoteStoreError.invalidData("노트 파일이 손상되었습니다: \(target.lastPathComponent)") }
            do { return try decoder.decode(Note.self, from: Data(contentsOf: backup)) }
            catch { throw NoteStoreError.invalidData("노트와 백업 파일을 읽을 수 없습니다: \(target.lastPathComponent)") }
        }
    }
    public func all(includeTrashed: Bool = false) throws -> [Note] {
        let urls: [URL]
        do { urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" } } catch { throw NoteStoreError.invalidData(error.localizedDescription) }
        var notes: [Note] = []
        for url in urls { guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }; let note = try load(id); if includeTrashed || !note.isTrashed { notes.append(note) } }
        return notes.sorted { ($0.isPinned == $1.isPinned) ? $0.updatedAt > $1.updatedAt : $0.isPinned }
    }
    public func search(_ query: String) throws -> [Note] { let q = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current); return try all().filter { q.isEmpty || $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(q) || $0.body.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(q) } }
    public func trash(_ id: UUID) throws { var note = try load(id); note.isTrashed = true; note.updatedAt = Date(); try save(note) }
    public func restore(_ id: UUID) throws { var note = try load(id); note.isTrashed = false; note.updatedAt = Date(); try save(note) }
    public func export(_ note: Note, to url: URL) throws { do { let markdown = note.isMarkdownDocument ? note.body : note.editorMarkdown; try markdown.data(using: .utf8)!.write(to: url, options: .atomic) } catch { throw NoteStoreError.writeFailed(error.localizedDescription) } }
}
