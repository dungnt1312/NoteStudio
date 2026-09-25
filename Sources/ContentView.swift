import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var assistant: AssistantEngine

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if store.sidebarVisible {
                    SidebarView()
                        .transition(.move(edge: .leading))
                }

                Group {
                    switch store.activeSection {
                    case .notes:
                        notesWorkspace
                    case .chat:
                        ChatPanelView(style: .full)
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Studio.background)
            }
            .ignoresSafeArea()

            if store.showCommandPalette {
                CommandPaletteView()
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
            }
        }
        .frame(minWidth: 880, minHeight: 600)
        .background(WindowChromeConfigurator())
        .onOpenURL { url in
            // notestudio://note/<uuid> — được MCP tool open_note gọi
            guard url.scheme?.lowercased() == "notestudio",
                  let id = UUID(uuidString: url.lastPathComponent) else { return }
            NSApp.activate(ignoringOtherApps: true)
            store.activeSection = .notes
            store.select(id)
        }
    }

    // MARK: Khu ghi chú: soạn thảo | trợ lý AI (tùy chọn)

    private var notesWorkspace: some View {
        HStack(spacing: 0) {
            EditorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.showAssistant {
                ChatPanelView(style: .side)
                    .frame(width: Studio.assistantPanelWidth)
                    .background(Studio.background)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Studio.hairline).frame(width: 1)
                    }
                    .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: - Toast: thông báo ngắn ở đáy cửa sổ, kèm nút hành động (Hoàn tác)

private struct ToastView: View {
    @EnvironmentObject private var store: NotesStore
    let toast: StudioToast

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message)
                .font(Studio.Typo.callout(.medium))
                .foregroundStyle(Studio.accentForeground)
                .lineLimit(1)
            if let label = toast.actionLabel, let action = toast.action {
                Button {
                    action()
                } label: {
                    HStack(spacing: 5) {
                        Text(label)
                        Text("⌘Z").opacity(0.6)
                    }
                    .font(Studio.Typo.callout(.semibold))
                    .foregroundStyle(Studio.accentForeground)
                }
                .buttonStyle(.plain)
            }
            Button {
                store.dismissToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Studio.accentForeground.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Đóng")
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(Capsule().fill(Studio.accent))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}
