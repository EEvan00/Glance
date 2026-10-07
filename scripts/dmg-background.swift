import AppKit
let image = NSImage(size: NSSize(width: 640, height: 400))
image.lockFocus()
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 640, height: 400).fill()
func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(calibratedWhite: 0.15, alpha: 1)) {
 let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
 let measured = (value as NSString).size(withAttributes: attrs)
 (value as NSString).draw(at: NSPoint(x: (640-measured.width)/2, y: y), withAttributes: attrs)
}
text("Install Glance", y: 330, size: 25, weight: .semibold)
text("→", y: 213, size: 48, color: NSColor(calibratedWhite: 0.4, alpha: 1))
text("Drag Glance to Applications", y: 115, size: 17, weight: .medium)
text("将 Glance 拖到「应用程序」以安装", y: 84, size: 15, color: NSColor(calibratedWhite: 0.4, alpha: 1))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
