import AppKit

// Genera el FONDO de la imagen Open Graph (1200×630, estilo de la página de revelar:
// copos y árbol) y lo incrusta en Sources/App/Services/OGImage.swift. Solo funciona en macOS.
// El texto (nombre y fecha del evento) lo dibuja el servidor encima: ver OGRenderer.swift.
// La mitad izquierda (x < 780) queda libre para ese texto.
//
//   swift scripts/make_og.swift            (desde la raíz del repo)
//   swift scripts/make_og.swift og.png     (además guarda el PNG para verlo)
let W = 1200, H = 630
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Coordenadas con origen arriba a la izquierda, como en SVG.
ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

ctx.setFillColor(black); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// Copos
func flake(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ alpha: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y); ctx.scaleBy(x: size / 12, y: size / 12)
    ctx.setStrokeColor(white.copy(alpha: alpha)!); ctx.setLineWidth(1); ctx.setLineCap(.round)
    ctx.move(to: .init(x: 6, y: 1)); ctx.addLine(to: .init(x: 6, y: 11))
    ctx.move(to: .init(x: 1.5, y: 3.5)); ctx.addLine(to: .init(x: 10.5, y: 8.5))
    ctx.move(to: .init(x: 1.5, y: 8.5)); ctx.addLine(to: .init(x: 10.5, y: 3.5))
    ctx.strokePath(); ctx.restoreGState()
}
for (l, t, s, a) in [(6, 14, 18, 0.5), (22, 76, 14, 0.4), (30, 8, 22, 0.35), (44, 84, 16, 0.45),
                     (58, 10, 20, 0.4), (66, 74, 14, 0.35), (88, 8, 24, 0.3), (97, 36, 16, 0.5),
                     (4, 88, 18, 0.35), (97, 90, 14, 0.4)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    flake(l / 100 * CGFloat(W), t / 100 * CGFloat(H), s, a)
}

// Árbol (viewBox 320×360 del diseño), escalado a 1.45 a la derecha
ctx.saveGState()
ctx.translateBy(x: 770, y: 50); ctx.scaleBy(x: 1.45, y: 1.45)
ctx.setStrokeColor(white); ctx.setLineWidth(1.5); ctx.setLineJoin(.round); ctx.setLineCap(.round)
func poly(_ pts: [CGFloat], fill: CGColor) {
    ctx.move(to: .init(x: pts[0], y: pts[1]))
    stride(from: 2, to: pts.count, by: 2).forEach { ctx.addLine(to: .init(x: pts[$0], y: pts[$0 + 1])) }
    ctx.closePath(); ctx.setFillColor(fill); ctx.drawPath(using: .fillStroke)
}
poly([160,14, 165.3,28.7, 180.9,29.2, 168.6,38.8, 172.9,53.8, 160,45, 147.1,53.8, 151.4,38.8, 139.1,29.2, 154.7,28.7], fill: white)
poly([160,170, 40,300, 280,300], fill: black)
poly([160,110, 65,220, 255,220], fill: black)
poly([160,66, 90,150, 230,150], fill: black)
poly([146,300, 174,300, 174,336, 146,336], fill: black)
for (x1, y, cy, x2) in [(118.0, 122.0, 136.0, 202.0), (102, 190, 208, 218), (82, 268, 290, 238)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    ctx.move(to: .init(x: x1, y: y)); ctx.addQuadCurve(to: .init(x: x2, y: y), control: .init(x: 160, y: cy)); ctx.strokePath()
}
for cy in [129, 199, 279] as [CGFloat] {
    ctx.addEllipse(in: CGRect(x: 155, y: cy - 5, width: 10, height: 10)); ctx.setFillColor(white); ctx.drawPath(using: .fillStroke)
}
ctx.move(to: .init(x: 60, y: 336)); ctx.addLine(to: .init(x: 260, y: 336)); ctx.strokePath()
poly([84,310, 120,310, 120,336, 84,336], fill: black)
ctx.move(to: .init(x: 102, y: 310)); ctx.addLine(to: .init(x: 102, y: 336)); ctx.strokePath()
poly([200,316, 228,316, 228,336, 200,336], fill: black)
ctx.move(to: .init(x: 214, y: 316)); ctx.addLine(to: .init(x: 214, y: 336)); ctx.strokePath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let png = rep.representation(using: .png, properties: [:])!
if CommandLine.arguments.count > 1 {
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

let b64 = png.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
    .split(separator: "\n").map { "        \($0)" }.joined(separator: "\n")
let swift = """
// Generado por scripts/make_og.swift — no editar a mano.
import Foundation

/// Fondo (PNG 1200×630) de la imagen de vista previa del enlace en WhatsApp, iMessage, etc.
/// Va incrustado en el binario; OGRenderer le dibuja encima el nombre y la fecha del evento.
enum OGImage {
    static let background: Data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!

    private static let base64 = \"\"\"
\(b64)
        \"\"\"
}

"""
try! swift.write(toFile: "Sources/App/Services/OGImage.swift", atomically: true, encoding: .utf8)
print("OGImage.swift actualizado (\(png.count) bytes de PNG)")
