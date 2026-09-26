import SwiftUI
import AppKit

@main
struct NoteStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: NotesStore
    @StateObject private var assistant: AssistantEngine
    @StateObject private var localization = LocalizationManager.shared

    init() {
        LLMService.bootstrap()
        let store = NotesStore()
        _store = StateObject(wrappedValue: store)
        _assistant = StateObject(wrappedValue: AssistantEngine(store: store))
        // Chạy thử (harness chụp ảnh offscreen): -studioSection chat|settings mở thẳng màn đó
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-studioSection"),
           index + 1 < arguments.count,
           let section = NotesStore.AppSection(rawValue: arguments[index + 1]) {
            store.activeSection = section
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(assistant)
                // Đổi ngôn ngữ → dựng lại toàn bộ cây view để mọi chuỗi L() cập nhật
                .id(localization.language)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("New note")) { store.createNote() }
                    .keyboardShortcut("n")
                Button(L("New chat")) {
                    store.newChatSession()
                    store.activeSection = .chat
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(before: .sidebar) {
                Button(L("Notes")) { go(.notes) }
                    .keyboardShortcut("1")
                Button(L("AI Assistant")) { go(.chat) }
                    .keyboardShortcut("2")
                Divider()
                Button(store.sidebarVisible ? L("Hide Sidebar") : L("Show Sidebar")) {
                    withAnimation(.easeInOut(duration: 0.2)) { store.sidebarVisible.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button(store.showAssistant ? L("Hide Assistant Panel") : L("Open Assistant Panel")) {
                    toggleAssistantPanel()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
            }
            CommandMenu(L("Tools")) {
                Button(L("Command Palette")) { store.showCommandPalette = true }
                    .keyboardShortcut("k")
                Menu(L("Appearance")) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button(mode.label) { AppearanceMode.current = mode }
                    }
                }
                Menu(L("Language")) {
                    ForEach(AppLanguage.allCases) { language in
                        Button(language.label) { localization.set(language) }
                    }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(L("Settings…")) { go(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra(L("NoteStudio — Quick Capture"), systemImage: "square.and.pencil") {
            QuickCaptureView()
                .environmentObject(store)
                .id(localization.language)
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
            Text(L("Quick capture to NoteStudio"))
                .font(Studio.Typo.callout(.semibold))
                .foregroundStyle(Studio.textPrimary)
            TextField(L("Type an idea, Enter to save…"), text: $text)
                .textFieldStyle(.plain)
                .font(Studio.Typo.callout())
                .foregroundStyle(Studio.textPrimary)
                .focused($focused)
                .onSubmit(save)
            Text(L("Enter saves · Esc closes · First line is the title"))
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
        // Chạy thử offscreen thì không giựt focus của người dùng
        if ProcessInfo.processInfo.arguments.contains("-studioSection") == false {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
