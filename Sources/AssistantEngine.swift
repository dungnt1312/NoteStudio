import SwiftUI
import AppKit

// MARK: - Vòng lặp AI agent dùng chung cho chat toàn màn hình và panel cạnh editor

@MainActor
final class AssistantEngine: ObservableObject {
    @Published private(set) var isLoading = false
    @Published var errorText: String?
    /// Kết quả xác nhận xóa của từng tool message delete_note (true = đã xóa, false = giữ lại)
    @Published private(set) var resolvedDeletes: [UUID: Bool] = [:]

    private unowned let store: NotesStore
    private var agentTask: Task<Void, Never>?

    init(store: NotesStore) {
        self.store = store
    }

    // MARK: Gửi tin nhắn

    /// Gom ghi chú được nhắc đến (chip + cú pháp @tên gõ tay) và tệp đính kèm rồi chạy agent.
    func send(_ rawText: String, mentions chips: [MentionedNote], attachments: [ChatAttachment] = []) {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !text.isEmpty || !attachments.isEmpty else { return }
        if text.isEmpty { text = AttachmentStore.defaultPrompt }

        var mentioned: [Note] = chips.compactMap { chip in store.notes.first { $0.id == chip.id } }
        for note in store.notes where !mentioned.contains(where: { $0.id == note.id }) {
            if text.range(of: "@" + note.displayTitle, options: .caseInsensitive) != nil {
                mentioned.append(note)
            }
        }
        var apiText = text
        if !mentioned.isEmpty {
            let blocks = mentioned.map { Lf("[Note @%@]", $0.displayTitle) + "\n\($0.content)" }
                .joined(separator: "\n\n")
            apiText += "\n\n" + blocks
        }
        submitTurn(
            userText: text,
            apiText: apiText,
            mentions: mentioned.map { MentionedNote(id: $0.id, title: $0.displayTitle) },
            attachments: attachments
        )
    }

    /// Quick AI từ editor: bôi đen đoạn văn → chọn hành động
    func submitQuick(text: String, prompt: String, mentions: [MentionedNote]) {
        guard !isLoading else { return }
        submitTurn(userText: text, apiText: prompt, mentions: mentions)
    }

    func stop() {
        agentTask?.cancel()
    }

    func regenerate(from messageID: UUID) {
        guard !isLoading else { return }
        store.truncateChat(after: messageID, includingSelf: false)
        errorText = nil
        runAgentTurn()
    }

    private func submitTurn(userText: String, apiText: String, mentions: [MentionedNote], attachments: [ChatAttachment] = []) {
        errorText = nil
        if store.agentHistory.count > 40 {
            store.rebuildAgentHistoryFromMessages(keepLast: 24)
        }
        syncSystemPrompt()
        store.appendChatMessage(ChatMessage(
            role: .user, text: userText, mentions: mentions,
            attachments: attachments.isEmpty ? nil : attachments
        ))
        store.agentHistory.append([
            "role": "user",
            "content": AttachmentStore.userContent(text: apiText, attachments: attachments)
        ])
        store.syncAgentHistoryToActiveSession()
        runAgentTurn()
    }

