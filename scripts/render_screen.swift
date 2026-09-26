// Harness chụp ảnh màn hình app không cần quyền Screen Recording và không activate app:
// dựng ContentView thật trong NSWindow (NSHostingView) rồi cacheDisplay ra PNG.
// Usage: ./l10n-harness -appLanguage english -studioSection notes -out /tmp/x.png
import AppKit
import SwiftUI

@MainActor
final class Harness {
    static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func run() {
        let language = argument("-appLanguage") ?? "system"
        let section = argument("-studioSection") ?? "notes"
        let output = argument("-out") ?? "/tmp/notestudio-screen.png"

        LLMService.bootstrap()
        let store = NotesStore()
        if let resolved = NotesStore.AppSection(rawValue: section) {
            store.activeSection = resolved
        }
        let assistant = AssistantEngine(store: store)

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited) // không hiện Dock, không giựt focus

        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "NoteStudio"
        window.isReleasedWhenClosed = false

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(store)
                .environmentObject(assistant)
        )
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Chờ vài vòng runloop để SwiftUI layout xong rồi mới chụp
        Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            guard let view = window.contentView else { exit(2) }
            let bounds = view.bounds
            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { exit(3) }
            rep.size = bounds.size
            view.cacheDisplay(in: bounds, to: rep)

            guard let png = rep.representation(using: .png, properties: [:]) else { exit(4) }
            do {
                try png.write(to: URL(fileURLWithPath: output))
                print("OK \(output)")
            } catch {
                print("ERROR: \(error)")
                exit(5)
            }
            exit(0)
        }

        app.run()
    }
}

// Nhảy lên main thread + MainActor rồi chạy harness
DispatchQueue.main.async {
    MainActor.assumeIsolated {
        Harness.run()
    }
}
dispatchMain()
