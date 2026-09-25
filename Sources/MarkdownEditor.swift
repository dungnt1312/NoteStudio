import SwiftUI
import AppKit

// MARK: - Soạn thảo Markdown trực quan (kiểu Typora)
// Chữ trong textStorage luôn là Markdown thô (an toàn với bộ gõ Telex, undo, lưu file .md).
// Chỉ thuộc tính hiển thị thay đổi: ký hiệu markdown ẩn đi ở các dòng không có con trỏ,
// checkbox / gạch đầu dòng / thẻ khối mã / thanh trích dẫn do layout manager tự vẽ.

extension NSAttributedString.Key {
    static let mdHidden = NSAttributedString.Key("studio.md.hidden")
    static let mdList = NSAttributedString.Key("studio.md.list")            // "bullet" | "todo" | "done"
    static let mdQuote = NSAttributedString.Key("studio.md.quote")
    static let mdCodeBlock = NSAttributedString.Key("studio.md.codeBlock")  // Int: số thứ tự khối
    static let mdCodeLang = NSAttributedString.Key("studio.md.codeLang")    // String
    static let mdInlineCode = NSAttributedString.Key("studio.md.inlineCode")
    static let mdRule = NSAttributedString.Key("studio.md.rule")
    static let mdLink = NSAttributedString.Key("studio.md.link")            // String: url

    /// Thuộc tính trang trí không được "lây" sang chữ gõ tiếp
    static let markdownDecorations: [NSAttributedString.Key] = [
        .mdHidden, .mdList, .mdQuote, .mdCodeBlock, .mdCodeLang, .mdInlineCode, .mdRule, .mdLink, .toolTip,
        .underlineStyle, .strikethroughStyle
    ]
}

enum MarkdownTheme {
    static let body = NSFont.systemFont(ofSize: 15)
    static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let sourceFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    static let sourceBold = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
    static let label = NSFont.systemFont(ofSize: 11, weight: .medium)

    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: return .systemFont(ofSize: 28, weight: .bold)
        case 2: return .systemFont(ofSize: 21, weight: .bold)
        case 3: return .systemFont(ofSize: 17.5, weight: .semibold)
        default: return .systemFont(ofSize: 15.5, weight: .semibold)
        }
    }

    static func headingSpacingBefore(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 18
        case 3: return 14
        default: return 10
        }
    }

    static let text = NSColor.studioTextPrimary
    static let secondary = NSColor.dynamic(0x5D5D5D, 0xB4B4B4)
    static let marker = NSColor.dynamic(0xA3A3A3, 0x7C7C7C)
    static let link = NSColor.dynamic(0x0B65C4, 0x5CA3FF)
    static let codeText = NSColor.dynamic(0x1F1F1F, 0xE6E6E6)
    static let codeFill = NSColor.dynamic(0xF6F6F6, 0x2B2B2B)
    static let codeBorder = NSColor.dynamic(0xE8E8E8, 0x3A3A3A)
    static let inlineCodeFill = NSColor.dynamic(0xEEEEEE, 0x363636)
    static let quoteBar = NSColor.dynamic(0xD4D4D4, 0x4F4F4F)
    static let rule = NSColor.dynamic(0xE3E3E3, 0x3D3D3D)
    static let checkboxStroke = NSColor.dynamic(0x9B9B9B, 0x8C8C8C)
    static let checkboxFill = NSColor.dynamic(0x0D0D0D, 0xECECEC)
    static let checkmark = NSColor.dynamic(0xFFFFFF, 0x0D0D0D)
    static let done = NSColor.dynamic(0x8A8A8A, 0x8C8C8C)

    static let lineSpacing: CGFloat = 5
    static let listIndent: CGFloat = 24
    static let quoteIndent: CGFloat = 18
    static let codePadding: CGFloat = 16

    static func paragraph(first: CGFloat = 0, head: CGFloat? = nil, tail: CGFloat = 0,
                          spacing: CGFloat = lineSpacing, before: CGFloat = 0,
                          lineHeight: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = first
        style.headIndent = head ?? first
        style.tailIndent = tail
        style.lineSpacing = spacing
        style.paragraphSpacingBefore = before
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
        return style
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: text, .paragraphStyle: paragraph()]
    }

    static var sourceTypingAttributes: [NSAttributedString.Key: Any] {
        [.font: sourceFont, .foregroundColor: text, .paragraphStyle: paragraph(spacing: 4)]
    }
}

// MARK: - Styler: Markdown thô → thuộc tính hiển thị (không đổi một ký tự nào)

struct MarkdownStyler {
    /// false = chế độ Mã nguồn: hiện hết ký hiệu, font mono, không trang trí
    let live: Bool
    /// Dòng nào giao với vùng chọn thì hiện ký hiệu markdown để sửa
    let selection: NSRange

    static let lengthLimit = 400_000

