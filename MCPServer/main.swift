// NoteStudio MCP server — expose ghi chú của app cho AI client (ZCode, Claude…) qua stdio.
// Giao thức: JSON-RPC 2.0, mỗi message một dòng (newline-delimited).
// Build: swiftc MCPServer/main.swift -o notestudio-mcp
import Foundation

signal(SIGPIPE, SIG_IGN)

// MARK: - Storage (dùng chung notes.json với app NoteStudio)

let storageURL: URL = {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NoteStudio", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("notes.json")
}()

struct NoteRecord: Codable {
    var id: String
    var title: String
    var content: String
    var createdAt: String
    var updatedAt: String
    var pinned: Bool
    var tags: [String]?

    init(title: String = "", content: String = "", pinned: Bool = false) {
        self.id = UUID().uuidString
        self.title = ""
        self.content = content
        self.createdAt = NoteRecord.nowISO()
        self.updatedAt = NoteRecord.nowISO()
        self.pinned = pinned
        setTitle(title)
    }

    // Ghi chú là Markdown: tiêu đề sống ở dòng "# " đầu tiên của nội dung
    private func headingRange() -> Range<String.Index>? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let trimmed = line.drop(while: { $0 == " " })
            return (trimmed == "#" || trimmed.hasPrefix("# ")) ? line.startIndex..<line.endIndex : nil
        }
        return nil
    }

    mutating func setTitle(_ newTitle: String) {
        let clean = newTitle.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if let range = headingRange() {
            content.replaceSubrange(range, with: "# " + clean)
        } else if !clean.isEmpty {
            let body = content.drop(while: { $0 == "\n" })
            content = "# \(clean)" + (body.isEmpty ? "\n" : "\n\n" + body)
        }
        title = clean
    }

    mutating func syncTitle() {
        guard let range = headingRange() else { return }
        title = content[range].drop(while: { $0 == " " }).dropFirst().trimmingCharacters(in: .whitespaces)
    }

    static func nowISO() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    var summary: [String: Any] {
        [
            "id": id,
            "title": title,
            "pinned": pinned,
            "updatedAt": updatedAt,
            "wordCount": content.split(whereSeparator: \.isWhitespace).count
        ]
    }

    var full: [String: Any] {
        [
            "id": id,
            "title": title,
            "content": content,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "pinned": pinned
        ]
    }
}

struct ToolError: Error {
    let message: String
}

func loadNotesOrThrow() throws -> [NoteRecord] {
    guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
    do {
        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder().decode([NoteRecord].self, from: data)
    } catch {
        throw ToolError(message: "File dữ liệu hỏng hoặc không đọc được: \(error.localizedDescription)")
    }
}

func saveNotes(_ notes: [NoteRecord]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(notes)
    try data.write(to: storageURL, options: .atomic)
}

func sortedSummaries(_ notes: [NoteRecord]) -> [[String: Any]] {
    notes
        .sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
        .map { $0.summary }
}

// MARK: - Tools

