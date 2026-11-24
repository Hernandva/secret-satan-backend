import Vapor
import Fluent

/// Páginas públicas de los enlaces de un solo uso.
///
/// GET solo muestra un botón y NO consume el enlace: WhatsApp, iMessage o Telegram
/// piden la URL para generar vistas previas y quemarían el enlace antes de que lo abra la persona.
/// El POST (al pulsar el botón) es lo que consume el enlace y muestra el resultado.
struct RevealController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("r", ":token", use: confirm)
        routes.post("r", ":token", use: reveal)
        routes.get("og.png", use: genericImage)
        routes.get("og", ":image", use: eventImage)
    }

    // MARK: - Imagen de la vista previa (og:image)

    /// Genérica: para enlaces caducados o no válidos.
    @Sendable func genericImage(req: Request) async throws -> Response {
        pngResponse(OGRenderer.render(title: "Amigo invisible", subtitle: "Descubre a quién le haces el regalo."))
    }

    /// Por evento: `/og/<id del evento>.png`, con el nombre y la fecha del evento.
    /// Se dibuja al pedirla (WhatsApp la pide al crear la vista previa); no se guarda.
    @Sendable func eventImage(req: Request) async throws -> Response {
        guard let file = req.parameters.get("image"), file.hasSuffix(".png"),
              let id = UUID(uuidString: String(file.dropLast(4))),
              let event = try await Event.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return pngResponse(OGRenderer.render(title: event.name, subtitle: event.formattedDate))
    }

    /// URL absoluta de la imagen de un evento. `v` cambia con el nombre y la fecha,
    /// así los enlaces nuevos no reutilizan una imagen antigua que esté en caché.
    private func imageURL(for event: Event) throws -> String {
        let version = Tokens.hash(event.label).prefix(8)
        return "\(Environment.baseURL)/og/\(try event.requireID().uuidString.lowercased()).png?v=\(version)"
    }

    private func pngResponse(_ png: Data) -> Response {
        var headers = HTTPHeaders()
        headers.contentType = .png
        headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=86400")
        return Response(status: .ok, headers: headers, body: .init(data: png))
    }

    @Sendable func confirm(req: Request) async throws -> Response {
        let token = try token(req)
        guard let link = try await findLink(token, db: req.db) else { return invalid() }
        if link.usedAt != nil { return alreadyUsed() }
        let giver = try await link.$giver.get(on: req.db)
        let event = try await link.$event.get(on: req.db)
        // La vista previa la ve cualquiera en el chat: solo el evento, nunca nombres de personas.
        return page("Amigo invisible", eyebrow: event.label, footer: event.message, previewTitle: event.label,
                    previewImage: try imageURL(for: event), """
            <h1>Hola, \(esc(giver.name))</h1>
            <p class="lead">Pulsa «Revelar» para ver el nombre de tu amigo invisible. Que no se entere nadie.</p>
            <form method="post" action="/r/\(token)"><button type="submit" class="btn">Revelar</button></form>
            <p class="note">Este enlace solo se puede abrir una vez.</p>
            """)
    }

    @Sendable func reveal(req: Request) async throws -> Response {
        let token = try token(req)
        guard let link = try await findLink(token, db: req.db) else { return invalid() }
        if link.usedAt != nil { return alreadyUsed() }

        let giverID = link.$giver.id
        let event = try await link.$event.get(on: req.db)
        guard let assignment = try await Assignment.query(on: req.db)
            .filter(\.$giver.$id == giverID).with(\.$receiver).first() else {
            return page("Sin sorteo", eyebrow: event.label, footer: event.message, """
                <h1>Todavía no hay sorteo</h1>
                <p class="lead">Pide al organizador que lo repita.</p>
                """)
        }

        link.usedAt = Date()
        try await link.save(on: req.db)

        return page("Tu amigo invisible", eyebrow: event.label, footer: event.message, """
            <p class="lead">Le haces el regalo a</p>
            <h1 class="name" id="name">\(esc(assignment.receiver.name))</h1>
            <p class="lead">Es un secreto. Feliz Navidad.</p>
            <div><button type="button" class="btn btn-outline" id="toggle" aria-controls="name">Ocultar</button></div>
            <p class="note">Este enlace ya no se puede volver a abrir. Si lo cierras, pide uno nuevo al organizador.</p>
            <script>
              (function () {
                var b = document.getElementById("toggle"), n = document.getElementById("name");
                b.addEventListener("click", function () {
                  var hidden = n.classList.toggle("hidden");
                  b.textContent = hidden ? "Mostrar" : "Ocultar";
                });
              })();
            </script>
            """)
    }

    // MARK: - Utilidades

    private func token(_ req: Request) throws -> String {
        guard let t = req.parameters.get("token"), t.count <= 128,
              t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw Abort(.notFound)
        }
        return t
    }

    private func findLink(_ token: String, db: Database) async throws -> RevealLink? {
        try await RevealLink.query(on: db).filter(\.$tokenHash == Tokens.hash(token)).first()
    }

    private func invalid() -> Response {
        page("Enlace no válido", """
            <h1>Enlace no válido</h1>
            <p class="lead">Pide al organizador que te envíe uno nuevo.</p>
            """, status: .notFound)
    }

    private func alreadyUsed() -> Response {
        page("Enlace usado", """
            <h1>Este enlace ya se usó</h1>
            <p class="lead">Si lo cerraste sin querer, pide al organizador que te envíe uno nuevo.</p>
            """, status: .gone)
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Plantilla

    /// Copos de nieve decorativos: (izquierda %, arriba %, tamaño px, opacidad, grosor de trazo).
    private static let snowflakes: [(Int, Int, Int, Double, Double)] = [
        (6, 14, 14, 0.5, 1), (14, 62, 10, 0.4, 1), (30, 8, 18, 0.35, 0.9), (44, 82, 12, 0.45, 1),
        (58, 12, 16, 0.4, 1), (70, 70, 10, 0.35, 1), (82, 20, 20, 0.3, 0.8), (91, 58, 12, 0.5, 1),
        (4, 86, 14, 0.35, 1), (96, 90, 10, 0.4, 1),
    ]

    private static let snowHTML: String = snowflakes.map { left, top, size, opacity, stroke in
        """
        <svg class="flake" width="\(size)" height="\(size)" viewBox="0 0 12 12" fill="none" stroke="#FFFFFF" stroke-width="\(stroke)" stroke-linecap="round" aria-hidden="true" style="left:\(left)%;top:\(top)%;opacity:\(opacity)"><path d="M6 1v10M1.5 3.5l9 5M1.5 8.5l9-5"/></svg>
        """
    }.joined(separator: "\n")

    /// Luces del árbol: repartidas por las tres guirnaldas (curvas Q del SVG), alternando amarillo,
    /// azul y rojo, cada una con su ritmo para que parpadeen como un árbol de verdad.
    private static let lightsSVG: String = {
        let garlands: [(p0: (Double, Double), c: (Double, Double), p2: (Double, Double))] = [
            ((118, 122), (160, 136), (202, 122)),
            ((102, 190), (160, 208), (218, 190)),
            ((82, 268), (160, 290), (238, 268)),
        ]
        let perGarland = [3, 5, 7]
        let colors = ["#FFD60A", "#0A84FF", "#FF453A"]   // amarillo, azul, rojo
        let durations = [1.6, 2.3, 1.9, 2.8, 1.4, 2.1, 2.6]
        var out: [String] = []
        var n = 0
        for (g, garland) in garlands.enumerated() {
            let count = perGarland[g]
            for i in 0..<count {
                let t = (Double(i) + 0.5) / Double(count)
                let u = 1 - t
                let x = u * u * garland.p0.0 + 2 * u * t * garland.c.0 + t * t * garland.p2.0
                let y = u * u * garland.p0.1 + 2 * u * t * garland.c.1 + t * t * garland.p2.1 + 1.5
                let color = colors[n % 3]
                let duration = durations[n % durations.count]
                let delay = Double((n * 7) % 11) / 10
                let f = { (v: Double) in String(format: "%.1f", v) }
                out.append("<g class=\"light\" style=\"color:\(color);animation-duration:\(f(duration))s;animation-delay:-\(f(delay))s\" stroke=\"none\" fill=\"currentColor\"><circle cx=\"\(f(x))\" cy=\"\(f(y))\" r=\"10\" opacity=\"0.3\"/><circle cx=\"\(f(x))\" cy=\"\(f(y))\" r=\"4.5\"/></g>")
                n += 1
            }
        }
        return out.joined(separator: "\n          ")
    }()

    private static let treeSVG = """
        <svg viewBox="0 0 320 360" width="320" role="img" aria-label="Árbol de Navidad con luces y regalos" fill="none" stroke="#FFFFFF" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round">
          <polygon points="160,14 165.3,28.7 180.9,29.2 168.6,38.8 172.9,53.8 160,45 147.1,53.8 151.4,38.8 139.1,29.2 154.7,28.7" fill="#FFFFFF"/>
          <polygon points="160,170 40,300 280,300" fill="#000000"/>
          <polygon points="160,110 65,220 255,220" fill="#000000"/>
          <polygon points="160,66 90,150 230,150" fill="#000000"/>
          <rect x="146" y="300" width="28" height="36" fill="#000000"/>
          <path d="M118 122 Q160 136 202 122"/>
          <path d="M102 190 Q160 208 218 190"/>
          <path d="M82 268 Q160 290 238 268"/>
          \(lightsSVG)
          <path d="M60 336 H260"/>
          <rect x="84" y="310" width="36" height="26" fill="#000000"/>
          <path d="M102 310 V336"/>
          <rect x="200" y="316" width="28" height="20" fill="#000000"/>
          <path d="M214 316 V336"/>
        </svg>
        """

    /// Pie de página: el mensaje del evento si tiene, si no una cita de Navidad.
    private func footerHTML(_ message: String?) -> String {
        if let message {
            return """
                <figure class="quote">
                  <blockquote class="custom">\(esc(message))</blockquote>
                </figure>
                """
        }
        return """
            <figure class="quote">
              <blockquote>«Es bueno ser niños a veces, y nunca mejor que en Navidad.»</blockquote>
              <figcaption>Charles Dickens, <cite>Canción de Navidad</cite></figcaption>
            </figure>
            """
    }

    private func page(_ title: String, eyebrow: String? = nil, footer: String? = nil, previewTitle: String = "Amigo invisible",
                      previewImage: String? = nil, _ body: String, status: HTTPStatus = .ok) -> Response {
        let eyebrowHTML = eyebrow.map { "<div class=\"eyebrow\">\(esc($0))</div>" } ?? ""
        let previewDescription = "Descubre a quién le haces el regalo. El enlace solo se puede abrir una vez."
        let ogImage = previewImage ?? "\(Environment.baseURL)/og.png"
        let html = """
        <!doctype html>
        <html lang="es"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex, nofollow">
        <meta name="theme-color" content="#000000">
        <meta name="description" content="\(esc(previewDescription))">
        <meta property="og:type" content="website">
        <meta property="og:site_name" content="Amigo invisible">
        <meta property="og:locale" content="es_ES">
        <meta property="og:title" content="\(esc(previewTitle))">
        <meta property="og:description" content="\(esc(previewDescription))">
        <meta property="og:image" content="\(esc(ogImage))">
        <meta property="og:image:type" content="image/png">
        <meta property="og:image:width" content="1200">
        <meta property="og:image:height" content="630">
        <meta property="og:image:alt" content="\(esc(previewTitle)), junto a un árbol de Navidad con regalos">
        <meta name="twitter:card" content="summary_large_image">
        <title>\(esc(title))</title>
        <style>
          :root { color-scheme: dark; --bg: #000000; --fg: #FFFFFF; --muted: #AEAEB2; }
          * { box-sizing: border-box; }
          html, body { margin: 0; background: var(--bg); color: var(--fg); }
          body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif;
                 -webkit-font-smoothing: antialiased; }
          .page { position: relative; overflow: hidden; min-height: 100vh; min-height: 100dvh;
                  display: flex; flex-direction: column; }
          .flake { position: absolute; pointer-events: none; }
          .content { position: relative; flex: 1 1 0; display: flex; align-items: center; justify-content: center;
                     padding: 64px 48px 48px; }
          .wrap { width: 100%; max-width: 1040px; display: flex; flex-wrap: wrap; align-items: center;
                  justify-content: center; gap: 48px; }
          .text { flex: 1 1 360px; min-width: 0; display: flex; flex-direction: column; gap: 24px;
                  align-items: center; text-align: center; }
          .art { flex: 0 1 320px; min-width: 0; display: flex; justify-content: center; }
          .art svg { max-width: 100%; height: auto; }
          .light { animation: twinkle 2s ease-in-out infinite; }
          @keyframes twinkle { 0%, 100% { opacity: 1; } 50% { opacity: .15; } }
          @media (prefers-reduced-motion: reduce) { .light { animation: none; } }
          .quote { position: relative; margin: 0; padding: 0 48px 40px; text-align: center; color: var(--muted); }
          .quote blockquote { margin: 0 auto 8px; max-width: 560px; font-size: 17px; line-height: 1.5;
                              font-style: italic; text-wrap: balance; }
          .quote blockquote.custom { white-space: pre-line; overflow-wrap: anywhere; }
          .quote figcaption { font-size: 13px; letter-spacing: .02em; }
          .eyebrow { font-size: 13px; line-height: 18px; font-weight: 600; letter-spacing: .08em;
                     text-transform: uppercase; color: var(--muted); }
          h1 { margin: 0; font-size: clamp(40px, 6vw, 72px); line-height: 1.02; font-weight: 700;
               letter-spacing: -.02em; text-wrap: balance; overflow-wrap: anywhere; }
          h1.name { font-size: clamp(48px, 8vw, 96px); line-height: 1; letter-spacing: -.03em;
                    transition: filter .2s ease; }
          h1.name.hidden { filter: blur(24px); user-select: none; }
          .lead { margin: 0; max-width: 440px; font-size: 19px; line-height: 1.5; color: var(--muted); text-wrap: pretty; }
          .lead strong { color: var(--fg); font-weight: 600; }
          .note { margin: 0; max-width: 440px; font-size: 15px; line-height: 1.5; color: var(--muted); }
          form { margin: 0; display: flex; justify-content: center; }
          .btn { font: inherit; height: 56px; padding: 0 40px; border: 1px solid var(--fg); border-radius: 999px;
                 background: var(--fg); color: var(--bg); font-size: 19px; font-weight: 600; cursor: pointer; }
          .btn-outline { background: transparent; color: var(--fg); }
          .btn:focus-visible { outline: 2px solid var(--fg); outline-offset: 3px; }
          @media (max-width: 640px) {
            .content { padding: 48px 16px 40px; align-items: flex-start; }
            .quote { padding: 0 16px 32px; }
            .wrap { gap: 40px; }
            .text { flex-basis: 100%; }
            .art svg { width: 220px; }
            .btn { width: 100%; }
            form { display: block; }
            .text > form, .text > div { align-self: stretch; }
          }
        </style></head>
        <body><div class="page">
        \(Self.snowHTML)
        <main class="content"><div class="wrap">
          <div class="text">\(eyebrowHTML)\(body)</div>
          <div class="art">\(Self.treeSVG)</div>
        </div></main>
        \(footerHTML(footer))
        </div></body></html>
        """
        var headers = HTTPHeaders()
        headers.contentType = .html
        headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return Response(status: status, headers: headers, body: .init(string: html))
    }
}
