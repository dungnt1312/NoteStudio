import Foundation

// MARK: - Lưu trữ ghi chú: mỗi note là một file .md (notes/<id>.md)
//
// Cấu trúc file: frontmatter tối giản giữ metadata, phần sau là nội dung Markdown
// (tiêu đề vẫn sống ở dòng "# " đầu tiên của nội dung — xem Note.leadingHeading).
//
//   ---
//   id: 3C9A4B1E-...
//   createdAt: 2026-09-26T09:41:00Z
//   updatedAt: 2026-09-26T09:41:00Z
//   pinned: false
//   tags: meeting, product
//   ---
//   # Tiêu đề
//
//   Nội dung...
//
// File này CHỈ dùng Foundation để MCP server (MCPServer/main.swift) compile chung được.

struct NoteFileRecord: Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
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

    var wordCount: Int {
        content.split(whereSeparator: \.isWhitespace).filter { $0 != "#" }.count
    }

    /// Dòng "# Tiêu đề" nếu nó là dòng có chữ đầu tiên của tài liệu (trả về range cả dòng)
    static func leadingHeading(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            let lineEnd = text[index...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[index..<lineEnd]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
                continue
            }
            let trimmed = line.drop(while: { $0 == " " })
            return (trimmed == "#" || trimmed.hasPrefix("# ")) ? index..<lineEnd : nil
        }
        return nil
    }

    /// Nội dung đổi → tiêu đề đi theo dòng "# " đầu
    mutating func syncTitleFromContent() {
        guard let range = Self.leadingHeading(in: content) else { return }
        title = content[range].drop(while: { $0 == " " }).dropFirst().trimmingCharacters(in: .whitespaces)
    }

    /// Tiêu đề đổi (MCP, AI…) → ghi vào dòng "# " đầu, chưa có thì chèn lên đầu
    mutating func setTitleInContent(_ newTitle: String) {
        let clean = newTitle.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if let range = Self.leadingHeading(in: content) {
            content.replaceSubrange(range, with: "# " + clean)
        } else if !clean.isEmpty {
            let body = content.drop(while: { $0 == "\n" })
            content = "# \(clean)" + (body.isEmpty ? "\n" : "\n\n" + body)
        }
        title = clean
    }

    /// Chuẩn hóa: nội dung là nguồn sự thật cho tiêu đề
    func normalized() -> NoteFileRecord {
        var copy = self
        if Self.leadingHeading(in: copy.content) != nil {
            copy.syncTitleFromContent()
        } else if !copy.title.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.setTitleInContent(copy.title)
        }
        return copy
    }
}

// MARK: - Encode/decode giữa NoteFileRecord và file .md

enum NoteFileCodec {
    static func encode(_ record: NoteFileRecord) -> String {
        var text = "---\n"
        text += "id: \(record.id.uuidString)\n"
        text += "createdAt: \(string(from: record.createdAt))\n"
        text += "updatedAt: \(string(from: record.updatedAt))\n"
        text += "pinned: \(record.pinned ? "true" : "false")\n"
        if let tags = record.tags, !tags.isEmpty {
            text += "tags: \(tags.joined(separator: ", "))\n"
        }
        text += "---\n"
        text += record.content
        return text
    }

    /// Đọc một file .md. Thiếu frontmatter (file do người dùng thả vào) → toàn bộ là nội dung,
    /// metadata được sinh mới — không bao giờ mất ghi chú vì file "lạ".
    static func decode(_ raw: String) -> NoteFileRecord {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            var orphan = NoteFileRecord(content: text)
            orphan.syncTitleFromContent()
            return orphan
        }

        lines.removeFirst()
        var meta: [String: String] = [:]
        while let line = lines.first {
            lines.removeFirst()
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            meta[key] = value
        }

        var content = lines.joined(separator: "\n")
        if content.hasPrefix("\n") { content.removeFirst() } // một dòng trống sau frontmatter là bình thường

