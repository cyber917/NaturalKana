// Generates the macOS input-mode icons (な for Japanese, na for English) as template PNGs.
// Usage: swift tools/make_macos_input_icons.swift <output-folder>
// Then convert into upstream/azooKey-macos/azooKeyMac:
//   sips -s format tiff -s dpiWidth 72 -s dpiHeight 72 <out>/main.png --out main.tiff
//   sips -s format tiff -s dpiWidth 144 -s dpiHeight 144 <out>/main@2x.png --out main@2x.tiff
// (same for en), and run tools/export_patches.py. Xcode combines the 1x and @2x files.
// Without these icons macOS shows a generic keyboard, and some versions crash the
// focused app (CFRelease(NULL) in the input-source indicator) when switching to NaturalKana.
import AppKit

// Template input-mode icon: filled rounded square with the label knocked out (same style as Apple's input methods).
func render(_ label: String, font: NSFont, px: Int, path: String, baselineShift: CGFloat = 0) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 16, height: 16)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: 0.5, y: 0.5, width: 15, height: 15)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5).fill()
    NSGraphicsContext.current?.compositingOperation = .destinationOut
    let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(text)
    let context = NSGraphicsContext.current!.cgContext
    // Centre the glyphs' ink, not the line box, measured from the baseline.
    let ink = CTLineGetImageBounds(line, context)
    context.textPosition = CGPoint(x: box.midX - ink.width / 2 - ink.minX, y: box.midY - ink.height / 2 - ink.minY + baselineShift)
    CTLineDraw(line, context)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let out = CommandLine.arguments[1]
let kana = NSFont(name: "HiraginoSans-W6", size: 11.5)!
let latin = NSFont.systemFont(ofSize: 11, weight: .semibold)
for (px, suffix) in [(16, ""), (32, "@2x")] {
    render("な", font: kana, px: px, path: "\(out)/main\(suffix).png")
    render("na", font: latin, px: px, path: "\(out)/en\(suffix).png")
}
