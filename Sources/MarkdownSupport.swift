import AppKit
import UniformTypeIdentifiers

// MARK: - Ảnh trong ghi chú: lưu ở <data>/images, Markdown tham chiếu bằng đường dẫn tương đối "images/…"

final class MarkdownImageStore {
    static let shared = MarkdownImageStore()
    static let didLoad = Notification.Name("studio.md.imageLoaded")
    static let folderName = "images"

    static var directory: URL {
        let dir = StudioPaths.dataDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var cache: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var loading: Set<String> = []

    /// src trong Markdown → URL thật (http(s), file://, đường dẫn tuyệt đối, ~/…, hoặc tương đối với thư mục dữ liệu)
    func resolve(_ src: String) -> URL? {
        let raw = src.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        let decoded = raw.removingPercentEncoding ?? raw
        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            return url
        }
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }
        return StudioPaths.dataDirectory.appendingPathComponent(decoded)
    }

    /// Ảnh đã sẵn sàng; ảnh mạng chưa tải thì bắt đầu tải và báo didLoad khi xong
    func image(for src: String) -> NSImage? {
        if let hit = cache[src] { return hit }
        guard !failed.contains(src), let url = resolve(src) else { return nil }
        if url.isFileURL {
            guard let image = NSImage(contentsOf: url), image.isValid else { failed.insert(src); return nil }
            cache[src] = image
            return image
        }
        guard !loading.contains(src) else { return nil }
        loading.insert(src)
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(src)
                if let image, image.isValid {
                    self.cache[src] = image
                    NotificationCenter.default.post(name: Self.didLoad, object: src)
                } else {
                    self.failed.insert(src)
                }
            }
        }.resume()
        return nil
    }

    /// Kích thước điểm ảnh thật → điểm hiển thị (ảnh Retina @2x không bị phóng to gấp đôi)
    static func naturalSize(_ image: NSImage) -> NSSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            let size = image.size
            if size.width > 0, size.height > 0 { return size }
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    // MARK: Nhập ảnh

    func save(data: Data, fileExtension: String) throws -> String {
        let ext = fileExtension.isEmpty ? "png" : fileExtension.lowercased()
        let name = UUID().uuidString.lowercased().prefix(12) + "." + ext
        try data.write(to: Self.directory.appendingPathComponent(String(name)), options: .atomic)
        return Self.folderName + "/" + name
    }

    func importFile(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return try save(data: data, fileExtension: url.pathExtension)
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    static func imageFileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(isImageFile)
    }

    static func hasImageData(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]) != nil
    }

    /// Ảnh trong pasteboard (file ảnh hoặc dữ liệu ảnh) → lưu lại, trả về đường dẫn Markdown
    func importImages(from pasteboard: NSPasteboard) -> [String] {
        let files = Self.imageFileURLs(in: pasteboard)
        if !files.isEmpty {
            return files.compactMap { try? importFile($0) }
        }
        if let data = pasteboard.data(forType: .png) {
            return [(try? save(data: data, fileExtension: "png"))].compactMap { $0 }
        }
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            return [(try? save(data: data, fileExtension: "jpg"))].compactMap { $0 }
        }
        if let data = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            return [(try? save(data: png, fileExtension: "png"))].compactMap { $0 }
        }
        return []
    }

    /// Ảnh cục bộ mà nội dung đang tham chiếu bằng đường dẫn tương đối — dùng khi xuất .md
    static func relativeImagePaths(in content: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "!\\[[^\\]\\n]*\\]\\(\\s*<?([^()\\s>]+)>?|<img[^>]*\\ssrc=\"([^\"]+)\"")
        let ns = content as NSString
        var result: [String] = []
        regex.enumerateMatches(in: content, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            guard r.location != NSNotFound else { return }
            let src = ns.substring(with: r)
            if URL(string: src)?.scheme == nil, !src.hasPrefix("/"), !src.hasPrefix("~"), !result.contains(src) {
                result.append(src)
            }
        }
        return result
    }
}

/// Ảnh đặt trên một dòng riêng: vẽ bởi layout manager
final class MarkdownImageRef: NSObject {
    let src: String
    let size: NSSize

    init(src: String, size: NSSize) {
        self.src = src
        self.size = size
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MarkdownImageRef else { return false }
        return other.src == src && other.size == size
    }

