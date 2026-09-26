// Chụp cửa sổ NoteStudio offscreen qua CGWindowListCreateImage (không cần activate app).
// Usage: swift scripts/capture_window.swift <ownerName> <output.png> [windowNameSubstring]
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else {
    print("usage: swift capture_window.swift <ownerName> <output.png>")
    exit(1)
}
let owner = CommandLine.arguments[1]
let output = CommandLine.arguments[2]

func findWindowID() -> CGWindowID? {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for info in list {
        guard let infoOwner = info[kCGWindowOwnerName as String] as? String,
              infoOwner == owner,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double, width > 400,
              let height = bounds["Height"] as? Double, height > 300,
              (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { continue }
        return info[kCGWindowNumber as String] as? CGWindowID
    }
    return nil
}

var windowID: CGWindowID?
for _ in 0..<60 {
    if let id = findWindowID() {
        windowID = id
        break
    }
    usleep(500_000)
}
guard let id = windowID else {
    print("ERROR: window not found for owner \(owner)")
    exit(2)
}

// CGWindowListCreateImage bị mark unavailable trên SDK macOS 15 — bind thẳng symbol C
@_silgen_name("CGWindowListCreateImage")
func _cgWindowListCreateImage(
    _ bounds: CGRect, _ option: UInt32, _ windowID: UInt32, _ imageOption: UInt32
) -> CGImage?

private let kCGWindowListOptionIncludingWindow: UInt32 = 1 << 3
private let kCGWindowImageBestResolution: UInt32 = 1 << 21

let image = _cgWindowListCreateImage(
    .null, kCGWindowListOptionIncludingWindow, id, kCGWindowImageBestResolution
)
guard let image, let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    print("ERROR: capture/destination failed")
    exit(3)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    print("ERROR: finalize failed")
    exit(4)
}
print("OK \(output)")
