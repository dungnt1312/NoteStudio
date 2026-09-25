import SwiftUI
import AppKit

// MARK: - Composer (NSTextView) hỗ trợ chip mention inline + trigger @ /

enum CompletionTrigger: Equatable {
    case mention(query: String)
    case slash(query: String)
}

extension NSAttributedString.Key {
    static let noteID = NSAttributedString.Key("com.demo.notestudio.noteID")
    static let noteTitle = NSAttributedString.Key("com.demo.notestudio.noteTitle")
}

// MARK: - Vẽ chip "@tên" dưới dạng ảnh (đưa vào NSTextAttachment của text view)

enum ComposerChipRenderer {
    static func chipImage(title: String, isDark: Bool) -> NSImage {
        let text = "@" + title
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let padX: CGFloat = 8
        let height: CGFloat = 21
        let width = ceil(textSize.width) + padX * 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocusFlipped(true)
        let rect = NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        (isDark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.07)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        (text as NSString).draw(
            at: NSPoint(x: padX, y: (height - textSize.height) / 2),
            withAttributes: [
                .font: font,
                .foregroundColor: isDark ? NSColor(hex: 0xECECEC) : NSColor(hex: 0x333333)
            ]
        )
        image.unlockFocus()
        return image
    }
}

// MARK: - Text view của composer: placeholder vẽ ngay trong view, theo dõi chữ đang ghép (Telex/VNI)

final class ComposerTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    /// Bộ gõ đang ghép chữ (marked text) không bắn textDidChange — báo riêng để UI cập nhật
    var onMarkedTextChange: (() -> Void)?
    /// Dán ảnh / tệp: trả true nếu đã nhận làm tệp đính kèm (không dán như chữ)
    var onPasteAttachments: ((NSPasteboard) -> Bool)?
    /// Thả tệp vào ô nhập: chuyển lên khay đính kèm thay vì chèn đường dẫn
    var onDropFiles: (([URL]) -> Void)?

    override func paste(_ sender: Any?) {
        if onPasteAttachments?(NSPasteboard.general) == true { return }
        super.paste(sender)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff] + super.readablePasteboardTypes
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty, let onDropFiles {
            onDropFiles(urls)
            return true
        }
        if onPasteAttachments?(sender.draggingPasteboard) == true { return true }
        return super.performDragOperation(sender)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
        onMarkedTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
        onMarkedTextChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // string đã gồm cả chữ đang ghép, nên chỉ vẽ placeholder khi thật sự trống
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: ComposerCoordinator.font,
            .foregroundColor: NSColor.placeholderTextColor
        ])
    }
}

// MARK: - Coordinator (NSTextViewDelegate): trigger @ /, chèn chip, keyboard

