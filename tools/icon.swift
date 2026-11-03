// Renders the Jot app icon (warm gradient + white 记) at any size.
// Usage: icon <output.png> [size]
// Used by tools/gen-icons.sh (PWA icons) and mac/build.sh (macOS .icns).

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let side = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 1024) : 1024

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(side), pixelsHigh: Int(side),
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    FileHandle.standardError.write("bitmap alloc failed\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: rounded square, leaving the margin macOS/PWA icons expect
let inset = side * 0.086
let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let squircle = NSBezierPath(roundedRect: rect, xRadius: side * 0.225, yRadius: side * 0.225)

let top = NSColor(srgbRed: 0.929, green: 0.424, blue: 0.298, alpha: 1)     // #ea6a4c
let bottom = NSColor(srgbRed: 0.788, green: 0.263, blue: 0.169, alpha: 1)  // #c9432b
NSGradient(starting: top, ending: bottom)?.draw(in: squircle, angle: -72)

// A soft highlight so it doesn't look flat
squircle.setClip()
NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0)])?
    .draw(in: NSRect(x: 0, y: side * 0.55, width: side, height: side * 0.45), angle: -90)

// 记 — the logomark, identical in both UI languages
let style = NSMutableParagraphStyle()
style.alignment = .center
let font = NSFont(name: "PingFang SC Semibold", size: side * 0.52)
    ?? NSFont.systemFont(ofSize: side * 0.52, weight: .semibold)
let glyph = NSAttributedString(string: "记", attributes: [
    .font: font,
    .foregroundColor: NSColor(white: 1, alpha: 0.98),
    .paragraphStyle: style,
])
let box = glyph.boundingRect(with: NSSize(width: side, height: side), options: [.usesLineFragmentOrigin])
glyph.draw(in: NSRect(x: 0, y: (side - box.height) / 2 + side * 0.01, width: side, height: box.height))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("icon -> \(out)")
