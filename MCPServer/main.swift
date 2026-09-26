// NoteStudio MCP server — expose ghi chú của app cho AI client (ZCode, Claude…) qua stdio.
// Giao thức: JSON-RPC 2.0, mỗi message một dòng (newline-delimited).
// Lưu trữ: mỗi note một file .md tại <data>/notes/<id>.md (dùng chung Sources/NoteFile.swift với app).
// Build: swiftc MCPServer/main.swift Sources/NoteFile.swift -o notestudio-mcp
import Foundation

signal(SIGPIPE, SIG_IGN)

// MARK: - Storage (thư mục notes/<id>.md, NOTESTUDIO_DATA_DIR ghi đè được — giống app)

_ = NoteFileStore.migrateIfNeeded() // notes.json cũ → file .md (chạy một lần)

func loadNotesOrThrow() throws -> [NoteFileRecord] {
    NoteFileStore.loadAll()
}

func recordSummary(_ record: NoteFileRecord) -> [String: Any] {
    [
        "id": record.id.uuidString,
        "title": record.title,
        "pinned": record.pinned,
        "updatedAt": NoteFileCodec.string(from: record.updatedAt),
        "wordCount": record.wordCount
    ]
}

func recordFull(_ record: NoteFileRecord) -> [String: Any] {
    [
        "id": record.id.uuidString,
        "title": record.title,
        "content": record.content,
        "createdAt": NoteFileCodec.string(from: record.createdAt),
        "updatedAt": NoteFileCodec.string(from: record.updatedAt),
        "pinned": record.pinned
    ]
}

func sortedSummaries(_ records: [NoteFileRecord]) -> [[String: Any]] {
    records
        .sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
        .map { recordSummary($0) }
}

/// JSONSerialization trả số dưới dạng NSNumber — đỡ lệch khi client gửi 3 hay 3.0
func intArg(_ args: [String: Any], _ key: String) -> Int? {
    (args[key] as? NSNumber)?.intValue
}

struct ToolError: Error {
    let message: String
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
        guard let note = try loadNotesOrThrow().first(where: { $0.id.uuidString == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        var payload = recordFull(note)
        let totalLines = NoteText.lines(note.content).count
        payload["totalLines"] = totalLines
        if args["offset"] != nil || args["limit"] != nil {
            let window = NoteText.slice(
                note.content,
                offset: intArg(args, "offset") ?? 0,
                limit: intArg(args, "limit")
            )
            payload["content"] = window.text
            payload["offset"] = window.offset
            payload["returnedLines"] = window.count
            payload["hasMore"] = window.hasMore
        }
        return payload

    case "open_note":
        let id = args["id"] as? String ?? ""
        guard try loadNotesOrThrow().contains(where: { $0.id.uuidString == id }) else {
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
        var note = NoteFileRecord(content: content, pinned: pinned)
        note.setTitleInContent(title)
        NoteFileStore.save(note.normalized())
        return ["created": true, "note": recordFull(note)]

    case "update_note":
        let id = args["id"] as? String ?? ""
        guard var note = try loadNotesOrThrow().first(where: { $0.id.uuidString == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        if args["offset"] != nil, args["content"] == nil {
            throw ToolError(message: "offset/limit phải đi kèm content (phần nội dung thay thế hoặc chèn).")
        }
        if let content = args["content"] as? String {
            if let offset = intArg(args, "offset") {
                // Thay `limit` dòng từ offset (limit bỏ qua/0 = chèn tại vị trí đó)
                note.content = NoteText.splice(note.content, offset: offset, limit: intArg(args, "limit"), replacement: content)
            } else {
                note.content = content
            }
            note.syncTitleFromContent()
        }
        if let title = args["title"] as? String { note.setTitleInContent(title) }
        if let pinned = args["pinned"] as? Bool { note.pinned = pinned }
        note.updatedAt = Date()
        NoteFileStore.save(note.normalized())
        var payload = recordFull(note)
        payload["totalLines"] = NoteText.lines(note.content).count
        return payload

    case "delete_note":
        let id = args["id"] as? String ?? ""
        guard let note = try loadNotesOrThrow().first(where: { $0.id.uuidString == id }) else {
            throw ToolError(message: "Không tìm thấy ghi chú với id: \(id)")
        }
        NoteFileStore.deleteFile(id: note.id)
        return ["deleted": id, "remaining": try loadNotesOrThrow().count]

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
        "description": "Đọc nội dung một ghi chú theo id. Ghi chú dài thì đọc từng phần bằng offset/limit (theo dòng).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "UUID của ghi chú"],
                "offset": ["type": "integer", "description": "Dòng bắt đầu đọc, tính từ 0 (mặc định 0)"],
                "limit": ["type": "integer", "description": "Số dòng tối đa trả về (mặc định đọc đến hết)"]
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
        "description": "Tạo ghi chú mới trong NoteStudio (lưu thành file .md). App đang mở sẽ hiện ghi chú này ngay.",
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
        "description": "Cập nhật tiêu đề, nội dung hoặc trạng thái ghim của ghi chú theo id. "
            + "Truyền offset (+limit tùy chọn) cùng content để sửa/chèn từng đoạn dòng thay vì ghi đè cả ghi chú: "
            + "có limit → thay `limit` dòng tính từ offset bằng content; không có limit → chèn content tại dòng offset.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "UUID của ghi chú"],
                "title": ["type": "string"],
                "content": ["type": "string"],
                "pinned": ["type": "boolean"],
                "offset": ["type": "integer", "description": "Dòng bắt đầu thay/chèn, tính từ 0 (chỉ dùng cùng content)"],
                "limit": ["type": "integer", "description": "Số dòng bị thay thế (bỏ qua/0 = chỉ chèn, không xóa dòng nào)"]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "delete_note",
        "description": "Xóa vĩnh viễn một ghi chú theo id (xóa file .md tương ứng).",
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
                "serverInfo": ["name": "notestudio-mcp", "version": "1.2.0"]
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
