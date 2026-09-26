import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Chat AI agent kiểu ChatGPT — dùng cho màn Trợ lý toàn màn hình và panel cạnh editor

struct ChatPanelView: View {
    enum Style { case full, side }

    let style: Style

    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var assistant: AssistantEngine
    @State private var composer = ComposerCoordinator()
    @State private var draft = ""
    @State private var mentionedNotes: [MentionedNote] = []
    @State private var completionTrigger: CompletionTrigger?
    @State private var completionIndex = 0
    @State private var composerHeight: CGFloat = ComposerCoordinator.minHeight
    @State private var showPlusMenu = false
    @State private var renaming: ChatSession?
    @State private var renameDraft = ""
    @State private var deleting: ChatSession?
    @State private var attachments: [ChatAttachment] = []
    @State private var importingCount = 0
    @State private var dropTargeted = false

    private var isSide: Bool { style == .side }
    private var columnWidth: CGFloat { isSide ? .infinity : 768 }
    private var horizontalPadding: CGFloat { isSide ? 16 : 24 }

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.activeMessages.isEmpty {
                emptyState
            } else {
                transcript
                composerArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if dropTargeted {
                DropOverlay(compact: isSide)
                    .transition(.opacity)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted.animation(.easeOut(duration: 0.12))) { providers in
            handleDrop(providers)
        }
        .sessionRenameAlert(session: $renaming, draft: $renameDraft)
        .sessionDeleteDialog(session: $deleting)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            if isSide {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Studio.textSecondary)
                    .padding(.leading, 14)
                modelMenu
                WindowDragArea()
                IconButton(systemName: "square.and.pencil", help: L("New chat")) {
                    store.newChatSession()
                }
                IconButton(systemName: "arrow.up.left.and.arrow.down.right", help: L("Open full screen (⌘2)")) {
                    withAnimation(.easeInOut(duration: 0.18)) { store.activeSection = .chat }
                }
                IconButton(systemName: "xmark", help: L("Close Assistant (⌘⇧J)")) {
                    withAnimation(.easeInOut(duration: 0.22)) { store.showAssistant = false }
                }
            } else {
                SidebarRevealControls()
                modelMenu
                    .padding(.leading, store.sidebarVisible ? 10 : 0)
                WindowDragArea()
                if let session = store.activeSession, !session.messages.isEmpty {
                    IconMenu(help: L("Chat options")) {
                        Button(L("Rename…")) {
                            renameDraft = session.title
                            renaming = session
                        }
                        Divider()
                        Button(L("Delete chat…"), role: .destructive) { deleting = session }
                    }
                }
            }
        }
        .padding(.trailing, 12)
        .frame(height: Studio.headerHeight)
        .background(Studio.background)
        .zIndex(2)
    }

    private var modelMenu: some View {
        ProviderPicker(compact: isSide)
    }

    // MARK: Hội thoại trống: lời chào + composer ở giữa màn hình

    private var emptyState: some View {
        VStack(spacing: isSide ? 18 : 28) {
            Spacer()
            Text(isSide ? greetingForSide : L("What can I help you with today?"))
                .font(isSide ? Studio.Typo.headline() : Studio.Typo.largeTitle(.semibold))
                .foregroundStyle(Studio.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalPadding)
            composerCard
                .frame(maxWidth: columnWidth)
                .padding(.horizontal, horizontalPadding)
            suggestions
                .frame(maxWidth: columnWidth)
                .padding(.horizontal, horizontalPadding)
            if let error = assistant.errorText {
                errorBanner(error)
                    .frame(maxWidth: columnWidth)
                    .padding(.horizontal, horizontalPadding)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var greetingForSide: String {
        if let note = store.selectedNote {
            return Lf("Ask about “%@”?", note.displayTitle)
        }
        return L("Ask the assistant anything")
    }

    private var suggestions: some View {
        let items: [(String, String, String)] = isSide
            ? [("list.bullet", L("Summarize"), L("Summarize the open note into key points")),
               ("checklist", L("To-dos"), L("Extract a to-do list from the open note")),
               ("wand.and.stars", L("Rewrite"), L("Rewrite the open note to be shorter and clearer"))]
            : [("magnifyingglass", L("Search & summarize"), L("Research my notes about Q4 and summarize")),
               ("lightbulb", L("Brainstorm"), L("Brainstorm 5 content ideas, building on my earlier ideas")),
               ("checklist", L("Plan"), L("Create a to-do note for this week")),
               ("chart.bar", L("Stats"), L("Give me stats about my notes by tag"))]
        return FlowRow(spacing: 8) {
            ForEach(items, id: \.2) { icon, label, prompt in
                SuggestionChip(icon: icon, label: label) {
                    assistant.send(prompt, mentions: [])
                }
                .help(prompt)
            }
        }
    }

    // MARK: Danh sách tin nhắn

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: isSide ? 10 : 14) {
                    ForEach(groupedMessages) { group in
                        switch group.kind {
                        case .user(let message):
                            UserMessageRow(message: message, compact: isSide) {
                                store.truncateChat(after: message.id, includingSelf: true)
                                attachments = message.attachments ?? []
                                composer.setText(message.text == AttachmentStore.defaultPrompt && !attachments.isEmpty ? "" : message.text)
                                composer.focus()
                            } onRetry: {
                                assistant.regenerate(from: message.id)
                            }
                        case .assistant(let message):
                            AssistantMessageRow(message: message, compact: isSide)
                        case .tools(let messages):
                            ToolActivityRow(messages: messages)
                        }
                    }

                    let pending = assistant.pendingDeletes(in: store.activeMessages)
                    if !pending.isEmpty {
                        DeleteConfirmationCard(items: pending)
                    }

                    if assistant.isLoading, store.activeMessages.last?.role != .assistant {
                        ThinkingIndicator()
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: columnWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.activeMessages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: store.activeMessages.last?.text) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: store.activeChatSessionID) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .clipped()
    }

    private struct MessageGroup: Identifiable {
        enum Kind {
            case user(ChatMessage)
            case assistant(ChatMessage)
            case tools([ChatMessage])
        }
        let id: UUID
        let kind: Kind
    }

    /// Các lần gọi tool liên tiếp gộp thành một dòng "Đã dùng N công cụ"
    private var groupedMessages: [MessageGroup] {
        var groups: [MessageGroup] = []
        var toolBuffer: [ChatMessage] = []
        func flush() {
            if let first = toolBuffer.first {
                groups.append(MessageGroup(id: first.id, kind: .tools(toolBuffer)))
                toolBuffer = []
            }
        }
        for message in store.activeMessages {
            switch message.role {
            case .tool:
                toolBuffer.append(message)
            case .user:
                flush()
                groups.append(MessageGroup(id: message.id, kind: .user(message)))
            case .assistant:
                if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                flush()
                groups.append(MessageGroup(id: message.id, kind: .assistant(message)))
            }
        }
        flush()
        return groups
    }

    // MARK: Composer + dropdown (@mention và slash dùng chung)

    private var composerArea: some View {
        VStack(spacing: 8) {
            if let error = assistant.errorText {
                errorBanner(error)
            }
            composerCard
            Text(L("AI can make mistakes. Check important info."))
                .font(Studio.Typo.caption())
                .foregroundStyle(Studio.textTertiary)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 10)
        .frame(maxWidth: columnWidth)
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Studio.danger)
                .padding(.top, 1)
            Text(message)
                .font(Studio.Typo.footnote())
                .foregroundStyle(Studio.textPrimary)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer(minLength: 0)
            Button(L("Settings")) { store.activeSection = .settings }
                .buttonStyle(.plain)
                .font(Studio.Typo.footnote(.semibold))
                .foregroundStyle(Studio.textPrimary)
            Button {
                assistant.errorText = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Studio.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Studio.Radius.medium).fill(Studio.dangerFill))
        .overlay(RoundedRectangle(cornerRadius: Studio.Radius.medium).stroke(Studio.dangerBorder))
    }

    private var completionItems: [CompletionItem] {
        switch completionTrigger {
        case .mention(let query):
            return sortedNotes
                .filter { query.isEmpty || $0.displayTitle.lowercased().contains(query.lowercased()) }
                .prefix(6)
                .map { note in
                    CompletionItem(id: note.id.uuidString, icon: "doc.text", title: note.displayTitle, subtitle: note.snippet)
                }
        case .slash(let query):
            return SlashCommand.all
                .filter { query.isEmpty || $0.name.lowercased().contains(query.lowercased()) }
                .map { CompletionItem(id: $0.id, icon: $0.icon, title: "/" + $0.name, subtitle: $0.desc) }
        case nil:
            return []
        }
    }

    private var dropdownOpen: Bool {
        completionTrigger != nil && !completionItems.isEmpty
    }

    private static let completionRowHeight: CGFloat = 44

    private var completionDropdownHeight: CGFloat {
        let count = CGFloat(completionItems.count)
        return min(count * Self.completionRowHeight + max(count - 1, 0) + 12, 260)
    }

    private func moveCompletion(_ delta: Int) {
        let count = completionItems.count
        guard count > 0 else { return }
        completionIndex = (completionIndex + delta + count) % count
    }

    private func acceptCompletion() {
        guard completionItems.indices.contains(completionIndex) else { return }
        let item = completionItems[completionIndex]
        switch completionTrigger {
        case .mention:
            if let note = store.notes.first(where: { $0.id.uuidString == item.id }) {
                composer.insertMention(note)
            }
        case .slash:
            if let command = SlashCommand.all.first(where: { $0.id == item.id }) {
                composer.applySlashTemplate(command.template)
            }
        case nil:
            break
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !mentionedNotes.isEmpty || !attachments.isEmpty || importingCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            ComposerAttachmentTile(attachment: attachment) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    attachments.removeAll { $0.id == attachment.id }
                                }
                                try? FileManager.default.removeItem(at: attachment.fileURL)
                            }
                        }
                        ForEach(0..<importingCount, id: \.self) { _ in
                            ImportingTile()
                        }
                        ForEach(mentionedNotes) { mention in
                            MentionAttachment(mention: mention) {
                                mentionedNotes.removeAll { $0.id == mention.id }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .padding(.top, 2)
            }

            ZStack(alignment: .topLeading) {
                ChatComposer(
                    coordinator: composer,
                    text: $draft,
                    mentions: $mentionedNotes,
                    isDropdownOpen: { dropdownOpen },
                    onTextChange: { _, trigger in
                        completionTrigger = trigger
                        completionIndex = 0
                    },
                    onMove: { moveCompletion($0) },
                    onAccept: { acceptCompletion() },
                    onCancel: { completionTrigger = nil },
                    onSubmit: { submitDraft() },
                    placeholder: attachments.isEmpty
                        ? (isSide ? L("Ask about this note…") : L("Ask anything"))
                        : L("Ask about the attachments… (leave empty to analyze)"),
                    onHeightChange: { composerHeight = $0 },
                    onPasteAttachments: { pasteboard in handlePaste(pasteboard) },
                    onDropFiles: { urls in importFiles(urls) }
                )
            }
            .frame(height: composerHeight)
            .padding(.horizontal, 6)

            HStack(spacing: 4) {
                plusButton
                ComposerToolButton(systemName: "at", help: L("Mention a note (@)")) {
                    composer.insertTrigger("@")
                }
                if isSide, let note = store.selectedNote, !mentionedNotes.contains(where: { $0.id == note.id }) {
                    AttachCurrentNoteChip(title: note.displayTitle) {
                        mentionedNotes.append(MentionedNote(id: note.id, title: note.displayTitle))
                    }
                }
                Spacer(minLength: 8)
                sendButton
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Studio.composerBackground)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Studio.composerBorder)
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { composer.focus() }
        .overlay(alignment: .top) {
            // Dropdown @ / nổi phía trên composer (khung cao 0, nội dung tràn lên trên)
            if dropdownOpen, let trigger = completionTrigger {
                completionDropdown(trigger)
                    .frame(height: completionDropdownHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Studio.popoverBackground)
                            .shadow(color: .black.opacity(0.14), radius: 16, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Studio.composerBorder)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.bottom, 8)
                    .frame(height: 0, alignment: .bottom)
            }
        }
        .zIndex(1)
        .onAppear {
            DispatchQueue.main.async { composer.focus() }
        }
    }

    private var plusButton: some View {
        ComposerToolButton(systemName: "plus", help: L("Attach files, mention notes, quick commands…")) {
            showPlusMenu.toggle()
        }
        .popover(isPresented: $showPlusMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                PlusMenuRow(icon: "paperclip", title: L("Attach images or files…"), subtitle: L("Images, PDF, Word, text · or drag & drop / ⌘V")) {
                    showPlusMenu = false
                    pickFiles()
                }
                PlusMenuRow(icon: "doc.text", title: L("Mention a note"), subtitle: L("Bring the note's content into context")) {
                    showPlusMenu = false
                    composer.insertTrigger("@")
                }
                Rectangle().fill(Studio.hairline).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
                Text(L("Quick commands"))
                    .font(Studio.Typo.caption(.medium))
                    .foregroundStyle(Studio.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                ForEach(SlashCommand.all) { command in
                    PlusMenuRow(icon: command.icon, title: command.desc, subtitle: "/" + command.name) {
                        showPlusMenu = false
                        composer.focus()
                        composer.applySlashTemplate(command.template)
                    }
                }
            }
            .padding(6)
            .frame(width: 280)
        }
    }

    private var sendButton: some View {
        Button {
            if assistant.isLoading {
                assistant.stop()
            } else {
                submitDraft()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(assistant.isLoading || canSend ? Studio.accent : Studio.sendDisabled)
                if assistant.isLoading {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Studio.accentForeground)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? Studio.accentForeground : Studio.sendDisabledForeground)
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!assistant.isLoading && !canSend)
        .help(assistant.isLoading ? L("Stop generating") : L("Send (Enter) · Shift+Enter for a new line"))
        .animation(.easeOut(duration: 0.12), value: canSend)
        .animation(.easeOut(duration: 0.12), value: assistant.isLoading)
    }

    private func completionDropdown(_ trigger: CompletionTrigger) -> some View {
        let items = completionItems
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            completionIndex = index
                            acceptCompletion()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 13))
                                    .frame(width: 18)
                                    .foregroundStyle(index == completionIndex ? Studio.textPrimary : Studio.textSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(Studio.Typo.callout(.medium))
                                        .foregroundStyle(Studio.textPrimary)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(Studio.Typo.caption())
                                        .foregroundStyle(Studio.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: Self.completionRowHeight)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(index == completionIndex ? Studio.hover : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(6)
            }
            .onChange(of: completionIndex) { newIndex in
                guard items.indices.contains(newIndex) else { return }
                proxy.scrollTo(items[newIndex].id, anchor: .center)
            }
        }
    }

    private var canSend: Bool {
        guard !assistant.isLoading, importingCount == 0 else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    private var sortedNotes: [Note] {
        store.notes.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func submitDraft() {
        guard canSend else { return }
        let text = draft
        let mentions = mentionedNotes
        let files = attachments
        draft = ""
        mentionedNotes = []
        attachments = []
        composer.clear()
        assistant.send(text, mentions: mentions, attachments: files)
    }

    // MARK: Đính kèm: chọn tệp, kéo thả, dán

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = L("Attach")
        panel.message = L("Choose images or documents to ask the assistant")
        panel.begin { response in
            guard response == .OK else { return }
            importFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { importFiles([url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // Ảnh kéo từ trình duyệt / app khác không có file
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { importImageData(data, name: provider.suggestedName.map { $0 + ".png" } ?? AttachmentStore.pastedImageName()) }
                }
            }
        }
        return accepted
    }

    private func handlePaste(_ pasteboard: NSPasteboard) -> Bool {
        switch AttachmentStore.attachableContent(in: pasteboard) {
        case .files(let urls):
            importFiles(urls)
            return true
        case .image(let data):
            importImageData(data, name: AttachmentStore.pastedImageName())
            return true
        case nil:
            return false
        }
    }

    private func importFiles(_ urls: [URL]) {
        let room = AttachmentStore.maxPerMessage - attachments.count - importingCount
        guard room > 0 else {
            store.showToast(StudioToast(message: Lf("Up to %d files per message", AttachmentStore.maxPerMessage)))
            return
        }
        let accepted = Array(urls.prefix(room))
        if urls.count > room {
            store.showToast(StudioToast(message: Lf("Only %d more file(s) can be attached", room)))
        }
        importingCount += accepted.count
        for url in accepted {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try AttachmentStore.importFile(at: url) }
                DispatchQueue.main.async { finishImport(result) }
            }
        }
        composer.focus()
    }

    private func importImageData(_ data: Data, name: String) {
        guard attachments.count + importingCount < AttachmentStore.maxPerMessage else {
            store.showToast(StudioToast(message: Lf("Up to %d files per message", AttachmentStore.maxPerMessage)))
            return
        }
        importingCount += 1
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AttachmentStore.importImage(data: data, name: name) }
            DispatchQueue.main.async { finishImport(result) }
        }
        composer.focus()
    }

    private func finishImport(_ result: Result<ChatAttachment, Error>) {
        importingCount = max(importingCount - 1, 0)
        switch result {
        case .success(let attachment):
            withAnimation(.easeOut(duration: 0.15)) { attachments.append(attachment) }
        case .failure(let error):
            store.showToast(StudioToast(message: error.localizedDescription))
        }
    }

    private struct CompletionItem: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
    }
}

