import SwiftUI
import AppKit
import Combine

/// Chế độ hiển thị ghi chú: soạn trực quan (Typora) · Markdown thô · xem trước chỉ đọc
enum EditorMode: String, CaseIterable {
    case live, source, preview

    static let storageKey = "editorMode"

    var icon: String {
        switch self {
        case .live: return "pencil"
        case .source: return "chevron.left.forwardslash.chevron.right"
        case .preview: return "eye"
        }
    }

    var help: String {
        switch self {
        case .live: return L("Live editing")
        case .source: return L("Markdown source")
        case .preview: return L("Preview (read-only)")
        }
    }
}

struct EditorView: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var assistant: AssistantEngine
    @AppStorage(EditorMode.storageKey) private var mode = EditorMode.live
    @State private var titleBusy = false
    @State private var aiError: String?
    @State private var selectedText: String?
    @State private var bridge = EditorBridge()

    var body: some View {
        VStack(spacing: 0) {
            header
            if let note = store.selectedNote {
                // Dựng lại toàn bộ ô nhập khi đổi note: ô đang focus không giữ chữ của note cũ
                editor(note)
                    .id(note.id)
            } else {
                emptyState
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { _ in
            selectedText = EditorSelection.grabSelectedText()
        }
        .onChange(of: store.selectedNoteID) { _ in
            aiError = nil
            selectedText = nil
        }
        .onChange(of: mode) { _ in
            bridge.closeMenus()
            selectedText = nil
        }
    }

    // MARK: Header: điều khiển sidebar · đường dẫn tài liệu · chế độ · thao tác

    private var header: some View {
        HStack(spacing: 4) {
            SidebarRevealControls()
            if let note = store.selectedNote {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                    Text(note.displayTitle + ".md")
                        .foregroundStyle(Studio.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(Lf("· Saved %@", note.updatedAt.studioRelative))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                .font(Studio.Typo.footnote())
                .foregroundStyle(Studio.textTertiary)
                .padding(.leading, store.sidebarVisible ? 18 : 6)
            }

            WindowDragArea()

            if let note = store.selectedNote {
                modeSwitch
                    .padding(.trailing, 4)
                IconButton(systemName: note.pinned ? "pin.fill" : "pin", active: note.pinned,
                           help: note.pinned ? L("Unpin") : L("Pin to top of list")) {
                    store.togglePin(noteID: note.id)
                }
                moreMenu(note)
            }
            assistantToggle
        }
        .padding(.trailing, 12)
        .frame(height: Studio.headerHeight)
    }

    /// Nhóm 3 nút như ảnh tham khảo: <> mã nguồn · ✎ soạn · 👁 xem trước
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach([EditorMode.source, .live, .preview], id: \.self) { item in
                Button {
                    mode = item
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(mode == item ? Studio.textPrimary : Studio.textTertiary)
                        .frame(width: 30, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(mode == item ? Studio.controlBackground : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.help)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Studio.hover))
    }

    private var assistantToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { store.showAssistant.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                Text(L("Assistant"))
                    .font(Studio.Typo.callout(.medium))
            }
            .foregroundStyle(store.showAssistant ? Studio.accentForeground : Studio.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(store.showAssistant ? Studio.accent : Studio.hover))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .help(store.showAssistant ? L("Hide Assistant (⌘⇧J)") : L("Open Assistant Panel (⌘⇧J)"))
    }

    private func moreMenu(_ note: Note) -> some View {
        IconMenu(help: L("More actions")) {
            Button {
                copyContent(note)
            } label: {
                Label(L("Copy Markdown"), systemImage: "doc.on.doc")
            }
            Button {
                ExportService.exportMarkdown(note: note)
            } label: {
                Label(L("Export as .md…"), systemImage: "arrow.down.doc")
            }
            Button {
                ExportService.exportPDF(note: note)
            } label: {
                Label(L("Export as PDF…"), systemImage: "doc.richtext")
            }
            Divider()
            Button {
                suggestTitle()
            } label: {
                Label(L("Suggest Title with AI"), systemImage: "sparkles")
            }
            .disabled(note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Divider()
            Section(Lf("%1$@ · %2$d words · %3$d characters", note.createdAt.studioDateTime, note.wordCount, note.content.count)) {}
            Divider()
            Button(role: .destructive) {
                store.delete(noteID: note.id)
            } label: {
                Label(L("Delete Note"), systemImage: "trash")
            }
        }
    }

    // MARK: Thân: thanh công cụ + tài liệu Markdown (tiêu đề chính là dòng "# " đầu tiên)

    private func editor(_ note: Note) -> some View {
        VStack(spacing: 0) {
            formatBar(note)
            Rectangle().fill(Studio.hairline).frame(height: 1)

            if mode != .source {
                metaStrip(note)
            }

            Group {
                switch mode {
                case .preview:
                    MarkdownPreviewView(content: contentBinding(note.id))
                        .padding(.horizontal, 48)
                        .frame(maxWidth: 760 + 96)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                case .live, .source:
                    MarkdownEditor(text: contentBinding(note.id), bridge: bridge,
                                   livePreview: mode == .live,
                                   focusOnAppear: store.newlyCreatedID == note.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let selection = selectedText, mode != .preview {
                quickActionsBar(selection)
            }
        }
        .onAppear {
            if store.newlyCreatedID == note.id {
                DispatchQueue.main.async { store.newlyCreatedID = nil }
            }
        }
    }

    // MARK: Thanh công cụ định dạng (giống ảnh tham khảo): ¶ H1 H2 H3 | B I S | list | quote link code …

    private func formatBar(_ note: Note) -> some View {
        HStack(spacing: 2) {
            if mode == .preview {
                Text(L("Preview mode — click ✎ to edit"))
                    .font(Studio.Typo.footnote())
                    .foregroundStyle(Studio.textTertiary)
                    .padding(.leading, 6)
            } else {
                FormatTextButton(label: "¶", help: L("Plain paragraph (⌥⌘0)")) { bridge.paragraph() }
                FormatTextButton(label: "H1", help: L("Heading 1 (⌥⌘1)")) { bridge.heading(1) }
                FormatTextButton(label: "H2", help: L("Heading 2 (⌥⌘2)")) { bridge.heading(2) }
                FormatTextButton(label: "H3", help: L("Heading 3 (⌥⌘3)")) { bridge.heading(3) }
                EditorToolDivider()
                FormatTextButton(label: "B", weight: .bold, help: L("Bold (⌘B)")) { bridge.bold() }
                FormatTextButton(label: "I", italic: true, help: L("Italic (⌘I)")) { bridge.italic() }
                FormatTextButton(label: "S", strike: true, help: L("Strikethrough (⌘⇧X)")) { bridge.strikethrough() }
                EditorToolDivider()
                EditorToolButton(icon: "list.bullet", help: L("Bulleted list")) { bridge.toggleBullets() }
                EditorToolButton(icon: "list.number", help: L("Numbered list")) { bridge.toggleNumbered() }
                EditorToolButton(icon: "checklist", help: L("Checklist (⌘⇧↩ to tick)")) { bridge.toggleChecklist() }
                EditorToolDivider()
                EditorToolButton(icon: "text.quote", help: L("Quote")) { bridge.toggleQuote() }
                EditorToolButton(icon: "link", help: L("Link")) { bridge.link() }
                EditorToolButton(icon: "chevron.left.forwardslash.chevron.right", help: L("Inline code (⌘E)")) { bridge.inlineCode() }
                Menu {
                    Button { bridge.codeBlock() } label: { Label(L("Code block"), systemImage: "curlybraces.square") }
                    Button { bridge.table() } label: { Label(L("Table"), systemImage: "tablecells") }
                    Button { bridge.rule() } label: { Label(L("Horizontal rule"), systemImage: "minus") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .foregroundStyle(Studio.textSecondary)
                .frame(width: 30, height: 28)
                .fixedSize()
                .help(L("Insert"))
            }
            Spacer(minLength: 12)
            Text(statsText(note))
                .font(Studio.Typo.footnote())
                .foregroundStyle(Studio.textTertiary)
                .lineLimit(1)
                .help(L("⌘F to search inside the note"))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    /// Thẻ + trạng thái AI: một dải mảnh ngay dưới thanh công cụ, chỉ hiện khi có nội dung
    private func metaStrip(_ note: Note) -> some View {
        HStack(spacing: 8) {
            TagStrip(note: note, aiError: $aiError)
            if titleBusy {
                ProgressView().controlSize(.small)
                Text(L("AI is naming the note…"))
                    .font(Studio.Typo.footnote())
                    .foregroundStyle(Studio.textTertiary)
            }
            if let aiError {
                Text(aiError)
                    .font(Studio.Typo.footnote())
                    .foregroundStyle(Studio.danger)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
    }

    private func statsText(_ note: Note) -> String {
        let words = note.wordCount
        guard words > 0 else { return L("0 words") }
        if words > 200 {
            return Lf("%1$d words · %2$d min read", words, max(1, words / 220))
        }
        return Lf("%d words", words)
    }

    // MARK: Quick AI — bôi đen đoạn văn → chọn hành động → gửi sang trợ lý bên cạnh

    private func quickActionsBar(_ selection: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Studio.textSecondary)
                .padding(.leading, 4)
            quickButton(L("Explain"), instruction: L("Explain the following paragraph in detail, in plain language"), selection: selection)
            quickButton(L("Translate to English"), instruction: L("Translate the following paragraph into English"), selection: selection)
            quickButton(L("Shorten"), instruction: L("Shorten the following paragraph while keeping the key points"), selection: selection)
            quickButton(L("Critique"), instruction: L("Critique the following paragraph and suggest improvements"), selection: selection)
            Button {
                selectedText = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Studio.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L("Close"))
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Studio.popoverBackground)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
        )
        .overlay(Capsule().stroke(Studio.composerBorder))
        .padding(.bottom, 28)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func quickButton(_ label: String, instruction: String, selection: String) -> some View {
        QuickActionChip(label: label) {
            submitQuickAI(instruction: instruction, selection: selection)
        }
    }

    private func submitQuickAI(instruction: String, selection: String) {
        guard let note = store.selectedNote else { return }
        let mention = MentionedNote(id: note.id, title: note.displayTitle)
        let bubbleText = Lf("%@ (selected text in @%@)", instruction, note.displayTitle)
        let prompt = Lf("%1$@:\n\n“%2$@”\n\n(The above is an excerpt from note @%3$@.)", instruction, selection, note.displayTitle)
        selectedText = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            store.showAssistant = true
        }
        assistant.submitQuick(text: bubbleText, prompt: prompt, mentions: [mention])
    }

    // MARK: AI gợi ý tiêu đề

    private func suggestTitle() {
        guard let note = store.selectedNote else { return }
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        titleBusy = true
        aiError = nil
        Task {
            do {
                let suggestion = try await LLMService.suggestTitle(content: content)
                store.update(noteID: note.id) { $0.title = suggestion }
            } catch {
                aiError = error.localizedDescription
            }
            titleBusy = false
        }
    }

    private func copyContent(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.content, forType: .string)
        store.showToast(StudioToast(message: L("Note Markdown copied")))
    }

    // MARK: Bindings

    /// Binding gắn cứng với id của note — ô nhập chỉ có thể ghi vào đúng note nó đang hiển thị
    private func contentBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.note(id)?.content ?? "" },
            set: { value in store.update(noteID: id) { $0.content = value } }
        )
    }

    // MARK: Trạng thái rỗng

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Studio.textTertiary)
            Text(store.notes.isEmpty ? L("No notes yet") : L("Select a note to get started"))
                .font(Studio.Typo.headline())
                .foregroundStyle(Studio.textPrimary)
            Text(L("Notes are saved automatically, right on your Mac."))
                .font(Studio.Typo.callout())
                .foregroundStyle(Studio.textSecondary)
            HStack(spacing: 8) {
                Button {
                    store.createNote()
                } label: {
                    Label(L("New note"), systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
                Keycap(text: "⌘N")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickActionChip: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Studio.Typo.footnote(.medium))
                .foregroundStyle(Studio.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(hovering ? Studio.hover : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Nút nhỏ cho thanh định dạng đáy editor

private struct EditorToolButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? Studio.textPrimary : Studio.textSecondary)
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Studio.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Nút chữ của thanh công cụ: ¶ H1 H2 H3 B I S
private struct FormatTextButton: View {
    let label: String
    var weight: Font.Weight = .semibold
    var italic = false
    var strike = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: weight, design: .default))
                .italic(italic)
                .strikethrough(strike)
                .foregroundStyle(hovering ? Studio.textPrimary : Studio.textSecondary)
                .frame(minWidth: 30, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Studio.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct EditorToolDivider: View {
    var body: some View {
        Rectangle()
            .fill(Studio.hairline)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 7)
    }
}

// MARK: - Thẻ ngay dưới tiêu đề (kiểu Notion): xem, xóa, thêm tay, nhờ AI gợi ý

private struct TagStrip: View {
    @EnvironmentObject private var store: NotesStore
    let note: Note
    @Binding var aiError: String?

    @State private var adding = false
    @State private var draft = ""
    @State private var suggesting = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(note.displayTags, id: \.self) { tag in
                TagChip(tag: tag) { remove(tag) }
            }

            if adding {
                TextField(L("tag name"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(Studio.Typo.footnote())
                    .foregroundStyle(Studio.textPrimary)
                    .frame(width: 90)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .overlay(Capsule().stroke(Studio.hairline))
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand { adding = false; draft = "" }
                    .onChange(of: fieldFocused) { focused in
                        if !focused { commit(); adding = false }
                    }
            } else {
                GhostChip(icon: "plus", label: note.displayTags.isEmpty ? L("Add tag") : nil) {
                    adding = true
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .help(L("Add tag"))
            }

            GhostChip(icon: "sparkles", label: suggesting ? L("Suggesting…") : L("Suggest tags")) {
                suggest()
            }
            .disabled(suggesting || note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(L("Let AI suggest tags from the content"))
        }
    }

    private func commit() {
        let tag = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        draft = ""
        guard !tag.isEmpty else { return }
        store.update(noteID: note.id) { note in
            var tags = note.tags ?? []
            if !tags.contains(tag) { tags.append(tag) }
            note.tags = tags
        }
    }

    private func remove(_ tag: String) {
        store.update(noteID: note.id) { note in
            note.tags = (note.tags ?? []).filter { $0 != tag }
        }
    }

    private func suggest() {
        suggesting = true
        aiError = nil
        let content = note.content
        let noteID = note.id
        Task {
            do {
                let suggested = try await LLMService.suggestTags(content: content)
                store.update(noteID: noteID) { note in
                    var tags = note.tags ?? []
                    for tag in suggested where !tags.contains(tag) { tags.append(tag) }
                    note.tags = tags
                }
            } catch {
                aiError = error.localizedDescription
            }
            suggesting = false
        }
    }
}

private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(Studio.Typo.footnote(.medium))
                .foregroundStyle(Studio.textSecondary)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Studio.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L("Remove tag"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Studio.hover))
        .onHover { hovering = $0 }
    }
}

private struct GhostChip: View {
    let icon: String
    let label: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                if let label {
                    Text(label)
                        .font(Studio.Typo.footnote(.medium))
                }
            }
            .foregroundStyle(Studio.textTertiary)
            .padding(.horizontal, label == nil ? 0 : 9)
            .frame(minWidth: 24)
            .frame(height: 24)
            .background(Capsule().fill(hovering && isEnabled ? Studio.hover : Color.clear))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Đọc đoạn văn đang bôi đen từ NSTextView (first responder của key window)

enum EditorSelection {
    static func grabSelectedText() -> String? {
        guard let window = NSApp.keyWindow else { return nil }
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if let textView = current as? NSTextView {
                // Chỉ lấy vùng soạn thảo ghi chú: bỏ qua composer chat và ô nhập một dòng
                guard textView.identifier != ComposerCoordinator.identifier, !textView.isFieldEditor else { return nil }
                let range = textView.selectedRange()
                guard range.length > 0 else { return nil }
                let text = (textView.string as NSString).substring(with: range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            responder = current.nextResponder
        }
        return nil
    }
}
