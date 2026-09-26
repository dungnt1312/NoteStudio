import SwiftUI

// MARK: - Màn hình Cài đặt: giao diện, AI providers, đồng bộ, giới thiệu

struct SettingsView: View {
    @EnvironmentObject private var store: NotesStore
    @ObservedObject private var localization = LocalizationManager.shared
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
                    Text(L("Settings"))
                        .font(Studio.Typo.largeTitle())
                        .foregroundStyle(Studio.textPrimary)

                    appearanceSection
                    languageSection
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
            Lf("Delete provider “%@”?", providerToDelete?.name ?? ""),
            isPresented: Binding(get: { providerToDelete != nil }, set: { if !$0 { providerToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Delete provider and API key"), role: .destructive) {
                if let provider = providerToDelete { remove(provider) }
                providerToDelete = nil
            }
            Button(L("Cancel"), role: .cancel) { providerToDelete = nil }
        } message: {
            Text(L("The stored API key for this provider will also be removed from this Mac."))
        }
    }

    // MARK: Giao diện

    private var appearanceSection: some View {
        SettingsSection(title: L("Appearance")) {
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

    // MARK: Ngôn ngữ

    private var languageSection: some View {
        SettingsSection(title: L("Language")) {
            SettingsCard {
                HStack(spacing: 10) {
                    ForEach(AppLanguage.allCases) { language in
                        LanguageOption(language: language, selected: localization.language == language) {
                            localization.set(language)
                        }
                    }
                }
            }
        }
    }

    // MARK: AI Providers

    private var providersSection: some View {
        SettingsSection(
            title: L("AI Providers"),
            caption: L("Any OpenAI-compatible service: OpenAI, OpenRouter, Groq, local Ollama, vLLM…")
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
                name: L("New provider"),
                baseURL: LLMService.defaultBaseURL,
                model: LLMService.defaultModel
            )
            providers.append(provider)
            activeID = provider.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(L("Add provider"))
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
        SettingsSection(title: L("Sync")) {
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Back up via iCloud Drive"))
                            .font(Studio.Typo.callout(.medium))
                            .foregroundStyle(Studio.textPrimary)
                        Text(NotesStore.iCloudAvailable
                            ? L("On every save, notes are mirrored to iCloud Drive/NoteStudio. When opening the app, the most recent edit between this Mac and iCloud wins.")
                            : L("iCloud Drive was not found on this Mac."))
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
        SettingsSection(title: L("Shortcuts & About")) {
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    shortcutRow(L("New note"), "⌘N")
                    shortcutRow(L("New chat"), "⌘⇧O")
                    shortcutRow(L("Switch Notes / Assistant"), "⌘1  ⌘2")
                    shortcutRow(L("Assistant panel next to note"), "⌘⇧J")
                    shortcutRow(L("Command Palette"), "⌘K")
                    shortcutRow(L("Hide / show sidebar"), "⌃⌘S")
                    shortcutRow(L("Undo delete"), "⌘Z")
                    infoRow(L("Data"), "~/Library/Application Support/NoteStudio")
                    infoRow("MCP server", L("notestudio-mcp — lets external AI clients read and write notes"), last: true)
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
                    .help(isActive ? L("Active") : L("Use this provider"))

                    TextField(L("Provider name"), text: $provider.name)
                        .textFieldStyle(.plain)
                        .font(Studio.Typo.body(.semibold))
                        .foregroundStyle(Studio.textPrimary)

                    if isActive {
                        Text(L("Active"))
                            .font(Studio.Typo.caption(.semibold))
                            .foregroundStyle(Studio.accentForeground)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(Studio.accent))
                    } else {
                        Button(L("Use"), action: onActivate)
                            .buttonStyle(SecondaryButtonStyle())
                            .controlSize(.small)
                    }

                    if canDelete {
                        IconButton(systemName: "trash", help: L("Delete provider (with API key)"), action: onDelete)
                    }
                }

                field("Base URL", text: $provider.baseURL, placeholder: LLMService.defaultBaseURL)
                field("Model", text: $provider.model, placeholder: LLMService.defaultModel)
                field(L("API key"), text: keyBinding, placeholder: L("sk-… (leave empty if not required)"), secure: true,
                      caption: L("Stored locally on this Mac, never synced."))

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
                            Text(L("Test connection"))
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
                    messages: [["role": "user", "content": L("ping — reply with exactly one word: ok")]],
                    temperature: 0,
                    provider: target
                )
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                testState = .ok(Lf("Connected · %d ms", ms))
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

// MARK: - Ô chọn ngôn ngữ: System / English / Tiếng Việt

private struct LanguageOption: View {
    let language: AppLanguage
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(language.label)
                    .font(Studio.Typo.callout(selected ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Studio.Radius.small)
                            .fill(selected ? Studio.selected : Studio.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Studio.Radius.small)
                            .stroke(selected ? Studio.textPrimary : Studio.hairline, lineWidth: selected ? 1.5 : 1)
                    )
            }
            .foregroundStyle(selected ? Studio.textPrimary : Studio.textSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
