import SwiftUI

// MARK: - Sidebar kiểu ChatGPT: chuyển Ghi chú / Trợ lý, danh sách theo thời gian, Cài đặt ở đáy

struct SidebarView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            topBar
            WorkspaceSwitcher()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            if store.lastWorkspace == .chat {
                SessionListView()
            } else {
                NoteListView()
            }

            Rectangle().fill(Studio.hairline).frame(height: 1)
            settingsRow
                .padding(8)
        }
        .frame(width: Studio.sidebarWidth)
        .background(Studio.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Studio.hairline).frame(width: 1)
        }
    }

    // Hàng trên cùng: chừa chỗ 3 nút cửa sổ, nút thu gọn sidebar + nút tạo mới
    private var topBar: some View {
        HStack(spacing: 2) {
            WindowDragArea()
            IconButton(systemName: "sidebar.left", help: L("Hide Sidebar (⌃⌘S)")) {
                withAnimation(.easeInOut(duration: 0.2)) { store.sidebarVisible = false }
            }
            NewItemButton()
        }
        .padding(.leading, Studio.trafficLightInset)
        .padding(.trailing, 10)
        .frame(height: Studio.headerHeight)
    }

    private var settingsRow: some View {
        SidebarRow(isSelected: store.activeSection == .settings) {
            store.activeSection = .settings
        } content: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(Studio.textSecondary)
                    .frame(width: 18)
                Text(L("Settings"))
                    .font(Studio.Typo.callout(.medium))
                    .foregroundStyle(Studio.textPrimary)
                Spacer()
                Keycap(text: "⌘,")
            }
            .padding(.vertical, 2)
        }
    }
}

/// Nút "tạo mới" theo ngữ cảnh: ghi chú mới hoặc hội thoại mới
struct NewItemButton: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        let chat = store.lastWorkspace == .chat
        IconButton(systemName: "square.and.pencil", help: chat ? L("New Chat (⌘⇧O)") : L("New Note (⌘N)")) {
            if chat {
                store.newChatSession()
                store.activeSection = .chat
            } else {
                store.createNote()
            }
        }
    }
}

/// Hiện ở header nội dung khi sidebar đang ẩn
struct SidebarRevealControls: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        if !store.sidebarVisible {
            HStack(spacing: 2) {
                IconButton(systemName: "sidebar.left", help: L("Show Sidebar (⌃⌘S)")) {
                    withAnimation(.easeInOut(duration: 0.2)) { store.sidebarVisible = true }
                }
                NewItemButton()
            }
            .padding(.leading, Studio.trafficLightInset - 4)
            .padding(.trailing, 6)
        }
    }
}

// MARK: - Công tắc Ghi chú / Trợ lý

private struct WorkspaceSwitcher: View {
    @EnvironmentObject private var store: NotesStore
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.notes, icon: "doc.text", label: L("Notes"))
            segment(.chat, icon: "sparkles", label: L("Assistant"))
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Studio.hover))
    }

    private func segment(_ section: NotesStore.AppSection, icon: String, label: String) -> some View {
        let active = store.lastWorkspace == section
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                store.activeSection = section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(Studio.Typo.callout(.medium))
            }
            .foregroundStyle(active ? Studio.textPrimary : Studio.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Studio.controlBackground)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section == .notes ? L("Notes (⌘1)") : L("AI Assistant (⌘2)"))
    }
}

// MARK: - Danh sách ghi chú

