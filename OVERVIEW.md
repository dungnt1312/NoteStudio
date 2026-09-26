# NoteStudio — Tổng quan chức năng & Design System

> Ứng dụng ghi chú macOS (SwiftUI + AppKit) theo phong cách ChatGPT: ghi chú Markdown-first, editor "live" kiểu Typora, trợ lý AI tích hợp có thể thao tác trực tiếp trên ghi chú, và MCP server để app ngoài (ZCode…) làm việc với dữ liệu.
>
> Build bằng `swiftc` qua `./build.sh` (không cần Xcode project). Target macOS 13+.

---

## 1. Chức năng chính

### 1.1. Ghi chú (`Note.swift`, `NoteFile.swift`, `NotesStore.swift`)

- **Model `Note`**: `id` (UUID), `content` (Markdown — nguồn sự thật), `createdAt`, `updatedAt`, `pinned`, `tags`. **Tiêu đề = dòng `# ` đầu tiên**, đồng bộ hai chiều giữa title ↔ content.
- **Lưu trên đĩa**: mỗi ghi chú một file `notes/<id>.md` trong `~/Library/Application Support/NoteStudio/` (ghi đè bằng env `NOTESTUDIO_DATA_DIR`), gồm frontmatter (id/createdAt/updatedAt/pinned/tags) + body Markdown. Tự migrate từ `notes.json` cũ; file `.md` ngoài không frontmatter vẫn đọc được (coi toàn bộ là nội dung).
- **Autosave** debounce ~0.6s cho đúng file bị đổi; flush khi thoát app. **File-watcher** trên thư mục `notes/` tự reload thay đổi từ ngoài (MCP, editor khác) — đồng bộ hai chiều real-time.
- **iCloud Drive** (tùy chọn trong Settings): mirror thư mục ghi chú, merge newest-wins khi mở app.
- **Tổ chức**: pin, tags (thủ công + AI gợi ý, lọc theo chip tag), không có thư mục. Tìm kiếm live (title + content). Sắp xếp pinned trước rồi `updatedAt` mới nhất; danh sách nhóm theo mốc thời gian (Pinned / Today / Yesterday / Last 7 days…).
- **Xóa** là xóa hẳn file (không có thùng rác) nhưng **undo được** qua toast "Hoàn tác" / ⌘Z.

### 1.2. Editor Markdown (`EditorView.swift`, `MarkdownEditor.swift`, `MarkdownView.swift`, `MarkdownSupport.swift`)

- **3 chế độ**: *live* (kiểu Typora), *source* (Markdown thô, mono), *preview* (chỉ đọc). Lưu lựa chọn vào UserDefaults.
- **Live mode**: Markdown thô nằm trong `NSTextStorage`; `MarkdownLayoutManager` ẩn marker (`**`, `##`…) trên các dòng không có con trỏ, vẽ checkbox, bullet, quote bar, nhãn ngôn ngữ code block. An toàn với **Tiếng Việt Telex/VNI** (xử lý marked-text). Enter tự tiếp danh sách, Tab/Shift-Tab thụt lề, click checkbox để tick, ⌘-click mở link, ⌘F tìm kiếm native, dán luôn là plain-text.
- **Menu slash** kiểu Notion (gõ `/`), **format bar**: ¶ H1 H2 H3 · B I S · danh sách / checklist · quote · link · code inline · menu chèn (code block, bảng, đường kẻ).
- **Phím tắt định dạng**: `⌘B` đậm · `⌘I` nghiêng · `⌘E` code inline · `⌘⇧X` gạch ngang · `⌥⌘0–3` cấp tiêu đề · `⌘⇧↩` tick/bỏ tick việc cần làm của dòng hiện tại.
- **Markdown render**: tiêu đề, danh sách, task list tương tác (tick ghi ngược vào file), quote, bảng GFM, code block có syntax highlight (keywords/strings/comments/numbers/types cho nhóm ngôn ngữ phổ biến), link, ảnh.
- **Ảnh**: dán/chèn vào được, lưu tại `<data>/images/`, tham chiếu tương đối; hỗ trợ thêm http(s)/file/đường dẫn tuyệt đối, load async có cache.
- **Quick AI**: bôi đen văn bản → capsule nổi với *Explain / Translate / Shorten / Critique* → gửi sang panel trợ lý kèm ghi chú được mention.

### 1.3. Sidebar & Command Palette

- **Sidebar** (`SidebarView.swift`): ô tìm kiếm, chip lọc tag, danh sách ghi chú (title + ngày + snippet + icon pin), menu chuột phải (Pin, Hỏi AI, Xóa); đổi workspace Notes/Assistant; nút Settings ở đáy.
- **Command Palette** (`CommandPaletteView.swift`, **⌘K**): lệnh tạo ghi chú/chat, chuyển khu, bật/tắt panel, export PDF, đổi Appearance… + tìm nhanh ghi chú và hội thoại.

