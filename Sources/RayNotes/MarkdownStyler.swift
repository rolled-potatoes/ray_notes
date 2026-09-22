import AppKit

enum MarkdownStyler {
    static func apply(to textView: NSTextView) {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let undo = textView.undoManager; undo?.disableUndoRegistration(); defer { undo?.enableUndoRegistration() }
        let whole = NSRange(location: 0, length: storage.length)
        let base = NSFont.systemFont(ofSize: 15)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.tabStops = []; paragraph.defaultTabInterval = 14
        storage.removeAttribute(.font, range: whole)
        storage.removeAttribute(.foregroundColor, range: whole)
        storage.removeAttribute(.strikethroughStyle, range: whole)
        storage.removeAttribute(.backgroundColor, range: whole)
        storage.addAttribute(.font, value: base, range: whole)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: whole)
        textView.typingAttributes = [.font: base, .foregroundColor: NSColor.labelColor]
        let source = storage.string as NSString
        let muted = NSColor.secondaryLabelColor
        var fenced: [NSRange] = []
        regex("(?s)```.*?```").matches(in: storage.string, range: whole).forEach { match in
            fenced.append(match.range)
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor], range: match.range)
            muteMarkers("```", in: match.range, source: source, storage: storage, color: muted)
        }
        source.enumerateSubstrings(in: whole, options: .byLines) { line, range, _, _ in
            guard let line else { return }
            if fenced.contains(where: { NSIntersectionRange($0, range).length > 0 }) { return }
            let prefix = line.prefix { $0 == "#" }
            if !prefix.isEmpty, line.dropFirst(prefix.count).first == " " {
                let headingStyle = paragraph.mutableCopy() as! NSMutableParagraphStyle; headingStyle.paragraphSpacingBefore = 10; headingStyle.paragraphSpacing = 6
                storage.addAttributes([.font: NSFont.systemFont(ofSize: CGFloat(max(18, 30 - prefix.count * 2)), weight: .semibold), .paragraphStyle: headingStyle], range: range)
                let marker = NSRange(location: range.location, length: prefix.count + 1)
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.1)], range: marker)
            }
            if line.hasPrefix("> ") { storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: range.location, length: 2)) }
            if let marker = line.range(of: "- [") {
                let offset = line.distance(from: line.startIndex, to: marker.lowerBound)
                let markerRange = NSRange(location: range.location + offset, length: min(5, line.distance(from: marker.lowerBound, to: line.endIndex)))
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                    let contentStart = markerRange.location + markerRange.length
                    storage.addAttributes([.foregroundColor: muted, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: contentStart, length: max(0, range.location + range.length - contentStart)))
                }
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: markerRange)
                storage.removeAttribute(.strikethroughStyle, range: markerRange)
            }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: range.location, length: 2)) }
        }
        for match in regex("\\*\\*([^*]+)\\*\\*").matches(in: storage.string, range: whole) where !inside(match.range, fenced) {
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: match.range)
            muteEnds(match.range, count: 2, storage: storage, color: muted)
        }
        for match in regex("(?<!\\*)\\*([^*]+)\\*(?!\\*)").matches(in: storage.string, range: whole) where !inside(match.range, fenced) {
            storage.addAttribute(.font, value: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask), range: match.range)
            muteEnds(match.range, count: 1, storage: storage, color: muted)
        }
        for match in regex("~~(.+?)~~").matches(in: storage.string, range: whole) where !inside(match.range, fenced) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            muteEnds(match.range, count: 2, storage: storage, color: muted)
        }
        for match in regex("`([^`]+)`").matches(in: storage.string, range: whole) where !inside(match.range, fenced) {
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor], range: match.range)
            muteEnds(match.range, count: 1, storage: storage, color: muted)
        }
    }
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    private static func inside(_ range: NSRange, _ ranges: [NSRange]) -> Bool { ranges.contains { NSIntersectionRange(range, $0).length > 0 } }
    private static func muteEnds(_ range: NSRange, count: Int, storage: NSTextStorage, color: NSColor) { storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: range.location, length: count)); storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: range.location + range.length - count, length: count)) }
    private static func muteMarkers(_ marker: String, in range: NSRange, source: NSString, storage: NSTextStorage, color: NSColor) { var search = range; while search.length > 0 { let found = source.range(of: marker, options: [], range: search); guard found.location != NSNotFound else { break }; storage.addAttribute(.foregroundColor, value: color, range: found); let next = found.location + found.length; search = NSRange(location: next, length: range.location + range.length - next) } }
}