final class ComposerCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: NSTextView?
    var onTextChange: ((String, CompletionTrigger?) -> Void)?
    var onMove: ((Int) -> Void)?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?
    var isDropdownOpen: (() -> Bool)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onPasteAttachments: ((NSPasteboard) -> Bool)?
    var onDropFiles: (([URL]) -> Void)?

    static let identifier = NSUserInterfaceItemIdentifier("studio.chat.composer")
    static let font = NSFont.systemFont(ofSize: 15)
    static let verticalInset: CGFloat = 6
    static let minHeight: CGFloat = 32
    static let maxHeight: CGFloat = 220
    private var lastReportedHeight: CGFloat = 0

    func makeScrollView() -> NSScrollView {
        let contentWidth: CGFloat = 700
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.addTextContainer(container)

        let textView = ComposerTextView(
            frame: NSRect(x: 0, y: 0, width: contentWidth, height: 40),
            textContainer: container
        )
        textView.delegate = self
        textView.onMarkedTextChange = { [weak self] in self?.notifyChange() }
        textView.onPasteAttachments = { [weak self] pasteboard in self?.onPasteAttachments?(pasteboard) ?? false }
        textView.onDropFiles = { [weak self] urls in self?.onDropFiles?(urls) }
        textView.identifier = ComposerCoordinator.identifier
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: ComposerCoordinator.verticalInset)
        textView.font = ComposerCoordinator.font
        textView.textColor = NSColor.labelColor

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 64))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        self.textView = textView

        // Text reflow khi đổi độ rộng cửa sổ → cập nhật chiều cao composer
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(textFrameDidChange),
            name: NSView.frameDidChangeNotification, object: textView
        )
        return scrollView
    }

    @objc private func textFrameDidChange(_ notification: Notification) {
        reportHeight()
    }

    /// Chiều cao nội dung (tự giãn từ 1 dòng tới maxHeight rồi mới cuộn)
    func reportHeight() {
        guard let textView, let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height
        let height = min(max(ceil(used) + ComposerCoordinator.verticalInset * 2, ComposerCoordinator.minHeight),
                         ComposerCoordinator.maxHeight)
        guard abs(height - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = height
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(height)
        }
    }

    /// Chèn ký tự kích hoạt (@ hoặc /) tại con trỏ — dùng cho menu "+"
    func insertTrigger(_ trigger: String) {
        guard let textView else { return }
        focus()
        var insertion = trigger
        let caret = textView.selectedRange().location
        if trigger == "/" {
            // lệnh / chỉ hoạt động ở đầu composer
            textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: NSAttributedString(
                string: "/", attributes: [.font: ComposerCoordinator.font, .foregroundColor: NSColor.labelColor]
            ))
            setSelectedRange(location: 1)
            notifyChange()
            return
        }
        if caret > 0 {
            let prev = (textView.string as NSString).character(at: caret - 1)
            if prev != 32 && prev != 10 { insertion = " " + trigger }
        }
        textView.insertText(insertion, replacementRange: textView.selectedRange())
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func clear() {
        guard let textView else { return }
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        notifyChange()
    }

    /// Đặt toàn bộ text (dùng cho Sửa tin nhắn) — không chip
    func setText(_ text: String) {
        guard let textView else { return }
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: ComposerCoordinator.font,
            .foregroundColor: NSColor.labelColor
        ]))
        setSelectedRange(location: (text as NSString).length)
        notifyChange()
    }

    func setSelectedRange(location: Int) {
        textView?.selectedRanges = [NSValue(range: NSRange(location: location, length: 0))]
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        notifyChange()
    }

    // ↑↓ / Enter / Esc điều khiển dropdown; Shift+Enter xuống dòng
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let dropdownOpen = isDropdownOpen?() ?? false
        let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if shiftHeld { return false }
            if dropdownOpen { onAccept?() } else { onSubmit?() }
            return true
        case #selector(NSResponder.moveUp(_:)):
            if dropdownOpen { onMove?(-1); return true }
            return false
        case #selector(NSResponder.moveDown(_:)):
            if dropdownOpen { onMove?(1); return true }
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    // MARK: Plain text / trigger detection

    func plainText() -> String {
        guard let storage = textView?.textStorage else { return "" }
        var out = ""
        storage.enumerateAttributes(
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { attrs, range, _ in
            if attrs[.noteID] != nil {
                let title = attrs[.noteTitle] as? String ?? "note"
                out += "@" + title
            } else {
                out += storage.attributedSubstring(from: range).string
            }
        }
        return out
    }

    func currentTrigger() -> CompletionTrigger? {
        guard let textView else { return nil }
        let caret = textView.selectedRange().location
        let ns = textView.string as NSString
        var start = caret
        while start > 0 {
            let ch = ns.character(at: start - 1)
            if ch == 32 || ch == 10 { break }
            start -= 1
        }
        guard caret > start else { return nil }
        let token = ns.substring(with: NSRange(location: start, length: caret - start))
        if token.hasPrefix("@") {
            return .mention(query: String(token.dropFirst()))
        }
        if start == 0, token.hasPrefix("/") {
            return .slash(query: String(token.dropFirst()))
        }
        return nil
    }

    func notifyChange() {
        onTextChange?(plainText(), currentTrigger())
        reportHeight()
    }

    // MARK: Chèn chip mention / áp dụng slash template

    func insertMention(_ note: Note) {
        guard let textView else { return }
        let caret = textView.selectedRange().location
        let ns = textView.string as NSString
        var start = caret
        while start > 0 {
            let ch = ns.character(at: start - 1)
            if ch == 32 || ch == 10 { break }
            start -= 1
        }
        let hasToken = start < caret && ns.character(at: start) == 64
        let range = hasToken ? NSRange(location: start, length: caret - start) : NSRange(location: caret, length: 0)
        insertChip(title: note.displayTitle, noteID: note.id, at: range)
    }

    private func insertChip(title: String, noteID: UUID, at range: NSRange) {
        guard let storage = textView?.textStorage else { return }
        let isDark = textView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let image = ComposerChipRenderer.chipImage(title: title, isDark: isDark)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -5, width: image.size.width, height: image.size.height)
        let content = NSMutableAttributedString(attachment: attachment)
        content.addAttributes([
            .noteID: noteID.uuidString,
            .noteTitle: title
        ], range: NSRange(location: 0, length: content.length))
        content.append(NSAttributedString(string: " ", attributes: [
            .font: ComposerCoordinator.font,
            .foregroundColor: NSColor.labelColor
        ]))
        storage.replaceCharacters(in: range, with: content)
        setSelectedRange(location: range.location + content.length)
        notifyChange()
    }

    func applySlashTemplate(_ template: String) {
        guard let textView else { return }
        let caret = textView.selectedRange().location
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: caret), with: template)
        setSelectedRange(location: (template as NSString).length)
        notifyChange()
    }

    func extractMentions() -> [MentionedNote] {
        guard let storage = textView?.textStorage else { return [] }
        var result: [MentionedNote] = []
        storage.enumerateAttributes(
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { attrs, _, _ in
            guard let idString = attrs[.noteID] as? String,
                  let id = UUID(uuidString: idString),
                  let title = attrs[.noteTitle] as? String else { return }
            guard !result.contains(where: { $0.id == id }) else { return }
            result.append(MentionedNote(id: id, title: title))
        }
        return result
    }
}

