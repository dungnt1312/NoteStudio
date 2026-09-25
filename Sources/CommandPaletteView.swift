import SwiftUI
import AppKit

// MARK: - Command palette ⌘K: chạy lệnh + nhảy tới ghi chú / hội thoại

struct CommandPaletteView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var fieldFocused: Bool

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        var subtitle: String?
        var shortcut: String?
        let perform: () -> Void
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let items: [Item]
    }

    private var groups: [Group] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ text: String) -> Bool { q.isEmpty || text.lowercased().contains(q) }

        let commands: [Item] = [
            Item(id: "new-note", icon: "square.and.pencil", title: "Ghi chú mới", shortcut: "⌘N") { store.createNote() },
            Item(id: "new-chat", icon: "bubble.left.and.bubble.right", title: "Hội thoại mới", shortcut: "⌘⇧O") {
                store.newChatSession()
                store.activeSection = .chat
            },
            Item(id: "notes", icon: "doc.text", title: "Đi tới Ghi chú", shortcut: "⌘1") { store.activeSection = .notes },
            Item(id: "chat", icon: "sparkles", title: "Đi tới Trợ lý AI", shortcut: "⌘2") { store.activeSection = .chat },
            Item(id: "assistant-panel", icon: "sidebar.right",
                 title: store.showAssistant ? "Ẩn trợ lý bên cạnh ghi chú" : "Mở trợ lý bên cạnh ghi chú", shortcut: "⌘⇧J") {
                store.activeSection = .notes
                withAnimation(.easeInOut(duration: 0.22)) { store.showAssistant.toggle() }
            },
            Item(id: "sidebar", icon: "sidebar.left", title: store.sidebarVisible ? "Ẩn thanh bên" : "Hiện thanh bên", shortcut: "⌃⌘S") {
                withAnimation(.easeInOut(duration: 0.2)) { store.sidebarVisible.toggle() }
            },
            Item(id: "export", icon: "arrow.down.doc", title: "Xuất ghi chú hiện tại ra PDF") {
                if let note = store.selectedNote { ExportService.exportPDF(note: note) }
            },
            Item(id: "settings", icon: "gearshape", title: "Cài đặt", shortcut: "⌘,") { store.activeSection = .settings },
        ] + AppearanceMode.allCases.map { mode in
            Item(id: "appearance-\(mode.rawValue)", icon: mode.icon, title: "Giao diện: \(mode.label)") {
                AppearanceMode.current = mode
            }
        }

        let noteItems = store.notes
            .filter { matches($0.displayTitle) || (!q.isEmpty && $0.content.lowercased().contains(q)) }
            .sorted {
                if $0.pinned != $1.pinned { return $0.pinned }
                return $0.updatedAt > $1.updatedAt
            }
            .prefix(q.isEmpty ? 5 : 8)
            .map { note in
                Item(id: "note-\(note.id)", icon: note.pinned ? "pin" : "doc.text", title: note.displayTitle,
                     subtitle: note.updatedAt.studioShort) {
                    store.activeSection = .notes
                    store.select(note.id)
                }
            }

        let chatItems = store.chatSessions
            .filter { !$0.messages.isEmpty && matches($0.title) }
            .prefix(q.isEmpty ? 3 : 6)
            .map { session in
                Item(id: "chat-\(session.id)", icon: "bubble.left", title: session.title,
                     subtitle: session.updatedAt.studioShort) {
                    store.selectSession(session.id)
                    store.activeSection = .chat
                }
            }

        return [
            Group(id: "commands", title: "Lệnh", items: commands.filter { matches($0.title) }),
            Group(id: "notes", title: q.isEmpty ? "Ghi chú gần đây" : "Ghi chú", items: Array(noteItems)),
            Group(id: "chats", title: "Hội thoại", items: Array(chatItems)),
        ].filter { !$0.items.isEmpty }
    }

    private var flatItems: [Item] { groups.flatMap(\.items) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Studio.textTertiary)
                    TextField("Tìm lệnh, ghi chú, hội thoại…", text: $query)
                        .textFieldStyle(.plain)
                        .font(Studio.Typo.body())
                        .foregroundStyle(Studio.textPrimary)
                        .focused($fieldFocused)
                    Keycap(text: "esc")
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Rectangle().fill(Studio.hairline).frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            let flat = flatItems
                            ForEach(groups) { group in
                                Text(group.title)
                                    .font(Studio.Typo.footnote(.semibold))
                                    .foregroundStyle(Studio.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                ForEach(group.items) { item in
                                    let index = flat.firstIndex { $0.id == item.id } ?? 0
                                    row(item, isSelected: index == selectedIndex)
                                        .id(item.id)
                                        .onHover { if $0 { selectedIndex = index } }
                                }
                            }
                            if flat.isEmpty {
                                Text("Không có kết quả cho “\(query)”")
                                    .font(Studio.Typo.callout())
                                    .foregroundStyle(Studio.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 28)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selectedIndex) { newIndex in
                        let flat = flatItems
                        guard flat.indices.contains(newIndex) else { return }
                        proxy.scrollTo(flat[newIndex].id)
                    }
                }

                Rectangle().fill(Studio.hairline).frame(height: 1)
                HStack(spacing: 14) {
                    hint("↑↓", "di chuyển")
                    hint("↵", "chọn")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
            }
            .frame(width: 600)
            .background(Studio.popoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: Studio.Radius.medium + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Studio.Radius.medium + 2, style: .continuous).stroke(Studio.composerBorder))
            .shadow(color: Color.black.opacity(0.22), radius: 30, y: 12)
            .padding(.top, 110)
        }
        .onAppear {
            installKeyMonitor()
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .onChange(of: query) { _ in selectedIndex = 0 }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Keycap(text: key)
            Text(label)
                .font(Studio.Typo.caption())
                .foregroundStyle(Studio.textTertiary)
        }
    }

    private func row(_ item: Item, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Studio.textPrimary : Studio.textSecondary)
                .frame(width: 18)
            Text(item.title)
                .font(Studio.Typo.callout(.medium))
                .foregroundStyle(Studio.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(Studio.Typo.footnote())
                    .foregroundStyle(Studio.textTertiary)
            }
            if let shortcut = item.shortcut {
                Keycap(text: shortcut)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill(isSelected ? Studio.hover : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { execute(item) }
    }

    private func execute(_ item: Item) {
        dismiss()
        item.perform()
    }

    private func executeSelected() {
        let flat = flatItems
        guard flat.indices.contains(selectedIndex) else { return }
        execute(flat[selectedIndex])
    }

    private func dismiss() {
        store.showCommandPalette = false
    }

    private func moveSelection(_ delta: Int) {
        let count = flatItems.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 125: moveSelection(1); return nil      // ↓
            case 126: moveSelection(-1); return nil     // ↑
            case 36, 76: executeSelected(); return nil  // Enter
            case 53: dismiss(); return nil              // Esc
            default: return event
            }
        }
    }
}
