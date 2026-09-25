import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tệp đính kèm trong chat: ảnh gửi thẳng cho model, tài liệu được trích chữ trên máy

struct ChatAttachment: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable { case image, document }

    var id = UUID()
    var name: String
    var kind: Kind
    var byteSize: Int
    /// Tên file lưu trong thư mục attachments
    var fileName: String
    var extractedText: String?
    var pageCount: Int?
    var truncated: Bool?

    var fileURL: URL { AttachmentStore.directory.appendingPathComponent(fileName) }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    var typeLabel: String {
        if kind == .image { return "Ảnh" }
        switch fileExtension {
        case "pdf": return "PDF"
        case "doc", "docx": return "Word"
        case "rtf", "rtfd": return "RTF"
        case "odt": return "ODT"
        case "md", "markdown": return "Markdown"
        case "csv", "tsv": return "Bảng"
        case "json": return "JSON"
        case "txt", "log", "": return "Văn bản"
        default:
            return AttachmentStore.codeExtensions.contains(fileExtension) ? "Mã nguồn" : fileExtension.uppercased()
        }
    }

    var detailLabel: String {
        if let pageCount, pageCount > 0 { return "\(typeLabel) · \(pageCount) trang" }
        return "\(typeLabel) · \(ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file))"
    }
}

enum AttachmentError: LocalizedError {
    case tooLarge(String)
    case unsupported(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let name):
            return "“\(name)” lớn hơn \(AttachmentStore.maxFileBytes / 1_048_576) MB"
        case .unsupported(let name):
            return "Chưa đọc được “\(name)” — hỗ trợ ảnh, PDF, Word, RTF, văn bản, CSV và mã nguồn"
        case .unreadable(let name):
            return "Không đọc được nội dung “\(name)”"
        }
    }
}

enum AttachmentStore {
    static let maxFileBytes = 25 * 1_048_576
    static let maxTextCharacters = 60_000
    static let maxImagePixels = 2048
    static let maxPerMessage = 10
    static let defaultPrompt = "Hãy phân tích (các) tệp đính kèm."