// MARK: - NSViewRepresentable

struct ChatComposer: NSViewRepresentable {
    let coordinator: ComposerCoordinator
    @Binding var text: String
    @Binding var mentions: [MentionedNote]
    let isDropdownOpen: () -> Bool
    let onTextChange: (String, CompletionTrigger?) -> Void
    let onMove: (Int) -> Void
    let onAccept: () -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var placeholder = ""
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onPasteAttachments: (NSPasteboard) -> Bool = { _ in false }
    var onDropFiles: ([URL]) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = coordinator.makeScrollView()
        bind(coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        bind(coordinator)
        (coordinator.textView as? ComposerTextView)?.placeholder = placeholder
        // Đang ghép chữ tiếng Việt thì tuyệt đối không ghi đè — sẽ xóa mất chữ đang gõ
        if coordinator.textView?.hasMarkedText() == true { return }
        // chỉ set text khi khác plain hiện tại (tránh phá chip khi SwiftUI render lại)
        let plain = coordinator.plainText()
        if plain != text {
            coordinator.textView?.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: [
                    .font: ComposerCoordinator.font,
                    .foregroundColor: NSColor.labelColor
                ])
            )
            coordinator.setSelectedRange(location: (text as NSString).length)
        }
    }

    private func bind(_ coordinator: ComposerCoordinator) {
        coordinator.onTextChange = { [weak coordinator] plain, trigger in
            guard let coordinator else { return }
            text = plain
            mentions = coordinator.extractMentions()
            onTextChange(plain, trigger)
        }
        coordinator.onMove = onMove
        coordinator.onAccept = onAccept
        coordinator.onCancel = onCancel
        coordinator.onSubmit = onSubmit
        coordinator.isDropdownOpen = isDropdownOpen
        coordinator.onHeightChange = onHeightChange
        coordinator.onPasteAttachments = onPasteAttachments
        coordinator.onDropFiles = onDropFiles
    }
}
