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
    /// Note đang chờ lưu debounced — mỗi note là một file .md nên chỉ ghi lại đúng file bị đổi
    private var dirtyNoteIDs: Set<UUID> = []
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
        // notes.json cũ → notes/<id>.md (chạy một lần, notes.json đổi tên thành notes.json.imported)
        let migrated = NoteFileStore.migrateIfNeeded()
        let hasStorage = migrated || FileManager.default.fileExists(atPath: NoteFileStore.notesDirectory.path)
        if hasStorage {
            let merged = Self.mergeWithICloud(Self.loadAllNotes())
            notes = merged.map { $0.normalizedMarkdown() }
            if notes != merged { saveNow() }
        } else {
            notes = Self.sampleNotes().map { $0.normalizedMarkdown() }
        }
        selectedNoteID = filteredNotes.first?.id
        startWatchingFile()

        chatSessions = Self.loadChats()
        if chatSessions.isEmpty {
            chatSessions = [ChatSession(title: L("New chat"))]
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
        saveNow(ids: [note.id])
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
        saveNow(ids: [note.id])
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
        dirtyNoteIDs.subtract(noteIDs)
        for id in removed.map(\.note.id) {
            NoteFileStore.deleteFile(id: id)
            deleteFromICloud(id: id)
        }
        lastKnownModificationDate = Self.scanModificationDate()

        let restore: () -> Void = { [weak self] in
            self?.restore(removed, selecting: previousSelection)
        }
        let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
        undoManager?.registerUndo(withTarget: self) { _ in restore() }
        undoManager?.setActionName(L("Delete Note"))

        let message = removed.count == 1
            ? Lf("Deleted “%@”", removed[0].note.displayTitle)
            : Lf("Deleted %d notes", removed.count)
        showToast(StudioToast(message: message, actionLabel: L("Undo"), action: restore))
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
        saveNow(ids: Set(removed.map { $0.note.id }))
        showToast(StudioToast(message: removed.count == 1 ? L("Note restored") : Lf("Restored %d notes", removed.count)))
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
        saveNow(ids: [noteID])
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
        dirtyNoteIDs.insert(edited.id)
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
        saveNow(ids: [noteID])
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
        let session = ChatSession(title: L("New chat"))
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
            let fresh = ChatSession(title: L("New chat"))
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
        if message.role == .user, chatSessions[index].title == L("New chat") || chatSessions[index].title == "Hội thoại mới" {
            let files = (message.attachments ?? []).map(\.name).joined(separator: ", ")
            let title = message.text == AttachmentStore.defaultPrompt && !files.isEmpty ? Lf("Analysis of %@", files) : message.text
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
        saveNow(ids: [note.id])
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
        saveNow(ids: [noteID])
        return true
    }

    // MARK: Theo dõi thư mục notes/ — để ghi chú do MCP server (AI) tạo/sửa hiện live trong app

    private func startWatchingFile() {
        // Thư mục notes/ có thể chưa tồn tại (cài mới chưa lưu gì) — tạo luôn để watcher gắn được
        try? FileManager.default.createDirectory(at: NoteFileStore.notesDirectory, withIntermediateDirectories: true)
        lastKnownModificationDate = Self.scanModificationDate()
        // Theo dõi thư mục chứ không phải từng file, vì save kiểu atomic (rename) thay thế inode
        let directoryPath = NoteFileStore.notesDirectory.path
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

    /// mtime mới nhất trong thư mục notes/ (cả thư mục lẫn từng file .md)
    private static func scanModificationDate() -> Date? {
        let fm = FileManager.default
        var latest: Date?
        func bump(_ path: String) {
            guard let modified = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return }
            latest = max(latest ?? .distantPast, modified)
        }
        bump(NoteFileStore.notesDirectory.path)
        for url in (try? fm.contentsOfDirectory(at: NoteFileStore.notesDirectory, includingPropertiesForKeys: nil)) ?? [] {
            bump(url.path)
        }
        return latest
    }

    private func scheduleExternalReload() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.reloadFromDiskIfNeeded() }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func reloadFromDiskIfNeeded() {
        guard let modified = Self.scanModificationDate(), modified != lastKnownModificationDate else { return }
        lastKnownModificationDate = modified
        let stored = Self.loadAllNotes().map { $0.normalizedMarkdown() }
        guard stored != notes else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            notes = stored
            if let current = selectedNoteID, !notes.contains(where: { $0.id == current }) {
                selectedNoteID = filteredNotes.first?.id
            }
        }
    }

    // MARK: Persistence (mỗi note một file .md, debounced) + mirror iCloud Drive

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveNow(ids: dirtyNoteIDs)
            dirtyNoteIDs = []
        }
    }

    /// Ghi file .md cho các note được chỉ định (nil = tất cả — dùng khi merge iCloud, flush khi thoát).
    func saveNow(ids: Set<UUID>? = nil) {
        saveTask?.cancel()
        let targets = ids ?? Set(notes.map(\.id))
        let changed = notes.filter { targets.contains($0.id) }
        for note in changed {
            NoteFileStore.save(note.fileRecord)
        }
        mirrorToICloud(changed)
        lastKnownModificationDate = Self.scanModificationDate()
    }

    private static func loadAllNotes() -> [Note] {
        NoteFileStore.loadAll().map { record in
            Note(id: record.id,
                 title: record.title,
                 content: record.content,
                 createdAt: record.createdAt,
                 updatedAt: record.updatedAt,
                 pinned: record.pinned,
                 tags: record.tags)
        }
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

    private static var iCloudNotesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/NoteStudio/notes", isDirectory: true)
    }

    private func mirrorToICloud(_ changed: [Note]) {
        guard Self.iCloudSyncActive, !changed.isEmpty else { return }
        try? FileManager.default.createDirectory(at: Self.iCloudNotesDirectory, withIntermediateDirectories: true)
        for note in changed {
            let url = Self.iCloudNotesDirectory.appendingPathComponent(note.id.uuidString + ".md")
            try? NoteFileCodec.encode(note.fileRecord).data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    private func deleteFromICloud(id: UUID) {
        guard Self.iCloudSyncActive else { return }
        try? FileManager.default.removeItem(
            at: Self.iCloudNotesDirectory.appendingPathComponent(id.uuidString + ".md")
        )
    }

    /// Gộp bản sao trên iCloud Drive vào danh sách local: union theo id, note có updatedAt mới hơn thắng.
    private static func mergeWithICloud(_ local: [Note]) -> [Note] {
        guard iCloudSyncActive else { return local }
        let remote = NoteFileStore.loadAll(in: iCloudNotesDirectory).map { record in
            Note(id: record.id,
                 title: record.title,
                 content: record.content,
                 createdAt: record.createdAt,
                 updatedAt: record.updatedAt,
                 pinned: record.pinned,
                 tags: record.tags)
                .normalizedMarkdown()
        }
        guard !remote.isEmpty else { return local }

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

    /// Nội dung ghi chú mẫu: chọn bản EN/VI theo ngôn ngữ đang chọn
    private static func sampleContent(vi: String, en: String) -> String {
        LocalizationManager.resolvedLanguage == .vietnamese ? vi : en
    }

    private static func sampleNotes() -> [Note] {
        let now = Date()
        func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3_600) }

        let welcome = Note(
            title: L("Welcome to NoteStudio ✨"),
            content: sampleContent(
                vi: """
                Đây là ứng dụng ghi chú demo được viết bằng Swift và SwiftUI, giao diện lấy cảm hứng từ OpenAI Studio.

                Vài điểm đáng chú ý:

                • Tự động lưu — mỗi ghi chú là một file .md tại ~/Library/Application Support/NoteStudio/notes
                • Tìm kiếm tức thời theo tiêu đề lẫn nội dung
                • Ghim ghi chú quan trọng lên đầu danh sách
                • Trợ lý AI ngay bên cạnh ghi chú — bấm ✦ trên thanh công cụ hoặc ⌘⇧J
                • Phím tắt ⌘N tạo ghi chú mới, ⌘K mở bảng lệnh

                Thử gõ vài dòng vào ghi chú này — danh sách bên trái cập nhật ngay.
                """,
                en: """
                This is a demo note-taking app written in Swift and SwiftUI, inspired by the OpenAI Studio look.

                A few things worth knowing:

                • Autosave — every note is a Markdown (.md) file at ~/Library/Application Support/NoteStudio/notes
                • Instant search across titles and content
                • Pin important notes to the top of the list
                • AI assistant right next to the note — click ✦ on the toolbar or press ⌘⇧J
                • ⌘N creates a new note, ⌘K opens the command palette

                Try typing a few lines into this note — the list on the left updates instantly.
                """
            ),
            createdAt: hoursAgo(1),
            updatedAt: now,
            pinned: true,
            tags: [L("demo")]
        )

        let meeting = Note(
            title: L("Team Meeting — weekly agenda"),
            content: sampleContent(
                vi: """
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
                en: """
                Attendees: An, Binh, Chi, Dung

                Agenda
                • Review sprint 12 progress
                • Lock the demo launch plan
                • Agree on the code review process

                Decisions
                — Launch the demo this Friday
                — Feature freeze from Wednesday

                Action items
                — An: finish the onboarding flow
                — Binh: prepare performance numbers
                — Chi: review the marketing copy
                """
            ),
            createdAt: daysAgo(1),
            updatedAt: hoursAgo(5),
            pinned: false,
            tags: [L("meeting"), L("product")]
        )

        let ideas = Note(
            title: L("Q4 Ideas"),
            content: sampleContent(
                vi: """
                Brainstorm cho quý 4:

                1. Series podcast nội bộ về engineering
                2. Workshop SwiftUI cho team
                3. Dashboard theo dõi chi phí hạ tầng theo thời gian thực
                4. Thử nghiệm gợi ý nội dung bằng LLM cho power users

                Ưu tiên: workshop trước, podcast chờ đủ 5 đề tài dự kiến.
                """,
                en: """
                Brainstorm for Q4:

                1. Internal engineering podcast series
                2. SwiftUI workshop for the team
                3. Real-time dashboard to track infra costs
                4. Try LLM-based content suggestions for power users

                Priority: workshop first, podcast waits until we have 5 topics.
                """
            ),
            createdAt: daysAgo(6),
            updatedAt: hoursAgo(20),
            pinned: false,
            tags: [L("ideas")]
        )

        let reading = Note(
            title: L("Reading list"),
            content: sampleContent(
                vi: """
                Đang đọc
                • Shape Up — Ryan Singer (Basecamp)
                • Thinking in Systems — Donella Meadows
                • The Making of Prince of Persia — Jordan Mechner

                Đã xong
                • Creative Selection — Ken Kocienda ✅
                """,
                en: """
                Reading
                • Shape Up — Ryan Singer (Basecamp)
                • Thinking in Systems — Donella Meadows
                • The Making of Prince of Persia — Jordan Mechner

                Done
                • Creative Selection — Ken Kocienda ✅
                """
            ),
            createdAt: daysAgo(20),
            updatedAt: daysAgo(2),
            pinned: false,
            tags: [L("books")]
        )

        return [reading, ideas, meeting, welcome]
    }
}

// MARK: - Note ↔ record file .md (cùng cấu trúc trường, chỉ dùng trong file này)

private extension Note {
    var fileRecord: NoteFileRecord {
        NoteFileRecord(id: id, title: title, content: content,
                       createdAt: createdAt, updatedAt: updatedAt,
                       pinned: pinned, tags: tags)
    }
}