// MARK: - Lệnh nhanh "/"

struct SlashCommand: Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let desc: String
    let template: String

    // computed var: tra lại bản dịch mỗi lần mở menu (đổi ngôn ngữ là đổi ngay)
    static var all: [SlashCommand] {
        [
            .init(name: L("summarize"), icon: "list.bullet",
                  desc: L("Summarize the selected note"),
                  template: L("Summarize the selected note into concise key points.")),
            .init(name: L("translate"), icon: "globe",
                  desc: L("Translate text into English"),
                  template: L("Translate the following text into English:\n\n")),
            .init(name: L("continue"), icon: "text.append",
                  desc: L("Continue writing"),
                  template: L("Continue the following text naturally:\n\n")),
            .init(name: L("checklist"), icon: "checklist",
                  desc: L("Convert to a markdown checklist"),
                  template: L("Convert the following content into a markdown checklist (- [ ] items):\n\n")),
            .init(name: L("brainstorm"), icon: "lightbulb",
                  desc: L("Brainstorm ideas"),
                  template: L("Brainstorm 5 ideas about: ")),
        ]
    }
}

// MARK: - Tin nhắn user: bubble xám nhạt bên phải, Sửa / Làm lại hiện khi hover

private struct UserMessageRow: View {
    let message: ChatMessage
    let compact: Bool
    let onEdit: () -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var assistant: AssistantEngine
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let files = message.attachments, !files.isEmpty {
                MessageAttachmentsView(attachments: files, compact: compact)
            }
            Text(styledText)
                .font(Studio.Typo.body())
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Studio.Radius.large, style: .continuous).fill(Studio.userBubble))
                .frame(maxWidth: compact ? 300 : 520, alignment: .trailing)

            HStack(spacing: 2) {
                HoverActionButton(systemName: "doc.on.doc", help: L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                }
                HoverActionButton(systemName: "pencil", help: L("Edit message"), action: onEdit)
                    .disabled(assistant.isLoading)
                HoverActionButton(systemName: "arrow.clockwise", help: L("Retry"), action: onRetry)
                    .disabled(assistant.isLoading)
            }
            .opacity(hovering ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// @note trong bubble user được highlight inline
    private var styledText: AttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attributed = NSMutableAttributedString(
            string: message.text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.studioTextPrimary,
                .paragraphStyle: paragraph
            ]
        )
        let ns = message.text as NSString
        for mention in message.mentions ?? [] {
            let needle = "@" + mention.title
            var searchRange = NSRange(location: 0, length: ns.length)
            while searchRange.location < ns.length {
                let found = ns.range(of: needle, options: [.caseInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                attributed.addAttributes([
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .backgroundColor: NSColor.mentionBackgroundNS
                ], range: found)
                searchRange.location = found.location + found.length
                searchRange.length = ns.length - searchRange.location
            }
        }
        return AttributedString(attributed)
    }
}

