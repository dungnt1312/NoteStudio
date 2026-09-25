import SwiftUI
import AppKit

@main
struct NoteStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: NotesStore
    @StateObject private var assistant: AssistantEngine

    init() {
        LLMService.bootstrap()
        let store = NotesStore()
        _store = StateObject(wrappedValue: store)
        _assistant = StateObject(wrappedValue: AssistantEngine(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(assistant)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ghi chú mới") { store.createNote() }
                    .keyboardShortcut("n")
                Button("Hội thoại mới") {
                    store.newChatSession()
                    store.activeSection = .chat
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(before: .sidebar) {
                Button("Ghi chú") { go(.notes) }
                    .keyboardShortcut("1")
                Button("Trợ lý AI") { go(.chat) }
                    .keyboardShortcut("2")
                Divider()
                Button(store.sidebarVisible ? "Ẩn thanh bên" : "Hiện thanh bên") {
                    withAnimation(.easeInOut(duration: 0.2)) { store.sidebarVisible.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button(store.showAssistant ? "Ẩn trợ lý bên cạnh ghi chú" : "Mở trợ lý bên cạnh ghi chú") {
                    toggleAssistantPanel()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
            }
            CommandMenu("Công cụ") {
                Button("Bảng lệnh") { store.showCommandPalette = true }
                    .keyboardShortcut("k")
                Menu("Giao diện") {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button(mode.label) { AppearanceMode.current = mode }
                    }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Cài đặt…") { go(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra("NoteStudio — ghi nhanh", systemImage: "square.and.pencil") {
            QuickCaptureView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }

    private func go(_ section: NotesStore.AppSection) {
        withAnimation(.easeInOut(duration: 0.15)) {
            store.activeSection = section
        }
    }

    private func toggleAssistantPanel() {
        withAnimation(.easeInOut(duration: 0.22)) {
            if store.activeSection != .notes {
                store.activeSection = .notes
                store.showAssistant = true
            } else {
                store.showAssistant.toggle()
            }
        }
    }
}

// MARK: - Quick capture từ menu bar

struct QuickCaptureView: View {
    @EnvironmentObject private var store: NotesStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ghi nhanh vào NoteStudio")
                .font(Studio.Typo.callout(.semibold))
                .foregroundStyle(Studio.textPrimary)
            TextField("Gõ ý tưởng, Enter để lưu…", text: $text)
                .textFieldStyle(.plain)
                .font(Studio.Typo.callout())
                .foregroundStyle(Studio.textPrimary)
                .focused($focused)
                .onSubmit(save)
            Text("Enter lưu · Esc đóng · Dòng đầu là tiêu đề")
                .font(Studio.Typo.caption())
                .foregroundStyle(Studio.textTertiary)
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
        .onExitCommand { dismiss() }
    }

    private func save() {
        store.createQuickNote(text)
        text = ""
        dismiss()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.apply()
        NSApp.activate(ignoringOtherApps: true)
    }
}