        var record = NoteFileRecord(content: content)
        if let id = meta["id"].flatMap(UUID.init(uuidString:)) { record.id = id }
        if let created = meta["createdat"].flatMap(parseDate) { record.createdAt = created }
        if let updated = meta["updatedat"].flatMap(parseDate) { record.updatedAt = updated }
        if let pinned = meta["pinned"] { record.pinned = pinned.lowercased() == "true" }
        let tags = (meta["tags"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !tags.isEmpty { record.tags = tags }
        record.syncTitleFromContent()
        return record
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String { isoFormatter.string(from: date) }

    static func parseDate(_ value: String) -> Date? {
        isoFormatter.date(from: value) ?? isoFractionalFormatter.date(from: value)
    }
}

// MARK: - Thao tác theo dòng (đọc/sửa từng phần ghi chú dài qua MCP / AI tools)

enum NoteText {
    /// Tách dòng: nội dung rỗng là 0 dòng; "a\n" là 2 dòng (dòng 1 "a", dòng 2 "")
    static func lines(_ content: String) -> [String] {
        content.isEmpty ? [] : content.components(separatedBy: "\n")
    }

    /// Cắt một cửa sổ dòng: offset tính từ 0; limit nil = đọc đến hết.
    /// Trả về (đoạn văn bản, offset thực tế, số dòng trả về, tổng số dòng, còn tiếp không)
    static func slice(_ content: String, offset: Int, limit: Int?) -> (text: String, offset: Int, count: Int, total: Int, hasMore: Bool) {
        let all = lines(content)
        let start = min(max(offset, 0), all.count)
        let end = min(start + max(limit ?? (all.count - start), 0), all.count)
        return (all[start..<end].joined(separator: "\n"), start, end - start, all.count, end < all.count)
    }

    /// Thay `limit` dòng tính từ `offset` bằng `replacement`.
    /// limit nil/0 = chèn tại vị trí offset (không xóa dòng nào); replacement rỗng = chỉ xóa vùng chọn.
    static func splice(_ content: String, offset: Int, limit: Int?, replacement: String) -> String {
        var all = lines(content)
        let start = min(max(offset, 0), all.count)
        let removed = min(max(limit ?? 0, 0), all.count - start)
        all.replaceSubrange(start..<(start + removed), with: lines(replacement))
        return all.joined(separator: "\n")
    }
}

// MARK: - Thư mục notes/<id>.md (NOTESTUDIO_DATA_DIR ghi đè — dùng khi chạy thử)

enum NoteFileStore {
    static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["NOTESTUDIO_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoteStudio", isDirectory: true)
    }

    static var notesDirectory: URL { dataDirectory.appendingPathComponent("notes", isDirectory: true) }
    static var legacyJSONURL: URL { dataDirectory.appendingPathComponent("notes.json") }
    static var legacyImportedURL: URL { dataDirectory.appendingPathComponent("notes.json.imported") }

    /// notes.json cũ → notes/<id>.md, rồi đổi tên notes.json thành notes.json.imported (bản lưu trắng).
    /// Trả về true nếu đã migrate. Không có dữ liệu cũ thì KHÔNG tạo thư mục notes/ (để lần chạy đầu
    /// vẫn biết đây là cài mới và hiện ghi chú mẫu).
    @discardableResult
    static func migrateIfNeeded() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyJSONURL.path) else { return false }
        guard let data = try? Data(contentsOf: legacyJSONURL),
              let legacy = try? makeLegacyDecoder().decode([NoteFileRecord].self, from: data) else { return false }
        try? fm.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        for record in legacy {
            save(record.normalized())
        }
        try? fm.removeItem(at: legacyImportedURL)
        try? fm.moveItem(at: legacyJSONURL, to: legacyImportedURL)
        return true
    }

    private static func makeLegacyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func loadAll() -> [NoteFileRecord] { loadAll(in: notesDirectory) }

    static func loadAll(in directory: URL) -> [NoteFileRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> NoteFileRecord? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return NoteFileCodec.decode(text)
            }
    }

    static func url(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent(id.uuidString + ".md")
    }

    static func save(_ record: NoteFileRecord) {
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try? NoteFileCodec.encode(record).data(using: .utf8)?
            .write(to: url(for: record.id), options: .atomic) // atomic → thư mục notes/ đổi mtime → watcher bắt được
    }

    static func deleteFile(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
