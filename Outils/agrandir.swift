// Agrandit des sprites en pixel art sans lissage.
// Usage : swift Outils/agrandir.swift <facteur> <source.png> <destination.png> [<source> <destination>...]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
guard let scale = Int(args.first ?? "") else { fatalError("facteur manquant") }
var index = 1
while index + 1 < args.count {
    let source = URL(fileURLWithPath: args[index]), target = URL(fileURLWithPath: args[index + 1])
    index += 2
    guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { fatalError("illisible : \(source.path)") }
    let width = image.width * scale, height = image.height * scale
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("contexte") }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil),
          let big = context.makeImage() else { fatalError("écriture") }
    CGImageDestinationAddImage(output, big, nil)
    CGImageDestinationFinalize(output)
}
