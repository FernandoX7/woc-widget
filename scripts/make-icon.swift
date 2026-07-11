// Renders a macOS-style app icon (rounded-rect tile with margin + soft shadow) from a
// square source image, then writes a 1024×1024 master PNG. Build the .icns with:
//   swiftc -O scripts/make-icon.swift -o /tmp/make-icon
//   /tmp/make-icon scripts/icon-source.png /tmp/icon_master.png
//   …then sips into an AppIcon.iconset and `iconutil -c icns`.  (see make-icon.sh)
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon <source.png> <out.png>\n".utf8))
    exit(1)
}
let out = args[2]
let size: CGFloat = 1024

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// macOS-template-ish geometry: ~9% margin, generous corner radius (squircle feel).
let margin = size * 0.09
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let radius = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Soft drop shadow under the tile for depth.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
              blur: size * 0.035,
              color: NSColor.black.withAlphaComponent(0.5).cgColor)
NSColor.black.setFill()
path.fill()
ctx.restoreGState()

// Clip to the rounded tile and fill it with the source art.
path.addClip()
src.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
do { try png.write(to: URL(fileURLWithPath: out)); print("wrote \(out)") }
catch { FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(3) }