    static let directory: URL = {
        let dir = StudioPaths.dataDirectory.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "java", "kt", "go", "rs", "c", "h", "cpp", "hpp", "m", "mm",
        "rb", "php", "sh", "zsh", "sql", "css", "scss", "vue", "dart", "lua", "r", "scala"
    ]
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml", "log", "html", "htm", "toml", "ini", "env", "srt", "vtt"
    ]
    private static let richTextExtensions: Set<String> = ["doc", "docx", "rtf", "rtfd", "odt"]

    // MARK: Nhập tệp

    /// Chạy được ngoài main thread (trích PDF/Word có thể chậm).
    static func importFile(at url: URL) throws -> ChatAttachment {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true, ext != "rtfd" { throw AttachmentError.unsupported(name) }
        if let size = values?.fileSize, size > maxFileBytes { throw AttachmentError.tooLarge(name) }

        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .image) == true, !["pdf", "svg"].contains(ext) {
            guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unreadable(name) }
            return try importImage(data: data, name: name)
        }

        let text: String
        var pages: Int?
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw AttachmentError.unreadable(name) }
            pages = pdf.pageCount
            text = pdf.string ?? ""
        } else if richTextExtensions.contains(ext) {
            guard let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
                throw AttachmentError.unreadable(name)
            }
            text = attributed.string
        } else if textExtensions.contains(ext) || codeExtensions.contains(ext)
                    || type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
            text = try readPlainText(url, name: name)
        } else if let data = try? Data(contentsOf: url), looksLikeText(data), let decoded = String(data: data, encoding: .utf8) {
            text = decoded
        } else {
            throw AttachmentError.unsupported(name)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // PDF chỉ có ảnh scan không có lớp chữ
            throw ext == "pdf"
                ? AttachmentError.unreadable(name + " (PDF dạng ảnh scan — hãy chụp màn hình trang cần hỏi)")
                : AttachmentError.unreadable(name)
        }

        let id = UUID()
        let fileName = id.uuidString + (ext.isEmpty ? "" : "." + ext)
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(fileName))
        let isTruncated = trimmed.count > maxTextCharacters
        return ChatAttachment(
            id: id,
            name: name,
            kind: .document,
            byteSize: values?.fileSize ?? 0,
            fileName: fileName,
            extractedText: isTruncated ? String(trimmed.prefix(maxTextCharacters)) : trimmed,
            pageCount: pages,
            truncated: isTruncated ? true : nil
        )
    }

    /// Ảnh: xoay đúng chiều EXIF, thu nhỏ cạnh dài tối đa 2048px, lưu PNG (ảnh chụp màn hình) hoặc JPEG.
    static func importImage(data: Data, name: String) throws -> ChatAttachment {
        guard data.count <= maxFileBytes else { throw AttachmentError.tooLarge(name) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxImagePixels
              ] as CFDictionary) else {
            throw AttachmentError.unreadable(name)
        }

        let sourceIsPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        var encoded = encode(image, as: sourceIsPNG ? .png : .jpeg)
        if let png = encoded, png.count > 4 * 1_048_576, sourceIsPNG {
            encoded = encode(image, as: .jpeg)
        }
        guard let output = encoded else { throw AttachmentError.unreadable(name) }

        let isPNG = output.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let id = UUID()
        let fileName = id.uuidString + (isPNG ? ".png" : ".jpg")
        try output.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return ChatAttachment(id: id, name: name, kind: .image, byteSize: output.count, fileName: fileName)
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func readPlainText(_ url: URL, name: String) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        for fallback in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let text = try? String(contentsOf: url, encoding: fallback) { return text }
        }
        throw AttachmentError.unreadable(name)
    }

    private static func looksLikeText(_ data: Data) -> Bool {
        !data.prefix(4096).contains(0)
    }

    // MARK: Hiển thị

    private static let thumbnailCache = NSCache<NSString, NSImage>()

    static func thumbnail(for attachment: ChatAttachment, maxPixels: Int = 480) -> NSImage? {
        let key = "\(attachment.fileName)-\(maxPixels)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(attachment.fileURL as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    static func imageAspectRatio(for attachment: ChatAttachment) -> CGFloat {
        guard let image = thumbnail(for: attachment), image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    // MARK: Nội dung gửi cho model

    /// Nội dung tin nhắn user trong agent history. Ảnh chỉ lưu tham chiếu (image_ref) để chats.json
    /// không phình base64 — chỉ khi gửi mới thay bằng data URL (xem `expandForAPI`).
    static func userContent(text: String, attachments: [ChatAttachment]) -> Any {
        var full = text
        for doc in attachments where doc.kind == .document {
            let note = doc.truncated == true ? ", đã cắt bớt vì quá dài" : ""
            full += "\n\n[Tệp đính kèm: \(doc.name) — \(doc.detailLabel)\(note)]\n\(doc.extractedText ?? "")\n[Hết tệp \(doc.name)]"
        }
        let images = attachments.filter { $0.kind == .image }
        guard !images.isEmpty else { return full }
        var parts: [[String: Any]] = [["type": "text", "text": full]]
        for image in images {
            parts.append(["type": "image_ref", "file": image.fileName, "name": image.name])
        }
        return parts
    }

    static func expandForAPI(_ history: [[String: Any]]) -> [[String: Any]] {
        history.map { message in
            guard let parts = message["content"] as? [[String: Any]] else { return message }
            var expanded = message
            expanded["content"] = parts.map { part -> [String: Any] in
                guard part["type"] as? String == "image_ref", let file = part["file"] as? String else { return part }
                guard let url = dataURL(fileName: file) else {
                    return ["type": "text", "text": "[Ảnh \(part["name"] as? String ?? "") không còn trên máy]"]
                }
                return ["type": "image_url", "image_url": ["url": url]]
            }
            return expanded
        }
    }

    static func dataURL(fileName: String) -> String? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        let mime = fileName.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: Dọn file không còn tin nhắn nào tham chiếu (chạy khi mở app)

    static func garbageCollect(keeping fileNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !fileNames.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: Dán từ clipboard

    enum PastedContent {
        case files([URL])
        case image(Data)
    }

    /// Clipboard có tệp (copy trong Finder) hoặc ảnh (chụp màn hình, "Sao chép ảnh" từ trình duyệt)?
    /// Chữ thường thì trả nil để dán như văn bản.
    static func attachableContent(in pasteboard: NSPasteboard) -> PastedContent? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return nil }
        // Trình duyệt kèm URL của ảnh dưới dạng chữ — vẫn coi là ảnh; đoạn văn có khoảng trắng thì là chữ
        if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty, string.contains(where: { $0.isWhitespace }) || string.count > 2048 {
            return nil
        }
        return .image(data)
    }

    static func pastedImageName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm.ss"
        return "Ảnh dán \(formatter.string(from: Date())).png"
    }
}