    override var hash: Int { src.hashValue }
}

// MARK: - Bảng GFM: tách ô, căn chỉnh, định dạng lại

enum TableAlign: Equatable {
    case none, left, center, right

    var delimiter: String {
        switch self {
        case .none: return "---"
        case .left: return ":---"
        case .center: return ":---:"
        case .right: return "---:"
        }
    }
}

struct MarkdownTable: Equatable {
    var rows: [[String]]          // hàng 0 = tiêu đề; không gồm hàng phân cách
    var aligns: [TableAlign]

    var columnCount: Int { aligns.count }

    static let delimiterRegex = try! NSRegularExpression(
        pattern: "^\\s*\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?\\s*$"
    )

    static func isDelimiterRow(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        return delimiterRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Vị trí (UTF-16) các dấu | phân cách ô: bỏ qua \| và | nằm trong `mã`
    static func pipePositions(_ line: String) -> [Int] {
        let ns = line as NSString
        var result: [Int] = []
        var i = 0
        var codeTicks = 0
        while i < ns.length {
            let ch = ns.character(at: i)
            if ch == 92 { i += 2; continue } // \
            if ch == 96 { // `
                var run = 0
                while i < ns.length, ns.character(at: i) == 96 { run += 1; i += 1 }
                if codeTicks == 0 { codeTicks = run } else if codeTicks == run { codeTicks = 0 }
                continue
            }
            if ch == 124, codeTicks == 0 { result.append(i) }
            i += 1
        }
        return result
    }

    /// Các đoạn giữa hai dấu | (vùng thô, chưa cắt khoảng trắng)
    static func cellSegments(_ line: String) -> [NSRange] {
        let ns = line as NSString
        let pipes = pipePositions(line)
        var cuts = [-1] + pipes + [ns.length]
        var segments: [NSRange] = []
        for i in 0..<(cuts.count - 1) {
            let start = cuts[i] + 1
            segments.append(NSRange(location: start, length: max(0, cuts[i + 1] - start)))
        }
        cuts.removeAll()
        // "| a | b |": đoạn trước | đầu và sau | cuối không phải ô
        if let first = pipes.first, ns.substring(to: first).trimmingCharacters(in: .whitespaces).isEmpty, segments.count > 1 {
            segments.removeFirst()
        }
        if let last = pipes.last, ns.substring(from: last + 1).trimmingCharacters(in: .whitespaces).isEmpty, segments.count > 1 {
            segments.removeLast()
        }
        return segments
    }

    static func cells(_ line: String) -> [String] {
        let ns = line as NSString
        return cellSegments(line).map { ns.substring(with: $0).trimmingCharacters(in: .whitespaces) }
    }

    static func parse(lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2, isDelimiterRow(lines[1]) else { return nil }
        let header = cells(lines[0])
        let aligns: [TableAlign] = cells(lines[1]).map { spec in
            let left = spec.hasPrefix(":"), right = spec.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            if left { return .left }
            return .none
        }
        let count = max(header.count, aligns.count)
        guard count > 0 else { return nil }
        func pad(_ row: [String]) -> [String] {
            row.count >= count ? Array(row.prefix(count)) : row + Array(repeating: "", count: count - row.count)
        }
        var rows = [pad(header)]
        for line in lines.dropFirst(2) { rows.append(pad(cells(line))) }
        let fullAligns = aligns.count >= count ? Array(aligns.prefix(count)) : aligns + Array(repeating: .none, count: count - aligns.count)
        return MarkdownTable(rows: rows, aligns: fullAligns)
    }

    /// Các dòng Markdown đã căn thẳng cột
    func formattedLines() -> [String] {
        var widths = Array(repeating: 3, count: columnCount)
        for row in rows {
            for (c, cell) in row.enumerated() where c < columnCount { widths[c] = max(widths[c], cell.count) }
        }
        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { c, cell in
                let padding = String(repeating: " ", count: max(0, widths[c] - cell.count))
                switch aligns[c] {
                case .right: return padding + cell
                case .center:
                    let left = padding.count / 2
                    return String(repeating: " ", count: left) + cell + String(repeating: " ", count: padding.count - left)
                default: return cell + padding
                }
            }.joined(separator: " | ") + " |"
        }
        var result = [line(rows[0])]
        result.append("| " + aligns.enumerated().map { c, align in
            let spec = align.delimiter
            let dashes = max(0, widths[c] - spec.count)
            switch align {
            case .none: return String(repeating: "-", count: widths[c])
            case .left: return ":" + String(repeating: "-", count: widths[c] - 1)
            case .right: return String(repeating: "-", count: widths[c] - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: max(1, dashes + 1)) + ":"
            }
        }.joined(separator: " | ") + " |")
        for row in rows.dropFirst() { result.append(line(row)) }
        return result
    }

