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
    }

    @Sendable func confirm(req: Request) async throws -> Response {
        let token = try token(req)
        guard let link = try await findLink(token, db: req.db) else { return invalid() }
        if link.usedAt != nil { return alreadyUsed() }
        let giver = try await link.$giver.get(on: req.db)
        return page("Amigo secreto", """
            <h1>Hola, \(esc(giver.name))</h1>
            <p>Tu amigo secreto está listo. Ábrelo cuando estés solo: <strong>este enlace solo se puede ver una vez.</strong></p>
            <form method="post" action="/r/\(token)"><button type="submit">Mostrar mi amigo secreto</button></form>
            """)
    }

    @Sendable func reveal(req: Request) async throws -> Response {
        let token = try token(req)
        guard let link = try await findLink(token, db: req.db) else { return invalid() }
        if link.usedAt != nil { return alreadyUsed() }

        let giverID = link.$giver.id
        guard let assignment = try await Assignment.query(on: req.db)
            .filter(\.$giver.$id == giverID).with(\.$receiver).first() else {
            return page("Sin sorteo", "<h1>Todavía no hay sorteo</h1><p>Pide al organizador que lo repita.</p>")
        }
        let giver = try await link.$giver.get(on: req.db)

        link.usedAt = Date()
        try await link.save(on: req.db)

        return page("Tu amigo secreto", """
            <p class="muted">\(esc(giver.name)), tu amigo secreto es</p>
            <h1 class="big">\(esc(assignment.receiver.name))</h1>
            <p class="muted">Este enlace ya no se puede volver a abrir. Si lo cerraste sin querer, pide uno nuevo al organizador.</p>
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
        page("Enlace no válido", "<h1>Enlace no válido</h1><p>Pide al organizador que te envíe uno nuevo.</p>", status: .notFound)
    }

    private func alreadyUsed() -> Response {
        page("Enlace usado", "<h1>Este enlace ya se usó</h1><p>Si lo cerraste sin querer, pide al organizador que te envíe uno nuevo.</p>", status: .gone)
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func page(_ title: String, _ body: String, status: HTTPStatus = .ok) -> Response {
        let html = """
        <!doctype html>
        <html lang="es"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex, nofollow">
        <title>\(esc(title))</title>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center;
                 font-family: Inter, -apple-system, system-ui, sans-serif;
                 background: Canvas; color: CanvasText; }
          main { max-width: 420px; padding: 32px 24px; text-align: center; }
          h1 { font-size: 24px; margin: 0 0 12px; }
          h1.big { font-size: 40px; margin: 16px 0 24px; }
          p { line-height: 1.5; margin: 0 0 20px; }
          .muted { opacity: .65; }
          button { font: inherit; font-weight: 600; padding: 14px 24px; border-radius: 12px;
                   border: 0; background: CanvasText; color: Canvas; cursor: pointer; }
        </style></head>
        <body><main>\(body)</main></body></html>
        """
        var headers = HTTPHeaders()
        headers.contentType = .html
        headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return Response(status: status, headers: headers, body: .init(string: html))
    }
}
