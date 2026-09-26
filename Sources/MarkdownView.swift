import SwiftUI

// MARK: - Xem trước Markdown (heading, list, checklist, quote, code, **bold**, *italic*)

struct MarkdownPreviewView: View {
    @Binding var content: String

    var body: some View {
        ScrollView {
            let blocks = MarkdownParser.parse(content)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block) { lineIndex in
                        toggleChecklist(at: lineIndex)
                    }
                }
                if blocks.isEmpty {
                    Text(L("Empty note"))
                        .font(.system(size: 13))
                        .foregroundStyle(Studio.textTertiary)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    /// Tick/bỏ tick checkbox trong preview → ghi ngược về nội dung note.
    private func toggleChecklist(at lineIndex: Int) {
        var lines = content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return }
        if lines[lineIndex].contains("- [ ] ") {
            lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else {
            lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [x] ", with: "- [ ] ")
        }
        content = lines.joined(separator: "\n")
    }
}

// MARK: - Parser

enum MarkdownParser {
    struct Block {
        enum Kind {
            case heading(level: Int, text: String)
            case paragraph(text: String)
            case quote(lines: [String])
            case code(text: String)
            case bullet(text: String)
            case numbered(index: Int, text: String)
            case checklistItem(checked: Bool, text: String, line: Int)
            case rule
        }
        let kind: Kind
    }

    static func parse(_ content: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []
        var codeLines: [String]?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(Block(kind: .paragraph(text: paragraphLines.joined(separator: "\n"))))
            paragraphLines.removeAll()
        }
        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(Block(kind: .quote(lines: quoteLines)))
            quoteLines.removeAll()
        }

        for (lineIndex, rawLine) in content.components(separatedBy: "\n").enumerated() {
            if rawLine.hasPrefix("```") {
                if let code = codeLines {
                    flushParagraph(); flushQuote()
                    blocks.append(Block(kind: .code(text: code.joined(separator: "\n"))))
                    codeLines = nil
                } else {
                    flushParagraph(); flushQuote()
                    codeLines = []
                }
                continue
            }
            if var code = codeLines {
                code.append(rawLine)
                codeLines = code
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph(); flushQuote()
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                flushParagraph(); flushQuote()
                blocks.append(Block(kind: .rule))
                continue
            }
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed where ch == "#" { level += 1 }
                let rest = trimmed.dropFirst(level)
                if (1...6).contains(level), rest.hasPrefix(" ") {
                    flushParagraph(); flushQuote()
                    blocks.append(Block(kind: .heading(level: level, text: String(rest.dropFirst()))))
                    continue
                }
            }
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                flushParagraph(); flushQuote()
                let checked = !trimmed.hasPrefix("- [ ] ")
                blocks.append(Block(kind: .checklistItem(
                    checked: checked,
                    text: String(trimmed.dropFirst(6)),
                    line: lineIndex
                )))
                continue
            }
            if trimmed == ">" || trimmed.hasPrefix("> ") {
                flushParagraph()
                quoteLines.append(trimmed == ">" ? "" : String(trimmed.dropFirst(2)))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushParagraph(); flushQuote()
                blocks.append(Block(kind: .bullet(text: String(trimmed.dropFirst(2)))))
                continue
            }
            if let ordered = parseOrdered(trimmed) {
                flushParagraph(); flushQuote()
                blocks.append(Block(kind: .numbered(index: ordered.0, text: ordered.1)))
                continue
            }
            paragraphLines.append(trimmed)
        }

        if let code = codeLines, !code.isEmpty {
            blocks.append(Block(kind: .code(text: code.joined(separator: "\n"))))
        }
        flushParagraph(); flushQuote()
        return blocks
    }

    private static func parseOrdered(_ line: String) -> (Int, String)? {
        var digitEnd = line.startIndex
        while digitEnd < line.endIndex, line[digitEnd].isNumber {
            digitEnd = line.index(after: digitEnd)
        }
        guard digitEnd > line.startIndex else { return nil }
        guard digitEnd < line.endIndex, line[digitEnd] == "." || line[digitEnd] == ")" else { return nil }
        let textStart = line.index(after: digitEnd)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }
        let number = Int(line[line.startIndex..<digitEnd]) ?? 0
        let text = String(line[line.index(after: textStart)...])
        return text.isEmpty ? nil : (number, text)
    }

    /// Parse inline markdown (bold, italic, code, link) bằng AttributedString có sẵn của hệ thống.
    static func inline(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attr = try? AttributedString(markdown: text, options: options) {
            return attr
        }
        return AttributedString(text)
    }
}

// MARK: - View từng block

struct MarkdownBlockView: View {
    let block: MarkdownParser.Block
    var onToggleChecklist: (Int) -> Void = { _ in }

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(MarkdownParser.inline(text))
                .font(headingFont(level))
                .foregroundStyle(Studio.textPrimary)
        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: 15))
                .foregroundStyle(Studio.textPrimary)
                .lineSpacing(6)
        case .quote(let lines):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Studio.textTertiary)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(MarkdownParser.inline(line))
                            .font(.system(size: 14.5).italic())
                            .foregroundStyle(Studio.textSecondary)
                            .lineSpacing(5)
                    }
                }
            }
            .padding(.vertical, 2)
        case .code(let text):
            Text(text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Studio.textPrimary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Studio.subtleFill))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Studio.hairline))
                .padding(.vertical, 2)
        case .checklistItem(let checked, let text, let line):
            Button {
                onToggleChecklist(line)
            } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(checked ? Studio.textSecondary : Studio.textTertiary)
                    Text(MarkdownParser.inline(text))
                        .font(.system(size: 15))
                        .foregroundStyle(checked ? Studio.textTertiary : Studio.textPrimary)
                        .strikethrough(checked, color: Studio.textTertiary)
                        .lineSpacing(6)
                }
            }
            .buttonStyle(.plain)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 9) {
                Text("•")
                    .font(.system(size: 15))
                    .foregroundStyle(Studio.textSecondary)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Studio.textPrimary)
                    .lineSpacing(6)
            }
        case .numbered(let index, let text):
            HStack(alignment: .top, spacing: 9) {
                Text("\(index).")
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(Studio.textSecondary)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Studio.textPrimary)
                    .lineSpacing(6)
            }
        case .rule:
            Rectangle()
                .fill(Studio.hairline)
                .frame(height: 1)
                .padding(.vertical, 5)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 22, weight: .bold)
        case 2: return .system(size: 18, weight: .semibold)
        default: return .system(size: 15.5, weight: .semibold)
        }
    }
}