    /// Vị trí nội dung ô (hàng r theo mô hình, cột c) trong các dòng formattedLines(), tương đối với đầu bảng
    func cellRange(row r: Int, column c: Int, in lines: [String]) -> NSRange {
        let lineIndex = r == 0 ? 0 : r + 1
        var offset = 0
        for i in 0..<lineIndex { offset += (lines[i] as NSString).length + 1 }
        let line = lines[lineIndex]
        let segments = MarkdownTable.cellSegments(line)
        guard c < segments.count else { return NSRange(location: offset + (line as NSString).length, length: 0) }
        let segment = segments[c]
        let text = (line as NSString).substring(with: segment)
        let lead = text.prefix(while: { $0 == " " }).utf16.count
        let content = text.trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            return NSRange(location: offset + segment.location + min(1, segment.length), length: 0)
        }
        return NSRange(location: offset + segment.location + lead, length: (content as NSString).length)
    }
}

/// Hình học một bảng đã dàn: mép các cột (tọa độ container) — layout manager dùng để kẻ lưới
final class MarkdownTableLayout: NSObject {
    let id: Int
    let edges: [CGFloat]

    init(id: Int, edges: [CGFloat]) {
        self.id = id
        self.edges = edges
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MarkdownTableLayout else { return false }
        return other.id == id && other.edges == edges
    }

    override var hash: Int { id }
}

// MARK: - Tô màu cú pháp trong khối mã (nhẹ, theo nhóm ngôn ngữ)

enum CodeHighlighter {
    enum Token { case keyword, string, comment, number, type }

    static func color(_ token: Token) -> NSColor {
        switch token {
        case .keyword: return .dynamic(0xCF222E, 0xFF7B72)
        case .string: return .dynamic(0x0A3069, 0xA5D6FF)
        case .comment: return .dynamic(0x6E7781, 0x8B949E)
        case .number: return .dynamic(0x0550AE, 0x79C0FF)
        case .type: return .dynamic(0x8250DF, 0xD2A8FF)
        }
    }

