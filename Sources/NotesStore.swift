import Foundation
import SwiftUI
import AppKit

// MARK: - Yêu cầu AI nhanh từ editor (bôi đen → chọn hành động)

struct QuickAIRequest: Equatable {
    let id = UUID()
    let text: String        // hiển thị trong bubble user
    let prompt: String      // nội dung đầy đủ gửi API (kèm đoạn trích)
    let mentions: [MentionedNote]

    static func == (lhs: QuickAIRequest, rhs: QuickAIRequest) -> Bool { lhs.id == rhs.id }
}

// MARK: - Thông báo nhỏ ở đáy cửa sổ (kèm nút hành động, ví dụ Hoàn tác)

struct StudioToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    static func == (lhs: StudioToast, rhs: StudioToast) -> Bool { lhs.id == rhs.id }
}

final class NotesStore: ObservableObject {
    enum AppSection: String {
        case notes, chat, settings
    }

    @Published private(set) var notes: [Note] = []
    @Published var selectedNoteID: UUID?
    @Published var searchText = ""
    @Published var activeSection: AppSection = .notes {
        didSet {
            if activeSection != .settings { lastWorkspace = activeSection }
        }
    }
    /// Khu làm việc gần nhất (ghi chú / trợ lý) — quyết định sidebar đang liệt kê gì
    @Published private(set) var lastWorkspace: AppSection = .notes
    @Published var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") }
    }
    /// Trợ lý AI dạng panel bên phải editor
    @Published var showAssistant = UserDefaults.standard.bool(forKey: "showAssistantPanel") {
        didSet { UserDefaults.standard.set(showAssistant, forKey: "showAssistantPanel") }
    }
    @Published var newlyCreatedID: UUID?
    @Published var showCommandPalette = false
    @Published var activeTagFilter: String?
    @Published var toast: StudioToast?

    // Các phiên chat AI — lưu chats.json, giữ nguyên khi qua lại giữa chat và editor
    @Published var chatSessions: [ChatSession] = []
    @Published var activeChatSessionID: UUID?
    @Published var agentHistory: [[String: Any]] = [] // bản làm việc của phiên đang mở

    private var toastTask: Task<Void, Never>?

    private var saveTask: Task<Void, Never>?
    private var chatSaveTask: Task<Void, Never>?
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var lastKnownModificationDate: Date?
    private var reloadWorkItem: DispatchWorkItem?

    private func scheduleChatSave() {
        chatSaveTask?.cancel()
        chatSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            saveChatsNow()
        }
    }

    // MARK: Init

    init() {
        if let stored = Self.load(), !stored.isEmpty {
            let merged = Self.mergeWithICloud(stored)
            notes = merged.map { $0.normalizedMarkdown() }
            if notes != merged { saveNow() }
        } else {
            notes = Self.sampleNotes().map { $0.normalizedMarkdown() }
        }
        selectedNoteID = filteredNotes.first?.id
        startWatchingFile()

        chatSessions = Self.loadChats()
        if chatSessions.isEmpty {
            chatSessions = [ChatSession(title: "Hội thoại mới")]
        }
        activeChatSessionID = chatSessions.first?.id
        agentHistory = ChatHistoryCodec.decode(activeSession?.agentHistoryData)
        collectUnusedAttachments()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveNow()
            self?.saveChatsNow()
        }
    }

    // MARK: Derived data

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = query.isEmpty
            ? notes
            : notes.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.content.localizedCaseInsensitiveContains(query)
            }
        if let tag = activeTagFilter {
            base = base.filter { $0.displayTags.contains(tag) }
        }
        return base.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var allTags: [String] {
        Array(Set(notes.flatMap { $0.displayTags })).sorted()
    }

    var pinnedNotes: [Note] { filteredNotes.filter(\.pinned) }
    var otherNotes: [Note] { filteredNotes.filter { !$0.pinned } }

    func note(_ id: UUID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    // MARK: Actions

    func select(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedNoteID = id
        }
    }

    func createNote() {
        let note = Note(content: "# ")
        activeSection = .notes
        withAnimation(.easeInOut(duration: 0.18)) {
            searchText = ""
            activeTagFilter = nil
            notes.insert(note, at: 0)
            selectedNoteID = note.id
            newlyCreatedID = note.id
        }
        saveNow()
    }

    /// Từ menu bar quick capture: dòng đầu là tiêu đề, phần sau là nội dung.
    func createQuickNote(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let lines = text.components(separatedBy: "\n")
        let title = String(lines[0].prefix(80))
        let body = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : ""
        let note = Note(content: body).titled(title)
        withAnimation(.easeInOut(duration: 0.18)) {
            notes.insert(note, at: 0)
        }
        saveNow()
    }

    func delete(noteID: UUID) {
        delete(noteIDs: [noteID])
    }

    /// Xóa (có Hoàn tác): toast ở đáy cửa sổ + ⌘Z qua undo manager của cửa sổ.
    func delete(noteIDs: [UUID]) {
        let removed: [(index: Int, note: Note)] = notes.enumerated()
            .filter { noteIDs.contains($0.element.id) }
            .map { ($0.offset, $0.element) }
        guard !removed.isEmpty else { return }
        let previousSelection = selectedNoteID
        withAnimation(.easeInOut(duration: 0.18)) {
            notes.removeAll { noteIDs.contains($0.id) }
            if let current = selectedNoteID, noteIDs.contains(current) {
                selectedNoteID = filteredNotes.first?.id
            }
        }
        saveNow()

        let restore: () -> Void = { [weak self] in
            self?.restore(removed, selecting: previousSelection)
        }
        let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
        undoManager?.registerUndo(withTarget: self) { _ in restore() }
        undoManager?.setActionName("Xóa ghi chú")

        let message = removed.count == 1
            ? "Đã xóa “\(removed[0].note.displayTitle)”"
            : "Đã xóa \(removed.count) ghi chú"
        showToast(StudioToast(message: message, actionLabel: "Hoàn tác", action: restore))
    }

    private func restore(_ removed: [(index: Int, note: Note)], selecting previousSelection: UUID?) {
        withAnimation(.easeInOut(duration: 0.18)) {
            for item in removed.sorted(by: { $0.index < $1.index }) where !notes.contains(where: { $0.id == item.note.id }) {
                notes.insert(item.note, at: min(item.index, notes.count))
            }
            if let previousSelection, notes.contains(where: { $0.id == previousSelection }) {
                selectedNoteID = previousSelection
            }
        }
        saveNow()
        showToast(StudioToast(message: removed.count == 1 ? "Đã khôi phục ghi chú" : "Đã khôi phục \(removed.count) ghi chú"))
    }

    func showToast(_ toast: StudioToast) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            self.toast = toast
        }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }

    func togglePin(noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            notes[index].pinned.toggle()
        }
        saveNow()
    }

    /// Sửa đúng note theo id. Không đổi gì thì không chạm updatedAt — tránh danh sách tự nhảy thứ tự
    /// khi ô nhập chỉ ghi lại đúng giá trị cũ (xảy ra lúc đổi note mà ô tiêu đề còn giữ focus).
    func update(noteID: UUID, _ mutate: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        var edited = notes[index]
        mutate(&edited)
        // Nội dung là nguồn sự thật: đổi nội dung → tiêu đề theo dòng "# " đầu; chỉ đổi tiêu đề → ghi vào nội dung
        if edited.content != notes[index].content {
            edited.syncTitleFromContent()
        } else if edited.title != notes[index].title {
            edited.setTitleInContent(edited.title)
        }
        guard edited != notes[index] else { return }
        edited.updatedAt = Date()
        notes[index] = edited
        scheduleSave()
    }

    func updateSelected(_ mutate: (inout Note) -> Void) {
        guard let id = selectedNoteID else { return }
        update(noteID: id, mutate)
    }

    func appendContent(_ addition: String, to noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].content += addition
        notes[index].syncTitleFromContent()
        notes[index].updatedAt = Date()
        saveNow()
    }

    /// Được gọi khi bật/tắt mirror iCloud ở panel phải.
    func iCloudSyncSettingChanged(enabled: Bool) {
        guard enabled else { return }
        notes = Self.mergeWithICloud(notes)
        if let current = selectedNoteID, !notes.contains(where: { $0.id == current }) {
            selectedNoteID = filteredNotes.first?.id
        }
        saveNow()
    }

    // MARK: Phiên chat AI (sessions)

    var activeSession: ChatSession? {
        chatSessions.first { $0.id == activeChatSessionID }
    }

    var activeMessages: [ChatMessage] {
        activeSession?.messages ?? []
    }

    func selectSession(_ id: UUID) {
        activeChatSessionID = id
        agentHistory = ChatHistoryCodec.decode(activeSession?.agentHistoryData)
    }

    func newChatSession() {
        // Đang ở hội thoại trống thì dùng luôn, không đẻ thêm phiên rỗng
        if let active = activeSession, active.messages.isEmpty {
            return
        }
        let session = ChatSession(title: "Hội thoại mới")
        withAnimation(.easeInOut(duration: 0.15)) {
            chatSessions.insert(session, at: 0)
            activeChatSessionID = session.id
        }
        agentHistory = []
        saveChatsNow()
    }

    func deleteSession(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            chatSessions.removeAll { $0.id == id }
        }
        if chatSessions.isEmpty {
            let fresh = ChatSession(title: "Hội thoại mới")
            chatSessions.append(fresh)
            activeChatSessionID = fresh.id
            agentHistory = []
        } else if activeChatSessionID == id {
            selectSession(chatSessions[0].id)
        }
        saveChatsNow()
    }

    func renameSession(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        chatSessions[index].title = trimmed
        saveChatsNow()
    }

    func appendChatMessage(_ message: ChatMessage) {
        if chatSessions.firstIndex(where: { $0.id == activeChatSessionID }) == nil {
            newChatSession()
        }
        guard let index = chatSessions.firstIndex(where: { $0.id == activeChatSessionID }) else { return }
        chatSessions[index].messages.append(message)
        chatSessions[index].updatedAt = Date()
        // Tin nhắn user đầu tiên đặt tên cho hội thoại
        if message.role == .user, chatSessions[index].title == "Hội thoại mới" {
            let files = (message.attachments ?? []).map(\.name).joined(separator: ", ")
            let title = message.text == AttachmentStore.defaultPrompt && !files.isEmpty ? "Phân tích \(files)" : message.text
            chatSessions[index].title = String(title.prefix(48))
        }
        scheduleChatSave()
    }

    func syncAgentHistoryToActiveSession() {
        guard let index = chatSessions.firstIndex(where: { $0.id == activeChatSessionID }) else { return }
        chatSessions[index].agentHistoryData = ChatHistoryCodec.encode(agentHistory)
        scheduleChatSave()
    }

    func clearActiveConversation() {
        guard let index = chatSessions.firstIndex(where: { $0.id == activeChatSessionID }) else { return }
        chatSessions[index].messages = []
        chatSessions[index].agentHistoryData = nil
        agentHistory = []
        saveChatsNow()
    }

    /// Cập nhật text của tin nhắn streaming (tạo mới nếu chưa tồn tại).
    func upsertStreamingMessage(id: UUID, text: String) {
        guard let si = chatSessions.firstIndex(where: { $0.id == activeChatSessionID }) else { return }
        if let mi = chatSessions[si].messages.firstIndex(where: { $0.id == id }) {
            chatSessions[si].messages[mi].text = text
        } else {
            chatSessions[si].messages.append(ChatMessage(id: id, role: .assistant, text: text))
        }
    }

    /// Cắt hội thoại từ một tin nhắn (dùng cho Sửa / Làm lại), sau đó dựng lại agent history.
    func truncateChat(after messageID: UUID, includingSelf: Bool) {
        guard let si = chatSessions.firstIndex(where: { $0.id == activeChatSessionID }),
              let mi = chatSessions[si].messages.firstIndex(where: { $0.id == messageID }) else { return }
        if includingSelf {
            chatSessions[si].messages.removeSubrange(mi...)
        } else {
            chatSessions[si].messages.removeSubrange(chatSessions[si].messages.index(after: mi)...)
        }
        rebuildAgentHistoryFromMessages()
        saveChatsNow()
    }

    /// Dựng lại agent history dạng phẳng (system + user/assistant) từ tin nhắn hiển thị.
    /// Dùng sau khi cắt hội thoại hoặc khi history dài quá cần gọt context.
    func rebuildAgentHistoryFromMessages(keepLast: Int? = nil) {
        var history: [[String: Any]] = [["role": "system", "content": AgentTools.systemPrompt]]
        var messages = activeMessages
        if let keepLast {
            messages = Array(messages.suffix(keepLast))
        }
        for message in messages where message.role != .tool {
            let content: Any = message.role == .user
                ? AttachmentStore.userContent(text: message.text, attachments: message.attachments ?? [])
                : message.text
            history.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": content
            ])
        }
        agentHistory = history
    }

    /// Xóa file đính kèm không còn tin nhắn nào dùng (sau khi xóa hội thoại, sửa/cắt tin nhắn…)
    private func collectUnusedAttachments() {
        let inUse = Set(chatSessions.flatMap { $0.messages.flatMap { ($0.attachments ?? []).map(\.fileName) } })
        DispatchQueue.global(qos: .utility).async {
            AttachmentStore.garbageCollect(keeping: inUse)
        }
    }

    // MARK: Lưu/tải chats.json

    private static let chatsURL = StudioPaths.dataDirectory.appendingPathComponent("chats.json")

    private static func loadChats() -> [ChatSession] {
        guard let data = try? Data(contentsOf: chatsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ChatSession].self, from: data)) ?? []
    }

    func saveChatsNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(chatSessions) else { return }
        try? data.write(to: Self.chatsURL, options: .atomic)
    }

    /// AI tạo ghi chú mới (không đổi selection, không focus title).
    @discardableResult
    func createAINote(title: String, content: String, pinned: Bool, tags: [String]?) -> Note {
        let note = Note(content: content, pinned: pinned, tags: tags).titled(title)
        withAnimation(.easeInOut(duration: 0.18)) {
            notes.insert(note, at: 0)
        }
        saveNow()
        return note
    }

    /// AI cập nhật một phần thông tin ghi chú. Trả về false nếu không tìm thấy id.
    func updateAIFields(noteID: UUID, title: String?, content: String?, pinned: Bool?, tags: [String]?) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        if let content = content {
            notes[index].content = content
            notes[index].syncTitleFromContent()
        }
        if let title = title { notes[index].setTitleInContent(title) }
        if let pinned = pinned { notes[index].pinned = pinned }
        if let tags = tags { notes[index].tags = tags }
        notes[index].updatedAt = Date()
        saveNow()
        return true
    }

    // MARK: Theo dõi notes.json — để ghi chú do MCP server (AI) tạo/sửa hiện live trong app

    private func startWatchingFile() {
        lastKnownModificationDate = Self.modificationDate()
        // Theo dõi thư mục chứ không phải file, vì save kiểu atomic (rename) thay thế inode
        let directoryPath = Self.storageURL.deletingLastPathComponent().path
        let descriptor = open(directoryPath, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleExternalReload() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatcherSource = source
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: storageURL.path))?[.modificationDate] as? Date
    }

    private func scheduleExternalReload() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.reloadFromDiskIfNeeded() }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func reloadFromDiskIfNeeded() {
        guard let modified = Self.modificationDate(), modified != lastKnownModificationDate else { return }
        lastKnownModificationDate = modified
        guard let stored = Self.load(), !stored.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            notes = stored.map { $0.normalizedMarkdown() }
            if let current = selectedNoteID, !notes.contains(where: { $0.id == current }) {
                selectedNoteID = filteredNotes.first?.id
            }
        }
    }

    // MARK: Persistence (JSON, debounced) + mirror iCloud Drive

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
        lastKnownModificationDate = Self.modificationDate()
        mirrorToICloud(data)
    }

    private static let storageURL = StudioPaths.dataDirectory.appendingPathComponent("notes.json")

    private static func load() -> [Note]? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Note].self, from: data)
    }

    // MARK: iCloud Drive (mirror + merge, mới-hơn-thắng)

    static var iCloudAvailable: Bool {
        FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path
        )
    }

    private static var iCloudSyncActive: Bool {
        UserDefaults.standard.bool(forKey: "icloudSync") && iCloudAvailable
    }

    private static var iCloudNotesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/NoteStudio", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    private func mirrorToICloud(_ data: Data) {
        guard Self.iCloudSyncActive else { return }
        try? FileManager.default.createDirectory(
            at: Self.iCloudNotesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.iCloudNotesURL, options: .atomic)
    }

    /// Gộp bản sao trên iCloud Drive vào danh sách local: union theo id, note có updatedAt mới hơn thắng.
    private static func mergeWithICloud(_ local: [Note]) -> [Note] {
        guard iCloudSyncActive,
              let data = try? Data(contentsOf: iCloudNotesURL) else { return local }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let remote = try? decoder.decode([Note].self, from: data), !remote.isEmpty else { return local }

        var merged = local
        for remoteNote in remote {
            if let index = merged.firstIndex(where: { $0.id == remoteNote.id }) {
                if remoteNote.updatedAt > merged[index].updatedAt {
                    merged[index] = remoteNote
                }
            } else {
                merged.append(remoteNote)
            }
        }
        return merged
    }

    // MARK: Sample data for first launch

    private static func sampleNotes() -> [Note] {
        let now = Date()
        func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3_600) }

        let welcome = Note(
            title: "Chào mừng đến NoteStudio ✨",
            content: """
            Đây là ứng dụng ghi chú demo được viết bằng Swift và SwiftUI, giao diện lấy cảm hứng từ OpenAI Studio.

            Vài điểm đáng chú ý:

            • Tự động lưu — mọi thay đổi được ghi vào file JSON tại ~/Library/Application Support/NoteStudio
            • Tìm kiếm tức thời theo tiêu đề lẫn nội dung
            • Ghim ghi chú quan trọng lên đầu danh sách
            • Trợ lý AI ngay bên cạnh ghi chú — bấm ✦ trên thanh công cụ hoặc ⌘⇧J
            • Phím tắt ⌘N tạo ghi chú mới, ⌘K mở bảng lệnh

            Thử gõ vài dòng vào ghi chú này — danh sách bên trái cập nhật ngay.
            """,
            createdAt: hoursAgo(1),
            updatedAt: now,
            pinned: true,
            tags: ["demo"]
        )

        let meeting = Note(
            title: "Họp nhóm Product — agenda tuần",
            content: """
            Tham dự: An, Bình, Chi, Dũng

            Agenda
            • Review tiến độ sprint 12
            • Chốt kế hoạch ra mắt bản demo
            • Thống nhất quy trình review code

            Quyết định
            — Ra mắt demo vào thứ Sáu tuần này
            — Đóng băng tính năng mới từ thứ Tư

            Action items
            — An: hoàn thiện onboarding flow
            — Bình: chuẩn bị số liệu hiệu năng
            — Chi: rà soát lại nội dung marketing
            """,
            createdAt: daysAgo(1),
            updatedAt: hoursAgo(5),
            pinned: false,
            tags: ["họp", "product"]
        )

        let ideas = Note(
            title: "Ý tưởng cho Q4",
            content: """
            Brainstorm cho quý 4:

            1. Series podcast nội bộ về engineering
            2. Workshop SwiftUI cho team
            3. Dashboard theo dõi chi phí hạ tầng theo thời gian thực
            4. Thử nghiệm gợi ý nội dung bằng LLM cho power users

            Ưu tiên: workshop trước, podcast chờ đủ 5 đề tài dự kiến.
            """,
            createdAt: daysAgo(6),
            updatedAt: hoursAgo(20),
            pinned: false,
            tags: ["ý tưởng"]
        )

        let reading = Note(
            title: "Danh sách sách đang đọc",
            content: """
            Đang đọc
            • Shape Up — Ryan Singer (Basecamp)
            • Thinking in Systems — Donella Meadows
            • The Making of Prince of Persia — Jordan Mechner

            Đã xong
            • Creative Selection — Ken Kocienda ✅
            """,
            createdAt: daysAgo(20),
            updatedAt: daysAgo(2),
            pinned: false,
            tags: ["sách"]
        )

        return [reading, ideas, meeting, welcome]
    }
}
