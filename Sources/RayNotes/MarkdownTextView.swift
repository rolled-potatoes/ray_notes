import AppKit
import RayNotesCore

final class MarkdownTextView: NSTextView {
    private var handlingMarkdownNewline = false
    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)), !hasMarkedText(), insertMarkdownNewline() { return }
        if selector == #selector(insertTab(_:)), !hasMarkedText(), applyListIndent(outdent: false) { return }
        if selector == #selector(insertBacktab(_:)), !hasMarkedText(), applyListIndent(outdent: true) { return }
        super.doCommand(by: selector)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if !handlingMarkdownNewline, let text = insertString as? String, text == "\n", !hasMarkedText() {
            if insertMarkdownNewline() { return }
        }
        handlingMarkdownNewline = true
        super.insertText(insertString, replacementRange: replacementRange)
        handlingMarkdownNewline = false
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager, let container = textContainer else { return }
        let source = string as NSString
        let regex = try! NSRegularExpression(pattern: "(?m)^[\\t ]*- \\[([ xX])\\]")
        for match in regex.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            let line = source.substring(with: match.range)
            let offset = (line as NSString).range(of: "- [").location
            let markerRange = NSRange(location: match.range.location + offset, length: 5)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard rect.intersects(dirtyRect) else { continue }
            let circle = NSRect(x: rect.minX + 4, y: rect.midY - 6, width: 12, height: 12)
            NSColor.secondaryLabelColor.setStroke(); let path = NSBezierPath(ovalIn: circle); path.lineWidth = 1.2; path.stroke()
            let state = source.substring(with: match.range).contains("[x]") || source.substring(with: match.range).contains("[X]")
            if state { NSColor.secondaryLabelColor.setFill(); path.fill(); NSColor.textBackgroundColor.setStroke(); let check = NSBezierPath(); check.move(to: NSPoint(x: circle.minX + 2, y: circle.midY)); check.line(to: NSPoint(x: circle.minX + 5, y: circle.minY + 3)); check.line(to: NSPoint(x: circle.maxX - 2, y: circle.maxY - 3)); check.lineWidth = 1.5; check.stroke() }
        }
    }
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertNewline(sender); return }
        if insertMarkdownNewline() { return }
        super.insertNewline(sender)
    }
    private func insertMarkdownNewline() -> Bool {
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: min(caret, ns.length), length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let before = ns.substring(to: min(caret, ns.length))
        if MarkdownEditing.isInsideFencedCode(before: before) {
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let replacement = "\n\(indent)"
            let range = selectedRange()
            guard shouldChangeText(in: range, replacementString: replacement) else { return true }
            textStorage?.replaceCharacters(in: range, with: replacement)
            setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
            didChangeText()
            return true
        }
        if let indent = MarkdownEditing.emptyListIndent(for: line) {
            let replacement = "\(indent)\n"
            guard shouldChangeText(in: lineRange, replacementString: replacement) else { return true }
            textStorage?.replaceCharacters(in: lineRange, with: replacement)
            setSelectedRange(NSRange(location: lineRange.location + replacement.utf16.count, length: 0))
            didChangeText()
            return true
        }
        if let next = MarkdownEditing.continuation(for: line) {
            let replacement = "\n\(next)"
            let range = selectedRange()
            guard shouldChangeText(in: range, replacementString: replacement) else { return true }
            handlingMarkdownNewline = true
            textStorage?.replaceCharacters(in: range, with: replacement)
            setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
            didChangeText()
            handlingMarkdownNewline = false
            return true
        }
        return false
    }
    private func applyListIndent(outdent: Bool) -> Bool {
        guard let edit = MarkdownEditing.listIndentEdit(document: string, selection: selectedRange(), outdent: outdent) else { return false }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return true }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        setSelectedRange(edit.selection)
        didChangeText()
        return true
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        guard index <= ns.length else { super.mouseDown(with: event); return }
        let lineRange = ns.lineRange(for: NSRange(location: min(index, ns.length), length: 0))
        let line = ns.substring(with: lineRange)
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        let checkboxRange = NSRange(location: lineRange.location + leading, length: min(5, lineRange.length - leading))
        if NSLocationInRange(index, checkboxRange), let toggled = MarkdownEditing.toggledChecklistLine(line) {
            guard shouldChangeText(in: lineRange, replacementString: toggled) else { return }
            replaceCharacters(in: lineRange, with: toggled)
            didChangeText()
            return
        }
        super.mouseDown(with: event)
    }
}
