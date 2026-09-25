import Foundation

// MARK: - Model phiên hội thoại AI (lưu/tải chats.json)

struct MentionedNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user, assistant, tool
    }

    var id = UUID()
    var role: Role
    var text: String
    // Các ghi chú được @mention trong tin nhắn user
    var mentions: [MentionedNote]?
    // Ảnh / tài liệu đính kèm trong tin nhắn user
    var attachments: [ChatAttachment]?
    // Dành cho role .tool: lưu chi tiết để expand xem được
    var toolName: String?
    var toolArgs: String?
    var toolResult: String?

    init(id: UUID = UUID(), role: Role, text: String,
         mentions: [MentionedNote]? = nil,
         attachments: [ChatAttachment]? = nil,
         toolName: String? = nil, toolArgs: String? = nil, toolResult: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.mentions = mentions
        self.attachments = attachments
        self.toolName = toolName
        self.toolArgs = toolArgs
        self.toolResult = toolResult
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var messages: [ChatMessage] = []
    // Lịch sử agent (system/tool_calls/tool) serialize bằng JSONSerialization vì chứa [String: Any]
    var agentHistoryData: Data?

    init(title: String) {
        self.title = title
    }
}

enum ChatHistoryCodec {
    static func encode(_ history: [[String: Any]]) -> Data? {
        try? JSONSerialization.data(withJSONObject: history, options: [.sortedKeys])
    }

    static func decode(_ data: Data?) -> [[String: Any]] {
        guard let data,
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list
    }
}