### 1.4. Trợ lý AI (`ChatPanelView`, `ChatComposer`, `AssistantEngine`, `ChatAgent`, `LLMService`, `Attachments`)

- **Hai dạng dùng chung một engine**: chat toàn màn hình (section Assistant, ⌘2) và **panel bên phải editor** (⌘⇧J). Nhiều phiên hội thoại lưu `chats.json`, tự đặt tên, đổi tên, xóa.
- **Agent có tool loop**: trả lời phải thao tác trên ghi chú qua **10 tools** — `list_notes`, `search_notes`, `read_note`, `append_to_note`, `get_active_note`, `get_stats`, `create_note`, `update_note`, `delete_note` (gom vào **một thẻ xác nhận** có checkbox từng ghi chú), `select_note` (mở ghi chú trong app). Có nút Stop, tự retry khi rate-limit.
- **Streaming** token-by-token (SSE); trả lời render Markdown; các lần gọi tool liên tiếp gộp thành dòng "Used N tools ›" mở ra xem chi tiết; nút lưu câu trả lời thành ghi chú mới.
- **Composer**: `@` mention ghi chú (chèn chip, gửi kèm toàn bộ nội dung), slash command (`/summarize`, `/translate`, `/continue`, `/checklist`, `/brainstorm`), tự giãn chiều cao, an toàn IME.
- **Đính kèm** (`Attachments.swift`): kéo-thả / ⌘V / nút +; tối đa 10 file/tin, 25 MB/file. Ảnh gửi dạng `image_url` (data URL, tự xoay EXIF, thu về ≤2048px); PDF/Word/RTF/ODT/TXT/MD/CSV/JSON/code trích text cục bộ (≤60k ký tự).
- **Provider** (`LLMService.swift`): bất kỳ API tương thích OpenAI (`/chat/completions`) — mỗi provider gồm tên + Base URL + model. Có sẵn OpenAI và Ollama local. API key lưu `secrets.json` (chmod 600). Chọn provider/model ngay trên header chat; có "Test connection" trong Settings.

### 1.5. Export, Settings, Localization

- **Export** (`ExportService.swift`): PDF (tự render bằng CoreText, khổ A4, tự phân trang) và Markdown thô — từ menu ⋯ của editor.
- **Settings** (`SettingsView.swift`): Appearance (Sáng/Tối/Theo hệ thống, có preview), Ngôn ngữ (System/English/Tiếng Việt), quản lý AI Provider (thêm/sửa/xóa/kích hoạt/test), bật tắt iCloud Drive, bảng phím tắt + About.
- **Localization** (`Localization.swift`): hệ key tiếng Anh với `L()`/`Lf()`, từ điển Anh→Việt ~400 mục; đổi ngôn ngữ dựng lại toàn bộ cây view.

### 1.6. MCP server (`MCPServer/main.swift` → binary `notestudio-mcp`)

- Server **stdio JSON-RPC 2.0** viết bằng Swift thuần (không Node), chia sẻ `NoteFile.swift` nên đọc/ghi đúng thư mục `notes/` của app; app nhận thay đổi ngay nhờ file-watcher.
- **7 tools**: `list_notes`, `search_notes`, `read_note`, `open_note` (gọi URL scheme `notestudio://note/<id>`), `create_note`, `update_note`, `delete_note`.
- Đã đăng ký làm MCP server trong ZCode → app điều khiển được bằng lệnh `mcp__notestudio__*`.

### 1.7. Khác

- **Quick Capture** trên menu bar (MenuBarExtra dạng window): gõ 1 dòng, Enter lưu — dòng đầu là tiêu đề.
- **URL scheme** `notestudio://note/<uuid>` mở app và chọn ghi chú.
- **Toast** đáy cửa sổ kèm nút hành động (ví dụ Hoàn tác khi xóa), tự ẩn sau 5s.
- **Window chrome tự chế**: ẩn title bar, header cao 52pt kéo được, đèn giao thông căn giữa qua NSToolbar rỗng.

### 1.8. Bảng phím tắt chính

| Phím tắt | Hành động |
|---|---|
| ⌘N | Ghi chú mới |
| ⌘⇧O | Chat mới |
| ⌘1 / ⌘2 | Chuyển Notes / AI Assistant |
| ⌘⇧J | Bật/tắt panel trợ lý bên editor |
| ⌃⌘S | Ẩn/hiện sidebar |
| ⌘K | Command palette |
| ⌘, | Settings |
| ⌘Z (sau khi xóa) | Hoàn tác xóa |
| ⌘B / ⌘I / ⌘E / ⌘⇧X | Đậm / nghiêng / code inline / gạch ngang |
| ⌥⌘0–3 | Đặt cấp tiêu đề (0 = thường) |
| ⌘⇧↩ | Tick việc cần làm của dòng hiện tại |
| ⌘F | Tìm kiếm trong ghi chú |