    private enum Rx {
        static let fence = try! NSRegularExpression(pattern: "^\\s{0,3}(```|~~~)")
        static let heading = try! NSRegularExpression(pattern: "^(\\s{0,3})(#{1,6})(?: +|$)")
        static let rule = try! NSRegularExpression(pattern: "^\\s{0,3}((?:-\\s*){3,}|(?:\\*\\s*){3,}|(?:_\\s*){3,})$")
        static let quote = try! NSRegularExpression(pattern: "^\\s{0,3}> ?")
        static let list = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|\\d{1,9}[.)])( \\[[ xX]\\])?( +|$)")
        static let inlineCode = try! NSRegularExpression(pattern: "(`+)([^`\\n]+?)\\1")
        static let link = try! NSRegularExpression(pattern: "(!?\\[)([^\\]\\n]+)(\\]\\(([^()\\s]+)(?:\\s+\"[^\"]*\")?\\))")
        static let autolink = try! NSRegularExpression(pattern: "(?<![\\w/(\\[])https?://[^\\s<>()\\[\\]]+[^\\s<>()\\[\\].,;:!?'\"]")
        static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
        static let italicStar = try! NSRegularExpression(pattern: "(?<![*\\w])(\\*)(?=[^\\s*])([^*\\n]+?)(?<=[^\\s*])\\*(?![*\\w])")
        static let italicUnderscore = try! NSRegularExpression(pattern: "(?<![_\\w])(_)(?=[^\\s_])([^_\\n]+?)(?<=[^\\s_])_(?![_\\w])")
        static let strike = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)~~")
    }

    func styled(_ text: String) -> NSAttributedString {
        let ns = text as NSString
        let out = NSMutableAttributedString(string: text, attributes: MarkdownTheme.typingAttributes)
        guard ns.length > 0, ns.length <= Self.lengthLimit else {
            if !live { applySourceFonts(out) }
            return out
        }

        let lines = Self.lines(ns)
        var index = 0
        var blockIndex = 0
        var seenContent = false
        while index < lines.count {
            let line = lines[index]
            let string = ns.substring(with: line)
            if Self.matches(Rx.fence, string) {
                var end = index + 1
                while end < lines.count, !Self.matches(Rx.fence, ns.substring(with: lines[end])) { end += 1 }
                let last = min(end, lines.count - 1)
                styleCodeBlock(out, ns, lines: Array(lines[index...last]), index: blockIndex, closed: end < lines.count)
                blockIndex += 1
                seenContent = true
                index = last + 1
                continue
            }
            styleLine(out, string, range: line, total: ns.length, first: !seenContent)
            if !string.trimmingCharacters(in: .whitespaces).isEmpty { seenContent = true }
            index += 1
        }
        if !live { applySourceFonts(out) }
        return out
    }

    /// Khoảng nội dung từng dòng (không gồm ký tự xuống dòng)
    static func lines(_ ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var start = 0
        while start < ns.length {
            var lineStart = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            result.append(NSRange(location: lineStart, length: contentsEnd - lineStart))
            start = end
        }
        return result
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length)) != nil
    }

    private func isActive(_ range: NSRange) -> Bool {
        guard live else { return true }
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= NSMaxRange(range)
        }
        return NSIntersectionRange(selection, range).length > 0
            || (selection.location >= range.location && selection.location <= NSMaxRange(range))
    }

    /// Ký hiệu markdown: dòng đang sửa → xám nhạt; dòng khác → ẩn hẳn
    private func marker(_ out: NSMutableAttributedString, _ range: NSRange, hidden: Bool) {
        guard range.length > 0 else { return }
        if hidden {
            out.addAttribute(.mdHidden, value: true, range: range)
        } else {
            out.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: range)
        }
    }

    private func withNewline(_ range: NSRange, total: Int) -> NSRange {
        NSRange(location: range.location, length: min(range.length + 1, total - range.location))
    }

    // MARK: Dòng thường: tiêu đề, kẻ ngang, trích dẫn, danh sách, bảng, đoạn văn

    private func styleLine(_ out: NSMutableAttributedString, _ line: String, range: NSRange, total: Int, first: Bool) {
        let active = isActive(range)
        let l = line as NSString
        let whole = NSRange(location: 0, length: l.length)
        let paragraphRange = withNewline(range, total: total)
        func abs(_ r: NSRange) -> NSRange { NSRange(location: range.location + r.location, length: r.length) }

        if let m = Rx.heading.firstMatch(in: line, range: whole) {
            let level = m.range(at: 2).length
            let contentStart = NSMaxRange(m.range)
            out.addAttributes([
                .font: MarkdownTheme.heading(level),
                .paragraphStyle: MarkdownTheme.paragraph(spacing: 4, before: first ? 0 : MarkdownTheme.headingSpacingBefore(level))
            ], range: paragraphRange)
            marker(out, abs(NSRange(location: 0, length: contentStart)), hidden: !active)
            inline(out, l, base: range.location, from: contentStart, active: active)
            return
        }
        if Rx.rule.firstMatch(in: line, range: whole) != nil {
            if active || !live {
                out.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: range)
            } else {
                out.addAttribute(.mdHidden, value: true, range: range)
                out.addAttribute(.mdRule, value: true, range: range)
            }
            return
        }
        if let m = Rx.quote.firstMatch(in: line, range: whole) {
            let contentStart = NSMaxRange(m.range)
            out.addAttributes([
                .mdQuote: true,
                .foregroundColor: MarkdownTheme.secondary,
                .paragraphStyle: MarkdownTheme.paragraph(first: MarkdownTheme.quoteIndent)
            ], range: paragraphRange)
            marker(out, abs(NSRange(location: 0, length: contentStart)), hidden: !active)
            inline(out, l, base: range.location, from: contentStart, active: active)
            return
        }
        if let m = Rx.list.firstMatch(in: line, range: whole) {
            styleListItem(out, l, m, range: range, paragraphRange: paragraphRange, active: active)
            return
        }
        if line.hasPrefix("|") {
            out.addAttributes([.font: MarkdownTheme.mono, .foregroundColor: MarkdownTheme.secondary], range: range)
            return
        }
        inline(out, l, base: range.location, from: 0, active: active)
    }

    private func styleListItem(_ out: NSMutableAttributedString, _ l: NSString, _ m: NSTextCheckingResult,
                               range: NSRange, paragraphRange: NSRange, active: Bool) {
        func abs(_ r: NSRange) -> NSRange { NSRange(location: range.location + r.location, length: r.length) }
        let indentText = l.substring(with: m.range(at: 1))
        let width = indentText.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        let level = CGFloat(width / 2)
        let bullet = l.substring(with: m.range(at: 2))
        let box = m.range(at: 3).location == NSNotFound ? nil : l.substring(with: m.range(at: 3))
        let contentStart = NSMaxRange(m.range)
        let base = MarkdownTheme.listIndent * level

        // Thụt lề hiển thị bằng paragraph indent, không bằng khoảng trắng thật
        if m.range(at: 1).length > 0 {
            out.addAttribute(.mdHidden, value: true, range: abs(m.range(at: 1)))
        }

        if bullet.first?.isNumber == true {
            let label = bullet + " "
            let labelWidth = (label as NSString).size(withAttributes: [.font: MarkdownTheme.body]).width
            out.addAttribute(.paragraphStyle, value: MarkdownTheme.paragraph(first: base, head: base + labelWidth), range: paragraphRange)
            out.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: abs(m.range(at: 2)))
        } else if active {
            let markerText = l.substring(with: NSRange(location: m.range(at: 2).location, length: contentStart - m.range(at: 2).location))
            let markerWidth = (markerText as NSString).size(withAttributes: [.font: MarkdownTheme.body]).width
            out.addAttribute(.paragraphStyle, value: MarkdownTheme.paragraph(first: base, head: base + markerWidth), range: paragraphRange)
            out.addAttribute(.foregroundColor, value: MarkdownTheme.marker,
                             range: abs(NSRange(location: m.range(at: 2).location, length: contentStart - m.range(at: 2).location)))
        } else {
            let indent = base + MarkdownTheme.listIndent
            out.addAttribute(.paragraphStyle, value: MarkdownTheme.paragraph(first: indent), range: paragraphRange)
            out.addAttribute(.mdHidden, value: true, range: abs(NSRange(location: 0, length: contentStart)))
            let kind = box == nil ? "bullet" : (box!.lowercased().contains("x") ? "done" : "todo")
            out.addAttribute(.mdList, value: kind, range: range)
        }
        if let box, box.lowercased().contains("x"), contentStart < l.length {
            let content = abs(NSRange(location: contentStart, length: l.length - contentStart))
            out.addAttributes([
                .foregroundColor: MarkdownTheme.done,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: MarkdownTheme.done
            ], range: content)
        }
        inline(out, l, base: range.location, from: contentStart, active: active)
    }

    // MARK: Khối mã ``` … ```

    private func styleCodeBlock(_ out: NSMutableAttributedString, _ ns: NSString, lines: [NSRange], index: Int, closed: Bool) {
        guard let first = lines.first, let last = lines.last else { return }
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let active = isActive(block)
        let pad = MarkdownTheme.codePadding
        out.addAttributes([
            .font: MarkdownTheme.mono,
            .foregroundColor: MarkdownTheme.codeText,
            .mdCodeBlock: index,
            .paragraphStyle: MarkdownTheme.paragraph(first: pad, tail: -pad, spacing: 3)
        ], range: block)

        let fences = closed && lines.count > 1 ? [first, last] : [first]
        for fence in fences {
            if active || !live {
                out.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: fence)
            } else {
                out.addAttribute(.mdHidden, value: true, range: fence)
                // Dòng ``` ẩn chữ, chỉ còn làm lề trên/dưới của thẻ. Tính cả ký tự xuống dòng:
                // glyph "\n" vẫn mang font mono 13pt và sẽ đẩy chiều cao dòng lên nếu bỏ sót
                let line = NSRange(location: fence.location, length: min(fence.length + 1, ns.length - fence.location))
                out.addAttributes([
                    .font: NSFont.systemFont(ofSize: 4),
                    .paragraphStyle: MarkdownTheme.paragraph(first: pad, tail: -pad, spacing: 0, lineHeight: fence == first ? 22 : 18)
                ], range: line)
            }
        }
        let info = ns.substring(with: first)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`~"))
            .trimmingCharacters(in: .whitespaces)
        if live, !active {
            out.addAttribute(.mdCodeLang, value: info.isEmpty ? "Plain text" : info, range: first)
        }
    }

    // MARK: Inline: `code`, [link](url), **đậm**, *nghiêng*, ~~gạch~~

    private func inline(_ out: NSMutableAttributedString, _ l: NSString, base: Int, from: Int, active: Bool) {
        let length = l.length
        guard from < length else { return }
        let s = l as String
        let scope = NSRange(location: from, length: length - from)
        var consumed = [Bool](repeating: false, count: length)

        func abs(_ r: NSRange) -> NSRange { NSRange(location: base + r.location, length: r.length) }
        func take(_ r: NSRange) {
            guard r.location != NSNotFound else { return }
            for i in r.location..<min(NSMaxRange(r), length) { consumed[i] = true }
        }
        func free(_ r: NSRange) -> Bool {
            guard r.location != NSNotFound, NSMaxRange(r) <= length else { return false }
            for i in r.location..<NSMaxRange(r) where consumed[i] { return false }
            return true
        }
        func hide(_ r: NSRange) { marker(out, abs(r), hidden: !active) }
        func addTrait(_ trait: NSFontTraitMask, _ r: NSRange) {
            let target = abs(r)
            out.enumerateAttribute(.font, in: target) { value, sub, _ in
                let font = value as? NSFont ?? MarkdownTheme.body
                out.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
            }
        }
        func delimited(_ m: NSTextCheckingResult) -> (open: NSRange, content: NSRange, close: NSRange) {
            let open = m.range(at: 1)
            let content = m.range(at: 2)
            let close = NSRange(location: NSMaxRange(content), length: NSMaxRange(m.range) - NSMaxRange(content))
            return (open, content, close)
        }

        Rx.inlineCode.enumerateMatches(in: s, range: scope) { m, _, _ in
            guard let m, free(m.range) else { return }
            let d = delimited(m)
            out.addAttributes([.font: MarkdownTheme.mono, .foregroundColor: MarkdownTheme.codeText, .mdInlineCode: true], range: abs(d.content))
            hide(d.open); hide(d.close)
            take(m.range)
        }
        Rx.link.enumerateMatches(in: s, range: scope) { m, _, _ in
            guard let m, free(m.range) else { return }
            let url = l.substring(with: m.range(at: 4))
            out.addAttributes([
                .foregroundColor: MarkdownTheme.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .mdLink: url,
                .toolTip: "\(url)  (⌘ + bấm để mở)"
            ], range: abs(m.range(at: 2)))
            hide(m.range(at: 1)); hide(m.range(at: 3))
            take(m.range)
        }
        Rx.autolink.enumerateMatches(in: s, range: scope) { m, _, _ in
            guard let m, free(m.range) else { return }
            let url = l.substring(with: m.range)
            out.addAttributes([
                .foregroundColor: MarkdownTheme.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .mdLink: url,
                .toolTip: "\(url)  (⌘ + bấm để mở)"
            ], range: abs(m.range))
            take(m.range)
        }
        Rx.bold.enumerateMatches(in: s, range: scope) { m, _, _ in
            guard let m else { return }
            let d = delimited(m)
            guard free(d.open), free(d.close) else { return }
            addTrait(.boldFontMask, d.content)
            hide(d.open); hide(d.close)
            take(d.open); take(d.close)
        }
        for regex in [Rx.italicStar, Rx.italicUnderscore] {
            regex.enumerateMatches(in: s, range: scope) { m, _, _ in
                guard let m else { return }
                let d = delimited(m)
                guard free(d.open), free(d.close) else { return }
                addTrait(.italicFontMask, d.content)
                hide(d.open); hide(d.close)
                take(d.open); take(d.close)
            }
        }
        Rx.strike.enumerateMatches(in: s, range: scope) { m, _, _ in
            guard let m else { return }
            let d = delimited(m)
            guard free(d.open), free(d.close) else { return }
            out.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: MarkdownTheme.done], range: abs(d.content))
            hide(d.open); hide(d.close)
            take(d.open); take(d.close)
        }
    }

    // MARK: Chế độ Mã nguồn: giữ màu, thay toàn bộ font bằng mono, bỏ thụt lề

    private func applySourceFonts(_ out: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.font, in: full) { value, range, _ in
            let font = value as? NSFont ?? MarkdownTheme.body
            let bold = font.pointSize > 15.2 || NSFontManager.shared.traits(of: font).contains(.boldFontMask)
            out.addAttribute(.font, value: bold ? MarkdownTheme.sourceBold : MarkdownTheme.sourceFont, range: range)
        }
        out.addAttribute(.paragraphStyle, value: MarkdownTheme.paragraph(spacing: 4), range: full)
        for key in [NSAttributedString.Key.mdHidden, .mdList, .mdQuote, .mdCodeBlock, .mdCodeLang, .mdInlineCode, .mdRule] {
            out.removeAttribute(key, range: full)
        }
    }
}

// MARK: - Layout manager: ẩn glyph ký hiệu + vẽ checkbox, chấm đầu dòng, thẻ khối mã, thanh trích dẫn

final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var decorationsEnabled = true

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let ns = storage.string as NSString
        var changed: [NSLayoutManager.GlyphProperty]?
        for i in 0..<glyphRange.length {
            let ci = charIndexes[i]
            guard ci < storage.length,
                  storage.attribute(.mdHidden, at: ci, effectiveRange: nil) != nil,
                  ns.character(at: ci) != 10 else { continue }
            if changed == nil {
                changed = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
            }
            changed?[i] = .null
        }
        guard let changed else { return 0 }
        changed.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    // MARK: Hình học dùng chung cho vẽ + bấm

    private func unionFragments(forCharacterRange range: NSRange) -> NSRect {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = NSRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
            rect = rect.union(fragment)
        }
        return rect
    }

    /// Baseline của dòng chứa ký tự (tọa độ container).
    /// Glyph bị ẩn (null) không được dàn trang — AppKit trả về vị trí của dòng TRƯỚC —
    /// nên neo vào ký tự nhìn thấy đầu tiên của dòng (hoặc ký tự xuống dòng).
    private func baseline(forCharacterAt start: Int) -> (fragment: NSRect, y: CGFloat)? {
        guard let storage = textStorage, start < storage.length else { return nil }
        let ns = storage.string as NSString
        let line = ns.lineRange(for: NSRange(location: start, length: 0))
        var index = start
        while index < NSMaxRange(line) - 1,
              storage.attribute(.mdHidden, at: index, effectiveRange: nil) != nil {
            index += 1
        }
        let glyph = glyphIndexForCharacter(at: index)
        guard glyph < numberOfGlyphs else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return (fragment, fragment.minY + location(forGlyphAt: glyph).y)
    }

    private func listMarkerCenter(forLineStart start: Int) -> NSPoint? {
        guard let storage = textStorage, let info = baseline(forCharacterAt: start) else { return nil }
        let style = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle
        let x = (style?.firstLineHeadIndent ?? MarkdownTheme.listIndent) - 13
        return NSPoint(x: x, y: info.y - MarkdownTheme.body.capHeight / 2)
    }

    /// Ô checkbox của dòng (tọa độ container) — dùng để bấm tick
    func checkboxRect(forLineStart start: Int) -> NSRect? {
        guard let center = listMarkerCenter(forLineStart: start) else { return nil }
        return NSRect(x: center.x - 7.5, y: center.y - 7.5, width: 15, height: 15)
    }

    // MARK: Vẽ

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard decorationsEnabled, let storage = textStorage, storage.length > 0,
              let container = textContainers.first else { return }
        let appearance = container.textView?.effectiveAppearance ?? NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            self.drawDecorations(storage: storage, container: container,
                                 characters: characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil),
                                 origin: origin)
        }
    }

    private func drawDecorations(storage: NSTextStorage, container: NSTextContainer, characters: NSRange, origin: NSPoint) {
        let full = NSRange(location: 0, length: storage.length)
        let width = container.size.width

        // Thẻ khối mã: vẽ trọn khối kể cả khi chỉ một phần đang hiện
        var drawnBlocks = Set<Int>()
        storage.enumerateAttribute(.mdCodeBlock, in: characters) { value, range, _ in
            guard value != nil else { return }
            var block = NSRange()
            _ = storage.attribute(.mdCodeBlock, at: range.location, longestEffectiveRange: &block, in: full)
            guard drawnBlocks.insert(block.location).inserted else { return }
            let rect = unionFragments(forCharacterRange: block)
            guard !rect.isNull else { return }
            let card = NSRect(x: origin.x, y: rect.minY + origin.y + 1, width: width, height: rect.height - 2)
            let path = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
            MarkdownTheme.codeFill.setFill()
            path.fill()
            MarkdownTheme.codeBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
            if let lang = storage.attribute(.mdCodeLang, at: block.location, effectiveRange: nil) as? String {
                let attrs: [NSAttributedString.Key: Any] = [.font: MarkdownTheme.label, .foregroundColor: MarkdownTheme.marker]
                let size = (lang as NSString).size(withAttributes: attrs)
                (lang as NSString).draw(at: NSPoint(x: card.maxX - size.width - 12, y: card.minY + 7), withAttributes: attrs)
            }
        }

        // Mã inline: nền bo góc theo từng dòng
        storage.enumerateAttribute(.mdInlineCode, in: characters) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(glyphs, lineGlyphs)
                guard part.length > 0 else { return }
                let bounds = self.boundingRect(forGlyphRange: part, in: container)
                let baseY = fragment.minY + self.location(forGlyphAt: part.location).y
                let font = MarkdownTheme.mono
                let pill = NSRect(x: bounds.minX - 3 + origin.x, y: baseY - font.ascender - 2 + origin.y,
                                  width: bounds.width + 6, height: font.ascender - font.descender + 4)
                MarkdownTheme.inlineCodeFill.setFill()
                NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
            }
        }

        // Trích dẫn: thanh dọc bên trái, liền mạch qua các dòng liên tiếp
        storage.enumerateAttribute(.mdQuote, in: characters) { value, range, _ in
            guard value != nil else { return }
            var quote = NSRange()
            _ = storage.attribute(.mdQuote, at: range.location, longestEffectiveRange: &quote, in: full)
            let rect = unionFragments(forCharacterRange: quote)
            guard !rect.isNull else { return }
            MarkdownTheme.quoteBar.setFill()
            NSBezierPath(roundedRect: NSRect(x: origin.x + 1, y: rect.minY + origin.y + 2, width: 3, height: rect.height - 4),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }

        // Đường kẻ ngang
        storage.enumerateAttribute(.mdRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let rect = unionFragments(forCharacterRange: range)
            guard !rect.isNull else { return }
            MarkdownTheme.rule.setFill()
            NSRect(x: origin.x, y: rect.midY + origin.y, width: width, height: 1).fill()
        }

        // Chấm đầu dòng / checkbox
        storage.enumerateAttribute(.mdList, in: characters) { value, range, _ in
            guard let kind = value as? String, let center = listMarkerCenter(forLineStart: range.location) else { return }
            let c = NSPoint(x: center.x + origin.x, y: center.y + origin.y)
            switch kind {
            case "bullet":
                let r: CGFloat = 2.6
                MarkdownTheme.text.setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
            default:
                let box = NSRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)
                let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
                if kind == "done" {
                    MarkdownTheme.checkboxFill.setFill()
                    path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: box.minX + 3.4, y: box.midY + 0.2))
                    check.line(to: NSPoint(x: box.minX + 6, y: box.maxY - 3.6))
                    check.line(to: NSPoint(x: box.maxX - 3.2, y: box.minY + 3.8))
                    check.lineWidth = 1.8
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    MarkdownTheme.checkmark.setStroke()
                    check.stroke()
                } else {
                    MarkdownTheme.checkboxStroke.setStroke()
                    let inner = NSBezierPath(roundedRect: box.insetBy(dx: 0.6, dy: 0.6), xRadius: 3.2, yRadius: 3.2)
                    inner.lineWidth = 1.2
                    inner.stroke()
                }
            }
        }
    }
}

// MARK: - Ô soạn thảo

final class EditorTextView: NSTextView {
    static let editorIdentifier = NSUserInterfaceItemIdentifier("studio.note.editor")
    static let maxColumn: CGFloat = 760

    var livePreview = true {
        didSet {
            guard oldValue != livePreview else { return }
            (layoutManager as? MarkdownLayoutManager)?.decorationsEnabled = livePreview
            typingAttributes = livePreview ? MarkdownTheme.typingAttributes : MarkdownTheme.sourceTypingAttributes
            restyleNow()
        }
    }
    var onMarkedTextChange: (() -> Void)?
    weak var editorCoordinator: EditorCoordinator?

    private var highlightItem: DispatchWorkItem?
    private var lastActiveKey: [Int] = []

    static func make() -> (NSScrollView, EditorTextView) {
        let storage = NSTextStorage()
        let manager = MarkdownLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 400), textContainer: container)
        textView.identifier = EditorTextView.editorIdentifier
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 48, height: 28)
        textView.font = MarkdownTheme.body
        textView.textColor = MarkdownTheme.text
        textView.typingAttributes = MarkdownTheme.typingAttributes
        textView.linkTextAttributes = [:]

        // Markdown: tắt thay thế tự động của hệ thống để không phá cú pháp
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        return (scrollView, textView)
    }

    // MARK: Cột chữ tối đa 760pt, căn giữa — thanh cuộn nằm sát mép cửa sổ

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(40, floor((newSize.width - Self.maxColumn) / 2))
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: 28)
        }
    }

    // MARK: Bộ gõ Telex: chữ đang ghép (marked text) không bắn textDidChange

    var isPlaceholderVisible: Bool {
        guard !hasMarkedText() else { return false }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "#"
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
        onMarkedTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
        onMarkedTextChange?()
    }

    /// Note trống / chỉ có "# ": gợi ý "Tiêu đề" ngay sau dấu # và một dòng hướng dẫn bên dưới
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isPlaceholderVisible, let manager = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin
        let titleFont = livePreview ? MarkdownTheme.heading(1) : MarkdownTheme.sourceBold
        var x = origin.x
        var top = origin.y
        var bottom = origin.y + titleFont.ascender - titleFont.descender + 6
        if manager.numberOfGlyphs > 0 {
            let ns = string as NSString
            let firstLine = ns.lineRange(for: NSRange(location: 0, length: 0))
            let glyphs = manager.glyphRange(forCharacterRange: firstLine, actualCharacterRange: nil)
            let fragment = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let used = manager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + manager.location(forGlyphAt: glyphs.location).y
            let visibleMarker = string.contains("#") && (textStorage?.attribute(.mdHidden, at: 0, effectiveRange: nil) == nil)
            x = origin.x + (visibleMarker ? used.maxX + 4 : 0)
            top = origin.y + baseline - titleFont.ascender
            bottom = origin.y + fragment.maxY
        }
        _ = container
        ("Tiêu đề" as NSString).draw(at: NSPoint(x: x, y: top), withAttributes: [
            .font: titleFont, .foregroundColor: NSColor.placeholderTextColor
        ])
        let hint = "Enter để bắt đầu viết · Gõ / để chèn tiêu đề, danh sách, việc cần làm, khối mã…"
        (hint as NSString).draw(at: NSPoint(x: origin.x, y: bottom + 14), withAttributes: [
            .font: MarkdownTheme.body, .foregroundColor: NSColor.placeholderTextColor
        ])
    }

    // MARK: Dán luôn là chữ thường

    override func paste(_ sender: Any?) {
        if NSPasteboard.general.types?.contains(.string) == true {
            pasteAsPlainText(sender)
        } else {
            super.paste(sender)
        }
    }

    // MARK: Bấm checkbox để tick · ⌘ + bấm liên kết để mở

    /// Điểm (tọa độ view) nằm trên ô checkbox nào → vị trí đầu dòng đó
    func checkboxLine(at point: NSPoint) -> Int? {
        guard livePreview, let manager = layoutManager as? MarkdownLayoutManager,
              let storage = textStorage, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        for line in MarkdownStyler.lines(string as NSString) where line.length > 0 {
            guard let kind = storage.attribute(.mdList, at: line.location, effectiveRange: nil) as? String, kind != "bullet",
                  let box = manager.checkboxRect(forLineStart: line.location) else { continue }
            if box.insetBy(dx: -5, dy: -4).contains(local) { return line.location }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lineStart = checkboxLine(at: point) {
            toggleCheckbox(atLineStart: lineStart)
            return
        }
        if livePreview, event.modifierFlags.contains(.command),
           let manager = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 {
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let index = min(manager.characterIndexForGlyph(at: manager.glyphIndex(for: local, in: container)), storage.length - 1)
            if let link = storage.attribute(.mdLink, at: index, effectiveRange: nil) as? String,
               let url = URL(string: link), url.scheme != nil {
                NSWorkspace.shared.open(url)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Con trỏ tay khi rê lên checkbox
    override func mouseMoved(with event: NSEvent) {
        if checkboxLine(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }

    private static let checkboxRegex = try! NSRegularExpression(pattern: "^[ \\t]*[-*+] \\[([ xX])\\]")

    /// Đổi [ ] ↔ [x] tại chỗ: có undo, không dời con trỏ
    func toggleCheckbox(atLineStart lineStart: Int) {
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: lineStart, length: 0))
        let text = ns.substring(with: line)
        guard let m = Self.checkboxRegex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return }
        let target = NSRange(location: line.location + m.range(at: 1).location, length: 1)
        let checked = (text as NSString).substring(with: m.range(at: 1)).lowercased() == "x"
        let replacement = checked ? " " : "x"
        let selection = selectedRanges
        guard shouldChangeText(in: target, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: target, with: replacement)
        didChangeText()
        selectedRanges = selection
        restyleNow()
    }

    // MARK: Phím tắt định dạng ⌘B / ⌘I / ⌘⇧X / ⌘⇧↩ / ⌘1-3 tiêu đề

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let ch = event.charactersIgnoringModifiers?.lowercased() {
            if flags == .command {
                switch ch {
                case "b": wrapSelection("**"); return true
                case "i": wrapSelection("*"); return true
                case "e": wrapSelection("`"); return true
                default: break
                }
            }
            if flags == [.command, .shift] {
                switch ch {
                case "x": wrapSelection("~~"); return true
                case "\r": toggleCheckedState(); return true
                default: break
                }
            }
            if flags == [.command, .option], let level = Int(ch), (0...3).contains(level) {
                setHeading(level)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Tô lại

    func scheduleHighlight(immediate: Bool = false) {
        highlightItem?.cancel()
        guard immediate else {
            let item = DispatchWorkItem { [weak self] in self?.restyleNow() }
            highlightItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
            return
        }
        restyleNow()
    }

    /// Chỉ ghi các đoạn thuộc tính thật sự đổi → không dựng lại layout cả tài liệu mỗi lần
    func restyleNow() {
        highlightItem?.cancel()
        guard let storage = textStorage, !hasMarkedText() else { return }
        let styled = MarkdownStyler(live: livePreview, selection: selectedRange()).styled(string)
        guard styled.length == storage.length else { return }
        let full = NSRange(location: 0, length: storage.length)
        var dirty = NSRange(location: NSNotFound, length: 0)
        storage.beginEditing()
        styled.enumerateAttributes(in: full) { attrs, range, _ in
            var effective = NSRange()
            let current = storage.attributes(at: range.location, longestEffectiveRange: &effective, in: range)
            if NSEqualRanges(effective, range), NSDictionary(dictionary: current).isEqual(to: attrs) { return }
            storage.setAttributes(attrs, range: range)
            dirty = dirty.location == NSNotFound ? range : NSUnionRange(dirty, range)
        }
        storage.endEditing()
        if dirty.location != NSNotFound {
            layoutManager?.invalidateGlyphs(forCharacterRange: dirty, changeInLength: 0, actualCharacterRange: nil)
            layoutManager?.invalidateLayout(forCharacterRange: dirty, actualCharacterRange: nil)
        }
        lastActiveKey = activeKey()
        needsDisplay = true
    }

    private func activeKey() -> [Int] {
        let ns = string as NSString
        let selection = selectedRange()
        let a = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0)).location
        let b = ns.lineRange(for: NSRange(location: min(NSMaxRange(selection), ns.length), length: 0)).location
        return [a, b]
    }

    /// Con trỏ sang dòng khác → hiện ký hiệu ở dòng mới, ẩn ở dòng cũ
    func selectionMoved() {
        guard livePreview, !hasMarkedText(), activeKey() != lastActiveKey else { return }
        restyleNow()
    }

    /// Đặt toàn bộ nội dung từ ngoài (đổi note, AI/MCP sửa)
    func setText(_ newText: String) {
        guard let storage = textStorage else { return }
        let keep = selectedRange()
        let base = livePreview ? MarkdownTheme.typingAttributes : MarkdownTheme.sourceTypingAttributes
        undoManager?.disableUndoRegistration()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: NSAttributedString(string: newText, attributes: base))
        undoManager?.enableUndoRegistration()
        let length = (newText as NSString).length
        setSelectedRange(NSRange(location: min(keep.location, length), length: 0))
        typingAttributes = base
        restyleNow()
    }

    func notifyChanged() {
        editorCoordinator?.textViewDidChangeContent()
    }

    // MARK: Vùng dòng

    /// Vùng dòng chứa caret (không gồm \n)
    func currentLineRange() -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let caret = min(selectedRange().location, ns.length)
        var start = caret, end = caret, contentEnd = caret
        ns.getLineStart(&start, end: &end, contentsEnd: &contentEnd, for: NSRange(location: caret, length: 0))
        return NSRange(location: start, length: contentEnd - start)
    }

    /// Mở rộng vùng chọn ra trọn dòng — dùng cho thao tác theo dòng
    func expandedLineRange() -> NSRange {
        let ns = string as NSString
        let sel = selectedRange()
        guard ns.length > 0, sel.location <= ns.length else { return sel }
        var start = sel.location, end = sel.location, contentEnd = sel.location
        ns.getLineStart(&start, end: &end, contentsEnd: &contentEnd, for: NSRange(location: sel.location, length: 0))
        if sel.length > 0 {
            let last = min(sel.location + sel.length, ns.length)
            var lastStart = last, lastEnd = last, lastContent = last
            ns.getLineStart(&lastStart, end: &lastEnd, contentsEnd: &lastContent, for: NSRange(location: max(last - 1, 0), length: 0))
            return NSRange(location: start, length: lastContent - start)
        }
        return NSRange(location: start, length: contentEnd - start)
    }

    // MARK: Marker danh sách — dùng chung cho Enter/Tab/toggle

    struct ListItemMarker {
        let indent: String
        let marker: String        // "- ", "1. ", "- [ ] ", "> "
        let content: String
        var isEmptyItem: Bool { content.trimmingCharacters(in: .whitespaces).isEmpty }

        func nextPrefix() -> String {
            if marker.hasPrefix(">") { return "> " }
            // "1. " → "2. "; "- [x] " → "- [ ] "
            let ns = marker as NSString
            let first = ns.character(at: 0)
            if first >= 48, first <= 57 {
                var digits = ""
                var i = 0
                while i < ns.length, ns.character(at: i) >= 48, ns.character(at: i) <= 57 {
                    digits += String(ns.character(at: i) - 48)
                    i += 1
                }
                let next = (Int(digits) ?? 0) + 1
                return "\(next)" + ns.substring(from: digits.count)
            }
            if marker.contains("[") { return "- [ ] " }
            return marker
        }

        static let pattern = try! NSRegularExpression(
            pattern: "^(\\s*)((?:[-*+]|\\d{1,9}[.)])(?: \\[[ xX]\\])?|>)( +)(.*)$"
        )

        static func parse(_ line: String) -> ListItemMarker? {
            let ns = line as NSString
            guard let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            // group 2 = marker (đã gồm "- [ ]" nếu là checkbox), group 3 = khoảng cách
            return ListItemMarker(
                indent: ns.substring(with: m.range(at: 1)),
                marker: ns.substring(with: m.range(at: 2)) + ns.substring(with: m.range(at: 3)),
                content: ns.substring(with: m.range(at: 4))
            )
        }
    }

    // MARK: Enter — tiếp tục danh sách; item rỗng thì xóa marker

    @discardableResult
    func handleEnter() -> Bool {
        guard !hasMarkedText() else { return false }
        let lineRange = currentLineRange()
        let ns = string as NSString
        let line = ns.substring(with: lineRange)
        guard let item = ListItemMarker.parse(line) else { return false }

        if item.isEmptyItem {
            // "- " + Enter → bỏ marker, caret về đầu dòng
            insertText(item.indent, replacementRange: lineRange)
            setSelectedRange(NSRange(location: lineRange.location + (item.indent as NSString).length, length: 0))
        } else {
            insertText("\n" + item.indent + item.nextPrefix(), replacementRange: selectedRange())
        }
        return true
    }

    // MARK: Tab / Shift+Tab — thụt lề dòng (list) 2 khoảng trắng mỗi bậc

    @discardableResult
    func handleTab(outdent: Bool) -> Bool {
        guard !hasMarkedText() else { return false }
        let ns = string as NSString
        let sel = selectedRange()
        let linesRange = expandedLineRange()
        guard linesRange.length > 0 else { return false }
        let lines = ns.substring(with: linesRange).components(separatedBy: "\n")

        // Tab giữa dòng thường (không phải list, không ở khoảng trắng đầu dòng) → tab thật
        if !outdent, sel.length == 0, lines.count == 1, ListItemMarker.parse(lines[0]) == nil {
            let column = sel.location - linesRange.location
            let leading = lines[0].prefix(column)
            if !leading.allSatisfy({ $0 == " " || $0 == "\t" }) { return false }
        }

        var newLines: [String] = []
        for var line in lines {
            if outdent {
                if line.hasPrefix("    ") { line.removeFirst(4) }
                else if line.hasPrefix("\t") { line.removeFirst() }
                else if line.hasPrefix("  ") { line.removeFirst(2) }
            } else {
                line = "  " + line
            }
            newLines.append(line)
        }
        let replacement = newLines.joined(separator: "\n")
        let delta = (replacement as NSString).length - linesRange.length
        let firstDelta = ((newLines.first ?? "") as NSString).length - ((lines.first ?? "") as NSString).length

        insertText(replacement, replacementRange: linesRange)
        let total = (string as NSString).length
        if sel.length == 0 {
            let column = sel.location - linesRange.location
            let newFirstLen = ((newLines.first ?? "") as NSString).length
            let location = linesRange.location + min(max(column + firstDelta, 0), newFirstLen)
            setSelectedRange(NSRange(location: min(max(location, 0), total), length: 0))
        } else {
            setSelectedRange(NSRange(location: sel.location, length: max(sel.length + delta, 0)))
        }
        return true
    }

    // MARK: Bọc selection bằng marker markdown (⌘B, ⌘I, ⌘⇧X, footer)

    func wrapSelection(_ marker: String) {
        let close = String(marker.reversed())
        let range = selectedRange()
        let ns = string as NSString
        guard range.location != NSNotFound else { return }
        let markerLen = (marker as NSString).length

        if range.length > 0 {
            let beforeLoc = max(range.location - markerLen, 0)
            let before = ns.substring(with: NSRange(location: beforeLoc, length: range.location - beforeLoc))
            let afterLoc = range.location + range.length
            let afterLen = min(markerLen, ns.length - afterLoc)
            let after = afterLen > 0 ? ns.substring(with: NSRange(location: afterLoc, length: afterLen)) : ""
            let inner = ns.substring(with: range)
            // đã bọc sẵn → tháo ra
            if before == marker, after == close {
                insertText(inner, replacementRange: NSRange(
                    location: range.location - markerLen,
                    length: range.length + markerLen * 2
                ))
                setSelectedRange(NSRange(location: range.location - markerLen, length: (inner as NSString).length))
            } else {
                insertText(marker + inner + close, replacementRange: range)
                setSelectedRange(NSRange(location: range.location + markerLen, length: (inner as NSString).length))
            }
        } else {
            // caret: chèn cặp rỗng, đặt caret giữa
            insertText(marker + close, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + markerLen, length: 0))
        }
        scheduleHighlight(immediate: true)
    }

    /// [chữ](url) — bọc selection, selection nhảy sẵn vào phần url
    func insertLink() {
        let range = selectedRange()
        let ns = string as NSString
        let inner = range.length > 0 ? ns.substring(with: range) : "liên kết"
        insertText("[\(inner)](url)", replacementRange: range)
        let urlStart = range.location + (inner as NSString).length + 3
        setSelectedRange(NSRange(location: urlStart, length: 3))
        scheduleHighlight(immediate: true)
    }

    // MARK: Tiền tố dòng: heading / bullet / số / checkbox / trích dẫn

    enum LineStyle { case bullet, numbered, checklist, quote }

    private struct LineParts {
        let indent: String
        let marker: String   // tiền tố hiện có (không gồm indent), "" nếu không có
        let content: String
    }

    private static let anyPrefixRegex = try! NSRegularExpression(
        pattern: "^(\\s*)(#{1,6} |- \\[[ xX]\\] |- |\\* |\\+ |\\d{1,9}[.)] |> )?(.*)$"
    )

    private func parts(of line: String) -> LineParts {
        let ns = line as NSString
        guard let m = EditorTextView.anyPrefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return LineParts(indent: "", marker: "", content: line)
        }
        return LineParts(
            indent: ns.substring(with: m.range(at: 1)),
            marker: m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2)),
            content: ns.substring(with: m.range(at: 3))
        )
    }

    /// Thay xong giữ mốc chọn tương đối (caret cùng cột trên dòng đầu, selection phủ lại các dòng)
    private func replaceLines(_ newLines: [String], originalLines: [String], linesRange: NSRange) {
        let sel = selectedRange()
        let replacement = newLines.joined(separator: "\n")
        let delta = (replacement as NSString).length - linesRange.length
        let firstDelta = ((newLines.first ?? "") as NSString).length - ((originalLines.first ?? "") as NSString).length

        insertText(replacement, replacementRange: linesRange)
        let total = (string as NSString).length
        if sel.length == 0 {
            let column = sel.location - linesRange.location
            let newFirstLen = ((newLines.first ?? "") as NSString).length
            let location = linesRange.location + min(max(column + firstDelta, 0), newFirstLen)
            setSelectedRange(NSRange(location: min(max(location, 0), total), length: 0))
        } else {
            setSelectedRange(NSRange(location: sel.location, length: max(sel.length + delta, 0)))
        }
    }

    func toggleLinePrefix(_ style: LineStyle) {
        guard !hasMarkedText() else { return }
        let ns = string as NSString
        let linesRange = expandedLineRange()
        guard linesRange.length > 0 else { return }
        let lines = ns.substring(with: linesRange).components(separatedBy: "\n")

        var number = 0
        let newLines: [String] = lines.map { line in
            let p = parts(of: line)
            let isBullet = ["- ", "* ", "+ "].contains(p.marker)
            let isNumbered = p.marker.range(of: "^\\d{1,9}[.)] $", options: .regularExpression) != nil
            let isCheck = p.marker.range(of: "^[-*+] \\[[ xX]\\] $", options: .regularExpression) != nil
            let isQuote = p.marker == "> "

            func wrap(_ marker: String?) -> String { p.indent + (marker ?? "") + p.content }

            switch style {
            case .bullet:
                return wrap(isBullet ? nil : "- ")
            case .numbered:
                if isNumbered { return wrap(nil) }
                number += 1
                return wrap("\(number). ")
            case .checklist:
                if isCheck { return wrap(nil) }
                return wrap("- [ ] ")
            case .quote:
                return wrap(isQuote ? nil : "> ")
            }
        }
        replaceLines(newLines, originalLines: lines, linesRange: linesRange)
    }

    /// H1 → H2 → H3 → bỏ tiêu đề, áp cho các dòng đang chọn
    func cycleHeading() {
        guard !hasMarkedText() else { return }
        let ns = string as NSString
        let linesRange = expandedLineRange()
        guard linesRange.length > 0 else { return }
        let lines = ns.substring(with: linesRange).components(separatedBy: "\n")

        let firstMarker = parts(of: lines.first ?? "").marker
        let isHeading = firstMarker.dropLast().allSatisfy { $0 == "#" } && firstMarker.hasSuffix(" ") && !firstMarker.isEmpty
        let currentLevel = isHeading ? firstMarker.count - 1 : 0
        let next = (currentLevel + 1) % 4

        let newLines = lines.map { line -> String in
            let p = parts(of: line)
            return p.indent + (next == 0 ? "" : String(repeating: "#", count: next) + " ") + p.content
        }
        replaceLines(newLines, originalLines: lines, linesRange: linesRange)
    }

    /// ⌘⇧↩ : tick/bỏ tick việc cần làm của dòng hiện tại (bullet thường → thành checkbox)
    func toggleCheckedState() {
        guard !hasMarkedText() else { return }
        let ns = string as NSString
        let linesRange = expandedLineRange()
        guard linesRange.length > 0 else { return }
        let lines = ns.substring(with: linesRange).components(separatedBy: "\n")

        let newLines: [String] = lines.map { line in
            let p = parts(of: line)
            if p.marker.range(of: "^[-*+] \\[([ xX])\\] $", options: .regularExpression) != nil {
                let bullet = String(p.marker.prefix(1))
                let checked = p.marker.contains("[x]") || p.marker.contains("[X]")
                return p.indent + bullet + " [" + (checked ? " " : "x") + "] " + p.content
            }
            if ["- ", "* ", "+ "].contains(p.marker) {
                return p.indent + String(p.marker.prefix(1)) + " [ ] " + p.content
            }
            if p.marker.isEmpty { return p.indent + "- [ ] " + p.content }
            return line
        }
        replaceLines(newLines, originalLines: lines, linesRange: linesRange)
    }


    // MARK: Chèn khối (thanh công cụ)

    /// ¶ / H1 / H2 / H3 cho các dòng đang chọn (0 = đoạn văn thường)
    func setHeading(_ level: Int) {
        guard !hasMarkedText() else { return }
        let ns = string as NSString
        let linesRange = expandedLineRange()
        let lines = ns.substring(with: linesRange).components(separatedBy: "\n")
        let newLines = lines.map { line -> String in
            var content = line.trimmingCharacters(in: .whitespaces)
            if let r = content.range(of: "^(#{1,6}( |$)|> ?|[-*+] \\[[ xX]\\] |[-*+] |\\d{1,9}[.)] )", options: .regularExpression) {
                content.removeSubrange(r)
            }
            return (level == 0 ? "" : String(repeating: "#", count: level) + " ") + content
        }
        replaceLines(newLines, originalLines: lines, linesRange: linesRange)
    }

    /// Chèn đoạn Markdown thành khối riêng: tự thêm dòng trống trước/sau nếu cần
    private func insertBlock(_ block: String, caretOffset: Int) {
        let ns = string as NSString
        let line = currentLineRange()
        let lineText = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
        var prefix = ""
        var target = selectedRange()
        if lineText.isEmpty {
            target = line
        } else {
            target = NSRange(location: NSMaxRange(line), length: 0)
            prefix = "\n\n"
        }
        let text = prefix + block
        insertText(text, replacementRange: target)
        setSelectedRange(NSRange(location: target.location + (prefix as NSString).length + caretOffset, length: 0))
        scheduleHighlight(immediate: true)
    }

    func insertCodeBlock() {
        let sel = selectedRange()
        if sel.length > 0 {
            let inner = (string as NSString).substring(with: sel)
            insertText("```\n\(inner)\n```", replacementRange: sel)
            scheduleHighlight(immediate: true)
            return
        }
        insertBlock("```\n\n```\n", caretOffset: 4)
    }

    func insertRule() {
        insertBlock("---\n", caretOffset: 4)
    }

    func insertTable() {
        insertBlock("| Cột 1 | Cột 2 |\n| --- | --- |\n|  |  |\n", caretOffset: 2)
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { editorCoordinator?.slash.close() }
        return ok
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { editorCoordinator?.slash.close() }
    }
}

