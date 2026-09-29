// Renders the Pace apple into an .icns file. Run: swift scripts/make-icon.swift Support/Pace.icns
import AppKit
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Support/Pace.icns"

func path(_ d: String) -> CGPath {
    let p = CGMutablePath()
    var nums: [CGFloat] = []
    var cmd: Character = "M"
    var tok = ""
    func flush() { if let v = Double(tok) { nums.append(CGFloat(v)) }; tok = "" }
    func apply() {
        switch cmd {
        case "M": if nums.count >= 2 { p.move(to: CGPoint(x: nums[0], y: nums[1])) }; nums.removeAll()
        case "C":
            while nums.count >= 6 {
                p.addCurve(to: CGPoint(x: nums[4], y: nums[5]), control1: CGPoint(x: nums[0], y: nums[1]), control2: CGPoint(x: nums[2], y: nums[3]))
                nums.removeFirst(6)
            }
        case "Z": p.closeSubpath(); nums.removeAll()
        default: nums.removeAll()
        }
    }
    for ch in d {
        if ch.isLetter { flush(); apply(); cmd = ch; if cmd == "Z" { apply() } }
        else if ch == " " || ch == "," { flush() }
        else if ch == "-" { flush(); tok = "-" }
        else { tok.append(ch) }
    }
    flush(); apply()
    return p
}

let body = path("M12 8.2C10.6 6.9 7.9 6.5 6 8C3.7 9.8 3.5 13.4 4.6 16.2C5.6 18.8 7.6 21.5 9.6 21.5C10.6 21.5 11.1 21 12 21C12.9 21 13.4 21.5 14.4 21.5C16.4 21.5 18.4 18.8 19.4 16.2C20.5 13.4 20.3 9.8 18 8C16.1 6.5 13.4 6.9 12 8.2Z")
let stem = path("M12 8.2C12 6.1 12.4 4.5 13.4 3.3")
let leaf = path("M12.9 5.3C13.6 3.3 15.8 2.5 17.8 3C17.2 5 15 6 12.9 5.3Z")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        // Rounded dark tile, like a macOS icon.
        let inset = s * 0.05
        let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil))
        ctx.setFillColor(color(0x262624))
        ctx.fillPath()
        // Apple, centred, 66% of the tile.
        let scale = s * 0.66 / 24
        ctx.translateBy(x: (s - 24 * scale) / 2, y: (s - 24 * scale) / 2 + s * 0.01)
        ctx.scaleBy(x: scale, y: scale)
        ctx.addPath(body); ctx.setFillColor(color(0xD97757)); ctx.fillPath()
        ctx.saveGState()
        ctx.translateBy(x: 7.9, y: 12); ctx.rotate(by: -18 * .pi / 180)
        ctx.setFillColor(color(0xFAF9F5, 0.35))
        ctx.fillEllipse(in: CGRect(x: -0.9, y: -1.9, width: 1.8, height: 3.8))
        ctx.restoreGState()
        ctx.addPath(stem); ctx.setStrokeColor(color(0x8A5A3A)); ctx.setLineWidth(1.5); ctx.setLineCap(.round); ctx.strokePath()
        ctx.addPath(leaf); ctx.setFillColor(color(0x8FB07A)); ctx.fillPath()
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Pace.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(size).write(to: tmp.appendingPathComponent("icon_\(name).png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(p.terminationStatus == 0 ? "Wrote \(out)" : "iconutil failed")
exit(p.terminationStatus)