---

## 2. Design System (`Theme.swift` — `enum Studio`)

Ngôn ngữ hình ảnh: **giống giao diện ChatGPT** — tối giản, đơn sắc, không màu thương hiệu (accent là đen/trắng, màu duy nhất xuất hiện là đỏ danger). Mọi token là **cặp light/dark** (`NSColor.dynamic`) tự đổi theo appearance, không cần if-else trong view.

### 2.1. Màu nền

| Token | Light | Dark | Dùng cho |
|---|---|---|---|
| `Studio.background` | `#FFFFFF` | `#212121` | Vùng nội dung chính |
| `Studio.sidebarBackground` | `#F9F9F9` | `#181818` | Sidebar |
| `Studio.hover` | `#EFEFEF` | `#2A2A2A` | Hover row |
| `Studio.selected` | `#E8E8E8` | `#303030` | Row đang chọn |
| `Studio.hairline` | `#E8E8E8` | `#363636` | Đường kẻ mảnh 1px |
| `Studio.controlBackground` | `#FFFFFF` | `#2A2A2A` | Ô input, card |
| `Studio.subtleFill` | `#F7F7F7` | `#262626` | Code block, thẻ phụ |
| `Studio.userBubble` | `#F4F4F4` | `#303030` | Bubble tin nhắn user |

### 2.2. Màu chữ

| Token | Light | Dark | Ghi chú |
|---|---|---|---|
| `Studio.textPrimary` | `#0D0D0D` | `#ECECEC` | Chữ chính |
| `Studio.textSecondary` | `#5D5D5D` | `#B4B4B4` | Contrast ≥ 4.5:1 trên nền chính |
| `Studio.textTertiary` | `#8A8A8A` | `#8C8C8C` | Contrast ≥ 3:1, dùng cho phụ đề/keycap |

### 2.3. Nút & trạng thái

| Token | Light | Dark | Dùng cho |
|---|---|---|---|
| `Studio.accent` | `#0D0D0D` | `#F3F3F3` | Nút chính (dark đảo thành trắng) |
| `Studio.accentForeground` | `#FFFFFF` | `#0D0D0D` | Chữ trên nút chính |
| `Studio.accentHover` | `#333333` | `#D6D6D6` | Hover nút chính |
| `Studio.danger` | `#D7373F` | `#E5484D` | Hành động phá hủy |
| `Studio.dangerFill` | `#FDEEEE` | `#3A2224` | Nền hộp thoại xác nhận xóa |
| `Studio.dangerBorder` | `#F3CACA` | `#5A2F31` | Viền hộp thoại xóa |

### 2.4. Composer chat

| Token | Light | Dark |
|---|---|---|
| `Studio.composerBackground` | `#FFFFFF` | `#303030` |
| `Studio.composerBorder` | `#E3E3E3` | `#3D3D3D` |
| `Studio.composerButtonHover` | `#F0F0F0` | `#424242` |
| `Studio.sendDisabled` | `#D7D7D7` | `#7A7A7A` |
| `Studio.sendDisabledForeground` | `#FFFFFF` | `#2F2F2F` |
| `Studio.popoverBackground` | `#FFFFFF` | `#353535` |

Ngoài ra `NSColor.mentionBackgroundNS` (đen 7% / trắng 14% alpha) làm nền highlight mention `@note` trong bubble user, và `NSColor.studioTextPrimary` cho side AppKit.

### 2.5. Typography — thang chữ duy nhất

App chỉ dùng cỡ chữ từ bảng này, **không dùng cỡ lẻ ngoài bảng**:

| Token | Size | Weight mặc định | Dùng cho |
|---|---|---|---|
| `Studio.Typo.caption` | 11 | regular | Nhãn nhỏ, keycap |
| `Studio.Typo.footnote` | 12 | regular | Chú thích phụ |
| `Studio.Typo.callout` | 13 | regular | Chữ UI, danh sách, nút |
| `Studio.Typo.body` | 15 | regular | Nội dung chính, tin nhắn |
| `Studio.Typo.headline` | 17 | semibold | Tiêu đề mục, tên section |
| `Studio.Typo.title` | 22 | semibold | Tiêu đề lớn |
| `Studio.Typo.largeTitle` | 28 | bold | Tiêu đề màn hình trống |

Mỗi token nhận tham số `weight` override khi cần: `Studio.Typo.callout(.semibold)`.