    private static let hashComment: Set<String> = ["python", "py", "ruby", "rb", "bash", "sh", "shell", "zsh", "yaml", "yml",
                                                     "toml", "r", "perl", "makefile", "dockerfile", "ini", "conf", "fish", "powershell", "ps1"]
    private static let dashComment: Set<String> = ["sql", "lua", "haskell", "hs", "mysql", "postgres", "postgresql", "sqlite"]
    private static let noHighlight: Set<String> = ["", "text", "plain", "plaintext", "txt", "md", "markdown", "math", "latex", "tex", "mermaid"]

    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "import", "class", "struct", "enum", "case", "switch",
        "break", "continue", "def", "from", "as", "in", "is", "not", "and", "or", "true", "false", "nil", "null", "None",
        "True", "False", "const", "function", "async", "await", "try", "catch", "throw", "throws", "new", "this", "self",
        "Self", "public", "private", "protected", "internal", "static", "final", "override", "extension", "protocol", "guard",
        "defer", "where", "interface", "type", "package", "fn", "impl", "pub", "mut", "use", "mod", "match", "yield",
        "lambda", "with", "pass", "raise", "except", "finally", "elif", "do", "end", "then", "fi", "echo", "export", "void",
        "int", "string", "bool", "float", "double", "char", "long", "go", "chan", "select", "default", "typeof",
        "instanceof", "extends", "implements", "super", "undefined", "of", "val", "when", "object", "init", "deinit",
        "inout", "some", "any", "module", "require", "include", "namespace", "using", "template", "typename", "auto",
        "unsafe", "loop", "trait", "dyn", "ref", "delete", "local", "elseif", "until", "begin", "rescue", "unless",
        "fun", "sealed", "data", "open", "lazy", "weak", "unowned", "mutating", "associatedtype", "operator", "subscript",
        "get", "set", "willSet", "didSet", "readonly", "declare", "abstract", "enum", "goto", "sizeof", "volatile",
        "unsigned", "signed", "short", "byte", "boolean", "del", "global", "nonlocal", "assert", "print"
    ]

    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "insert", "into", "update", "delete", "create", "table", "join", "left", "right", "inner",
        "outer", "on", "group", "by", "order", "limit", "and", "or", "not", "null", "as", "values", "set", "drop", "alter",
        "index", "primary", "key", "foreign", "references", "distinct", "having", "union", "all", "case", "when", "then",
        "else", "end", "is", "in", "like", "between", "exists", "asc", "desc", "count", "sum", "avg", "min", "max", "with",
        "default", "unique", "constraint", "view", "offset", "returning", "true", "false"
    ]

    private static let numberRegex = try! NSRegularExpression(pattern: "\\b(?:0x[0-9a-fA-F_]+|\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b")
    private static let wordRegex = try! NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`")
    private static let lineCommentSlash = try! NSRegularExpression(pattern: "//[^\\n]*")
    private static let blockComment = try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")
    private static let lineCommentHash = try! NSRegularExpression(pattern: "(?<![\\w$\"'])#(?![{!\\[])[^\\n]*|^#[^\\n]*", options: [.anchorsMatchLines])
    private static let lineCommentDash = try! NSRegularExpression(pattern: "--[^\\n]*")
    private static let htmlComment = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->")
    private static let htmlTag = try! NSRegularExpression(pattern: "</?[A-Za-z][A-Za-z0-9-]*")

    /// Tô màu `range` (vị trí tuyệt đối trong `out`) theo ngôn ngữ
    static func highlight(_ out: NSMutableAttributedString, range: NSRange, language: String) {
        let lang = language.lowercased().split(separator: " ").first.map(String.init) ?? ""
        guard !noHighlight.contains(lang), range.length > 0, range.length < 60_000 else { return }
        let text = (out.string as NSString).substring(with: range)
        let scope = NSRange(location: 0, length: (text as NSString).length)
        var consumed = IndexSet()

        func paint(_ r: NSRange, _ token: Token) {
            out.addAttribute(.foregroundColor, value: color(token), range: NSRange(location: range.location + r.location, length: r.length))
        }
        func claim(_ regex: NSRegularExpression, _ token: Token) {
            regex.enumerateMatches(in: text, range: scope) { m, _, _ in
                guard let r = m?.range, r.length > 0, !consumed.intersects(integersIn: r.location..<NSMaxRange(r)) else { return }
                consumed.insert(integersIn: r.location..<NSMaxRange(r))
                paint(r, token)
            }
        }

        if ["html", "xml", "svg", "vue", "xhtml"].contains(lang) {
            claim(htmlComment, .comment)
            claim(stringRegex, .string)
            claim(htmlTag, .keyword)
            return
        }
        let isJSON = lang == "json" || lang == "jsonc"
        if hashComment.contains(lang) {
            claim(stringRegex, .string)
            claim(lineCommentHash, .comment)
        } else if dashComment.contains(lang) {
            claim(lineCommentDash, .comment)
            claim(blockComment, .comment)
            claim(stringRegex, .string)
        } else {
            claim(blockComment, .comment)
            claim(lineCommentSlash, .comment)
            claim(stringRegex, .string)
        }
        claim(numberRegex, .number)
        let isSQL = dashComment.contains(lang) && lang != "lua" && lang != "haskell" && lang != "hs"
        wordRegex.enumerateMatches(in: text, range: scope) { m, _, _ in
            guard let r = m?.range, !consumed.intersects(integersIn: r.location..<NSMaxRange(r)) else { return }
            let word = (text as NSString).substring(with: r)
            if isJSON {
                if ["true", "false", "null"].contains(word) { paint(r, .keyword) }
            } else if isSQL ? sqlKeywords.contains(word.lowercased()) : keywords.contains(word) {
                paint(r, .keyword)
            } else if !isSQL, let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first),
                      word.count > 1, word != word.uppercased() {
                paint(r, .type)
            }
        }
    }
}
