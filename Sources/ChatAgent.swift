import Foundation

// MARK: - Bộ tool cho AI agent: toàn quyền thao tác với ghi chú trong app

enum AgentTools {
    static let systemPrompt = """
    Bạn là trợ lý AI bên trong app ghi chú NoteStudio trên macOS, có TOÀN QUYỀN làm việc với ghi chú của người dùng qua các tools: list_notes, search_notes, read_note, create_note, update_note, append_to_note, delete_note, get_active_note, get_stats, select_note.

    Cách làm việc:
    - Câu hỏi kiến thức chung, giải thích, dịch thuật: trả lời trực tiếp bằng kiến thức của bạn, KHÔNG cần gọi tool.
    - Khi hội thoại liên quan đến ghi chú của người dùng (review, tìm, tóm tắt, đối chiếu, thống kê, liệt kê…): LUÔN gọi tool trước (list_notes / search_notes / read_note / get_stats) để có dữ liệu thật. TUYỆT ĐỐI không trả lời suông hay yêu cầu người dùng gửi nội dung — họ không thể đính kèm note qua chat (trừ cú pháp @tên-ghi-chú, khi đó nội dung đã đính kèm cuối tin nhắn).
    - Khi brainstorm / research: chủ động đọc các ghi chú liên quan để bám bối cảnh, rồi đề xuất ý tưởng mới; nếu người dùng muốn lưu kết quả, gọi create_note.
    - Khi người dùng yêu cầu tạo / sửa / bổ sung / ghim / gắn thẻ / xóa: gọi tool tương ứng rồi xác nhận ngắn gọn những gì đã làm.
    - delete_note KHÔNG xóa ngay: app gom mọi đề nghị xóa vào MỘT thẻ xác nhận ngay dưới câu trả lời của bạn (người dùng có thể bỏ chọn từng ghi chú, và hoàn tác bằng ⌘Z). Sau khi gọi, chỉ cần nói ngắn gọn bạn đề nghị xóa những ghi chú nào và mời người dùng xác nhận ở thẻ bên dưới.
    - Nếu người dùng nhắc đến ghi chú bằng cú pháp @tên-ghi-chú thì nội dung đã đính kèm cuối tin nhắn, không cần đọc lại bằng tool.
    - Người dùng có thể đính kèm ảnh (bạn nhìn thấy trực tiếp) và tài liệu (nội dung nằm giữa [Tệp đính kèm: …] và [Hết tệp …]). Hãy phân tích kỹ nội dung đó: tóm tắt, rút ý chính, số liệu, việc cần làm. Chỉ tạo ghi chú khi người dùng yêu cầu — ở cuối câu trả lời có thể gợi ý ngắn "muốn mình lưu thành ghi chú không?".
    - Trả lời bằng tiếng Việt, ngắn gọn, hữu ích; dùng markdown khi trình bày có cấu trúc.
    """