// MARK: - Menu "/" kiểu Notion: NSPanel không chiếm focus, nội dung SwiftUI

struct SlashItem: Identifiable {
    let id = UUID()
    let title: String
    let hint: String
    let icon: String
    let keywords: [String]
    let insert: () -> String

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static let all: [SlashItem] = [
        SlashItem(title: "Tiêu đề 1", hint: "#", icon: "textformat.size.larger",
                  keywords: ["h1", "heading", "tieu de", "de muc"], insert: { "# \u{1}" }),
        SlashItem(title: "Tiêu đề 2", hint: "##", icon: "textformat.size",
                  keywords: ["h2", "heading", "tieu de"], insert: { "## \u{1}" }),
        SlashItem(title: "Tiêu đề 3", hint: "###", icon: "textformat.size.smaller",
                  keywords: ["h3", "heading", "tieu de"], insert: { "### \u{1}" }),
        SlashItem(title: "Danh sách", hint: "-", icon: "list.bullet",
                  keywords: ["danh sach", "list", "bullet", "gach dau dong"], insert: { "- \u{1}" }),
        SlashItem(title: "Danh sách số", hint: "1.", icon: "list.number",
                  keywords: ["danh sach so", "numbered", "so thu tu"], insert: { "1. \u{1}" }),
        SlashItem(title: "Việc cần làm", hint: "- [ ]", icon: "checklist",
                  keywords: ["viec", "todo", "checklist", "nhiem vu", "can lam"], insert: { "- [ ] \u{1}" }),
        SlashItem(title: "Trích dẫn", hint: ">", icon: "text.quote",
                  keywords: ["trich dan", "quote", "trich"], insert: { "> \u{1}" }),
        SlashItem(title: "Đường kẻ", hint: "---", icon: "minus",
                  keywords: ["duong ke", "ke ngang", "divider", "hr", "ngan cach"], insert: { "---\n\u{1}" }),
        SlashItem(title: "Khối mã", hint: "```", icon: "chevron.left.forwardslash.chevron.right",
                  keywords: ["ma", "code", "khoi ma"], insert: { "```\n\u{1}\n```" }),
        SlashItem(title: "Ngày hôm nay", hint: "", icon: "calendar",
                  keywords: ["ngay", "date", "hom nay", "today"], insert: { Date().studioDate }),
        SlashItem(title: "Giờ hiện tại", hint: "", icon: "clock",
                  keywords: ["gio", "time", "thoi gian"],
                  insert: { Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Studio.locale)) })
    ]

    /// Lọc không phân biệt hoa thường/dấu — "tieu de" vẫn ra "Tiêu đề"
    static func filter(_ query: String, limit: Int = 7) -> [SlashItem] {
        let q = fold(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(all.prefix(limit)) }
        var starts: [SlashItem] = []
        var contains: [SlashItem] = []
        for item in all {
            let title = fold(item.title)
            if title.hasPrefix(q) || fold(item.hint).hasPrefix(q) {
                starts.append(item)
            } else if title.contains(q) || item.keywords.contains(where: { fold($0).contains(q) }) {
                contains.append(item)
            }
        }
        return Array((starts + contains).prefix(limit))
    }
}

