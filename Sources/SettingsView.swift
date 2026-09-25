import SwiftUI

// MARK: - Màn hình Cài đặt: giao diện, AI providers, đồng bộ, giới thiệu

struct SettingsView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var providers: [LLMService.Provider] = LLMService.providers
    @State private var activeID: UUID? = LLMService.activeProviderID
    @State private var appearance = AppearanceMode.current
    @State private var providerToDelete: LLMService.Provider?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarRevealControls()
                WindowDragArea()
            }
            .frame(height: Studio.headerHeight)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Cài đặt")
                        .font(Studio.Typo.largeTitle())
                        .foregroundStyle(Studio.textPrimary)

                    appearanceSection
                    providersSection
                    syncSection
                    aboutSection
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 48)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(
            "Xóa provider “\(providerToDelete?.name ?? "")”?",
            isPresented: Binding(get: { providerToDelete != nil }, set: { if !$0 { providerToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xóa provider và API key", role: .destructive) {
                if let provider = providerToDelete { remove(provider) }
                providerToDelete = nil
            }
            Button("Hủy", role: .cancel) { providerToDelete = nil }
        } message: {
            Text("API key đã lưu cho provider này cũng sẽ bị xóa khỏi máy.")
        }
    }

    // MARK: Giao diện

    private var appearanceSection: some View {
        SettingsSection(title: "Giao diện") {
            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceOption(mode: mode, selected: appearance == mode) {
                        appearance = mode
                        AppearanceMode.current = mode
                    }
                }
            }
        }
    }

    // MARK: AI Providers

    private var providersSection: some View {
        SettingsSection(
            title: "Nhà cung cấp AI",
            caption: "Mọi dịch vụ theo chuẩn OpenAI: OpenAI, OpenRouter, Groq, Ollama chạy local, vLLM…"
        ) {
            VStack(spacing: 12) {
                ForEach($providers) { $provider in
                    ProviderCard(
                        provider: $provider,
                        isActive: provider.id == activeID,
                        canDelete: providers.count > 1,
                        onActivate: { activeID = provider.id },
                        onDelete: { providerToDelete = provider }
                    )
                }
                addProviderButton
            }
        }
        .onChange(of: providers) { newValue in
            LLMService.providers = newValue
        }
        .onChange(of: activeID) { newID in
            LLMService.activeProviderID = newID
        }
    }

    private func remove(_ provider: LLMService.Provider) {
        LLMService.setKey("", for: provider.id)
        providers.removeAll { $0.id == provider.id }
        if activeID == provider.id {
            activeID = providers.first?.id
        }
    }

    private var addProviderButton: some View {
        Button {
            let provider = LLMService.Provider(
                name: "Provider mới",
                baseURL: LLMService.defaultBaseURL,
                model: LLMService.defaultModel
            )
            providers.append(provider)
            activeID = provider.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Thêm provider")
                    .font(Studio.Typo.callout(.medium))
            }
            .foregroundStyle(Studio.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Studio.Radius.medium)
                    .stroke(Studio.hairline, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Đồng bộ

    private var syncSection: some View {
        SettingsSection(title: "Đồng bộ") {
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sao lưu qua iCloud Drive")
                            .font(Studio.Typo.callout(.medium))
                            .foregroundStyle(Studio.textPrimary)
                        Text(NotesStore.iCloudAvailable
                            ? "Mỗi lần lưu, ghi chú được sao sang iCloud Drive/NoteStudio. Khi mở app, bản sửa gần nhất giữa máy này và iCloud sẽ được giữ."
                            : "Không tìm thấy iCloud Drive trên máy này.")
                            .font(Studio.Typo.footnote())
                            .foregroundStyle(Studio.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "icloudSync") },
                        set: { enabled in
                            UserDefaults.standard.set(enabled, forKey: "icloudSync")
                            store.iCloudSyncSettingChanged(enabled: enabled)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!NotesStore.iCloudAvailable)
                }
            }
        }
    }

    // MARK: Giới thiệu + phím tắt

    private var aboutSection: some View {
        SettingsSection(title: "Phím tắt & thông tin") {
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    shortcutRow("Ghi chú mới", "⌘N")
                    shortcutRow("Hội thoại mới", "⌘⇧O")
                    shortcutRow("Chuyển Ghi chú / Trợ lý", "⌘1  ⌘2")
                    shortcutRow("Trợ lý bên cạnh ghi chú", "⌘⇧J")
                    shortcutRow("Bảng lệnh", "⌘K")
                    shortcutRow("Ẩn / hiện thanh bên", "⌃⌘S")
                    shortcutRow("Hoàn tác xóa", "⌘Z")
                    infoRow("Dữ liệu", "~/Library/Application Support/NoteStudio")
                    infoRow("MCP server", "notestudio-mcp — cho AI client bên ngoài đọc/ghi ghi chú", last: true)
                }
            }
        }
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(Studio.Typo.callout())
                    .foregroundStyle(Studio.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(keys.components(separatedBy: "  "), id: \.self) { Keycap(text: $0) }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            Rectangle().fill(Studio.hairline).frame(height: 1).padding(.leading, 16)
        }
    }

    private func infoRow(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Studio.Typo.callout())
                    .foregroundStyle(Studio.textPrimary)
                Spacer(minLength: 20)
                Text(value)
                    .font(Studio.Typo.footnote())
                    .foregroundStyle(Studio.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            if !last {
                Rectangle().fill(Studio.hairline).frame(height: 1).padding(.leading, 16)
            }
        }
    }
}