// MARK: - Câu trả lời AI: chữ trơn full width, không khung

private struct AssistantMessageRow: View {
    let message: ChatMessage
    let compact: Bool

    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var assistant: AssistantEngine
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let blocks = MarkdownParser.parse(message.text)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
                }
                if blocks.isEmpty {
                    Text(message.text)
                        .font(Studio.Typo.body())
                        .foregroundStyle(Studio.textPrimary)
                }
            }
            .textSelection(.enabled)

            HStack(spacing: 2) {
                HoverActionButton(systemName: copied ? "checkmark" : "doc.on.doc", help: L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                if let note = store.selectedNote {
                    HoverActionButton(systemName: "text.append", help: Lf("Append to “%@”", note.displayTitle)) {
                        store.appendContent("\n\n\(message.text)\n", to: note.id)
                        store.showToast(StudioToast(message: Lf("Appended to “%@”", note.displayTitle)))
                    }
                }
                HoverActionButton(systemName: "square.and.pencil", help: L("Save reply as a new note")) {
                    saveAsNote()
                }
                HoverActionButton(systemName: "arrow.clockwise", help: L("Regenerate reply")) {
                    if let userMessage = store.activeMessages.last(where: { $0.role == .user }) {
                        assistant.regenerate(from: userMessage.id)
                    }
                }
                .disabled(assistant.isLoading || store.activeMessages.last?.id != message.id)
            }
            .opacity(hovering && !(assistant.isLoading && store.activeMessages.last?.id == message.id) ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

extension AssistantMessageRow {
    /// Tiêu đề lấy từ heading đầu tiên của câu trả lời, hoặc từ tin nhắn/tệp của người dùng
    fileprivate func saveAsNote() {
        let messages = store.activeMessages
        let index = messages.firstIndex { $0.id == message.id } ?? messages.count
        let question = messages[..<index].last { $0.role == .user }
        var title = ""
        for line in message.text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).replacingOccurrences(of: "**", with: "")
                break
            }
        }
        if title.isEmpty, let files = question?.attachments, !files.isEmpty {
            title = files.count == 1 ? Lf("Analysis of %@", (files[0].name as NSString).deletingPathExtension) : Lf("Analysis of %d files", files.count)
        }
        if title.isEmpty, let question {
            title = String(question.text.prefix(60))
        }
        var content = message.text
        if let files = question?.attachments, !files.isEmpty {
            content += "\n\n---\n" + L("Sources: ") + files.map(\.name).joined(separator: ", ")
        }
        let note = store.createAINote(title: title, content: content, pinned: false, tags: nil)
        store.showToast(StudioToast(message: Lf("Saved “%@”", note.displayTitle), actionLabel: L("Open")) { [weak store] in
            store?.activeSection = .notes
            store?.select(note.id)
        })
    }
}