func callTool(name: String, args: [String: Any]) throws -> Any {
    switch name {
    case "list_notes":
        return ["notes": sortedSummaries(try loadNotesOrThrow())]

    case "search_notes":
        let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ToolError(message: "Thiếu từ khóa tìm kiếm (query).")
        }
        let matched = try loadNotesOrThrow().filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
        return ["query": query, "matches": sortedSummaries(matched)]

    case "read_note":
        let id = args["id"] as? String ?? ""
        guard let note = try loadNotesOrThrow().first(where: { $0.id == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        return note.full

    case "open_note":
        let id = args["id"] as? String ?? ""
        guard try loadNotesOrThrow().contains(where: { $0.id == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        let urlString = "notestudio://note/\(id)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [urlString]
        try process.run()
        return ["opened": true, "url": urlString]

    case "create_note":
        let title = args["title"] as? String ?? ""
        let content = args["content"] as? String ?? ""
        let pinned = args["pinned"] as? Bool ?? false
        var notes = try loadNotesOrThrow()
        let note = NoteRecord(title: title, content: content, pinned: pinned)
        notes.append(note)
        try saveNotes(notes)
        return ["created": true, "note": note.full]

    case "update_note":
        let id = args["id"] as? String ?? ""
        var notes = try loadNotesOrThrow()
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        if let content = args["content"] as? String {
            notes[index].content = content
            notes[index].syncTitle()
        }
        if let title = args["title"] as? String { notes[index].setTitle(title) }
        if let pinned = args["pinned"] as? Bool { notes[index].pinned = pinned }
        notes[index].updatedAt = NoteRecord.nowISO()
        try saveNotes(notes)
        return ["updated": true, "note": notes[index].full]

    case "delete_note":
        let id = args["id"] as? String ?? ""
        var notes = try loadNotesOrThrow()
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        notes.remove(at: index)
        try saveNotes(notes)
        return ["deleted": id, "remaining": notes.count]

    default:
        throw ToolError(message: "Tool không tồn tại: \(name)")
    }
}

// MARK: - Định nghĩa tools (schema cho client)

let toolDefinitions: [[String: Any]] = [
    [
        "name": "list_notes",
        "description": "Liệt kê tất cả ghi chú trong app NoteStudio (id, tiêu đề, thời gian sửa, số từ).",
        "inputSchema": [
            "type": "object",
            "properties": [String: Any](),
            "additionalProperties": false
        ]
    ],
    [
        "name": "search_notes",
        "description": "Tìm ghi chú theo từ khóa (so khớp tiêu đề và nội dung, không phân biệt hoa thường).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Từ khóa tìm kiếm"]
            ],
            "required": ["query"]
        ]
    ],
    [
        "name": "read_note",
        "description": "Đọc đầy đủ nội dung một ghi chú theo id.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "UUID của ghi chú"]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "open_note",
        "description": "Mở app NoteStudio và nhảy tới ghi chú theo id (app sẽ hiện lên với ghi chú được chọn).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "UUID của ghi chú"]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "create_note",
        "description": "Tạo ghi chú mới trong NoteStudio. App đang mở sẽ hiện ghi chú này ngay.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Tiêu đề ghi chú"],
                "content": ["type": "string", "description": "Nội dung ghi chú"],
                "pinned": ["type": "boolean", "description": "Ghim lên đầu danh sách (mặc định false)"]
            ],
            "required": ["title"]
        ]
    ],
    [
        "name": "update_note",
        "description": "Cập nhật tiêu đề, nội dung hoặc trạng thái ghim của ghi chú theo id.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "UUID của ghi chú"],
                "title": ["type": "string"],
                "content": ["type": "string"],
                "pinned": ["type": "boolean"]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "delete_note",
        "description": "Xóa vĩnh viễn một ghi chú theo id.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "UUID của ghi chú"]
            ],
            "required": ["id"]
        ]
    ]
]

// MARK: - JSON-RPC over stdio

func send(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    var line = data
    line.append(0x0A)
    FileHandle.standardOutput.write(line)
}

func respond(id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func respondError(id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func textResult(_ text: String, isError: Bool = false) -> [String: Any] {
    var result: [String: Any] = ["content": [["type": "text", "text": text]]]
    if isError { result["isError"] = true }
    return result
}

func pretty(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return "ok" }
    return text
}

func handleMessage(_ message: [String: Any]) {
    let method = message["method"] as? String ?? ""

    if method == "initialize" {
        let params = message["params"] as? [String: Any]
        let requested = params?["protocolVersion"] as? String ?? "2025-06-18"
        respond(
            id: message["id"] ?? NSNull(),
            result: [
                "protocolVersion": requested,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "notestudio-mcp", "version": "1.1.0"]
            ]
        )
        return
    }

    // notification (không có id) → không cần trả lời
    guard message["id"] != nil else { return }
    let id = message["id"]!

    switch method {
    case "ping":
        respond(id: id, result: [:])
    case "tools/list":
        respond(id: id, result: ["tools": toolDefinitions])
    case "tools/call":
        let params = message["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        do {
            guard !name.isEmpty else { throw ToolError(message: "Thiếu tên tool.") }
            respond(id: id, result: textResult(pretty(try callTool(name: name, args: args))))
        } catch let error as ToolError {
            respond(id: id, result: textResult(error.message, isError: true))
        } catch {
            respond(id: id, result: textResult("\(error)", isError: true))
        }
    default:
        respondError(id: id, code: -32601, message: "Method not found: \(method)")
    }
}

var inputBuffer: [UInt8] = []

func handleLine(_ line: [UInt8]) {
    guard !line.isEmpty else { return }
    guard let message = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { return }
    handleMessage(message)
}

FileHandle.standardError.write(Data("[notestudio-mcp] ready\n".utf8))

while true {
    let chunk = FileHandle.standardInput.availableData
    if chunk.isEmpty { break } // client đóng stream
    inputBuffer.append(contentsOf: chunk)
    while let newlineIndex = inputBuffer.firstIndex(of: 0x0A) {
        let line = Array(inputBuffer[..<newlineIndex])
        inputBuffer.removeSubrange(inputBuffer.startIndex...newlineIndex)
        handleLine(line)
    }
}
