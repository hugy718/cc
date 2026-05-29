// Re-clip a rasterized icon PNG to a rounded rectangle with REAL transparency.
// qlmanage flattens SVG thumbnails onto opaque white, filling the corners; this
// redraws the image clipped to a rounded-rect path into an alpha context so the
// corners become transparent. Prints corner/center alpha to stderr for verification.
//
// usage: swift round_corners.swift <input.png> <output.png> <size> <radiusFraction>
import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 5,
      let size = Int(args[3]),
      let radiusFrac = Double(args[4]) else {
    FileHandle.standardError.write(Data("usage: round_corners <in.png> <out.png> <size> <radiusFraction>\n".utf8))
    exit(1)
}
let inPath = args[1], outPath = args[2]

guard let img = NSImage(contentsOfFile: inPath),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("error: cannot load \(inPath)\n".utf8)); exit(2)
}

let w = size, h = size, bpr = size * 4
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: bpr, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("error: no context\n".utf8)); exit(3)
}
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
let r = CGFloat(Double(size) * radiusFrac)
let rect = CGRect(x: 0, y: 0, width: w, height: h)
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
ctx.clip()
ctx.draw(cg, in: rect)

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("error: cannot write \(outPath)\n".utf8)); exit(4)
}
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("error: finalize failed\n".utf8)); exit(5)
}

if let data = ctx.data {
    let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    let cornerA = p[3]                                  // pixel (0,0), premultipliedLast => A is 4th byte
    let centerA = p[(h/2) * bpr + (w/2) * 4 + 3]
    FileHandle.standardError.write(Data("corner alpha=\(cornerA) center alpha=\(centerA)\n".utf8))
}