// MARK: - Các bước gọi tool liên tiếp: một dòng xám thu gọn

private struct ToolActivityRow: View {
    let messages: [ChatMessage]

    @EnvironmentObject private var assistant: AssistantEngine
    @State private var expanded = false
    @State private var expandedDetail: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11))
                    Text(summary)
                        .font(Studio.Typo.callout())
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(Studio.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("See what the AI did"))

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(messages) { message in
                        stepRow(message)
                    }
                }
                .padding(.leading, 6)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Studio.hairline).frame(width: 1)
                }
            }
        }
    }

    private var summary: String {
        guard let last = messages.last else { return "" }
        if messages.count == 1 { return label(for: last) }
        let deletes = messages.filter { $0.toolName == "delete_note" }
        if deletes.count > 1 {
            return Lf("Used %d tools · suggested deleting %d notes", messages.count, deletes.count)
        }
        return Lf("Used %d tools · %@", messages.count, label(for: last))
    }

    private func stepRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expandedDetail = expandedDetail == message.id ? nil : message.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: message))
                        .font(.system(size: 10))
                        .foregroundStyle(Studio.textTertiary)
                        .frame(width: 14)
                    Text(label(for: message))
                        .font(Studio.Typo.footnote())
                        .foregroundStyle(Studio.textSecondary)
                        .lineLimit(1)
                    Text(L("detail"))
                        .font(Studio.Typo.caption())
                        .foregroundStyle(Studio.textTertiary)
                        .underline()
                }
                .padding(.leading, 8)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedDetail == message.id {
                Text(detail(message))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Studio.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill(Studio.subtleFill))
                    .padding(.leading, 8)
            }
        }
    }

    private func icon(for message: ChatMessage) -> String {
        switch message.toolName {
        case "delete_note": return "trash"
        case "create_note": return "plus"
        case "update_note", "append_to_note": return "pencil"
        case "search_notes": return "magnifyingglass"
        default: return "doc.text"
        }
    }

    private func label(for message: ChatMessage) -> String {
        guard message.toolName == "delete_note" else { return message.text }
        let title = AssistantEngine.deleteTitle(of: message) ?? L("note")
        switch assistant.deleteResolution(for: message) {
        case .some(true): return Lf("Deleted “%@”", title)
        case .some(false): return Lf("Kept “%@”", title)
        case .none: return Lf("Suggested deleting “%@”", title)
        }
    }

    private func detail(_ message: ChatMessage) -> String {
        var parts: [String] = []
        if let args = message.toolArgs { parts.append("▶ arguments\n" + Self.pretty(args)) }
        if let result = message.toolResult { parts.append("◀ result\n" + Self.pretty(result)) }
        return parts.joined(separator: "\n\n")
    }

    private static func pretty(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return raw
    }
}