struct SlashToken {
    let range: NSRange   // từ '/' đến caret
    let query: String

    /// Tìm "/từ-khóa" ngay trước caret: '/' phải là ký tự đầu của token
    static func scan(_ textView: NSTextView) -> SlashToken? {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return nil }
        let ns = textView.string as NSString
        guard ns.length > 0, sel.location <= ns.length else { return nil }
        let caret = sel.location
        var start = caret
        while start > 0 {
            let ch = ns.character(at: start - 1)
            if ch == 32 || ch == 10 || ch == 9 { break }
            start -= 1
        }
        guard start < caret else { return nil }
        var slash = caret
        while slash > start, ns.character(at: slash - 1) != UInt16(UnicodeScalar("/").value) {
            slash -= 1
        }
        guard slash == start + 1 else { return nil }
        let query = ns.substring(with: NSRange(location: slash, length: caret - slash))
        return SlashToken(range: NSRange(location: start, length: caret - start), query: String(query.dropFirst()))
    }
}

final class SlashMenuController: ObservableObject {
    @Published private(set) var items: [SlashItem] = []
    @Published var selectedIndex = 0
    var isOpen: Bool { panel?.isVisible == true }

    weak var textView: EditorTextView?
    weak var coordinator: EditorCoordinator?
    private var tokenRange = NSRange(location: 0, length: 0)
    private var panel: NSPanel?

