import Vapor

/// Protege las rutas del organizador con un token Bearer (ADMIN_TOKEN).
struct AdminAuthMiddleware: AsyncMiddleware {
    let token: String

    init() {
        self.token = Environment.get("ADMIN_TOKEN") ?? ""
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard !token.isEmpty,
              let bearer = request.headers.bearerAuthorization,
              Tokens.constantTimeEquals(bearer.token, token) else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }
}