// MARK: - Một thẻ xác nhận duy nhất cho mọi đề nghị xóa đang chờ

private struct DeleteConfirmationCard: View {
    let items: [AssistantEngine.PendingDelete]
    @EnvironmentObject private var assistant: AssistantEngine
    @State private var excluded: Set<UUID> = []

    private var selected: [AssistantEngine.PendingDelete] {
        items.filter { !excluded.contains($0.id) }
    }

    private var undoHint: some View {
        Text(L("Undo with ⌘Z"))
            .font(Studio.Typo.footnote())
            .foregroundStyle(Studio.textTertiary)
            .fixedSize()
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(L("Keep all")) {
                assistant.rejectDeletes(items)
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
            Button {
                assistant.confirmDeletes(selected)
                assistant.rejectDeletes(items.filter { excluded.contains($0.id) })
            } label: {
                Text(selected.count == 1 ? L("Delete 1 note") : Lf("Delete %d notes", selected.count))
                    .font(Studio.Typo.callout(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Studio.danger))
                    .contentShape(Capsule())
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.5 : 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Studio.danger)
                Text(items.count == 1 ? L("AI wants to delete 1 note") : Lf("AI wants to delete %d notes", items.count))
                    .font(Studio.Typo.callout(.semibold))
                    .foregroundStyle(Studio.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    Button {
                        if excluded.contains(item.id) { excluded.remove(item.id) } else { excluded.insert(item.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: excluded.contains(item.id) ? "square" : "checkmark.square.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(excluded.contains(item.id) ? Studio.textTertiary : Studio.textPrimary)
                            Text(item.title)
                                .font(Studio.Typo.callout())
                                .foregroundStyle(excluded.contains(item.id) ? Studio.textTertiary : Studio.textPrimary)
                                .strikethrough(!excluded.contains(item.id), color: Studio.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    undoHint
                    Spacer(minLength: 8)
                    actionButtons
                }
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        actionButtons
                    }
                    undoHint
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Studio.Radius.medium, style: .continuous).fill(Studio.controlBackground))
        .overlay(RoundedRectangle(cornerRadius: Studio.Radius.medium, style: .continuous).stroke(Studio.dangerBorder))
    }
}

// MARK: - Thành phần nhỏ

private struct ThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Studio.textPrimary)
                .frame(width: 10, height: 10)
                .scaleEffect(0.75 + 0.25 * sin(phase))
            Text(L("Thinking…"))
                .font(Studio.Typo.callout())
                .foregroundStyle(Studio.textSecondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { phase = .pi / 2 }
        }
    }
}