private struct NoteListView: View {
    @EnvironmentObject private var store: NotesStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)

            if !store.allTags.isEmpty {
                tagFilterRow
                    .padding(.top, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .header(_, let text): SidebarSectionLabel(text: text)
                        case .item(let note): row(note)
                        }
                    }
                    if store.filteredNotes.isEmpty {
                        emptyPlaceholder
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var entries: [SidebarEntry<Note>] {
        var result: [SidebarEntry<Note>] = []
        if !store.pinnedNotes.isEmpty {
            result.append(.header(id: "pinned", text: L("Pinned")))
            result += store.pinnedNotes.map { .item($0) }
        }
        return result + SidebarEntry.grouped(store.otherNotes, by: \.updatedAt)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Studio.textTertiary)
            TextField(L("Search notes"), text: $store.searchText)
                .textFieldStyle(.plain)
                .font(Studio.Typo.callout())
                .foregroundStyle(Studio.textPrimary)
                .focused($searchFocused)
            if !store.searchText.isEmpty {
                Button { store.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Studio.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill(Studio.controlBackground))
        .overlay(
            RoundedRectangle(cornerRadius: Studio.Radius.small)
                .stroke(searchFocused ? Studio.textTertiary : Studio.hairline, lineWidth: 1)
        )
    }

    // Hàng chip thẻ cuộn ngang, mờ dần ở mép phải để báo còn nữa
    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.allTags, id: \.self) { tag in
                    let active = store.activeTagFilter == tag
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            store.activeTagFilter = active ? nil : tag
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("#\(tag)")
                            if active {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .font(Studio.Typo.footnote(.medium))
                        .foregroundStyle(active ? Studio.accentForeground : Studio.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(active ? Studio.accent : Studio.hover))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .mask(
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
            }
        )
    }

    private func row(_ note: Note) -> some View {
        SidebarRow(isSelected: note.id == store.selectedNoteID && store.activeSection == .notes) {
            store.activeSection = .notes
            store.select(note.id)
        } content: {
            NoteRowContent(note: note)
        }
        .contextMenu {
            Button {
                store.togglePin(noteID: note.id)
            } label: {
                Label(note.pinned ? L("Unpin") : L("Pin to Top"), systemImage: note.pinned ? "pin.slash" : "pin")
            }
            Button {
                store.activeSection = .notes
                store.select(note.id)
                store.showAssistant = true
            } label: {
                Label(L("Ask AI about this note"), systemImage: "sparkles")
            }
            Divider()
            Button(role: .destructive) {
                store.delete(noteID: note.id)
            } label: {
                Label(L("Delete Note"), systemImage: "trash")
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: store.notes.isEmpty ? "square.and.pencil" : "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(Studio.textTertiary)
            Text(store.notes.isEmpty ? L("No notes yet") : L("No notes found"))
                .font(Studio.Typo.callout())
                .foregroundColor(Studio.textSecondary)
            if !store.notes.isEmpty, store.activeTagFilter != nil || !store.searchText.isEmpty {
                Button(L("Clear Filter")) {
                    store.searchText = ""
                    store.activeTagFilter = nil
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

private struct NoteRowContent: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(Studio.textTertiary)
                Text(note.displayTitle)
                    .font(Studio.Typo.callout(.medium))
                    .foregroundColor(Studio.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Studio.textTertiary)
                }
            }
            HStack(spacing: 6) {
                Text(note.updatedAt.studioShort)
                    .foregroundStyle(Studio.textSecondary)
                    .layoutPriority(1)
                Text(note.snippet.isEmpty ? L("No content yet") : note.snippet)
                    .foregroundStyle(Studio.textTertiary)
                    .lineLimit(1)
            }
            .font(Studio.Typo.footnote())
            .padding(.leading, 17)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Danh sách hội thoại

private struct SessionListView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var renaming: ChatSession?
    @State private var renameDraft = ""
    @State private var deleting: ChatSession?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(SidebarEntry.grouped(store.chatSessions, by: \.updatedAt)) { entry in
                    switch entry {
                    case .header(_, let text):
                        SidebarSectionLabel(text: text)
                    case .item(let session):
                        SessionRow(
                            session: session,
                            isActive: session.id == store.activeChatSessionID && store.activeSection == .chat,
                            onSelect: {
                                store.selectSession(session.id)
                                store.activeSection = .chat
                            },
                            onRename: {
                                renameDraft = session.title
                                renaming = session
                            },
                            onDelete: { deleting = session }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .sessionRenameAlert(session: $renaming, draft: $renameDraft)
        .sessionDeleteDialog(session: $deleting)
    }
}

private struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        SidebarRow(isSelected: isActive, action: onSelect) {
            HStack(spacing: 4) {
                Text(session.title)
                    .font(Studio.Typo.callout(isActive ? .medium : .regular))
                    .foregroundStyle(Studio.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hovering || isActive {
                    Menu {
                        Button(L("Rename"), action: onRename)
                        Divider()
                        Button(L("Delete Chat"), role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .foregroundStyle(Studio.textSecondary)
                    .fixedSize()
                    .help(L("Options"))
                }
            }
            .frame(height: 22)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Rename"), action: onRename)
            Divider()
            Button(L("Delete Chat"), role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Thành phần chung của sidebar

/// Danh sách phẳng (tiêu đề nhóm + dòng) cho một ForEach duy nhất.
/// ForEach lồng nhau trong LazyVStack không vẽ lại dòng khi nhóm đổi (vd. qua nửa đêm "Hôm nay" → "Hôm qua"),
/// làm dòng đang chọn không còn sáng lên.
enum SidebarEntry<Item: Identifiable>: Identifiable where Item.ID == UUID {
    case header(id: String, text: String)
    case item(Item)

    var id: String {
        switch self {
        case .header(let id, _): return "header-\(id)"
        case .item(let item): return item.id.uuidString
        }
    }

    static func grouped(_ items: [Item], by date: (Item) -> Date) -> [SidebarEntry] {
        TimeBucket.group(items, by: date).flatMap { bucket, list in
            [.header(id: "\(bucket.rawValue)", text: bucket.label)] + list.map { .item($0) }
        }
    }
}

struct SidebarSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Studio.Typo.footnote(.semibold))
            .foregroundColor(Studio.textSecondary)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

struct SidebarRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Studio.Radius.small)
                    .fill(isSelected ? Studio.selected : (hovering ? Studio.hover : Color.clear))
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            // Dòng bị dời chỗ khi danh sách sắp xếp lại không nhận được sự kiện rời chuột
            .onDisappear { hovering = false }
            .onChange(of: isSelected) { _ in hovering = false }
    }
}

// MARK: - Đổi tên / xóa hội thoại (dùng chung cho sidebar và header chat)

extension View {
    func sessionRenameAlert(session: Binding<ChatSession?>, draft: Binding<String>) -> some View {
        modifier(SessionRenameAlert(session: session, draft: draft))
    }

    func sessionDeleteDialog(session: Binding<ChatSession?>) -> some View {
        modifier(SessionDeleteDialog(session: session))
    }
}

private struct SessionRenameAlert: ViewModifier {
    @EnvironmentObject private var store: NotesStore
    @Binding var session: ChatSession?
    @Binding var draft: String

    func body(content: Content) -> some View {
        content.alert(L("Rename Chat"), isPresented: Binding(
            get: { session != nil },
            set: { if !$0 { session = nil } }
        )) {
            TextField(L("Chat name"), text: $draft)
            Button(L("Save")) {
                if let session { store.renameSession(session.id, to: draft) }
                session = nil
            }
            Button(L("Cancel"), role: .cancel) { session = nil }
        }
    }
}

private struct SessionDeleteDialog: ViewModifier {
    @EnvironmentObject private var store: NotesStore
    @Binding var session: ChatSession?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Lf("Delete chat “%@”?", session?.title ?? ""),
            isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Delete"), role: .destructive) {
                if let session { store.deleteSession(session.id) }
                session = nil
            }
            Button(L("Cancel"), role: .cancel) { session = nil }
        } message: {
            Text(L("All messages in this chat will be deleted. Notes are not affected."))
        }
    }
}
