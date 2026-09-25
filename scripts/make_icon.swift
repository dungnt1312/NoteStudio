// Vẽ icon app bằng CoreGraphics: squircle đen + "trang giấy" trắng + các dòng chữ.
// Usage: swift make_icon.swift <output.png>  (1024x1024)
import Foundation
import CoreGraphics
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("usage: swift make_icon.swift <output.png>")
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])

guard let context = CGContext(
    data: nil,
    width: 1024,
    height: 1024,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("cannot create CGContext")
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    ))
    context.setFillColor(color)
    context.fillPath()
}

// Nền đen bo góc lớn
fillRoundedRect(
    CGRect(x: 0, y: 0, width: 1024, height: 1024),
    radius: 230,
    color: CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
)

// "Trang giấy" trắng ở giữa
fillRoundedRect(
    CGRect(x: 292, y: 292, width: 440, height: 440),
    radius: 56,
    color: CGColor(gray: 1.0, alpha: 1)
)

// Các dòng chữ trên trang
let lineColor = CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
let widths: [CGFloat] = [320, 280, 200]
for (index, width) in widths.enumerated() {
    let y: CGFloat = 562 - CGFloat(index) * 68
    fillRoundedRect(
        CGRect(x: 352, y: y, width: width, height: 34),
        radius: 17,
        color: lineColor
    )
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL, "public.png" as CFString, 1, nil
      ) else {
    fatalError("cannot encode PNG")
}
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("icon written: \(outputURL.path)")