private struct HoverActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Studio.textSecondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering && isEnabled ? Studio.hover : Color.clear))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct SuggestionChip: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Studio.textSecondary)
                Text(label)
                    .font(Studio.Typo.callout())
                    .foregroundStyle(Studio.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(hovering ? Studio.hover : Studio.background))
            .overlay(Capsule().stroke(Studio.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AttachCurrentNoteChip: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                Text(title)
                    .font(Studio.Typo.footnote(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Studio.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: 170)
            .background(Capsule().fill(hovering ? Studio.composerButtonHover : Color.clear))
            .overlay(Capsule().stroke(Studio.composerBorder, style: StrokeStyle(lineWidth: 1, dash: [3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L("Attach the content of the open note"))
    }
}

private struct MentionAttachment: View {
    let mention: MentionedNote
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: NSColor(hex: 0xFF8A3D))))
            VStack(alignment: .leading, spacing: 1) {
                Text(mention.title)
                    .font(Studio.Typo.footnote(.semibold))
                    .foregroundStyle(Studio.textPrimary)
                    .lineLimit(1)
                Text(L("Note"))
                    .font(Studio.Typo.caption())
                    .foregroundStyle(Studio.textSecondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Studio.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Studio.hover))
            }
            .buttonStyle(.plain)
            .help(L("Remove this note"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.composerBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Studio.composerBorder))
    }
}