    func attach(textView: EditorTextView, coordinator: EditorCoordinator) {
        self.textView = textView
        self.coordinator = coordinator
    }

    // MARK: Cập nhật theo caret

    func refresh() {
        guard let textView,
              textView.window?.firstResponder === textView,
              textView.window?.isVisible == true,
              let token = SlashToken.scan(textView)
        else { close(); return }
        let filtered = SlashItem.filter(token.query)
        guard !filtered.isEmpty else { close(); return }
        if filtered.map(\.id) != items.map(\.id) { selectedIndex = 0 }
        items = filtered
        if selectedIndex >= filtered.count { selectedIndex = 0 }
        tokenRange = token.range
        showBelowCaret()
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
    }

    func close() {
        panel?.orderOut(nil)
        items = []
    }

    func accept() {
        guard let textView, selectedIndex < items.count else { return }
        let template = items[selectedIndex].insert()
        if textView.hasMarkedText() { textView.unmarkText() }
        textView.insertText(template, replacementRange: tokenRange)

        // \u{1} = vị trí caret mong muốn sau khi chèn
        let ns = textView.string as NSString
        let markerRange = ns.range(of: "\u{1}")
        if markerRange.location != NSNotFound {
            if let undo = textView.undoManager {
                undo.disableUndoRegistration()
                textView.textStorage?.replaceCharacters(in: markerRange, with: "")
                undo.enableUndoRegistration()
            } else {
                textView.textStorage?.replaceCharacters(in: markerRange, with: "")
            }
            textView.setSelectedRange(NSRange(location: markerRange.location, length: 0))
        }
        close()
        coordinator?.textViewDidChangeContent()
    }

