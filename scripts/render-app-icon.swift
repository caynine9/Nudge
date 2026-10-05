import AppKit
import Foundation

let canvasSize = 1024
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-app-icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
graphics.shouldAntialias = true
let context = graphics.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func fillGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
}

// The background stays full bleed; macOS applies its standard icon mask.
NSColor.clear.setFill()
NSBezierPath(rect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()
let background = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 230, yRadius: 230)
fillGradient(background, colors: [color(0.10, 0.16, 0.30), color(0.16, 0.18, 0.36), color(0.10, 0.25, 0.37)], angle: 135)

let halo = NSBezierPath(ovalIn: CGRect(x: 165, y: 140, width: 700, height: 700))
NSGradient(colors: [color(0.30, 0.74, 1.0, 0.25), color(0.28, 0.48, 1.0, 0.0)])?.draw(in: halo, angle: 90)

// A small glassy edge gives the blue creature enough separation at Finder sizes.
let inset = NSBezierPath(roundedRect: CGRect(x: 15, y: 15, width: 994, height: 994), xRadius: 220, yRadius: 220)
color(1, 1, 1, 0.07).setStroke()
inset.lineWidth = 2
inset.stroke()

let body = NSBezierPath()
body.move(to: CGPoint(x: 376, y: 190))
body.curve(to: CGPoint(x: 218, y: 348), controlPoint1: CGPoint(x: 287, y: 190), controlPoint2: CGPoint(x: 218, y: 260))
body.line(to: CGPoint(x: 218, y: 622))
body.curve(to: CGPoint(x: 375, y: 780), controlPoint1: CGPoint(x: 218, y: 710), controlPoint2: CGPoint(x: 288, y: 780))
body.line(to: CGPoint(x: 624, y: 780))
body.curve(to: CGPoint(x: 682, y: 760), controlPoint1: CGPoint(x: 648, y: 780), controlPoint2: CGPoint(x: 668, y: 773))
body.line(to: CGPoint(x: 804, y: 880))
body.line(to: CGPoint(x: 766, y: 700))
body.curve(to: CGPoint(x: 806, y: 622), controlPoint1: CGPoint(x: 774, y: 671), controlPoint2: CGPoint(x: 806, y: 650))
body.line(to: CGPoint(x: 806, y: 348))
body.curve(to: CGPoint(x: 648, y: 190), controlPoint1: CGPoint(x: 806, y: 260), controlPoint2: CGPoint(x: 736, y: 190))
body.close()

let shadow = NSShadow()
shadow.shadowColor = color(0.02, 0.06, 0.16, 0.52)
shadow.shadowBlurRadius = 44
shadow.shadowOffset = NSSize(width: 0, height: -22)
shadow.set()
fillGradient(body, colors: [color(0.62, 0.86, 1.0), color(0.43, 0.75, 1.0), color(0.43, 0.64, 0.98)], angle: 90)
NSShadow().set()

color(1, 1, 1, 0.32).setStroke()
body.lineWidth = 3
body.stroke()

let sheen = NSBezierPath()
sheen.move(to: CGPoint(x: 310, y: 707))
sheen.curve(to: CGPoint(x: 425, y: 750), controlPoint1: CGPoint(x: 325, y: 745), controlPoint2: CGPoint(x: 365, y: 758))
color(1, 1, 1, 0.24).setStroke()
sheen.lineWidth = 8
sheen.lineCapStyle = .round
sheen.stroke()

// Keep Nudgie's original simple face: two dark, vertical capsule eyes.
let leftEye = NSBezierPath(roundedRect: CGRect(x: 397, y: 442, width: 43, height: 112), xRadius: 21, yRadius: 21)
let rightEye = NSBezierPath(roundedRect: CGRect(x: 565, y: 442, width: 43, height: 112), xRadius: 21, yRadius: 21)
color(0.07, 0.12, 0.20).setFill()
leftEye.fill()
rightEye.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode app icon PNG.\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outputURL, options: .atomic)