private struct ComposerToolButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Studio.textPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(hovering ? Studio.composerButtonHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct PlusMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Studio.textPrimary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Studio.Typo.callout())
                        .foregroundStyle(Studio.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Studio.Typo.caption())
                        .foregroundStyle(Studio.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Studio.Radius.small, style: .continuous).fill(hovering ? Studio.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Hàng tự xuống dòng, căn giữa (chip gợi ý)
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let row = rows.count - 1
            rows[row].width += rows[row].indices.isEmpty ? size.width : size.width + spacing
            rows[row].height = max(rows[row].height, size.height)
            rows[row].indices.append(index)
        }
        return rows
    }
}

// MARK: - Chọn provider/model kiểu ChatGPT: tên + model + mũi tên, bấm mở danh sách

struct ProviderPicker: View {
    var compact = false
    @EnvironmentObject private var store: NotesStore
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let active = LLMService.activeProvider
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(active.name)
                    .font(compact ? Studio.Typo.callout(.semibold) : Studio.Typo.headline())
                    .foregroundStyle(Studio.textPrimary)
                    .lineLimit(1)
                if !compact {
                    Text(active.model)
                        .font(Studio.Typo.headline(.regular))
                        .foregroundStyle(Studio.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(Studio.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill(hovering || open ? Studio.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L("Switch AI provider / model"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Provider")
                    .font(Studio.Typo.caption(.medium))
                    .foregroundStyle(Studio.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                ForEach(LLMService.providers) { provider in
                    PickerRow(
                        title: provider.name,
                        subtitle: provider.model,
                        checked: provider.id == active.id
                    ) {
                        LLMService.activeProviderID = provider.id
                        store.objectWillChange.send()
                        open = false
                    }
                }
                Rectangle().fill(Studio.hairline).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
                PickerRow(title: L("Manage providers…"), subtitle: nil, checked: false, icon: "gearshape") {
                    open = false
                    store.activeSection = .settings
                }
            }
            .padding(6)
            .frame(width: 260)
        }
    }

    private struct PickerRow: View {
        let title: String
        let subtitle: String?
        let checked: Bool
        var icon: String?
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundStyle(Studio.textSecondary)
                            .frame(width: 18)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(Studio.Typo.callout(.medium))
                            .foregroundStyle(Studio.textPrimary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(Studio.Typo.caption())
                                .foregroundStyle(Studio.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Studio.textPrimary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill(hovering ? Studio.hover : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

// MARK: - Tệp đính kèm: ô trong composer, trong tin nhắn, lớp phủ khi kéo thả

private struct ComposerAttachmentTile: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if attachment.kind == .image {
                AttachmentImage(attachment: attachment, maxPixels: 200)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Studio.composerBorder))
            } else {
                DocumentCard(attachment: attachment)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Studio.accentForeground)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Studio.accent))
                    .overlay(Circle().stroke(Studio.composerBackground, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .opacity(hovering ? 1 : 0.85)
            .help(L("Remove this file"))
        }
        .padding(.top, 5)
        .padding(.trailing, 5)
        .onHover { hovering = $0 }
        .help(attachment.name)
    }
}

private struct ImportingTile: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("Reading file…"))
                .font(Studio.Typo.footnote())
                .foregroundStyle(Studio.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Studio.subtleFill))
        .padding(.top, 5)
    }
}