    // MARK: Panel

    private func showBelowCaret() {
        guard let textView, textView.window != nil else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let host = panel.contentView else { return }

        var size = host.fittingSize
        if size.width <= 0 || size.height <= 0 {
            size = NSSize(width: 252, height: CGFloat(items.count * 34 + 12))
        }
        panel.setContentSize(size)

        let caret = textView.firstRect(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualRange: nil)
        guard caret.width > 0 || caret.height > 0 else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: caret.minX, y: caret.minY - 6 - size.height)
        if origin.y < visible.minY { origin.y = caret.maxY + 6 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces]
        let host = NSHostingView(rootView: SlashMenuList(model: self))
        panel.contentView = host
        return panel
    }
}

private struct SlashMenuList: View {
    @ObservedObject var model: SlashMenuController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 9) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Studio.textSecondary)
                        .frame(width: 20)
                    Text(item.title)
                        .font(Studio.Typo.callout())
                        .foregroundStyle(Studio.textPrimary)
                    Spacer(minLength: 12)
                    Text(item.hint)
                        .font(Studio.Typo.footnote(.medium))
                        .foregroundStyle(Studio.textTertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(index == model.selectedIndex ? Studio.hover : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { model.selectedIndex = index; model.accept() }
            }
        }
        .padding(6)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: Studio.Radius.medium)
                .fill(Studio.popoverBackground)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: Studio.Radius.medium).stroke(Studio.composerBorder))
        .padding(8)
    }
}


