import Vapor
import Fluent
import FluentSQLiteDriver

public func configure(_ app: Application) async throws {
    guard let token = Environment.get("ADMIN_TOKEN"), token.count >= 16 else {
        fatalError("Define ADMIN_TOKEN (mínimo 16 caracteres) en el entorno.")
    }

    // Fechas en ISO 8601 para la app iOS.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    let dbPath = Environment.get("DATABASE_PATH") ?? "db.sqlite"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)

    app.migrations.add(CreateSchema())
    try await app.autoMigrate()

    try routes(app)
}
