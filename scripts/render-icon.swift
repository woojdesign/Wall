import Foundation
import CoreGraphics
import ImageIO

// Wall app icon: two atmospheres meeting at a hard horizontal seam.
// The seam IS the wall — no drawn line. Palette pulled from Theme.swift's
// gradient stops so the icon and the in-app field share DNA.
//
// Composition (calmest pairing, per Sean):
//   • Warm field on top (60%):  cream (#fffcf8) → slight peach (#fef5ed)
//   • Cool field on bottom (40%): blue (#f5f9fb) → slight cool-pink (#faf5f8)
//   • Seam at 60% from top (lower-third, horizon-like)
//   • Rounded square at the standard macOS icon corner radius (~22.37%)
//
// Each field has its own subtle vertical gradient — flat enough to stay
// monastic, just-not-flat enough to give the icon atmospheric depth.

func makeIcon(size px: Int) -> CGImage {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Rounded square clip (macOS app icon corner radius ~22.37% of size).
    let cr = s * 0.2237
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: cr, cornerHeight: cr, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Seam at lower-third (60% from top = 40% from bottom in CG coords).
    let seamY = s * 0.4

    // Warm field — top 60%. Cream at very top, slight peach above seam.
    let warm = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0xff/255.0, green: 0xfc/255.0, blue: 0xf8/255.0, alpha: 1),
        CGColor(red: 0xfe/255.0, green: 0xf5/255.0, blue: 0xed/255.0, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: seamY, width: s, height: s - seamY))
    ctx.drawLinearGradient(warm,
                           start: CGPoint(x: s/2, y: s),
                           end:   CGPoint(x: s/2, y: seamY),
                           options: [])
    ctx.restoreGState()

    // Cool field — bottom 40%. Blue just below seam, slight cool-pink at base.
    let cool = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0xf5/255.0, green: 0xf9/255.0, blue: 0xfb/255.0, alpha: 1),
        CGColor(red: 0xfa/255.0, green: 0xf5/255.0, blue: 0xf8/255.0, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: s, height: seamY))
    ctx.drawLinearGradient(cool,
                           start: CGPoint(x: s/2, y: seamY),
                           end:   CGPoint(x: s/2, y: 0),
                           options: [])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                      "public.png" as CFString,
                                                      1, nil) else {
        throw NSError(domain: "WallIcon", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "PNG dest"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "WallIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG finalize"])
    }
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Standard macOS iconset slots: 16, 32, 128, 256, 512 at @1x and @2x.
let entries: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (px, name) in entries {
    let image = makeIcon(size: px)
    try! writePNG(image, to: iconset.appendingPathComponent(name))
    print("✓ \(name) (\(px)px)")
}

print("\niconset ready at \(iconset.path)")
