import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    // Público: solo se entra con el token del enlace.
    try app.register(collection: RevealController())

    // Login con Apple / Google → token de sesión.
    try app.register(collection: AuthController())

    // Organizador: requiere el token de sesión como Bearer.
    let organizer = app.grouped(SessionAuthenticator(), User.guardMiddleware())
    try organizer.register(collection: EventController())
}
