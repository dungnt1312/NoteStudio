import Foundation

// MARK: - Bộ tool cho AI agent: toàn quyền thao tác với ghi chú trong app

enum AgentTools {
    // computed var: đổi ngôn ngữ thì prompt (và ngôn ngữ trả lời) đổi theo ngay
    static var systemPrompt: String {
        if LocalizationManager.resolvedLanguage == .vietnamese {
            return """
            Bạn là trợ lý AI bên trong app ghi chú NoteStudio trên macOS, có TOÀN QUYỀN làm việc với ghi chú của người dùng qua các tools: list_notes, search_notes, read_note, create_note, update_note, append_to_note, delete_note, get_active_note, get_stats, select_note.

            Cách làm việc:
            - Câu hỏi kiến thức chung, giải thích, dịch thuật: trả lời trực tiếp bằng kiến thức của bạn, KHÔNG cần gọi tool.
            - Khi hội thoại liên quan đến ghi chú của người dùng (review, tìm, tóm tắt, đối chiếu, thống kê, liệt kê…): LUÔN gọi tool trước (list_notes / search_notes / read_note / get_stats) để có dữ liệu thật. TUYỆT ĐỐI không trả lời suông hay yêu cầu người dùng gửi nội dung — họ không thể đính kèm note qua chat (trừ cú pháp @tên-ghi-chú, khi đó nội dung đã đính kèm cuối tin nhắn).
            - Khi brainstorm / research: chủ động đọc các ghi chú liên quan để bám bối cảnh, rồi đề xuất ý tưởng mới; nếu người dùng muốn lưu kết quả, gọi create_note.
            - Khi người dùng yêu cầu tạo / sửa / bổ sung / ghim / gắn thẻ / xóa: gọi tool tương ứng rồi xác nhận ngắn gọn những gì đã làm.
            - Ghi chú dài: read_note hỗ trợ offset/limit (theo dòng) để đọc từng phần; update_note nhận offset/limit cùng content để thay/chèn từng đoạn dòng thay vì ghi đè cả ghi chú.
            - delete_note KHÔNG xóa ngay: app gom mọi đề nghị xóa vào MỘT thẻ xác nhận ngay dưới câu trả lời của bạn (người dùng có thể bỏ chọn từng ghi chú, và hoàn tác bằng ⌘Z). Sau khi gọi, chỉ cần nói ngắn gọn bạn đề nghị xóa những ghi chú nào và mời người dùng xác nhận ở thẻ bên dưới.
            - Nếu người dùng nhắc đến ghi chú bằng cú pháp @tên-ghi-chú thì nội dung đã đính kèm cuối tin nhắn, không cần đọc lại bằng tool.
            - Người dùng có thể đính kèm ảnh (bạn nhìn thấy trực tiếp) và tài liệu (nội dung nằm giữa [Tệp đính kèm: …] và [Hết tệp …]). Hãy phân tích kỹ nội dung đó: tóm tắt, rút ý chính, số liệu, việc cần làm. Chỉ tạo ghi chú khi người dùng yêu cầu — ở cuối câu trả lời có thể gợi ý ngắn "muốn mình lưu thành ghi chú không?".
            - Trả lời bằng tiếng Việt, ngắn gọn, hữu ích; dùng markdown khi trình bày có cấu trúc.
            """
        }
        return """
        You are the AI assistant inside NoteStudio, a note-taking app on macOS, with FULL authority to work with the user's notes through these tools: list_notes, search_notes, read_note, create_note, update_note, append_to_note, delete_note, get_active_note, get_stats, select_note.

        How to work:
        - General knowledge questions, explanations, translations: answer directly from your own knowledge, NO tool call needed.
        - When the conversation concerns the user's notes (review, search, summarize, compare, stats, listing…): ALWAYS call a tool first (list_notes / search_notes / read_note / get_stats) to get real data. NEVER answer from thin air or ask the user to paste content — they cannot attach notes to chat (except the @note-title syntax, in which case the content is already attached at the end of the message).
        - When brainstorming / researching: proactively read related notes to ground context, then propose new ideas; if the user wants to keep the result, call create_note.
        - When the user asks to create / edit / append / pin / tag / delete: call the matching tool, then briefly confirm what you did.
        - Long notes: read_note supports offset/limit (line-based) for reading in parts; update_note accepts offset/limit with content to replace/insert line ranges instead of overwriting the whole note.
        - delete_note does NOT delete immediately: the app gathers all delete suggestions into ONE confirmation card right below your reply (the user can uncheck individual notes, and undo with ⌘Z). After calling it, just briefly say which notes you suggest deleting and invite the user to confirm in the card below.
        - If the user refers to a note with the @note-title syntax, its content is already attached at the end of the message — no need to read it again with a tool.
        - The user can attach images (you see them directly) and documents (content is between [Attachment: …] and [End of file …]). Analyze that content carefully: summary, key points, numbers, action items. Only create a note when asked — you may end with a short offer like "want me to save this as a note?".
        - Reply in English, concise and helpful; use markdown when structure helps.
        """
    }