// MARK: - Coordinator: delegate của EditorTextView

final class EditorCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: EditorTextView?
    var onTextChange: ((String) -> Void)?
    let slash = SlashMenuController()

    func attach(textView: EditorTextView) {
        self.textView = textView
        textView.editorCoordinator = self
        textView.onMarkedTextChange = { [weak self] in self?.markedTextChanged() }
        slash.attach(textView: textView, coordinator: self)
    }

    /// Đẩy nội dung mới nhất về SwiftUI + tô lại ngay (menu "/" chèn xong, thao tác định dạng…)
    func textViewDidChangeContent() {
        onTextChange?(textView?.string ?? "")
        textView?.scheduleHighlight(immediate: true)
        slash.refresh()
    }

    private func markedTextChanged() {
        onTextChange?(textView?.string ?? "")
        slash.refresh()
        textView?.scheduleHighlight()
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        onTextChange?(textView?.string ?? "")
        textView?.scheduleHighlight()
        slash.refresh()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView?.selectionMoved()
        slash.refresh()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let editor = textView as? EditorTextView else { return false }

        if slash.isOpen, !editor.hasMarkedText() {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertTab(_:)):
                slash.accept()
                return true
            case #selector(NSResponder.moveUp(_:)):
                slash.move(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                slash.move(1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                slash.close()
                return true
            default:
                break
            }
        }

        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            return editor.handleEnter()
        case #selector(NSResponder.insertTab(_:)):
            return editor.handleTab(outdent: false)
        case #selector(NSResponder.insertBacktab(_:)):
            return editor.handleTab(outdent: true)
        default:
            return false
        }
    }
}

