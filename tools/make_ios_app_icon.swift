// Generates the iPhone app icon (shown on the home screen and in Settings → Keyboards): a white speech
// bubble with な on a blue-violet gradient. The upstream azooKey icon is the upstream project's mark and is not used.
// Usage: swift tools/make_ios_app_icon.swift upstream/azooKey-ios/MainApp/Assets.xcassets/NaturalKana.appiconset/icon-1024.png
// then run tools/export_patches.py.
import AppKit

let size = 1024
// No alpha channel: the App Store rejects icons with transparency.
let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

// Opaque square; iOS applies the rounded mask itself.
NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.36, blue: 0.95, alpha: 1),
           ending: NSColor(srgbRed: 0.13, green: 0.12, blue: 0.42, alpha: 1))!.draw(in: canvas, angle: -60)

// Speech bubble with a tail at the lower left.
let bubble = NSBezierPath(roundedRect: NSRect(x: 172, y: 262, width: 680, height: 540), xRadius: 190, yRadius: 190)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 300, y: 320))
tail.curve(to: NSPoint(x: 210, y: 170), controlPoint1: NSPoint(x: 300, y: 250), controlPoint2: NSPoint(x: 270, y: 200))
tail.curve(to: NSPoint(x: 470, y: 280), controlPoint1: NSPoint(x: 330, y: 190), controlPoint2: NSPoint(x: 420, y: 230))
tail.close()
NSColor.white.setFill()
bubble.fill()
tail.fill()

// な, centred on its ink inside the bubble.
let font = NSFont(name: "HiraginoSans-W6", size: 400)!
let text = NSAttributedString(string: "な", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.62, alpha: 1)])
let line = CTLineCreateWithAttributedString(text)
let context = NSGraphicsContext.current!.cgContext
let ink = CTLineGetImageBounds(line, context)
context.textPosition = CGPoint(x: 512 - ink.width / 2 - ink.minX, y: 532 - ink.height / 2 - ink.minY)
CTLineDraw(line, context)

NSGraphicsContext.restoreGraphicsState()
try! NSBitmapImageRep(cgImage: bitmap.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
