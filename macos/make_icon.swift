#!/usr/bin/env swift
// Generates the vimb macOS app icon (.icns) with a retro, dithered aesthetic.
// Writes an .iconset (all required PNG sizes) that iconutil compiles to .icns.
// Usage: swift make_icon.swift <outdir>
//
// The icon: a dark CRT/terminal backdrop with checkerboard dither, a pixeled
// "V" mark (vimb) in amber/green phosphor tones, and a dithered underline.

import AppKit
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: swift make_icon.swift <outdir>\n", stderr)
    exit(1)
}
let outDir = args[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func ctx(_ size: Int) -> CGContext {
    guard let c = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("ctx")
    }
    return c
}

// Draw the icon at `size` px.
func render(_ size: Int) -> CGImage {
    let s = CGFloat(size)
    let c = ctx(size)

    let amber    = (r: 0.98, g: 0.76, b: 0.12)
    let green    = (r: 0.32, g: 0.90, b: 0.55)
    let white    = (r: 0.95, g: 0.95, b: 0.92)

    // Vertical gradient with row-dither banding.
    let topR = 0.06, topG = 0.08, topB = 0.12
    let botR = 0.13, botG = 0.17, botB = 0.26
    for y in 0..<size {
        let f = Double(y) / Double(size - 1)
        let hash = Double((y * 17) % 64) / 64.0 - 0.5
        var r = topR + (botR - topR) * f + hash * 0.04
        var g = topG + (botG - topG) * f + hash * 0.04
        var b = topB + (botB - topB) * f + hash * 0.05
        if r < 0 || r > 1 { r = r < 0 ? 0 : 1 }
        if g < 0 || g > 1 { g = g < 0 ? 0 : 1 }
        if b < 0 || b > 1 { b = b < 0 ? 0 : 1 }
        c.setFillColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
        c.fill(CGRect(x: 0, y: size - 1 - y, width: size, height: 1))
    }

    // Checker dither overlay on the whole canvas (subtle CRT texture).
    let cell = max(1, size / 128)
    for cy in stride(from: 0, to: size, by: cell) {
        for cx in stride(from: 0, to: size, by: cell) {
            let on = ((cx / cell) + (cy / cell)) % 2 == 0
            if on {
                c.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.03)
                c.fill(CGRect(x: cx, y: cy, width: cell, height: cell))
            }
        }
    }

    // Rounded screen border.
    let inset = s * 0.06
    let bezel = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    c.setStrokeColor(red: 0.28, green: 0.33, blue: 0.44, alpha: 1)
    c.setLineWidth(max(1, s * 0.015))
    c.addPath(CGPath(roundedRect: bezel, cornerWidth: s * 0.15, cornerHeight: s * 0.15, transform: nil))
    c.strokePath()

    // Pixeled "V" mark (two thick strokes meeting at a point) with phosphor colors.
    let cx = s / 2
    let topY = s * 0.72
    let bottomY = s * 0.34
    let halfW = s * 0.30
    let thick = s * 0.11
    func dot(_ px: CGFloat, _ py: CGFloat, _ col: (Double,Double,Double), _ a: Double = 1) {
        c.setFillColor(red: CGFloat(col.0), green: CGFloat(col.1), blue: CGFloat(col.2), alpha: CGFloat(a))
        c.fill(CGRect(x: px, y: py, width: thick, height: thick))
    }
    let steps = 12
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let ly = topY - (topY - bottomY) * t - thick / 2
        // left arm: from top-left inward
        let lx = (cx - halfW) + t * (halfW)     // moves toward center
        dot(lx - thick / 2, ly, i > 6 ? green : white)
        // right arm: mirrored
        let rx = (cx + halfW) - t * (halfW)
        dot(rx - thick / 2, ly, i > 6 ? amber : white)
        // dithered underline "vim" bar under the V
        let uy = s * 0.25
        dot(cx + (t - 0.5) * halfW * 2 - thick / 2, uy, amber, 0.9)
    }

    guard let img = c.makeImage() else { fatalError("img") }
    return img
}

func renderPNG(_ base: CGImage, _ px: Int) -> Data {
    let c = ctx(px)
    c.interpolationQuality = .high
    c.translateBy(x: 0, y: CGFloat(px))
    c.scaleBy(x: 1, y: -1)
    c.draw(base, in: CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
    let out = c.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

let base = render(1024)
let iconset = (outDir as NSString).appendingPathComponent("vimb.iconset") as String
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16.png",16),("icon_16x16@2x.png",32),
    ("icon_32x32.png",32),("icon_32x32@2x.png",64),
    ("icon_128x128.png",128),("icon_128x128@2x.png",256),
    ("icon_256x256.png",256),("icon_256x256@2x.png",512),
    ("icon_512x512.png",512),("icon_512x512@2x.png",1024),
]
for (name, px) in entries {
    try renderPNG(base, px).write(to: URL(fileURLWithPath: (iconset as NSString).appendingPathComponent(name)))
}
print("iconset written to \(iconset)")