    // Định nghĩa function theo chuẩn OpenAI (được bọc {"type":"function","function":…} khi gửi)
    static let functionDefinitions: [[String: Any]] = [
        [
            "name": "list_notes",
            "description": L("List all notes (id, title, tags, updated time)."),
            "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ],
        [
            "name": "search_notes",
            "description": L("Search notes by keyword in title and content."),
            "parameters": [
                "type": "object",
                "properties": ["query": ["type": "string", "description": L("Search keyword")]],
                "required": ["query"]
            ] as [String: Any]
        ],
        [
            "name": "read_note",
            "description": L("Read a note's content by id. For long notes, read in parts with offset/limit (line-based)."),
            "parameters": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": L("UUID of the note")],
                    "offset": ["type": "integer", "description": L("Line to start reading from, 0-based (default 0)")],
                    "limit": ["type": "integer", "description": L("Max lines to return (default: to the end)")]
                ],
                "required": ["id"]
            ] as [String: Any]
        ],
        [
            "name": "append_to_note",
            "description": L("Append content to the END of an existing note (does not overwrite)."),
            "parameters": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": L("UUID of the note")],
                    "text": ["type": "string", "description": L("Content to append")]
                ],
                "required": ["id", "text"]
            ] as [String: Any]
        ],
        [
            "name": "get_active_note",
            "description": L("Get the note currently selected in the app (if any)."),
            "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ],
        [
            "name": "get_stats",
            "description": L("Note stats: total count, pinned count, count per tag."),
            "parameters": ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
        ],
        [
            "name": "create_note",
            "description": L("Create a new note. The user will see it appear in the app right away."),
            "parameters": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": L("Title")],
                    "content": ["type": "string", "description": L("Content")],
                    "pinned": ["type": "boolean", "description": L("Pin to top (default false)")],
                    "tags": ["type": "array", "items": ["type": "string"], "description": L("Tags")]
                ],
                "required": ["title"]
            ] as [String: Any]
        ],
        [
            "name": "update_note",
            "description": L("Update a note's title, content, pinned state or tags. Only pass the fields to change. Pass offset (+ optional limit) with content to replace/insert a line range instead of overwriting the whole note."),
            "parameters": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": L("UUID of the note")],
                    "title": ["type": "string"],
                    "content": ["type": "string"],
                    "pinned": ["type": "boolean"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "offset": ["type": "integer", "description": L("Line to start replacing/inserting at, 0-based (only with content; with limit → replaces that many lines, without limit → inserts at that line)")],
                    "limit": ["type": "integer", "description": L("Number of lines replaced (omit/0 = insert only, no lines removed)")]
                ],
                "required": ["id"]
            ] as [String: Any]
        ],
        [
            "name": "delete_note",
            "description": L("Permanently delete a note. Only use when the user explicitly asks."),
            "parameters": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": L("UUID of the note")]],
                "required": ["id"]
            ] as [String: Any]
        ],
        [
            "name": "select_note",
            "description": L("Select and show a note in the app (switches to the notes screen)."),
            "parameters": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": L("UUID of the note")]],
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
                var payload: [String: Any] = ["id": note.id.uuidString, "title": note.displayTitle,
                                              "content": note.content, "tags": note.displayTags,
                                              "pinned": note.pinned,
                                              "totalLines": NoteText.lines(note.content).count]
                if args["offset"] != nil || args["limit"] != nil {
                    let window = NoteText.slice(
                        note.content,
                        offset: (args["offset"] as? NSNumber)?.intValue ?? 0,
                        limit: (args["limit"] as? NSNumber)?.intValue
                    )
                    payload["content"] = window.text
                    payload["offset"] = window.offset
                    payload["returnedLines"] = window.count
                    payload["hasMore"] = window.hasMore
                }
                result = payload
            } else {
                result = ["error": L("No note found with the given id")]
            }

        case "append_to_note":
            if let id = uuid(from: args), store.notes.contains(where: { $0.id == id }) {
                let text = args["text"] as? String ?? ""
                store.appendContent(text, to: id)
                result = ["appended": true, "id": id.uuidString]
            } else {
                result = ["error": L("No note found with the given id")]
            }

        case "get_active_note":
            if let note = store.selectedNote {
                result = ["id": note.id.uuidString, "title": note.displayTitle,
                          "content": note.content, "tags": note.displayTags]
            } else {
                result = ["active": false, "hint": L("The user has not selected any note in the app")]
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
                if (args["offset"] as? NSNumber) != nil && args["content"] == nil {
                    result = ["error": L("offset/limit must be passed together with content (the replacement or inserted text)")]
                } else {
                    var content = args["content"] as? String
                    if let offset = (args["offset"] as? NSNumber)?.intValue,
                       let current = store.note(id)?.content {
                        // Thay `limit` dòng từ offset (limit bỏ qua/0 = chèn tại vị trí đó)
                        content = NoteText.splice(
                            current,
                            offset: offset,
                            limit: (args["limit"] as? NSNumber)?.intValue,
                            replacement: content ?? ""
                        )
                    }
                    let ok = store.updateAIFields(
                        noteID: id,
                        title: args["title"] as? String,
                        content: content,
                        pinned: args["pinned"] as? Bool,
                        tags: args["tags"] as? [String]
                    )
                    result = ok ? ["updated": true, "id": id.uuidString]
                                : ["error": "Không tìm thấy ghi chú với id đã cho"]
                }
            } else {
                result = ["error": L("Missing or invalid id")]
            }

        case "delete_note":
            if let id = uuid(from: args), let note = store.notes.first(where: { $0.id == id }) {
                // Không xóa ngay — UI sẽ hiển thị nút xác nhận cho người dùng
                result = [
                    "status": "awaiting_user_confirmation",
                    "id": id.uuidString,
                    "title": note.displayTitle,
                    "hint": L("Not deleted. The UI shows a combined confirmation card below the reply — ask the user to confirm there.")
                ]
            } else {
                result = ["error": L("No note found with the given id")]
            }

        case "select_note":
            if let id = uuid(from: args), store.notes.contains(where: { $0.id == id }) {
                store.activeSection = .notes
                store.select(id)
                result = ["shown": true, "id": id.uuidString]
            } else {
                result = ["error": L("No note found with the given id")]
            }

        default:
            result = ["error": Lf("Unknown tool: %@", name)]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: Tóm tắt ngắn hiển thị dạng pill trong chat

    static func uiSummary(for name: String, argumentsJSON: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        switch name {
        case "list_notes": return L("List notes")
        case "search_notes": return Lf("Search “%@”", args["query"] as? String ?? "")
        case "read_note": return L("Read note")
        case "create_note": return Lf("Create note “%@”", args["title"] as? String ?? "")
        case "update_note": return L("Update note")
        case "append_to_note": return L("Append to note")
        case "get_active_note": return L("View active note")
        case "get_stats": return L("Note stats")
        case "delete_note": return L("Suggest deleting a note")
        case "select_note": return L("Open note in app")
        default: return Lf("Call %@", name)
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
