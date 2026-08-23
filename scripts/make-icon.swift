import AppKit
import CoreText

// Master geometry is defined on the 1024 canvas: an 824 plate inset by 100,
// with the mark's core, its 2x halo, and the letter it trails behind.
let canvas: CGFloat = 1024
let plateInset: CGFloat = 100
let plateSide: CGFloat = 824

let haloRadius: CGFloat = 175.0
let coreRadius: CGFloat = 87.5

/// The letter's x-height is set against the core so the dot reads as a caret at
/// the end of a line of text rather than as a separate blob.
let letterSize: CGFloat = 430.0
/// Gap from the letter's right edge to the halo's left edge.
let letterGap: CGFloat = 26.0

let orange = NSColor(srgbRed: 1.0, green: 0.5804, blue: 0.0, alpha: 1.0)
let ink = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1.0)

/// The macOS plate: an 824 square with the documented 185.4 corner radius.
func squirclePath(in rect: CGRect) -> CGPath {
    let r = rect.width * (185.4 / 824.0)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Plate, with a gradient shallow enough to read as light falling on white
/// rather than as grey — it is what keeps the silhouette against Finder.
func drawPlate(in ctx: CGContext, scale s: CGFloat) {
    let plate = CGRect(x: plateInset * s, y: plateInset * s, width: plateSide * s, height: plateSide * s)
    ctx.saveGState()
    ctx.addPath(squirclePath(in: plate))
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.949, green: 0.945, blue: 0.937, alpha: 1).cgColor,
        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.minY),
            end: CGPoint(x: plate.midX, y: plate.maxY),
            options: []
        )
    }
    ctx.restoreGState()
}

/// The letter is measured, not guessed: its ink box drives the whole layout, so
/// the dot lands where a caret would sit rather than at a hard-coded offset.
func drawMark(in ctx: CGContext, size: CGFloat, scale s: CGFloat) {
    let font = NSFont.systemFont(ofSize: letterSize * s, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ink,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink.cgColor,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "a", attributes: attrs))
    let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

    let haloDiameter = haloRadius * 2 * s
    let coreDiameter = coreRadius * 2 * s
    let groupWidth = inkBounds.width + letterGap * s + haloDiameter
    let groupLeft = (size - groupWidth) / 2
    let centreY = size / 2
    let haloCentreX = groupLeft + inkBounds.width + letterGap * s + haloDiameter / 2

    ctx.setFillColor(orange.withAlphaComponent(0.3).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: haloCentreX - haloDiameter / 2, y: centreY - haloDiameter / 2,
        width: haloDiameter, height: haloDiameter
    ))

    ctx.setFillColor(orange.cgColor)
    ctx.fillEllipse(in: CGRect(
        x: haloCentreX - coreDiameter / 2, y: centreY - coreDiameter / 2,
        width: coreDiameter, height: coreDiameter
    ))

    // The letter's ink centre and the dot's centre share a line.
    ctx.textPosition = CGPoint(x: groupLeft - inkBounds.minX, y: centreY - inkBounds.midY)
    CTLineDraw(line, ctx)
}

func render(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate \(px)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let s = size / canvas
    drawPlate(in: ctx, scale: s)
    drawMark(in: ctx, size: size, scale: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments[1]
let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in variants {
    let rep = render(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(name).png (\(Int(size))px)")
}
