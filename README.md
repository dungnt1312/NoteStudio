# NoteStudio — Demo app ghi chú cho macOS

Ứng dụng ghi chú mẫu viết bằng **Swift / SwiftUI**, giao diện lấy cảm hứng từ **OpenAI Studio / ChatGPT**:
nền sáng tối giản, đường kẻ hairline, sidebar + vùng nội dung, trợ lý AI mở ngay cạnh ghi chú.

## Chạy thử

```bash
open NoteStudio.app   # app đã build sẵn
./build.sh            # hoặc build lại từ source
```

Yêu cầu: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

## Tính năng

### Thiết kế lại v2.0 — bố cục kiểu ChatGPT

- **Một sidebar duy nhất** (bỏ rail dọc) — công tắc **Ghi chú / Trợ lý** ở đầu, **Cài đặt** ở đáy, thu gọn bằng ⌃⌘S.
  3 nút cửa sổ nằm cùng hàng header 52pt. Danh sách nhóm theo **Hôm nay / Hôm qua / 7 ngày qua…**, mỗi ghi chú
  có dòng trích nội dung thay cho thẻ; hàng chip thẻ mờ dần ở mép để báo còn cuộn được
- **Trợ lý ngay cạnh ghi chú** (⌘⇧J hoặc nút ✦ Trợ lý) — thay cho panel chi tiết; có chip đính kèm ghi chú đang mở,
  gợi ý Tóm tắt / Việc cần làm / Viết lại; bôi đen đoạn văn → hỏi AI không rời editor. Nút ⤢ mở toàn màn hình
- **Editor gọn** — cột chữ tối đa 720pt, **thẻ nằm ngay dưới tiêu đề** (thêm tay / AI gợi ý), header còn
  Xem trước · Ghim · ⋯ (Sao chép, Xuất PDF, AI gợi ý tiêu đề, thông tin, Xóa) · Trợ lý
- **Chat kiểu ChatGPT** — tin user là bong bóng xám, câu trả lời AI là chữ trơn full width; nút Sao chép / Sửa /
  Gửi lại / Chèn vào ghi chú chỉ hiện khi rê chuột. Các lần gọi tool gộp thành một dòng "Đã dùng N công cụ ›".
  Hội thoại trống: lời chào + composer ở giữa màn hình. Chọn provider/model ở header
- **Xóa an toàn** — xóa ghi chú hiện toast **"Đã xóa · Hoàn tác"** và hỗ trợ **⌘Z**. Khi AI muốn xóa, mọi đề nghị
  gom vào **một thẻ xác nhận** có tên từng ghi chú (bỏ chọn được từng cái)
- **Giao diện Sáng / Tối / Theo hệ thống** trong Cài đặt (và menu Công cụ → Giao diện)
- **Cài đặt** — nút **Kiểm tra kết nối** cho từng provider, hỏi xác nhận trước khi xóa provider, bảng phím tắt
- **⌘K** chia nhóm Lệnh / Ghi chú gần đây / Hội thoại, hiện phím tắt từng lệnh
- **Hệ thống thiết kế** — thang chữ 11/12/13/15/17/22/28, 3 mức bo góc, chữ phụ đạt tương phản ≥ 4.5:1

- **Đính kèm ảnh & tệp để hỏi trợ lý** 📎 — kéo thả vào khung chat, dán ⌘V (ảnh chụp màn hình, ảnh copy từ web,
  tệp copy trong Finder) hoặc nút **+ → Đính kèm ảnh hoặc tệp…** (tối đa 10 tệp/tin, 25 MB/tệp).
  Ảnh gửi thẳng cho model có vision (tự thu nhỏ còn cạnh dài 2048px); PDF, Word (.docx/.doc), RTF, ODT, TXT,
  Markdown, CSV, JSON và mã nguồn được **trích chữ ngay trên máy** rồi gửi kèm. Để trống ô chat = "phân tích tệp".
  Tệp lưu ở `attachments/`, lịch sử chỉ giữ tham chiếu (không nhúng base64), tệp không còn dùng tự dọn khi mở app.
  Câu trả lời có nút **Lưu thành ghi chú mới** (ghi kèm nguồn tệp)

