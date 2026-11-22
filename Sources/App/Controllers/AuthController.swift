import Vapor
import Fluent
import JWT

/// Login con Sign in with Apple y Google.
///
/// La app obtiene un ID token (JWT) del proveedor y lo envía aquí. El servidor verifica
/// la firma con las claves públicas del proveedor, el emisor, la caducidad y la audiencia
/// (bundle ID / client ID de la app) y, si todo es válido, devuelve un token de sesión
/// propio que la app usa como `Authorization: Bearer` en el resto de la API.
struct AuthController: RouteCollection {
    /// Duración de la sesión; se renueva sola mientras se use.
    static let sessionLifetime: TimeInterval = 30 * 24 * 3600

    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("apple", use: signInWithApple)
        auth.post("google", use: signInWithGoogle)

        let protected = auth.grouped(SessionAuthenticator(), User.guardMiddleware())
        protected.get("me", use: me)
        protected.post("logout", use: logout)
        // Borrar la cuenta (obligatorio en App Store si la app permite crear cuentas).
        protected.delete("me", use: deleteAccount)
    }

    // MARK: - Login

    @Sendable func signInWithApple(req: Request) async throws -> SessionDTO {
        guard let bundleID = Environment.get("APPLE_BUNDLE_ID").nilIfEmpty else {
            throw Abort(.serviceUnavailable, reason: "Sign in with Apple no está configurado.")
        }
        let body = try req.content.decode(SignInRequest.self)
        let token: AppleIdentityToken
        do {
            token = try await req.jwt.apple.verify(body.idToken, applicationIdentifier: bundleID)
        } catch {
            req.logger.info("Token de Apple rechazado: \(error)")
            throw Abort(.unauthorized, reason: "Token de Apple no válido.")
        }
        try checkNonce(expected: body.nonce, inToken: token.nonce)

        // Apple solo envía el nombre a la app la primera vez; la app lo manda en el body.
        let user = try await upsertUser(
            provider: "apple", subject: token.subject.value,
            email: token.email, name: body.name.nilIfEmpty, db: req.db
        )
        return try await startSession(for: user, db: req.db)
    }

    @Sendable func signInWithGoogle(req: Request) async throws -> SessionDTO {
        guard let clientID = Environment.get("GOOGLE_CLIENT_ID").nilIfEmpty else {
            throw Abort(.serviceUnavailable, reason: "Google Sign-In no está configurado.")
        }
        let body = try req.content.decode(SignInRequest.self)
        let token: GoogleIdentityToken
        do {
            token = try await req.jwt.google.verify(body.idToken, applicationIdentifier: clientID)
        } catch {
            req.logger.info("Token de Google rechazado: \(error)")
            throw Abort(.unauthorized, reason: "Token de Google no válido.")
        }
        try checkNonce(expected: body.nonce, inToken: token.nonce)

        let user = try await upsertUser(
            provider: "google", subject: token.subject.value,
            email: token.email, name: token.name ?? body.name.nilIfEmpty, db: req.db
        )
        return try await startSession(for: user, db: req.db)
    }

    // MARK: - Sesión

    @Sendable func me(req: Request) async throws -> UserDTO {
        try UserDTO(try req.auth.require(User.self))
    }

    @Sendable func logout(req: Request) async throws -> HTTPStatus {
        if let bearer = req.headers.bearerAuthorization {
            try await UserSession.query(on: req.db)
                .filter(\.$tokenHash == Tokens.hash(bearer.token)).delete()
        }
        req.auth.logout(User.self)
        return .noContent
    }

    /// Borra el usuario, sus sesiones y todos sus eventos (en cascada).
    @Sendable func deleteAccount(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        try await user.delete(on: req.db)
        return .noContent
    }

    // MARK: - Utilidades

    /// La app genera un nonce aleatorio, pasa su SHA-256 (hex) al proveedor y envía aquí
    /// el nonce en claro. Así un ID token interceptado no se puede reutilizar desde otro sitio.
    private func checkNonce(expected raw: String?, inToken tokenNonce: String?) throws {
        switch (raw.nilIfEmpty, tokenNonce) {
        case (nil, nil):
            return
        case let (raw?, tokenNonce?) where Tokens.constantTimeEquals(Tokens.hash(raw), tokenNonce):
            return
        default:
            throw Abort(.unauthorized, reason: "El nonce no coincide.")
        }
    }

    private func upsertUser(provider: String, subject: String, email: String?, name: String?, db: Database) async throws -> User {
        if let user = try await User.query(on: db)
            .filter(\.$provider == provider).filter(\.$subject == subject).first() {
            if let email, user.email != email { user.email = email }
            if user.name == nil, let name { user.name = name }
            if user.hasChanges { try await user.save(on: db) }
            return user
        }
        let user = User(provider: provider, subject: subject, email: email, name: name)
        try await user.save(on: db)
        return user
    }

    private func startSession(for user: User, db: Database) async throws -> SessionDTO {
        let token = Tokens.make()
        let expiresAt = Date().addingTimeInterval(Self.sessionLifetime)
        try await UserSession(userID: try user.requireID(), tokenHash: Tokens.hash(token), expiresAt: expiresAt).save(on: db)
        // Limpieza oportunista de sesiones caducadas.
        try await UserSession.query(on: db).filter(\.$expiresAt < Date()).delete()
        return SessionDTO(token: token, expiresAt: expiresAt, user: try UserDTO(user))
    }
}

/// Autentica las peticiones con el token de sesión emitido por `/auth/apple` o `/auth/google`.
struct SessionAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        guard bearer.token.count <= 128,
              let session = try await UserSession.query(on: request.db)
                .filter(\.$tokenHash == Tokens.hash(bearer.token))
                .with(\.$user).first(),
              session.expiresAt > Date() else { return }

        // Renovación deslizante: como mucho una escritura al día por sesión.
        let renewed = Date().addingTimeInterval(AuthController.sessionLifetime)
        if renewed.timeIntervalSince(session.expiresAt) > 24 * 3600 {
            session.expiresAt = renewed
            try await session.save(on: request.db)
        }
        request.auth.login(session.user)
    }
}