// MARK: - Bridge: thanh công cụ gọi định dạng mà không cần biết NSTextView

@MainActor
final class EditorBridge: ObservableObject {
    weak var coordinator: EditorCoordinator?

    func attach(_ coordinator: EditorCoordinator) {
        self.coordinator = coordinator
    }

    var textView: EditorTextView? { coordinator?.textView }

    private var editor: EditorTextView? {
        guard let editor = coordinator?.textView, editor.window != nil else { return nil }
        return editor
    }

    func focus() {
        if let editor { editor.window?.makeFirstResponder(editor) }
    }

    func paragraph() { focus(); editor?.setHeading(0) }
    func heading(_ level: Int) { focus(); editor?.setHeading(level) }
    func bold() { focus(); editor?.wrapSelection("**") }
    func italic() { focus(); editor?.wrapSelection("*") }
    func strikethrough() { focus(); editor?.wrapSelection("~~") }
    func inlineCode() { focus(); editor?.wrapSelection("`") }
    func link() { focus(); editor?.insertLink() }
    func toggleBullets() { focus(); editor?.toggleLinePrefix(.bullet) }
    func toggleNumbered() { focus(); editor?.toggleLinePrefix(.numbered) }
    func toggleChecklist() { focus(); editor?.toggleLinePrefix(.checklist) }
    func toggleQuote() { focus(); editor?.toggleLinePrefix(.quote) }
    func codeBlock() { focus(); editor?.insertCodeBlock() }
    func rule() { focus(); editor?.insertRule() }
    func table() { focus(); editor?.insertTable() }

    func closeMenus() {
        coordinator?.slash.close()
    }
}

// MARK: - NSViewRepresentable

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let bridge: EditorBridge
    var livePreview = true
    var focusOnAppear = false

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = EditorTextView.make()
        textView.delegate = context.coordinator
        context.coordinator.attach(textView: textView)
        context.coordinator.onTextChange = { value in text = value }
        bridge.attach(context.coordinator)
        textView.livePreview = livePreview
        textView.setText(text)
        if focusOnAppear {
            // Note mới "# ": con trỏ đứng ngay sau dấu # để gõ tiêu đề
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        bridge.attach(context.coordinator)
        context.coordinator.onTextChange = { value in text = value }
        if textView.livePreview != livePreview { textView.livePreview = livePreview }
        // Đang ghép chữ tiếng Việt thì không ghi đè — sẽ mất chữ đang gõ
        if textView.hasMarkedText() { return }
        if textView.string != text {
            textView.setText(text)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: EditorCoordinator) {
        coordinator.slash.close()
        coordinator.textView?.delegate = nil
    }
}
