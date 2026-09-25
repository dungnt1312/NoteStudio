import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
    // Optional để decode được notes.json cũ (chưa có trường tags)
    var tags: [String]?

    init(id: UUID = UUID(),
         title: String = "",
         content: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         pinned: Bool = false,
         tags: [String]? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.tags = tags
    }
}

extension Note {
    var displayTitle: String {
        if !title.isEmpty { return title }
        return Note.plainLines(content).first.map { String($0.prefix(80)) } ?? "Không có tiêu đề"
    }
    var displayTags: [String] { tags ?? [] }
    var wordCount: Int { content.split(whereSeparator: \.isWhitespace).filter { $0 != "#" }.count }
}

// MARK: - Ghi chú là một tài liệu Markdown: tiêu đề = dòng "# " đầu tiên của nội dung

extension Note {
    /// Dòng "# Tiêu đề" nếu nó là dòng có chữ đầu tiên của tài liệu
    static func leadingHeading(in content: String) -> (range: Range<String.Index>, text: String)? {
        var index = content.startIndex
        while index < content.endIndex {
            let lineEnd = content[index...].firstIndex(of: "\n") ?? content.endIndex
            let line = content[index..<lineEnd]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index = lineEnd < content.endIndex ? content.index(after: lineEnd) : content.endIndex
                continue
            }
            let trimmed = line.drop(while: { $0 == " " })
            guard trimmed == "#" || trimmed.hasPrefix("# ") else { return nil }
            let text = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
            return (index..<lineEnd, text)
        }
        return nil
    }

    /// Nội dung đổi → tiêu đề đi theo dòng "# " đầu
    mutating func syncTitleFromContent() {
        title = Note.leadingHeading(in: content)?.text ?? ""
    }

    /// Tiêu đề đổi (AI gợi ý, MCP, đổi tên) → ghi vào dòng "# " đầu, chưa có thì chèn lên đầu
    mutating func setTitleInContent(_ newTitle: String) {
        let clean = newTitle.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if let heading = Note.leadingHeading(in: content) {
            content.replaceSubrange(heading.range, with: "# " + clean)
        } else if !clean.isEmpty {
            let body = content.drop(while: { $0 == "\n" })
            content = "# \(clean)" + (body.isEmpty ? "\n" : "\n\n" + body)
        }
        title = clean
    }

    /// Chuẩn hóa note cũ / note do MCP ghi: nội dung là nguồn sự thật
    mutating func normalizeMarkdown() {
        if Note.leadingHeading(in: content) != nil {
            syncTitleFromContent()
        } else if !title.trimmingCharacters(in: .whitespaces).isEmpty {
            setTitleInContent(title)
        }
    }

    func normalizedMarkdown() -> Note {
        var copy = self
        copy.normalizeMarkdown()
        return copy
    }

    /// Các dòng chữ thuần (bỏ ký hiệu markdown, bỏ khối mã) — dùng cho tiêu đề dự phòng và snippet
    static func plainLines(_ content: String) -> [String] {
        var result: [String] = []
        var inFence = false
        for raw in content.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence || trimmed.isEmpty { continue }
            if trimmed.range(of: "^([-*_]\\s*){3,}$", options: .regularExpression) != nil { continue }
            if trimmed.hasPrefix("|") { continue }
            let plain = plainInline(stripBlockPrefix(trimmed))
            if !plain.isEmpty { result.append(plain) }
        }
        return result
    }

    static func stripBlockPrefix(_ line: String) -> String {
        var s = line
        while let r = s.range(of: "^(#{1,6} |> ?|[-*+] \\[[ xX]\\] |[-*+•—] |\\d{1,9}[.)] )", options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func plainInline(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        for marker in ["**", "__", "~~", "`"] { s = s.replacingOccurrences(of: marker, with: "") }
        s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])[*_]([^*_]+)[*_](?![A-Za-z0-9])", with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Dòng mô tả dưới tiêu đề trong sidebar: dòng chữ đầu tiên SAU tiêu đề
    var snippet: String {
        var lines = Note.plainLines(content)
        if Note.leadingHeading(in: content) != nil, !lines.isEmpty { lines.removeFirst() }
        else if title.isEmpty, !lines.isEmpty { lines.removeFirst() } // dòng đầu đã làm tiêu đề dự phòng
        return lines.first.map { String($0.prefix(120)) } ?? ""
    }
}

// MARK: - Thư mục dữ liệu (NOTESTUDIO_DATA_DIR ghi đè — dùng khi chạy thử, không đụng dữ liệu thật)

enum StudioPaths {
    static let dataDirectory: URL = {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["NOTESTUDIO_DATA_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NoteStudio", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}

extension Note {
    /// Note mới với tiêu đề đặt vào dòng "# " đầu (nội dung đã có "# " thì giữ nguyên)
    func titled(_ newTitle: String) -> Note {
        var copy = self
        if Note.leadingHeading(in: copy.content) != nil {
            copy.syncTitleFromContent()
        } else {
            copy.setTitleInContent(newTitle)
        }
        return copy
    }
}
