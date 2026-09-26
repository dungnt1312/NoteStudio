import Foundation
import SwiftUI

// MARK: - Đa ngôn ngữ EN/VI: L("English") → bản dịch tiếng Việt
//  Khóa là chuỗi tiếng Anh gốc trong UI; khi người dùng chọn tiếng Việt, L() tra bảng dưới đây.
//  Đổi ngôn ngữ ở Cài đặt → LocalizationManager phát thay đổi → app dựng lại toàn bộ cây view.

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, vietnamese

    var id: String { rawValue }

    /// Nhãn hiển thị: tên tiếng bản thân, "System" dịch theo ngôn ngữ hiện tại
    var label: String {
        switch self {
        case .system: return L("System")
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }
}

enum ResolvedLanguage {
    case english, vietnamese
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    static let storageKey = "appLanguage"

    @Published private(set) var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var resolved: ResolvedLanguage {
        Self.resolve(language)
    }

    func set(_ newLanguage: AppLanguage) {
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.storageKey)
    }

    static func resolve(_ language: AppLanguage) -> ResolvedLanguage {
        switch language {
        case .vietnamese: return .vietnamese
        case .english: return .english
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english
        }
    }

    // MARK: Bảng dịch Anh → Việt

    static let vietnamese: [String: String] = [
        // Chung
        "Close": "Đóng",
        "Cancel": "Hủy",
        "Save": "Lưu",
        "Delete": "Xóa",
        "Open": "Mở",
        "Undo": "Hoàn tác",
        "Untitled": "Không có tiêu đề",
        "Options": "Tùy chọn",
        "Settings": "Cài đặt",
        "Settings…": "Cài đặt…",
        "System": "Theo hệ thống",
        "Light": "Sáng",
        "Dark": "Tối",
        "Language": "Ngôn ngữ",
        "Notes": "Ghi chú",
        "Note": "Ghi chú",
        "Assistant": "Trợ lý",
        "AI Assistant": "Trợ lý AI",
        "New note": "Ghi chú mới",
        "New chat": "Hội thoại mới",
        "Yesterday": "Hôm qua",
        "Today": "Hôm nay",
        "Pinned": "Đã ghim",
        "Thinking…": "Đang suy nghĩ…",

        // Menu bar app
        "NoteStudio — Quick Capture": "NoteStudio — ghi nhanh",
        "Quick capture to NoteStudio": "Ghi nhanh vào NoteStudio",
        "Type an idea, Enter to save…": "Gõ ý tưởng, Enter để lưu…",
        "Enter saves · Esc closes · First line is the title": "Enter lưu · Esc đóng · Dòng đầu là tiêu đề",

        // Menu bar app menu
        "New Chat": "Hội thoại mới",
        "Hide Sidebar": "Ẩn thanh bên",
        "Show Sidebar": "Hiện thanh bên",
        "Hide Assistant Panel": "Ẩn trợ lý bên cạnh ghi chú",
        "Open Assistant Panel": "Mở trợ lý bên cạnh ghi chú",
        "Tools": "Công cụ",
        "Command Palette": "Bảng lệnh",
        "Appearance": "Giao diện",

        // Sidebar
        "Hide Sidebar (⌃⌘S)": "Ẩn thanh bên (⌃⌘S)",
        "Show Sidebar (⌃⌘S)": "Hiện thanh bên (⌃⌘S)",
        "New Chat (⌘⇧O)": "Hội thoại mới (⌘⇧O)",
        "New Note (⌘N)": "Ghi chú mới (⌘N)",
        "Notes (⌘1)": "Ghi chú (⌘1)",
        "AI Assistant (⌘2)": "Trợ lý AI (⌘2)",
        "Search notes": "Tìm ghi chú",
        "Unpin": "Bỏ ghim",
        "Pin to Top": "Ghim lên đầu",
        "Pin to top of list": "Ghim lên đầu danh sách",
        "Ask AI about this note": "Hỏi trợ lý về ghi chú này",
        "Delete Note": "Xóa ghi chú",
        "No notes yet": "Chưa có ghi chú nào",
        "No notes found": "Không tìm thấy ghi chú",
        "Clear Filter": "Xóa bộ lọc",
        "No content yet": "Chưa có nội dung",
        "Rename": "Đổi tên",
        "Delete Chat": "Xóa hội thoại",
        "Rename Chat": "Đổi tên hội thoại",
        "Delete chat “%@”?": "Xóa hội thoại “%@”?",
        "Chat name": "Tên hội thoại",
        "All messages in this chat will be deleted. Notes are not affected.":
            "Toàn bộ tin nhắn trong hội thoại này sẽ bị xóa. Ghi chú không bị ảnh hưởng.",

        // Editor
        "Live editing": "Soạn trực quan",
        "Markdown source": "Mã nguồn Markdown",
        "Preview (read-only)": "Xem trước (chỉ đọc)",
        "Unpin (⌘)": "Bỏ ghim",
        "Hide Assistant (⌘⇧J)": "Ẩn trợ lý (⌘⇧J)",
        "Open Assistant Panel (⌘⇧J)": "Mở trợ lý bên cạnh ghi chú (⌘⇧J)",
        "More actions": "Thêm thao tác",
        "Copy Markdown": "Sao chép Markdown",
        "Export as .md…": "Xuất file .md…",
        "Export as PDF…": "Xuất ra PDF…",
        "Suggest Title with AI": "AI gợi ý tiêu đề",
        "Preview mode — click ✎ to edit": "Chế độ xem trước — bấm ✎ để sửa",
        "Plain paragraph (⌥⌘0)": "Đoạn văn thường (⌥⌘0)",
        "Heading 1 (⌥⌘1)": "Tiêu đề 1 (⌥⌘1)",
        "Heading 2 (⌥⌘2)": "Tiêu đề 2 (⌥⌘2)",
        "Heading 3 (⌥⌘3)": "Tiêu đề 3 (⌥⌘3)",
        "Bold (⌘B)": "Đậm (⌘B)",
        "Italic (⌘I)": "Nghiêng (⌘I)",
        "Strikethrough (⌘⇧X)": "Gạch ngang (⌘⇧X)",
        "Bulleted list": "Danh sách",
        "Numbered list": "Danh sách số",
        "Checklist (⌘⇧↩ to tick)": "Việc cần làm (⌘⇧↩ tick/bỏ tick)",
        "Quote": "Trích dẫn",
        "Link": "Liên kết",
        "Inline code (⌘E)": "Mã inline (⌘E)",
        "Code block": "Khối mã",
        "Table": "Bảng",
        "Horizontal rule": "Đường kẻ ngang",
        "Insert": "Chèn thêm",
        "⌘F to search inside the note": "⌘F tìm trong ghi chú",
        "AI is naming the note…": "AI đang đặt tiêu đề…",
        "0 words": "0 từ",
        "%d words": "%d từ",
        "%1$d words · %2$d min read": "%1$d từ · %2$d phút đọc",
        "· Saved %@": "· Đã lưu %@",
        "Explain": "Giải thích",
        "Translate to English": "Dịch sang Anh",
        "Shorten": "Rút gọn",
        "Critique": "Phản biện",
        "tag name": "tên thẻ",
        "Add tag": "Thêm thẻ",
        "Suggesting…": "Đang gợi ý…",
        "Suggest tags": "Gợi ý thẻ",
        "Let AI suggest tags from the content": "Nhờ AI gợi ý thẻ từ nội dung",
        "Remove tag": "Bỏ thẻ",
        "Select a note to get started": "Chọn một ghi chú để bắt đầu",
        "Notes are saved automatically, right on your Mac.": "Ghi chú được lưu tự động ngay trên máy của bạn.",
        "Empty note": "Ghi chú trống",

        // Quick AI prompts (gửi model + hiện trong bubble)
        "Explain the following paragraph in detail, in plain language":
            "Giải thích chi tiết, dễ hiểu đoạn văn sau",
        "Translate the following paragraph into English": "Dịch đoạn văn sau sang tiếng Anh",
        "Shorten the following paragraph while keeping the key points":
            "Rút gọn đoạn văn sau nhưng giữ đủ ý chính",
        "Critique the following paragraph and suggest improvements":
            "Phản biện và góp ý cải thiện đoạn văn sau",
        "%@ (selected text in @%@)": "%@ (đoạn đang chọn trong @%@)",
        "%1$@:\n\n“%2$@”\n\n(The above is an excerpt from note @%3$@.)":
            "%1$@:\n\n“%2$@”\n\n(Đoạn trên trích từ ghi chú @%3$@.)",
        "Note Markdown copied": "Đã sao chép Markdown của ghi chú",

        // Settings
        "Appearance: %@": "Giao diện: %@",
        "Delete provider “%@”?": "Xóa provider “%@”?",
        "Delete provider and API key": "Xóa provider và API key",
        "The stored API key for this provider will also be removed from this Mac.":
            "API key đã lưu cho provider này cũng sẽ bị xóa khỏi máy.",
        "AI Providers": "Nhà cung cấp AI",
        "Any OpenAI-compatible service: OpenAI, OpenRouter, Groq, local Ollama, vLLM…":
            "Mọi dịch vụ theo chuẩn OpenAI: OpenAI, OpenRouter, Groq, Ollama chạy local, vLLM…",
        "New provider": "Provider mới",
        "Add provider": "Thêm provider",
        "Sync": "Đồng bộ",
        "Back up via iCloud Drive": "Sao lưu qua iCloud Drive",
        "On every save, notes are mirrored to iCloud Drive/NoteStudio. When opening the app, the most recent edit between this Mac and iCloud wins.":
            "Mỗi lần lưu, ghi chú được sao sang iCloud Drive/NoteStudio. Khi mở app, bản sửa gần nhất giữa máy này và iCloud sẽ được giữ.",
        "iCloud Drive was not found on this Mac.": "Không tìm thấy iCloud Drive trên máy này.",
        "Shortcuts & About": "Phím tắt & thông tin",
        "Switch Notes / Assistant": "Chuyển Ghi chú / Trợ lý",
        "Assistant panel next to note": "Trợ lý bên cạnh ghi chú",
        "Hide / show sidebar": "Ẩn / hiện thanh bên",
        "Undo delete": "Hoàn tác xóa",
        "Data": "Dữ liệu",
        "notestudio-mcp — lets external AI clients read and write notes":
            "notestudio-mcp — cho AI client bên ngoài đọc/ghi ghi chú",
        "Active": "Đang dùng",
        "Use this provider": "Dùng provider này",
        "Use": "Dùng",
        "Delete provider (with API key)": "Xóa provider (kèm API key)",
        "Provider name": "Tên provider",
        "sk-… (leave empty if not required)": "sk-… (để trống nếu không cần)",
        "Stored locally on this Mac, never synced.": "Lưu cục bộ trên máy, không đồng bộ đi đâu.",
        "Test connection": "Kiểm tra kết nối",
        "Connected · %d ms": "Kết nối được · %d ms",
        "ping — reply with exactly one word: ok": "ping — trả lời đúng một chữ: ok",

        // Chat panel
        "New chat (⌘⇧O)": "Hội thoại mới (⌘⇧O)",
        "Open full screen (⌘2)": "Mở toàn màn hình (⌘2)",
        "Close Assistant (⌘⇧J)": "Đóng trợ lý (⌘⇧J)",
        "Chat options": "Tùy chọn hội thoại",
        "Rename…": "Đổi tên…",
        "Delete chat…": "Xóa hội thoại…",
        "What can I help you with today?": "Hôm nay mình giúp gì cho bạn?",
        "Ask about “%@”?": "Hỏi gì về “%@”?",
        "Ask the assistant anything": "Hỏi trợ lý bất cứ điều gì",
        "Summarize": "Tóm tắt",
        "Summarize the open note into key points": "Tóm tắt ghi chú đang mở thành các ý chính",
        "To-dos": "Việc cần làm",
        "Extract a to-do list from the open note": "Rút ra danh sách việc cần làm từ ghi chú đang mở",
        "Rewrite": "Viết lại",
        "Rewrite the open note to be shorter and clearer": "Viết lại ghi chú đang mở cho gọn và rõ ràng hơn",
        "Search & summarize": "Tìm & tóm tắt",
        "Research my notes about Q4 and summarize": "Research các ghi chú về Q4 rồi tóm tắt",
        "Brainstorm": "Brainstorm",
        "Brainstorm 5 content ideas, building on my earlier ideas":
            "Brainstorm 5 ý tưởng nội dung, đối chiếu với ý tưởng cũ",
        "Plan": "Lên kế hoạch",
        "Create a to-do note for this week": "Tạo ghi chú việc cần làm tuần này",
        "Stats": "Thống kê",
        "Give me stats about my notes by tag": "Thống kê kho ghi chú của mình theo thẻ",
        "AI can make mistakes. Check important info.": "AI có thể mắc lỗi. Hãy kiểm tra các thông tin quan trọng.",
        "Ask about this note…": "Hỏi về ghi chú này…",
        "Ask anything": "Hỏi bất kỳ điều gì",
        "Ask about the attachments… (leave empty to analyze)": "Hỏi về tệp đính kèm… (để trống = phân tích)",
        "Mention a note (@)": "Nhắc đến ghi chú (@)",
        "Attach files, mention notes, quick commands…": "Đính kèm tệp, nhắc đến ghi chú, lệnh nhanh…",
        "Attach images or files…": "Đính kèm ảnh hoặc tệp…",
        "Images, PDF, Word, text · or drag & drop / ⌘V": "Ảnh, PDF, Word, văn bản · hoặc kéo thả / ⌘V",
        "Mention a note": "Nhắc đến ghi chú",
        "Bring the note's content into context": "Đưa nội dung note vào ngữ cảnh",
        "Quick commands": "Lệnh nhanh",
        "Stop generating": "Dừng phản hồi",
        "Send (Enter) · Shift+Enter for a new line": "Gửi (Enter) · Shift+Enter để xuống dòng",
        "Attach": "Đính kèm",
        "Choose images or documents to ask the assistant": "Chọn ảnh hoặc tài liệu để hỏi trợ lý",
        "Up to %d files per message": "Tối đa %d tệp mỗi tin nhắn",
        "Only %d more file(s) can be attached": "Chỉ đính kèm thêm được %d tệp",
        "Copy": "Sao chép",
        "Edit message": "Sửa tin nhắn",
        "Retry": "Gửi lại",
        "Append to “%@”": "Chèn vào cuối “%@”",
        "Appended to “%@”": "Đã chèn vào “%@”",
        "Save reply as a new note": "Lưu câu trả lời thành ghi chú mới",
        "Regenerate reply": "Tạo lại câu trả lời",
        "Analysis of %@": "Phân tích %@",
        "Analysis of %d files": "Phân tích %d tệp",
        "Sources: ": "Nguồn: ",
        "Saved “%@”": "Đã lưu “%@”",
        "See what the AI did": "Xem các bước AI đã làm",
        "Used %d tools · suggested deleting %d notes": "Đã dùng %d công cụ · đề nghị xóa %d ghi chú",
        "Used %d tools · %@": "Đã dùng %d công cụ · %@",
        "detail": "chi tiết",
        "Deleted “%@”": "Đã xóa “%@”",
        "Kept “%@”": "Đã giữ lại “%@”",
        "Suggested deleting “%@”": "Đề nghị xóa “%@”",
        "note": "ghi chú",
        "Undo with ⌘Z": "Có thể hoàn tác bằng ⌘Z",
        "Keep all": "Giữ lại tất cả",
        "Delete 1 note": "Xóa 1 ghi chú",
        "Delete %d notes": "Xóa %d ghi chú",
        "AI wants to delete 1 note": "AI muốn xóa 1 ghi chú",
        "AI wants to delete %d notes": "AI muốn xóa %d ghi chú",
        "Attach the content of the open note": "Đính kèm nội dung ghi chú đang mở",
        "Remove this note": "Bỏ ghi chú này",
        "Switch AI provider / model": "Đổi AI provider / model",
        "Provider": "Provider",
        "Manage providers…": "Quản lý provider…",
        "Remove this file": "Bỏ tệp này",
        "Reading file…": "Đang đọc tệp…",
        "Double-click to open %@": "Nhấp đúp để mở %@",
        "Double-click to view the full image": "Nhấp đúp để xem ảnh đầy đủ",
        "Drop files here": "Thả tệp vào đây",
        "Images, PDF, Word, text — the assistant will analyze them for you":
            "Ảnh, PDF, Word, văn bản — trợ lý sẽ phân tích giúp bạn",

        // Slash commands (chat + editor)
        "summarize": "tóm-tắt",
        "Summarize the selected note": "Tóm tắt ghi chú đang chọn",
        "Summarize the selected note into concise key points.":
            "Tóm tắt ghi chú đang chọn thành các ý chính ngắn gọn.",
        "translate": "dịch",
        "Translate text into English": "Dịch văn bản sang tiếng Anh",
        "Translate the following text into English:\n\n": "Dịch đoạn văn sau sang tiếng Anh:\n\n",
        "continue": "viết-tiếp",
        "Continue writing": "Viết tiếp văn bản",
        "Continue the following text naturally:\n\n": "Viết tiếp nội dung sau một cách tự nhiên:\n\n",
        "checklist": "checklist",
        "Convert to a markdown checklist": "Chuyển thành checklist markdown",
        "Convert the following content into a markdown checklist (- [ ] items):\n\n":
            "Chuyển nội dung sau thành checklist markdown (dạng - [ ]):\n\n",
        "brainstorm": "brainstorm",
        "Brainstorm ideas": "Brainstorm ý tưởng",
        "Brainstorm 5 ideas about: ": "Brainstorm 5 ý tưởng về: ",

        // Command palette
        "Go to Notes": "Đi tới Ghi chú",
        "Go to AI Assistant": "Đi tới Trợ lý AI",
        "Export current note as PDF": "Xuất ghi chú hiện tại ra PDF",
        "Commands": "Lệnh",
        "Recent notes": "Ghi chú gần đây",
        "Chats": "Hội thoại",
        "Search commands, notes, chats…": "Tìm lệnh, ghi chú, hội thoại…",
        "No results for “%@”": "Không có kết quả cho “%@”",
        "navigate": "di chuyển",
        "select": "chọn",

        // Thời gian
        "Last 7 days": "7 ngày qua",
        "Last 30 days": "30 ngày qua",
        "Older": "Cũ hơn",

        // Toast / hành động store
        "Deleted “%@” (toast)": "Đã xóa “%@”",
        "Deleted %d notes": "Đã xóa %d ghi chú",
        "Note restored": "Đã khôi phục ghi chú",
        "Restored %d notes": "Đã khôi phục %d ghi chú",

        // Attachments
        "Image": "Ảnh",
        "Sheet": "Bảng",
        "Text": "Văn bản",
        "Source code": "Mã nguồn",
        "%@ · %d pages": "%@ · %d trang",
        "“%@” is larger than %d MB": "“%@” lớn hơn %d MB",
        "Couldn't read “%@” — supported: images, PDF, Word, RTF, text, CSV and source code":
            "Chưa đọc được “%@” — hỗ trợ ảnh, PDF, Word, RTF, văn bản, CSV và mã nguồn",
        "Couldn't read the content of “%@”": "Không đọc được nội dung “%@”",
        "Please analyze the attached file(s).": "Hãy phân tích (các) tệp đính kèm.",
        " (scanned-image PDF — screenshot the page you want to ask about)":
            " (PDF dạng ảnh scan — hãy chụp màn hình trang cần hỏi)",
        "truncated because too long": "đã cắt bớt vì quá dài",
        "[Attachment: %1$@ — %2$@%3$@]": "[Tệp đính kèm: %1$@ — %2$@%3$@]",
        "[End of file %@]": "[Hết tệp %@]",
        "[Image %@ is no longer on disk]": "[Ảnh %@ không còn trên máy]",
        "Pasted image %@": "Ảnh dán %@",

        // Export
        "Export Note as PDF": "Xuất ghi chú ra PDF",
        "Couldn't export PDF": "Không xuất được PDF",
        "Export Note as Markdown": "Xuất ghi chú ra Markdown",
        "Couldn't export the .md file": "Không xuất được file .md",
        "%1$@ · %2$d words · %3$d characters": "%1$@ · %2$d từ · %3$d ký tự",
        "Couldn't create the PDF consumer": "Không tạo được PDF consumer",
        "Couldn't create the PDF context": "Không tạo được PDF context",
        "%d words · %d characters": "%d từ · %d ký tự",

        // LLM errors
        "No response received from the provider": "Không nhận được phản hồi từ provider",
        "Unknown error": "Lỗi không xác định",
        "Couldn't decode the response body": "Không đọc được nội dung phản hồi",
        "Invalid Base URL: %@": "Base URL không hợp lệ: %@",
        "LLM provider error (%d): %@": "Lỗi LLM provider (%d): %@",
        "Model %1$@ can't read images. Pick a vision-capable model (e.g. gpt-4o, gpt-4o-mini, llava) in the model menu above. — %2$@":
            "Model %1$@ không đọc được ảnh. Hãy chọn model có vision (vd. gpt-4o, gpt-4o-mini, llava) ở menu model phía trên. — %2$@",

        // Editor slash menu + placeholder
        "Type to start writing · Type / to insert headings, lists, to-dos, code blocks…":
            "Enter để bắt đầu viết · Gõ / để chèn tiêu đề, danh sách, việc cần làm, khối mã…",
        "Heading 1": "Tiêu đề 1",
        "Heading 2": "Tiêu đề 2",
        "Heading 3": "Tiêu đề 3",
        // "Title" đã có ở trên
        "To-do": "Việc cần làm",
        "Divider": "Đường kẻ",
        "Today's date": "Ngày hôm nay",
        "Current time": "Giờ hiện tại",

        // Ghi chú mẫu (chạy lần đầu)
        "Welcome to NoteStudio ✨": "Chào mừng đến NoteStudio ✨",
        "Team Meeting — weekly agenda": "Họp nhóm Product — agenda tuần",
        "Q4 Ideas": "Ý tưởng cho Q4",
        "Reading list": "Danh sách sách đang đọc",
        "demo": "demo",
        "meeting": "họp",
        "product": "product",
        "ideas": "ý tưởng",
        "books": "sách",

        // Tool summaries + kết quả
        "List notes": "Liệt kê ghi chú",
        "Search “%@”": "Tìm kiếm “%@”",
        "Read note": "Đọc ghi chú",
        "Create note “%@”": "Tạo ghi chú “%@”",
        "Update note": "Cập nhật ghi chú",
        "Append to note": "Bổ sung vào ghi chú",
        "View active note": "Xem ghi chú đang chọn",
        "Note stats": "Thống kê kho ghi chú",
        "Suggest deleting a note": "Đề nghị xóa ghi chú",
        "Open note in app": "Mở ghi chú trong app",
        "Call %@": "Gọi %@",
        "No note found with the given id": "Không tìm thấy ghi chú với id đã cho",
        "Missing or invalid id": "Thiếu hoặc sai id",
        "The user has not selected any note in the app": "Người dùng chưa chọn ghi chú nào trong app",
        "Unknown tool: %@": "Tool không tồn tại: %@",
        "List all notes (id, title, tags, updated time).": "Liệt kê tất cả ghi chú (id, tiêu đề, thẻ, thời gian sửa).",
        "Search notes by keyword in title and content.": "Tìm ghi chú theo từ khóa trong tiêu đề và nội dung.",
        "Read the full content of a note by id.": "Đọc đầy đủ nội dung một ghi chú theo id.",
        "Append content to the END of an existing note (does not overwrite).":
            "Bổ sung nội dung vào CUỐI một ghi chú có sẵn (không ghi đè nội dung cũ).",
        "Get the note currently selected in the app (if any).": "Lấy ghi chú đang được chọn trong app (nếu có).",
        "Note stats: total count, pinned count, count per tag.":
            "Thống kê kho ghi chú: tổng số, số đã ghim, số lượng theo từng thẻ.",
        "Create a new note. The user will see it appear in the app right away.":
            "Tạo ghi chú mới. Người dùng sẽ thấy ghi chú này hiện ngay trong app.",
        "Update a note's title, content, pinned state or tags. Only pass the fields to change.":
            "Cập nhật tiêu đề, nội dung, ghim hoặc thẻ của một ghi chú. Chỉ truyền các trường cần thay đổi.",
        "Permanently delete a note. Only use when the user explicitly asks.":
            "Xóa vĩnh viễn một ghi chú. Chỉ dùng khi người dùng yêu cầu rõ ràng.",
        "Select and show a note in the app (switches to the notes screen).":
            "Chọn và hiển thị một ghi chú trong app (chuyển sang màn ghi chú để người dùng xem).",
        "Search keyword": "Từ khóa tìm kiếm",
        "UUID of the note": "UUID của ghi chú",
        "Content to append": "Nội dung cần bổ sung",
        "Title": "Tiêu đề",
        "Content": "Nội dung",
        "Pin to top (default false)": "Ghim lên đầu (mặc định false)",
        "Tags": "Các thẻ",
        "Not deleted. The UI shows a combined confirmation card below the reply — ask the user to confirm there.":
            "Chưa xóa. UI hiển thị thẻ xác nhận gộp bên dưới câu trả lời — mời người dùng xác nhận ở đó.",

        // Quick AI chèn
        "[Note @%@]": "[Ghi chú @%@]",
        "(AI returned no content)": "(AI không trả về nội dung)",
    ]
}

// MARK: - API tra cứu

/// Dịch chuỗi tiếng Anh sang tiếng Việt (khi ngôn ngữ đang chọn là tiếng Việt), giữ nguyên nếu không có bản dịch.
func L(_ key: String) -> String {
    guard LocalizationManager.resolvedLanguage == .vietnamese,
          let vi = LocalizationManager.vietnamese[key] else { return key }
    return vi
}

/// Dịch + định dạng kiểu String(format:). Khóa dùng %-placeholder, ví dụ Lf("Deleted %d notes", 3).
func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

// MARK: - Trạng thái dùng được từ mọi thread

extension LocalizationManager {
    /// Ngôn ngữ đã phân giải (theo hệ thống nếu chọn "System"). Không phụ thuộc MainActor.
    static var resolvedLanguage: ResolvedLanguage {
        if Thread.isMainThread {
            return shared.resolved
        }
        let raw = UserDefaults.standard.string(forKey: storageKey)
        let language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        return resolve(language)
    }
}
