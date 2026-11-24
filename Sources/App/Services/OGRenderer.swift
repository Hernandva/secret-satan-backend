import Foundation
import Cgd

/// Dibuja la imagen de vista previa (1200×630) de un enlace: el fondo de `OGImage`
/// (copos y árbol) con un título grande y un subtítulo a la izquierda.
///
/// Usa libgd con FreeType y fontconfig. Las fuentes se buscan por nombre (Inter si está
/// instalada, si no otra sans del sistema). Si algo falla, devuelve el fondo sin texto.
enum OGRenderer {
    static let width = 1200, height = 630

    /// Zona libre para el texto, a la izquierda del árbol.
    private static let textX: Int32 = 96
    private static let maxTextWidth = 660

    private static let boldFont = "Inter,Helvetica Neue,DejaVu Sans:bold"
    private static let regularFont = "Inter,Helvetica Neue,DejaVu Sans"

    static func render(title: String, subtitle: String?) -> Data {
        render(title: title, subtitle: subtitle) ?? OGImage.background
    }

    private static func render(title: String, subtitle: String?) -> Data? {
        guard gdFTUseFontConfig(1) != 0 else { return nil }

        var background = OGImage.background
        guard let im = background.withUnsafeMutableBytes({
            gdImageCreateFromPngPtr(Int32($0.count), $0.baseAddress)
        }) else { return nil }
        defer { gdImageDestroy(im) }

        let white = gdImageColorAllocate(im, 255, 255, 255)
        let muted = gdImageColorAllocate(im, 0xAE, 0xAE, 0xB2)

        // Título: hasta 3 líneas, reduciendo el tamaño hasta que quepa.
        guard let (titleSize, lines) = fitTitle(title) else { return nil }
        let lineHeight = titleSize * 1.08
        let subtitleSize = 34.0, gap = 28.0
        let subtitleText = subtitle.map { truncate($0, font: regularFont, px: subtitleSize) }

        var blockHeight = Double(lines.count) * lineHeight
        if subtitleText != nil { blockHeight += gap + subtitleSize }
        let top = (Double(height) - blockHeight) / 2

        for (i, line) in lines.enumerated() {
            let baseline = top + titleSize * 0.9 + Double(i) * lineHeight
            guard draw(line, on: im, color: white, font: boldFont, px: titleSize, y: baseline) else { return nil }
        }
        if let subtitleText {
            let baseline = top + Double(lines.count) * lineHeight + gap + subtitleSize * 0.8
            guard draw(subtitleText, on: im, color: muted, font: regularFont, px: subtitleSize, y: baseline) else { return nil }
        }

        var size: Int32 = 0
        guard let png = gdImagePngPtr(im, &size), size > 0 else { return nil }
        defer { gdFree(png) }
        return Data(bytes: png, count: Int(size))
    }

    // MARK: - Texto

    /// Tamaño (px) y líneas del título. Prueba de mayor a menor; en el mínimo recorta con "…".
    private static func fitTitle(_ title: String) -> (Double, [String])? {
        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        for px in stride(from: 88.0, through: 52.0, by: -4) {
            if let lines = wrap(words, px: px), lines.count <= 3 { return (px, lines) }
        }
        let px = 52.0
        var lines = wrapLoosely(words, px: px)
        if lines.count > 3 {
            lines = Array(lines.prefix(3))
            lines[2] += "…"
        }
        return (px, lines.map { truncate($0, font: boldFont, px: px) })
    }

    /// Reparto voraz por palabras; nil si alguna palabra sola no cabe.
    private static func wrap(_ words: [String], px: Double) -> [String]? {
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if fits(candidate, font: boldFont, px: px) {
                current = candidate
            } else {
                guard !current.isEmpty, fits(word, font: boldFont, px: px) else { return nil }
                lines.append(current)
                current = word
            }
        }
        lines.append(current)
        return lines
    }

    /// Como `wrap`, pero una palabra que no cabe va sola en su línea (luego se recorta).
    private static func wrapLoosely(_ words: [String], px: Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if current.isEmpty || fits(candidate, font: boldFont, px: px) {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        lines.append(current)
        return lines
    }

    /// Quita caracteres del final (y añade "…") hasta que el texto quepa.
    private static func truncate(_ text: String, font: String, px: Double) -> String {
        if fits(text, font: font, px: px) { return text }
        var s = text.hasSuffix("…") ? String(text.dropLast()) : text
        while !s.isEmpty {
            s.removeLast()
            let candidate = s.trimmingCharacters(in: .whitespaces) + "…"
            if fits(candidate, font: font, px: px) { return candidate }
        }
        return "…"
    }

    private static func fits(_ text: String, font: String, px: Double) -> Bool {
        guard let w = textWidth(text, font: font, px: px) else { return false }
        return w <= maxTextWidth
    }

    /// Ancho en px del texto (gd mide sin dibujar si la imagen es nil).
    private static func textWidth(_ text: String, font: String, px: Double) -> Int? {
        var rect = [Int32](repeating: 0, count: 8)
        let error = stringFT(nil, &rect, 0, font, px, 0, text)
        guard error == nil else { return nil }
        return Int(rect[2] - rect[0])
    }

    private static func draw(_ text: String, on im: gdImagePtr, color: Int32, font: String, px: Double, y: Double) -> Bool {
        var rect = [Int32](repeating: 0, count: 8)
        return stringFT(im, &rect, color, font, px, Int32(y.rounded()), text) == nil
    }

    /// gdImageStringFT. Devuelve el mensaje de error de gd, o nil si fue bien.
    /// Tamaño en puntos: gd usa 96 ppp, así que pt = px × 0,75.
    private static func stringFT(_ im: gdImagePtr?, _ rect: inout [Int32], _ color: Int32,
                                 _ font: String, _ px: Double, _ y: Int32, _ text: String) -> String? {
        guard let fontC = strdup(font), let textC = strdup(text) else { return "sin memoria" }
        defer { free(fontC); free(textC) }
        let error = rect.withUnsafeMutableBufferPointer { r in
            gdImageStringFT(im, r.baseAddress, color, fontC, px * 0.75, 0, textX, y, textC)
        }
        return error.map { String(cString: $0) }
    }
}
