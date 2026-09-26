import AppKit
import CoreText
import UniformTypeIdentifiers

// MARK: - Xuất ghi chú ra PDF (A4, nhiều trang nếu cần) — CoreText thuần

enum ExportService {
    static func exportPDF(note: Note) {
        let panel = NSSavePanel()
        panel.title = L("Export Note as PDF")
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName(note: note)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writePDF(note: note, to: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = L("Couldn't export PDF")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Ghi chú vốn là Markdown: xuất nguyên văn ra file .md
    static func exportMarkdown(note: Note) {
        let panel = NSSavePanel()
        panel.title = L("Export Note as Markdown")
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = String(fileName(note: note).dropLast(4)) + ".md"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = note.content.hasSuffix("\n") ? note.content : note.content + "\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = L("Couldn't export the .md file")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func fileName(note: Note) -> String {
        let base = note.displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? L("Untitled") + ".pdf" : base + ".pdf"
    }

    static func writePDF(note: Note, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 @72dpi
        let margin: CGFloat = 56
        let contentRect = CGRect(
            x: margin, y: margin,
            width: pageRect.width - margin * 2,
            height: pageRect.height - margin * 2
        )

        let flow = buildAttributedString(note: note)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ExportFailure(errorDescription: L("Couldn't create the PDF consumer"))
        }
        var mediaBox = pageRect
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportFailure(errorDescription: L("Couldn't create the PDF context"))
        }

        let framesetter = CTFramesetterCreateWithAttributedString(flow as CFAttributedString)
        let total = flow.length
        var location = 0

        while location < total {
            pdf.beginPDFPage(nil)
            let path = CGPath(rect: contentRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, pdf)
            let visible = CTFrameGetVisibleStringRange(frame)
            pdf.endPDFPage()

            let next = visible.location + visible.length
            if visible.length == 0 || next <= location { break } // chặn vòng lặp vô hạn
            location = next
        }
        pdf.closePDF()

        try data.write(to: url, options: .atomic)
    }

    // MARK: Bố cục nội dung PDF

    private static func buildAttributedString(note: Note) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let black = CGColor(gray: 0, alpha: 1)
        let darkGray = CGColor(gray: 0.13, alpha: 1)
        let midGray = CGColor(gray: 0.45, alpha: 1)

        result.append(NSAttributedString(string: note.displayTitle + "\n", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): boldFont(size: 21),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): black
        ]))
        result.append(NSAttributedString(
            string: Lf("%1$@ · %2$d words · %3$d characters", note.createdAt.studioDate, note.wordCount, note.content.count) + "\n\n",
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): systemFont(size: 10.5),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): midGray
            ]
        ))
        var body = note.content
        if let heading = Note.leadingHeading(in: body) {
            body.removeSubrange(heading.range)
            body = String(body.drop(while: { $0 == "\n" }))
        }
        result.append(NSAttributedString(string: body, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): systemFont(size: 12.5),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): darkGray,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(
                paragraphSpacing: 7, lineHeightMultiple: 1.25
            )
        ]))
        return result
    }

    private static func systemFont(size: CGFloat) -> CTFont {
        if let font = CTFontCreateUIFontForLanguage(.system, size, nil) {
            return font
        }
        return CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func boldFont(size: CGFloat) -> CTFont {
        let base = systemFont(size: size)
        let traits = CTFontSymbolicTraits.traitBold
        if let bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) {
            return bold
        }
        return base
    }

    private static func paragraphStyle(paragraphSpacing: CGFloat, lineHeightMultiple: CGFloat) -> CTParagraphStyle {
        var spacingValue = paragraphSpacing
        var multipleValue = lineHeightMultiple
        var settings: [CTParagraphStyleSetting] = []
        withUnsafeBytes(of: &spacingValue) { pointer in
            settings.append(CTParagraphStyleSetting(
                spec: .paragraphSpacing,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointer.baseAddress!
            ))
        }
        withUnsafeBytes(of: &multipleValue) { pointer in
            settings.append(CTParagraphStyleSetting(
                spec: .lineHeightMultiple,
                valueSize: MemoryLayout<CGFloat>.size,
                value: pointer.baseAddress!
            ))
        }
        return CTParagraphStyleCreate(settings, settings.count)
    }

    private struct ExportFailure: LocalizedError {
        let errorDescription: String?
    }
}
