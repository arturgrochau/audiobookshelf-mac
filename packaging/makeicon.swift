// Composites the ABS logo (packaging/logo-1024.png, rendered once from
// client/static/icon.svg) onto a dark macOS squircle and writes an .icns.
// Usage: swift packaging/makeicon.swift packaging/Audiobookshelf.icns [Resources/images/logo.png]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Audiobookshelf.icns"
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
guard let logo = NSImage(contentsOf: here.appendingPathComponent("logo-1024.png")) else {
  fatalError("missing logo-1024.png")
}

func render(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = CGFloat(px) / 1024
  let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
  let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
  NSGradient(
    starting: NSColor(red: 0x3A / 255, green: 0x3B / 255, blue: 0x3B / 255, alpha: 1),
    ending: NSColor(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255, alpha: 1))!
    .draw(in: path, angle: -90)
  let l = 640 * s
  let r = NSRect(x: (CGFloat(px) - l) / 2, y: (CGFloat(px) - l) / 2, width: l, height: l)
  NSGraphicsContext.saveGraphicsState()
  // qlmanage renders on white: clip to the gold disc (inside the SVG's white ring).
  NSBezierPath(ovalIn: r.insetBy(dx: l * 0.016, dy: l * 0.016)).addClip()
  logo.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

/// The in-app logo (Appbar.vue's icon.svg): the full disc with its white ring, transparent outside.
func renderLogo(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let r = NSRect(x: 0, y: 0, width: px, height: px)
  NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).addClip()
  logo.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}
if CommandLine.arguments.count > 2 {
  try! renderLogo(256).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}

let set = FileManager.default.temporaryDirectory.appendingPathComponent("abs.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
  try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out]
try! p.run()
p.waitUntilExit()
try! render(1024).write(to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("png"))
