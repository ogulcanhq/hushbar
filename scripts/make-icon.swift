// Draws the app icon from code and writes an .icns: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)

    // The standard macOS icon grid: an 824/1024 rounded square, centered.
    let inset = s * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(
        starting: NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.33, alpha: 1),
        ending: NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.13, alpha: 1)
    )!.draw(in: tilePath, angle: -90)

    // Three faders. The middle one is pulled to the bottom in the accent color: hushed.
    let positions: [(x: CGFloat, level: CGFloat, active: Bool)] = [(0.31, 0.68, false), (0.50, 0.20, true), (0.69, 0.50, false)]
    let bottom = s * 0.26
    let height = s * 0.48
    for fader in positions {
        let x = s * fader.x
        let trackWidth = s * 0.035
        NSColor(white: 1, alpha: 0.22).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: x - trackWidth / 2, y: bottom, width: trackWidth, height: height),
            xRadius: trackWidth / 2, yRadius: trackWidth / 2
        ).fill()

        let knobWidth = s * 0.125
        let knobHeight = s * 0.075
        let y = bottom + height * fader.level
        (fader.active
            ? NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.40, alpha: 1)
            : NSColor(white: 0.95, alpha: 1)).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: x - knobWidth / 2, y: y - knobHeight / 2, width: knobWidth, height: knobHeight),
            xRadius: knobHeight / 2.4, yRadius: knobHeight / 2.4
        ).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("hushbar-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