    private func syncSystemPrompt() {
        let currentSystem = AgentTools.systemPrompt
        if store.agentHistory.isEmpty {
            store.agentHistory.append(["role": "system", "content": currentSystem])
        } else if store.agentHistory.first?["role"] as? String == "system" {
            store.agentHistory[0]["content"] = currentSystem
        } else {
            store.agentHistory.insert(["role": "system", "content": currentSystem], at: 0)
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    // MARK: Vòng lặp agent (streaming, không giới hạn bước — ngắt bằng nút Dừng)

    private func runAgentTurn() {
        isLoading = true
        agentTask = Task { @MainActor in
            defer { isLoading = false }
            while !Task.isCancelled {
                let streamId = UUID()
                var streamedText = ""
                var response: LLMService.LLMResponse

                do {
                    response = try await LLMService.chatStreaming(
                        messages: AttachmentStore.expandForAPI(store.agentHistory),
                        tools: AgentTools.functionDefinitions,
                        onDelta: { [weak self] fragment in
                            streamedText += fragment
                            self?.store.upsertStreamingMessage(id: streamId, text: streamedText)
                        }
                    )
                } catch {
                    if isCancellation(error) { return }
                    // Provider không hỗ trợ stream / lỗi tạm thời → thử lại không stream
                    do {
                        response = try await LLMService.chatWithTools(
                            messages: AttachmentStore.expandForAPI(store.agentHistory),
                            tools: AgentTools.functionDefinitions
                        )
                    } catch {
                        if isCancellation(error) { return }
                        errorText = Self.friendlyError(error, history: store.agentHistory)
                        return
                    }
                }

                if !response.toolCalls.isEmpty {
                    var assistantMessage: [String: Any] = ["role": "assistant"]
                    assistantMessage["content"] = response.content
                    assistantMessage["tool_calls"] = response.toolCalls.map { call in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": ["name": call.name, "arguments": call.argumentsJSON]
                        ] as [String: Any]
                    }
                    store.agentHistory.append(assistantMessage)

                    for call in response.toolCalls {
                        if Task.isCancelled { break }
                        let resultJSON = AgentTools.execute(
                            name: call.name,
                            argumentsJSON: call.argumentsJSON,
                            store: store
                        )
                        store.appendChatMessage(ChatMessage(
                            role: .tool,
                            text: AgentTools.uiSummary(for: call.name, argumentsJSON: call.argumentsJSON),
                            toolName: call.name,
                            toolArgs: call.argumentsJSON,
                            toolResult: resultJSON
                        ))
                        store.agentHistory.append([
                            "role": "tool",
                            "tool_call_id": call.id,
                            "content": resultJSON
                        ])
                    }
                    store.syncAgentHistoryToActiveSession()
                    continue
                }

                let finalText = response.content.isEmpty ? L("(AI returned no content)") : response.content
                if store.activeMessages.last?.id == streamId {
                    store.upsertStreamingMessage(id: streamId, text: finalText)
                } else {
                    store.appendChatMessage(ChatMessage(id: streamId, role: .assistant, text: finalText))
                }
                store.agentHistory.append(["role": "assistant", "content": finalText])
                store.syncAgentHistoryToActiveSession()
                break
            }
        }
    }

    /// Model không nhận ảnh → nói rõ cách xử lý thay vì dump lỗi API
    private static func friendlyError(_ error: Error, history: [[String: Any]]) -> String {
        let message = error.localizedDescription
        let hasImage = history.contains { message in
            (message["content"] as? [[String: Any]])?.contains { $0["type"] as? String == "image_ref" } == true
        }
        let lowered = message.lowercased()
        if hasImage, ["image", "vision", "multimodal", "content must be a string", "image_url"].contains(where: lowered.contains) {
            return Lf("Model %1$@ can't read images. Pick a vision-capable model (e.g. gpt-4o, gpt-4o-mini, llava) in the model menu above. — %2$@", LLMService.activeProvider.model, message)
        }
        return message
    }

    // MARK: Xác nhận xóa ghi chú do AI đề nghị

    struct PendingDelete: Identifiable {
        let id: UUID          // tool message id
        let noteID: UUID
        let title: String
    }

    /// Các đề nghị xóa chưa được trả lời. Note đã không còn thì coi như xong.
    func pendingDeletes(in messages: [ChatMessage]) -> [PendingDelete] {
        messages.compactMap { message in
            guard message.toolName == "delete_note", resolvedDeletes[message.id] == nil,
                  let noteID = Self.deleteTarget(of: message),
                  let note = store.notes.first(where: { $0.id == noteID }) else { return nil }
            return PendingDelete(id: message.id, noteID: noteID, title: note.displayTitle)
        }
    }

    func confirmDeletes(_ items: [PendingDelete]) {
        guard !items.isEmpty else { return }
        store.delete(noteIDs: items.map(\.noteID))
        for item in items { resolvedDeletes[item.id] = true }
    }

    func rejectDeletes(_ items: [PendingDelete]) {
        for item in items { resolvedDeletes[item.id] = false }
    }

    func deleteResolution(for message: ChatMessage) -> Bool? {
        resolvedDeletes[message.id]
    }

    static func deleteTarget(of message: ChatMessage) -> UUID? {
        guard let data = message.toolArgs?.data(using: .utf8),
              let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return UUID(uuidString: args["id"] as? String ?? "")
    }

    /// Tiêu đề lấy từ kết quả tool (vẫn đọc được sau khi note đã bị xóa)
    static func deleteTitle(of message: ChatMessage) -> String? {
        guard let data = message.toolResult?.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return result["title"] as? String
    }
}