/// Thẻ tài liệu kiểu ChatGPT: ô màu theo loại tệp + tên + loại/kích thước. Bấm để mở bằng app mặc định.
private struct DocumentCard: View {
    let attachment: ChatAttachment
    var maxWidth: CGFloat = 230

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(Studio.Typo.footnote(.semibold))
                    .foregroundStyle(Studio.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.detailLabel)
                    .font(Studio.Typo.caption())
                    .foregroundStyle(Studio.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .frame(height: 58)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Studio.composerBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Studio.composerBorder))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(attachment.fileURL) }
    }

    private var icon: String {
        switch attachment.fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "csv", "tsv": return "tablecells.fill"
        case "doc", "docx", "rtf", "rtfd", "odt": return "doc.text.fill"
        case "json", "xml", "yaml", "yml", "html", "htm": return "curlybraces"
        default:
            return AttachmentStore.codeExtensions.contains(attachment.fileExtension) ? "chevron.left.forwardslash.chevron.right" : "doc.plaintext.fill"
        }
    }

    private var color: Color {
        switch attachment.fileExtension {
        case "pdf": return Color(nsColor: NSColor(hex: 0xE5484D))
        case "doc", "docx", "rtf", "rtfd", "odt": return Color(nsColor: NSColor(hex: 0x2F6FEB))
        case "csv", "tsv": return Color(nsColor: NSColor(hex: 0x1F9D55))
        default:
            return AttachmentStore.codeExtensions.contains(attachment.fileExtension)
                ? Color(nsColor: NSColor(hex: 0x8250DF))
                : Color(nsColor: NSColor(hex: 0x6E6E73))
        }
    }
}

private struct AttachmentImage: View {
    let attachment: ChatAttachment
    var maxPixels = 480

    var body: some View {
        if let image = AttachmentStore.thumbnail(for: attachment, maxPixels: maxPixels) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Studio.subtleFill
                Image(systemName: "photo")
                    .foregroundStyle(Studio.textTertiary)
            }
        }
    }
}

/// Ảnh + tài liệu hiển thị phía trên bong bóng tin nhắn của người dùng
private struct MessageAttachmentsView: View {
    let attachments: [ChatAttachment]
    let compact: Bool

    private var images: [ChatAttachment] { attachments.filter { $0.kind == .image } }
    private var documents: [ChatAttachment] { attachments.filter { $0.kind == .document } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if images.count == 1, let image = images.first {
                let ratio = AttachmentStore.imageAspectRatio(for: image)
                let maxSide: CGFloat = compact ? 220 : 300
                let size = ratio >= 1
                    ? CGSize(width: maxSide, height: max(maxSide / ratio, 80))
                    : CGSize(width: max(maxSide * ratio, 80), height: maxSide)
                imageTile(image)
                    .frame(width: size.width, height: size.height)
            } else if !images.isEmpty {
                let side: CGFloat = compact ? 92 : 120
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 6), count: min(images.count, compact ? 3 : 3)), spacing: 6) {
                    ForEach(images) { image in
                        imageTile(image)
                            .frame(width: side, height: side)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
            ForEach(documents) { document in
                DocumentCard(attachment: document, maxWidth: compact ? 260 : 300)
                    .help(Lf("Double-click to open %@", document.name))
            }
        }
    }

    private func imageTile(_ image: ChatAttachment) -> some View {
        AttachmentImage(attachment: image, maxPixels: 700)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Studio.hairline))
            .contentShape(Rectangle())
            .environment(\.layoutDirection, .leftToRight)
            .onTapGesture(count: 2) { NSWorkspace.shared.open(image.fileURL) }
            .help(L("Double-click to view the full image"))
    }
}

private struct DropOverlay: View {
    let compact: Bool

    var body: some View {
        ZStack {
            Studio.background.opacity(0.92)
            VStack(spacing: 12) {
                ZStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(nsColor: NSColor(hex: 0x2F6FEB)))
                        .rotationEffect(.degrees(-12))
                        .offset(x: -18)
                    Image(systemName: "photo.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(nsColor: NSColor(hex: 0x1F9D55)))
                        .rotationEffect(.degrees(12))
                        .offset(x: 18)
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color(nsColor: NSColor(hex: 0xE5484D)))
                        .offset(y: -6)
                }
                .frame(height: 48)
                Text(L("Drop files here"))
                    .font(compact ? Studio.Typo.headline() : Studio.Typo.title())
                    .foregroundStyle(Studio.textPrimary)
                Text(L("Images, PDF, Word, text — the assistant will analyze them for you"))
                    .font(Studio.Typo.callout())
                    .foregroundStyle(Studio.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Studio.Radius.large, style: .continuous)
                .strokeBorder(Studio.textTertiary, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(12)
        )
        .allowsHitTesting(false)
    }
}
