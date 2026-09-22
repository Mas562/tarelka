import AppKit

// Native vector artwork rendered at every macOS icon resolution.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let green = NSColor(srgbRed: 0.16, green: 0.36, blue: 0.27, alpha: 1)
let mint = NSColor(srgbRed: 0.89, green: 0.94, blue: 0.84, alpha: 1)

func stroke(_ points: [NSPoint], width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0]); for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
    color.setStroke(); path.stroke()
}
func draw(size: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
    green.setFill(); base.fill()
    let plate = NSBezierPath(ovalIn: NSRect(x: 200, y: 200, width: 624, height: 624))
    mint.setFill(); plate.fill()
    let ring = NSBezierPath(ovalIn: NSRect(x: 249, y: 249, width: 526, height: 526))
    ring.lineWidth = 7; green.withAlphaComponent(0.18).setStroke(); ring.stroke()
    // A small leaf on the plate, with a curved center vein.
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 448, y: 414))
    leaf.curve(to: NSPoint(x: 635, y: 650), controlPoint1: NSPoint(x: 382, y: 610), controlPoint2: NSPoint(x: 513, y: 655))
    leaf.curve(to: NSPoint(x: 448, y: 414), controlPoint1: NSPoint(x: 651, y: 477), controlPoint2: NSPoint(x: 567, y: 374))
    green.setFill(); leaf.fill()
    let vein = NSBezierPath(); vein.move(to: NSPoint(x: 429, y: 366))
    vein.curve(to: NSPoint(x: 573, y: 573), controlPoint1: NSPoint(x: 480, y: 443), controlPoint2: NSPoint(x: 489, y: 493))
    vein.lineWidth = 14; vein.lineCapStyle = .round; mint.setStroke(); vein.stroke()
    stroke([NSPoint(x: 144, y: 337), NSPoint(x: 144, y: 570)], width: 17, color: mint)
    stroke([NSPoint(x: 113, y: 667), NSPoint(x: 113, y: 578), NSPoint(x: 175, y: 578), NSPoint(x: 175, y: 667)], width: 15, color: mint)
    stroke([NSPoint(x: 144, y: 578), NSPoint(x: 144, y: 667)], width: 15, color: mint)
    stroke([NSPoint(x: 879, y: 336), NSPoint(x: 879, y: 676)], width: 17, color: mint)
    let knife = NSBezierPath(); knife.move(to: NSPoint(x: 879, y: 679))
    knife.curve(to: NSPoint(x: 849, y: 485), controlPoint1: NSPoint(x: 837, y: 646), controlPoint2: NSPoint(x: 838, y: 526))
    knife.line(to: NSPoint(x: 879, y: 485)); knife.close(); mint.setFill(); knife.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
}
for dimension in [16, 32, 128, 256, 512] {
    try draw(size: dimension, filename: "icon_\(dimension)x\(dimension).png")
    try draw(size: dimension * 2, filename: "icon_\(dimension)x\(dimension)@2x.png")
}