Phím tắt: ⌘N ghi chú mới · ⌘⇧O hội thoại mới · ⌘1/⌘2 Ghi chú/Trợ lý · ⌘⇧J trợ lý cạnh ghi chú ·
⌘K bảng lệnh · ⌃⌘S ẩn/hiện thanh bên · ⌘, cài đặt · ⌘Z hoàn tác xóa

### Cơ bản

- Tạo / xóa / ghim ghi chú (menu chuột phải hoặc thanh công cụ editor)
- Tìm kiếm tức thời theo tiêu đề & nội dung
- Tự động lưu (debounce ~0.6 giây) vào `~/Library/Application Support/NoteStudio/notes.json`
- Phím tắt ⌘N — tạo ghi chú mới
- Lần chạy đầu tự tạo 4 ghi chú demo

### Nâng cấp v1.1

- **Dark mode** 🌙 — nút mặt trăng/mặt trời trên toolbar, palette tối theo ChatGPT (sidebar #171717, nền #212121)
- **Markdown preview** 👁 — nút con mắt để chuyển soạn thảo ↔ xem trước (heading, list, quote, code block, **bold**, *italic*)
- **Xuất PDF** 📄 — nút "Xuất ra PDF" ở panel phải, A4 tự phân trang, dùng CoreText
- **Tóm tắt bằng AI** ✨ — dán OpenAI API key vào panel phải (lưu UserDefaults), bấm "Tóm tắt ghi chú này";
  kết quả có thể sao chép hoặc chèn thẳng vào ghi chú

### Nâng cấp v1.3 — AI làm việc được với app, hai chiều

- **Tách bạch 3 khu với rail điều hướng dọc** 🧭 — 📄 Ghi chú (danh sách + soạn thảo + chi tiết) ·
  ✨ Trợ lý AI (chat full vùng giữa) · ⚙️ Cài đặt (màn hình riêng: providers, iCloud, giới thiệu). Phím ⌘1/⌘2/⌘,
- **Nhiều LLM provider (chuẩn OpenAI)** 🔌 — thêm/xóa/chuyển giữa nhiều provider (mỗi cái có tên, Base URL,
  Model, API key riêng — lưu file secrets.json chmod 600, không dùng Keychain để tránh bị macOS hỏi password khi rebuild). Seed sẵn OpenAI + Ollama local; trỏ được tới OpenRouter, Groq, vLLM…
- **Chat AI agent toàn quyền** 💬 — chat chiếm vùng giữa (layout lớn kiểu ChatGPT), **không gắn với note nào**.
  AI LUÔN có 10 tools và **tự quyết định** khi nào dùng: hỏi kiến thức chung thì trả lời luôn, hỏi/review/brainstorm
  về note thì tự gọi tool (loop không giới hạn số bước, nút Dừng, auto-retry khi rate limit), muốn lưu thì tự tạo/sửa note.
  **Streaming** — chữ hiện dần theo token. **Trả lời render markdown** đầy đủ.
  Tools: list/search/read/**append_to_note**/**get_active_note**/**get_stats**/**create**/**update**/
  **delete** (hiện chip Xác nhận/Hủy trong chat)/**select** — bấm pill tool để xem arguments + kết quả raw.
  Gõ **@** hiện dropdown chọn note (↑↓/Enter/Esc), chọn xong chèn **chip inline** vào composer và bubble user. Đổi provider nhanh ngay header.
  Context tự gọt khi hội thoại dài. Sửa/Làm lại tin nhắn.
  **Nhiều phiên hội thoại**: sidebar phiên — tạo mới, đổi tên, xóa, tự đặt tên, lưu `chats.json`. ⌘⇧J bật/tắt chat
- **AI gợi ý tiêu đề** ✨ — nút sparkles cạnh tiêu đề; **AI gợi ý thẻ** — nút trong section Thẻ
- **Thẻ + lọc** — thêm thẻ tay hoặc nhờ AI; chip lọc ở sidebar, click chip để lọc ghi chú
- **Command palette ⌘K** — gõ để nhảy tới note / tạo note / bật dark mode / xuất PDF…
- **Checklist tương tác** — `- [ ]` trong markdown preview thành checkbox bấm được thật (tick lưu ngược vào note)
- **Menu bar quick capture** — icon giấy bút trên menu bar, ghi nhanh không cần mở app
- **iCloud Drive sync** — mirror notes.json sang iCloud Drive mỗi lần lưu, merge mới-hơn-thắng khi mở app
- **MCP tool `open_note`** — AI mở app và nhảy tới đúng ghi chú qua URL scheme `notestudio://note/<id>`

### Nâng cấp v1.2 — MCP server 🤖

- **`notestudio-mcp`** — MCP server viết bằng Swift (stdio, JSON-RPC 2.0, không cần Node)
- Cho AI client (ZCode, Claude Desktop…) thao tác trực tiếp với ghi chú qua 6 tools:
  `list_notes`, `search_notes`, `read_note`, `create_note`, `update_note`, `delete_note`
- App đang mở **tự nhận thay đổi** từ AI ngay lập tức nhờ file-watcher (theo dõi `notes.json`, hai chiều)
- Đăng ký trong `~/.zcode/cli/config.json`:

```json
{
  "mcp": {
    "servers": {
      "notestudio": {
        "command": "/Users/dungnt/workspace/NoteStudio/notestudio-mcp",
        "args": []
      }
    }
  }
}
```

- Test thủ công:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | ./notestudio-mcp
```

## Cấu trúc

```
NoteStudio/
├── Sources/
│   ├── NoteStudioApp.swift   # entry point, cửa sổ, phím tắt
│   ├── Note.swift            # model
│   ├── NotesStore.swift      # state + lưu JSON + file-watcher + mirror iCloud
│   ├── ContentView.swift     # khung cửa sổ: sidebar + nội dung (+ trợ lý bên phải), toast
│   ├── SidebarView.swift     # sidebar: Ghi chú/Trợ lý, danh sách theo thời gian, Cài đặt
│   ├── EditorView.swift      # soạn thảo + preview + thẻ dưới tiêu đề + quick AI
│   ├── ChatPanelView.swift   # chat kiểu ChatGPT — toàn màn hình hoặc panel cạnh editor
│   ├── ChatComposer.swift    # composer NSTextView: chip @mention, lệnh /, tự giãn
│   ├── AssistantEngine.swift # vòng lặp AI agent + xác nhận xóa (dùng chung 2 chế độ chat)
│   ├── Attachments.swift     # đính kèm: nhập ảnh/tài liệu, trích chữ, gửi image_url, dọn tệp
│   ├── ChatAgent.swift       # 10 tools của agent + system prompt
│   ├── ChatSession.swift     # model phiên hội thoại
│   ├── SettingsView.swift    # giao diện, AI providers (kiểm tra kết nối), iCloud, phím tắt
│   ├── CommandPaletteView.swift # bảng lệnh ⌘K
│   ├── MarkdownView.swift    # parser + render markdown (checklist tương tác)
│   ├── ExportService.swift   # xuất PDF (CoreText, A4 phân trang)
│   ├── LLMService.swift      # provider chuẩn OpenAI (baseURL/model tùy ý) + secrets.json
│   └── Theme.swift           # design tokens, thang chữ, bo góc, Sáng/Tối/Hệ thống
├── MCPServer/main.swift      # MCP server (stdio) — cầu nối AI ↔ ghi chú (10 tools)
├── Resources/Info.plist
├── scripts/make_icon.swift   # vẽ icon bằng CoreGraphics
└── build.sh                  # build thành .app (kèm icon + codesign)
```

## Tùy chỉnh giao diện

Mọi màu sắc / thông số của "Studio theme" nằm gọn trong `Sources/Theme.swift` — mỗi token có cặp
giá trị light/dark, ví dụ `background = dynamic(0xFFFFFF, 0x212121)`. Cỡ chữ dùng `Studio.Typo`
(caption 11 · footnote 12 · callout 13 · body 15 · headline 17 · title 22 · largeTitle 28), bo góc dùng `Studio.Radius`.

## Ghi chú

- API key của provider lưu trong `secrets.json` (chmod 600) tại thư mục dữ liệu — không dùng Keychain vì app build ad-hoc sẽ bị macOS hỏi password keychain mỗi lần rebuild
- Reset dữ liệu demo: xóa thư mục `~/Library/Application Support/NoteStudio`
