import SwiftUI
import AppKit

// MARK: - Design tokens theo phong cách ChatGPT (light + dark)

enum Studio {
    static let locale = Locale(identifier: "vi_VN")

    /// Màu động: tự chọn biến thể theo appearance hiện tại (aqua / darkAqua).
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(NSColor.dynamic(light, dark))
    }

    // Nền
    static let background = dynamic(0xFFFFFF, 0x212121)        // vùng nội dung chính
    static let sidebarBackground = dynamic(0xF9F9F9, 0x181818) // sidebar
    static let hover = dynamic(0xEFEFEF, 0x2A2A2A)             // hover row
    static let selected = dynamic(0xE8E8E8, 0x303030)          // row đang chọn
    static let hairline = dynamic(0xE8E8E8, 0x363636)          // đường kẻ mảnh
    static let controlBackground = dynamic(0xFFFFFF, 0x2A2A2A) // ô input / card
    static let subtleFill = dynamic(0xF7F7F7, 0x262626)        // code block, thẻ phụ
    static let userBubble = dynamic(0xF4F4F4, 0x303030)        // bubble tin nhắn user

    // Chữ — secondary ≥ 4.5:1, tertiary ≥ 3:1 trên nền chính
    static let textPrimary = dynamic(0x0D0D0D, 0xECECEC)
    static let textSecondary = dynamic(0x5D5D5D, 0xB4B4B4)
    static let textTertiary = dynamic(0x8A8A8A, 0x8C8C8C)

    // Nút & trạng thái
    static let accent = dynamic(0x0D0D0D, 0xF3F3F3)            // nút chính (dark: trắng)
    static let accentForeground = dynamic(0xFFFFFF, 0x0D0D0D)
    static let accentHover = dynamic(0x333333, 0xD6D6D6)
    static let danger = dynamic(0xD7373F, 0xE5484D)
    static let dangerFill = dynamic(0xFDEEEE, 0x3A2224)
    static let dangerBorder = dynamic(0xF3CACA, 0x5A2F31)

    // Composer chat
    static let composerBackground = dynamic(0xFFFFFF, 0x303030)
    static let composerBorder = dynamic(0xE3E3E3, 0x3D3D3D)
    static let composerButtonHover = dynamic(0xF0F0F0, 0x424242)
    static let sendDisabled = dynamic(0xD7D7D7, 0x7A7A7A)
    static let sendDisabledForeground = dynamic(0xFFFFFF, 0x2F2F2F)
    static let popoverBackground = dynamic(0xFFFFFF, 0x353535)

    // Kích thước khung cửa sổ: header cao 52pt, 3 nút đèn giao thông căn giữa theo header
    static let headerHeight: CGFloat = 52
    static let trafficLightInset: CGFloat = 86
    static let sidebarWidth: CGFloat = 264
    static let assistantPanelWidth: CGFloat = 384

    /// Thang chữ duy nhất của app — không dùng cỡ chữ lẻ ngoài bảng này
    enum Typo {
        static func caption(_ weight: Font.Weight = .regular) -> Font { .system(size: 11, weight: weight) }
        static func footnote(_ weight: Font.Weight = .regular) -> Font { .system(size: 12, weight: weight) }
        static func callout(_ weight: Font.Weight = .regular) -> Font { .system(size: 13, weight: weight) }
        static func body(_ weight: Font.Weight = .regular) -> Font { .system(size: 15, weight: weight) }
        static func headline(_ weight: Font.Weight = .semibold) -> Font { .system(size: 17, weight: weight) }
        static func title(_ weight: Font.Weight = .semibold) -> Font { .system(size: 22, weight: weight) }
        static func largeTitle(_ weight: Font.Weight = .bold) -> Font { .system(size: 28, weight: weight) }
    }

    /// Ba mức bo góc: control nhỏ, card/popover, composer/bubble lớn
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 22
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    static let studioTextPrimary = NSColor.dynamic(0x0D0D0D, 0xECECEC)

    // Nền highlight cho mention @note inline trong bubble user
    static let mentionBackgroundNS = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor.white.withAlphaComponent(0.14)
                      : NSColor.black.withAlphaComponent(0.07)
    }
}

