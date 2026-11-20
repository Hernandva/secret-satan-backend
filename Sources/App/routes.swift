import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    // Público: solo se entra con el token del enlace.
    try app.register(collection: RevealController())

    // Organizador: requiere ADMIN_TOKEN como Bearer.
    let admin = app.grouped(AdminAuthMiddleware())
    try admin.register(collection: EventController())
}