// MARK: - Thẻ cấu hình một provider

private struct ProviderCard: View {
    @Binding var provider: LLMService.Provider
    let isActive: Bool
    let canDelete: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    enum TestState: Equatable { case idle, running, ok(String), failed(String) }
    @State private var testState: TestState = .idle

    var body: some View {
        SettingsCard(highlighted: isActive) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: onActivate) {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(isActive ? Studio.textPrimary : Studio.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(isActive ? "Đang dùng" : "Dùng provider này")

                    TextField("Tên provider", text: $provider.name)
                        .textFieldStyle(.plain)
                        .font(Studio.Typo.body(.semibold))
                        .foregroundStyle(Studio.textPrimary)

                    if isActive {
                        Text("Đang dùng")
                            .font(Studio.Typo.caption(.semibold))
                            .foregroundStyle(Studio.accentForeground)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(Studio.accent))
                    } else {
                        Button("Dùng", action: onActivate)
                            .buttonStyle(SecondaryButtonStyle())
                            .controlSize(.small)
                    }

                    if canDelete {
                        IconButton(systemName: "trash", help: "Xóa provider (kèm API key)", action: onDelete)
                    }
                }

                field("Base URL", text: $provider.baseURL, placeholder: LLMService.defaultBaseURL)
                field("Model", text: $provider.model, placeholder: LLMService.defaultModel)
                field("API key", text: keyBinding, placeholder: "sk-… (để trống nếu không cần)", secure: true,
                      caption: "Lưu cục bộ trên máy, không đồng bộ đi đâu.")

                HStack(spacing: 10) {
                    Button {
                        runTest()
                    } label: {
                        HStack(spacing: 6) {
                            if testState == .running {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "bolt.horizontal")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("Kiểm tra kết nối")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(testState == .running)

                    switch testState {
                    case .idle, .running:
                        EmptyView()
                    case .ok(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(Studio.Typo.footnote(.medium))
                            .foregroundStyle(Color(nsColor: NSColor.dynamic(0x1A7F37, 0x3FB950)))
                            .lineLimit(1)
                    case .failed(let message):
                        Label(message, systemImage: "xmark.octagon.fill")
                            .font(Studio.Typo.footnote())
                            .foregroundStyle(Studio.danger)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .onChange(of: provider) { _ in testState = .idle }
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { LLMService.key(for: provider.id) },
            set: { LLMService.setKey($0, for: provider.id); testState = .idle }
        )
    }

    private func runTest() {
        testState = .running
        let target = provider
        Task {
            let started = Date()
            do {
                _ = try await LLMService.chat(
                    messages: [["role": "user", "content": "ping — trả lời đúng một chữ: ok"]],
                    temperature: 0,
                    provider: target
                )
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                testState = .ok("Kết nối được · \(ms) ms")
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Studio.Typo.footnote(.medium))
                .foregroundStyle(Studio.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(Studio.Typo.callout())
            .foregroundStyle(Studio.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill(Studio.background))
            .overlay(RoundedRectangle(cornerRadius: Studio.Radius.small).stroke(Studio.hairline))
            if let caption {
                Text(caption)
                    .font(Studio.Typo.caption())
                    .foregroundStyle(Studio.textTertiary)
            }
        }
    }
}

// MARK: - Thành phần chung

private struct SettingsSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Studio.Typo.headline())
                    .foregroundStyle(Studio.textPrimary)
                if let caption {
                    Text(caption)
                        .font(Studio.Typo.footnote())
                        .foregroundStyle(Studio.textSecondary)
                }
            }
            content()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var highlighted = false
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Studio.Radius.medium).fill(Studio.controlBackground))
            .overlay(
                RoundedRectangle(cornerRadius: Studio.Radius.medium)
                    .stroke(highlighted ? Studio.textPrimary : Studio.hairline, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

private struct AppearanceOption: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Studio.Radius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: Studio.Radius.small)
                            .stroke(selected ? Studio.textPrimary : Studio.hairline, lineWidth: selected ? 2 : 1)
                    )
                HStack(spacing: 5) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11))
                    Text(mode.label)
                        .font(Studio.Typo.footnote(selected ? .semibold : .regular))
                }
                .foregroundStyle(selected ? Studio.textPrimary : Studio.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .light: miniWindow(dark: false)
        case .dark: miniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                miniWindow(dark: false)
                miniWindow(dark: true)
            }
        }
    }

    private func miniWindow(dark: Bool) -> some View {
        HStack(spacing: 0) {
            Color(nsColor: NSColor(hex: dark ? 0x181818 : 0xF9F9F9)).frame(width: 22)
            ZStack(alignment: .topLeading) {
                Color(nsColor: NSColor(hex: dark ? 0x212121 : 0xFFFFFF))
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color(nsColor: NSColor(hex: dark ? 0xECECEC : 0x0D0D0D))).frame(width: 34, height: 5)
                    Capsule().fill(Color(nsColor: NSColor(hex: dark ? 0x5A5A5A : 0xD0D0D0))).frame(width: 50, height: 4)
                    Capsule().fill(Color(nsColor: NSColor(hex: dark ? 0x5A5A5A : 0xD0D0D0))).frame(width: 40, height: 4)
                }
                .padding(10)
            }
        }
    }
}