// MARK: - Giao diện Sáng / Tối / Theo hệ thống

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    static let storageKey = "appearanceMode"

    var label: String {
        switch self {
        case .system: return "Theo hệ thống"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    static var current: AppearanceMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey), let mode = AppearanceMode(rawValue: raw) {
                return mode
            }
            // bản cũ chỉ có công tắc dark mode
            return UserDefaults.standard.bool(forKey: "preferDarkMode") ? .dark : .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            apply(newValue)
        }
    }

    /// Đặt thẳng NSApp.appearance — preferredColorScheme(nil) không trả về theo hệ thống được trên macOS
    static func apply(_ mode: AppearanceMode = current) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Ngày giờ

extension Date {
    var studioRelative: String {
        formatted(.relative(presentation: .named).locale(Studio.locale))
    }
    var studioDateTime: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Studio.locale))
    }
    var studioDate: String {
        formatted(Date.FormatStyle(date: .long, time: .omitted).locale(Studio.locale))
    }

    /// Kiểu Apple Notes: hôm nay → giờ, hôm qua, trong tuần → thứ, còn lại → ngày/tháng
    var studioShort: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Studio.locale))
        }
        if calendar.isDateInYesterday(self) { return "Hôm qua" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: Date())).day,
           days < 7 {
            return formatted(Date.FormatStyle().weekday(.wide).locale(Studio.locale)).capitalized(with: Studio.locale)
        }
        return formatted(Date.FormatStyle().day(.twoDigits).month(.twoDigits).locale(Studio.locale))
    }
}

/// Nhóm theo thời gian cho danh sách ghi chú / hội thoại (kiểu ChatGPT)
enum TimeBucket: Int, CaseIterable {
    case today, yesterday, week, month, older

    var label: String {
        switch self {
        case .today: return "Hôm nay"
        case .yesterday: return "Hôm qua"
        case .week: return "7 ngày qua"
        case .month: return "30 ngày qua"
        case .older: return "Cũ hơn"
        }
    }

    static func of(_ date: Date) -> TimeBucket {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return .week }
        if days < 30 { return .month }
        return .older
    }

    static func group<T>(_ items: [T], by date: (T) -> Date) -> [(TimeBucket, [T])] {
        let grouped = Dictionary(grouping: items) { of(date($0)) }
        return allCases.compactMap { bucket in
            guard let list = grouped[bucket], !list.isEmpty else { return nil }
            return (bucket, list)
        }
    }
}

// MARK: - Khung cửa sổ: header 52pt, nút đèn giao thông căn giữa, kéo cửa sổ từ header

/// Gắn một NSToolbar rỗng để macOS đặt 3 nút đèn giao thông vào giữa dải 52pt trên cùng.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window, window.toolbar?.identifier != "studio.chrome" else { return }
        let toolbar = NSToolbar(identifier: "studio.chrome")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }
}

/// Vùng trống của header: kéo để di chuyển cửa sổ, nhấp đúp để phóng to như title bar thật.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Nút dùng chung

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Studio.Typo.callout(.semibold))
            .foregroundColor(Studio.accentForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Studio.accent)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Studio.Typo.callout(.medium))
            .foregroundColor(destructive ? Studio.danger : Studio.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Studio.controlBackground))
            .overlay(Capsule().stroke(destructive ? Studio.dangerBorder : Studio.hairline))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Nút icon vuông 30pt cho header
struct IconButton: View {
    let systemName: String
    var active = false
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(active ? Studio.textPrimary : Studio.textSecondary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Studio.Radius.small).fill((active || hovering) ? Studio.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Nút "⋯" mở menu, cùng kích thước với IconButton
struct IconMenu<Content: View>: View {
    var systemName = "ellipsis"
    var help = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(Studio.textSecondary)
        .frame(width: 32, height: 32)
        .fixedSize()
        .help(help)
    }
}

/// Phím tắt hiển thị dạng keycap nhỏ
struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Studio.Typo.caption(.medium))
            .foregroundStyle(Studio.textTertiary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(Studio.subtleFill))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Studio.hairline))
    }
}
