import Foundation

public enum MarkdownEditing {
    public struct LineIndentEdit: Equatable, Sendable { public let range: NSRange; public let replacement: String; public let selection: NSRange }
    public static func listIndentEdit(document: String, selection: NSRange, outdent: Bool, unit: String = "  ") -> LineIndentEdit? {
        let ns = document as NSString
        guard selection.location <= ns.length else { return nil }
        let selected = NSRange(location: selection.location, length: min(selection.length, ns.length - selection.location))
        let first = ns.lineRange(for: NSRange(location: selected.location, length: 0)).location
        let rawEnd = selected.length == 0 ? selected.location : NSMaxRange(selected)
        let endLocation = selected.length > 0 && rawEnd > selected.location && rawEnd < ns.length && ns.substring(with: NSRange(location: rawEnd - 1, length: 1)) == "\n" ? rawEnd - 1 : rawEnd
        let lastRange = ns.lineRange(for: NSRange(location: min(endLocation, ns.length), length: 0))
        let range = NSRange(location: first, length: NSMaxRange(lastRange) - first)
        let original = ns.substring(with: range)
        let endsWithNewline = original.hasSuffix("\n")
        var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.allSatisfy({ line in let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines); return emptyListIndent(for: line) != nil || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") || trimmed.hasPrefix("- [") || trimmed.range(of: "^\\d+[.)]\\s+", options: .regularExpression) != nil }) else { return nil }
        var deltaBefore = 0
        let replacementBody = lines.enumerated().map { index, line -> String in
            let originalOffset = lines.prefix(index).map { ($0 as NSString).length + 1 }.reduce(0, +)
            if outdent {
                let remove = line.hasPrefix("\t") ? 1 : min(unit.count, line.prefix { $0 == " " }.count)
                if originalOffset < selection.location - range.location { deltaBefore -= remove }
                return String(line.dropFirst(remove))
            }
            if originalOffset < selection.location - range.location { deltaBefore += unit.utf16.count }
            return unit + line
        }.joined(separator: "\n")
        let replacement = replacementBody + (endsWithNewline ? "\n" : "")
        let totalDelta = (replacement as NSString).length - range.length
        return LineIndentEdit(range: range, replacement: replacement, selection: NSRange(location: max(range.location, selection.location + deltaBefore), length: max(0, selection.length + totalDelta)))
    }
    public static func emptyListIndent(for line: String) -> String? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = String(line.dropFirst(indent.count))
        let empty = ["-", "- ", "*", "* ", "+", "+ ", "- [ ]", "- [ ] ", "- [x]", "- [x] ", "- [X]", "- [X] "]
        return empty.contains(rest) || rest.range(of: "^\\d+[.)]\\s*$", options: .regularExpression) != nil ? indent : nil
    }
    public static func isInsideFencedCode(before text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count.isMultiple(of: 2) == false
    }
    public static func continuation(for line: String) -> String? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = String(line.dropFirst(indent.count))
        if emptyListIndent(for: line) != nil { return nil }
        if rest.hasPrefix("- [ ") || rest.hasPrefix("- [x]") || rest.hasPrefix("- [X]") { return indent + "- [ ] " }
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") { return indent + String(rest.prefix(2)) }
        if let match = try? NSRegularExpression(pattern: "^(\\d+)([.)])\\s+").firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)), let numberRange = Range(match.range(at: 1), in: rest), let suffixRange = Range(match.range(at: 2), in: rest), let number = Int(rest[numberRange]) { return "\(indent)\(number + 1)\(rest[suffixRange]) " }
        return nil
    }
    public static func toggledChecklistLine(_ line: String) -> String? {
        if let range = line.range(of: "- [ ]") { var copy = line; copy.replaceSubrange(range, with: "- [x]"); return copy }
        if let range = line.range(of: "- [x]") ?? line.range(of: "- [X]") { var copy = line; copy.replaceSubrange(range, with: "- [ ]"); return copy }
        return nil
    }
}