### 2.6. Bo góc

| Token | Giá trị | Dùng cho |
|---|---|---|
| `Studio.Radius.small` | 8 | Control nhỏ, icon button |
| `Studio.Radius.medium` | 12 | Card, popover |
| `Studio.Radius.large` | 22 | Composer, bubble lớn |

### 2.7. Kích thước layout

| Hằng số | Giá trị | Ý nghĩa |
|---|---|---|
| `Studio.headerHeight` | 52pt | Header tự chế cao 52pt (đèn giao thông căn giữa dải này) |
| `Studio.trafficLightInset` | 86pt | Chừa lề trái cho 3 nút đèn giao thông |
| `Studio.sidebarWidth` | 264pt | Độ rộng sidebar |
| `Studio.assistantPanelWidth` | 384pt | Độ rộng panel trợ lý bên editor |
| Cửa sổ mặc định | 1240×820 | Tối thiểu 880×600 |

### 2.8. Components dùng chung (`Theme.swift`)

- **`PillButtonStyle`** — nút chính hình capsule: `callout(.semibold)`, nền `accent`, chữ `accentForeground`, mờ 0.82 khi nhấn.
- **`SecondaryButtonStyle`** — nút phụ capsule viền `hairline`, nền `controlBackground`; biến thể `destructive` đổi sang đỏ.
- **`IconButton`** — nút icon vuông 32×32, radius 8, hover/active đổ nền `hover`, chữ `textSecondary` → `textPrimary`.
- **`IconMenu`** — nút "⋯" cùng cỡ IconButton, ẩn indicator menu.
- **`Keycap`** — hiển thị phím tắt dạng keycap nhỏ (radius 5, nền `subtleFill`, viền `hairline`).
- **`ToastView`** (`ContentView.swift`) — capsule nền `accent`, cao 40pt, chữ ngược, shadow mềm.
- **`TimeBucket`** — nhóm danh sách theo thời gian kiểu ChatGPT: Today / Yesterday / Last 7 days / Last 30 days / Older.
- **Định dạng ngày** (`Date` extension): `studioRelative` (relative), `studioDateTime`, `studioDate`, `studioShort` (kiểu Apple Notes: hôm nay → giờ, hôm qua, trong tuần → thứ, cũ hơn → dd/MM). Locale theo ngôn ngữ app (`Studio.locale`).
- **`WindowChromeConfigurator` / `WindowDragArea`** — dựng header 52pt: toolbar rỗng để macOS đặt đèn giao thông vào giữa, vùng trống kéo/đúp-click phóng to cửa sổ.
- **`AppearanceMode`** — Sáng/Tối/Theo hệ thống; áp thẳng `NSApp.appearance` (`.aqua` / `.darkAqua` / `nil`) vì `preferredColorScheme(nil)` không trả về theo hệ thống được trên macOS. Lưu UserDefaults `appearanceMode`.

### 2.9. Nguyên tắc khi thêm UI mới

1. **Chỉ lấy màu từ `Studio.*`** — không hardcode hex trong view; token nào thiếu thì thêm vào `Theme.swift` dạng cặp light/dark.
2. **Cỡ chữ chỉ từ `Studio.Typo`** — không dùng `.font(.system(size: …))` lẻ (ngoại lệ hiếm: icon 15pt trong `IconButton`).
3. **Bo góc chỉ từ `Studio.Radius`** (keycap là ngoại lệ cố ý với radius 5).
4. **Không dùng màu thương hiệu**: nút chính là đen/trắng; chỉ `danger` có màu. Trạng thái dùng nền xám (`hover`/`selected`) thay vì màu.
5. **Kẻ ngang = `hairline` 1px**, phân tách khu vực bằng nền khác nhau (sidebar vs background) thay vì viền đậm.
6. Bubble chat: user dùng `userBubble`, trả lời AI là **text full-width không bubble** — giữ đúng pattern ChatGPT.

---

## 3. Ghi chú kỹ thuật

- Thư mục dữ liệu: `~/Library/Application Support/NoteStudio/` chứa `notes/*.md`, `images/`, `attachments/`, `chats.json`, `secrets.json`. Env `NOTESTUDIO_DATA_DIR` trỏ chỗ khác (dùng cho test harness).
- Chạy thử offscreen (chụp ảnh kiểm thử, không giật focus): launch arg `-studioSection chat|settings`; script hỗ trợ trong `scripts/`.
- Source của thuộc tính `notes-are-markdown`, MCP và localization nằm ở các file đã nêu trên; thay đổi format frontmatter phải cập nhật đồng thời `NoteFile.swift` (app) và `MCPServer/main.swift` (server dùng bản copy riêng).