    // Định nghĩa function theo chuẩn OpenAI (được bọc {"type":"function","function":…} khi gửi)
    static let functionDefinitions: [[String: Any]] = [
        [
            "name": "list_notes",
            "description": "Liệt kê tất cả ghi chú (id, tiêu đề, thẻ, thời gian sửa).",
            "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ],
        [
            "name": "search_notes",
            "description": "Tìm ghi chú theo từ khóa trong tiêu đề và nội dung.",
            "parameters": [
                "type": "object",
                "properties": ["query": ["type": "string", "description": "Từ khóa tìm kiếm"]],
                "required": ["query"]
            ] as [String: Any]
        ],
        [
            "name": "read_note",
            "description": "Đọc đầy đủ nội dung một ghi chú theo id.",
            "parameters": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "UUID của ghi chú"]],
                "required": ["id"]
            ] as [String: Any]
        ],
        [
            "name": "append_to_note",
            "description": "Bổ sung nội dung vào CUỐI một ghi chú có sẵn (không ghi đè nội dung cũ).",
            "parameters": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "UUID của ghi chú"],
                    "text": ["type": "string", "description": "Nội dung cần bổ sung"]
                ],
                "required": ["id", "text"]
            ] as [String: Any]
        ],
        [
            "name": "get_active_note",
            "description": "Lấy ghi chú đang được chọn trong app (nếu có).",
            "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ],
        [
            "name": "get_stats",
            "description": "Thống kê kho ghi chú: tổng số, số đã ghim, số lượng theo từng thẻ.",
            "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ],
        [
            "name": "create_note",
            "description": "Tạo ghi chú mới. Người dùng sẽ thấy ghi chú này hiện ngay trong app.",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Tiêu đề"],
                    "content": ["type": "string", "description": "Nội dung"],
                    "pinned": ["type": "boolean", "description": "Ghim lên đầu (mặc định false)"],
                    "tags": ["type": "array", "items": ["type": "string"], "description": "Các thẻ"]
                ],
                "required": ["title"]
            ] as [String: Any]
        ],
        [
            "name": "update_note",
            "description": "Cập nhật tiêu đề, nội dung, ghim hoặc thẻ của một ghi chú. Chỉ truyền các trường cần thay đổi.",
            "parameters": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "UUID của ghi chú"],
                    "title": ["type": "string"],
                    "content": ["type": "string"],
                    "pinned": ["type": "boolean"],
                    "tags": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["id"]
            ] as [String: Any]
        ],
        [
            "name": "delete_note",
            "description": "Xóa vĩnh viễn một ghi chú. Chỉ dùng khi người dùng yêu cầu rõ ràng.",
            "parameters": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "UUID của ghi chú"]],
                "required": ["id"]
            ] as [String: Any]
        ],
        [
            "name": "select_note",
            "description": "Chọn và hiển thị một ghi chú trong app (chuyển sang màn ghi chú để người dùng xem).",
            "parameters": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "UUID của ghi chú"]],
                "required": ["id"]
            ] as [String: Any]
        ]
    ]

    // MARK: Thực thi tool, trả về chuỗi JSON kết quả để feed lại cho model

    @discardableResult
    static func execute(name: String, argumentsJSON: String, store: NotesStore) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        let result: [String: Any]

        switch name {
        case "list_notes":
            result = ["notes": store.notes.map { note in
                [
                    "id": note.id.uuidString,
                    "title": note.displayTitle,
                    "pinned": note.pinned,
                    "tags": note.displayTags,
                    "updatedAt": note.updatedAt.studioRelative
                ] as [String: Any]
            }]

        case "search_notes":
            let query = args["query"] as? String ?? ""
            let matches = store.notes.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || $0.content.localizedCaseInsensitiveContains(query)
            }
            result = ["query": query, "matches": matches.map { note in
                [
                    "id": note.id.uuidString,
                    "title": note.displayTitle,
                    "snippet": String(note.content.prefix(200))
                ] as [String: Any]
            }]

        case "read_note":
            if let note = note(from: args, in: store) {
                result = ["id": note.id.uuidString, "title": note.displayTitle,
                          "content": note.content, "tags": note.displayTags, "pinned": note.pinned]
            } else {
                result = ["error": "Không tìm thấy ghi chú với id đã cho"]
            }

        case "append_to_note":
            if let id = uuid(from: args), store.notes.contains(where: { $0.id == id }) {
                let text = args["text"] as? String ?? ""
                store.appendContent(text, to: id)
                result = ["appended": true, "id": id.uuidString]
            } else {
                result = ["error": "Không tìm thấy ghi chú với id đã cho"]
            }

        case "get_active_note":
            if let note = store.selectedNote {
                result = ["id": note.id.uuidString, "title": note.displayTitle,
                          "content": note.content, "tags": note.displayTags]
            } else {
                result = ["active": false, "hint": "Người dùng chưa chọn ghi chú nào trong app"]
            }

        case "get_stats":
            let tagCounts = Dictionary(grouping: store.notes.flatMap { $0.displayTags }, by: { $0 })
                .mapValues { $0.count }
            result = [
                "total": store.notes.count,
                "pinned": store.notes.filter(\.pinned).count,
                "tags": tagCounts
            ]

        case "create_note":
            let note = store.createAINote(
                title: args["title"] as? String ?? "",
                content: args["content"] as? String ?? "",
                pinned: args["pinned"] as? Bool ?? false,
                tags: args["tags"] as? [String]
            )
            result = ["created": true, "id": note.id.uuidString, "title": note.displayTitle]

        case "update_note":
            if let id = uuid(from: args) {
                let ok = store.updateAIFields(
                    noteID: id,
                    title: args["title"] as? String,
                    content: args["content"] as? String,
                    pinned: args["pinned"] as? Bool,
                    tags: args["tags"] as? [String]
                )
                result = ok ? ["updated": true, "id": id.uuidString]
                            : ["error": "Không tìm thấy ghi chú với id đã cho"]
            } else {
                result = ["error": "Thiếu hoặc sai id"]
            }

        case "delete_note":
            if let id = uuid(from: args), let note = store.notes.first(where: { $0.id == id }) {
                // Không xóa ngay — UI sẽ hiển thị nút xác nhận cho người dùng
                result = [
                    "status": "awaiting_user_confirmation",
                    "id": id.uuidString,
                    "title": note.displayTitle,
                    "hint": "Chưa xóa. UI hiển thị thẻ xác nhận gộp bên dưới câu trả lời — mời người dùng xác nhận ở đó."
                ]
            } else {
                result = ["error": "Không tìm thấy ghi chú với id đã cho"]
            }

        case "select_note":
            if let id = uuid(from: args), store.notes.contains(where: { $0.id == id }) {
                store.activeSection = .notes
                store.select(id)
                result = ["shown": true, "id": id.uuidString]
            } else {
                result = ["error": "Không tìm thấy ghi chú với id đã cho"]
            }

        default:
            result = ["error": "Tool không tồn tại: \(name)"]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: Tóm tắt ngắn hiển thị dạng pill trong chat

    static func uiSummary(for name: String, argumentsJSON: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        switch name {
        case "list_notes": return "Liệt kê ghi chú"
        case "search_notes": return "Tìm kiếm \"\(args["query"] as? String ?? "")\""
        case "read_note": return "Đọc ghi chú"
        case "create_note": return "Tạo ghi chú \"\(args["title"] as? String ?? "")\""
        case "update_note": return "Cập nhật ghi chú"
        case "append_to_note": return "Bổ sung vào ghi chú"
        case "get_active_note": return "Xem ghi chú đang chọn"
        case "get_stats": return "Thống kê kho ghi chú"
        case "delete_note": return "Đề nghị xóa ghi chú"
        case "select_note": return "Mở ghi chú trong app"
        default: return "Gọi \(name)"
        }
    }

    private static func uuid(from args: [String: Any]) -> UUID? {
        UUID(uuidString: args["id"] as? String ?? "")
    }

    private static func note(from args: [String: Any], in store: NotesStore) -> Note? {
        guard let id = uuid(from: args) else { return nil }
        return store.notes.first { $0.id == id }
    }
}
