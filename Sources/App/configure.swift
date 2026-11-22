import Vapor
import Fluent
import FluentSQLiteDriver
import JWT

extension Environment {
    /// URL pública del servidor (enlaces que se envían y URLs absolutas de la vista previa).
    static var baseURL: String {
        (Environment.get("BASE_URL") ?? "https://secretsanta.hdvillamil.dev")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

public func configure(_ app: Application) async throws {
    let appleBundleID = Environment.get("APPLE_BUNDLE_ID").nilIfEmpty
    let googleClientID = Environment.get("GOOGLE_CLIENT_ID").nilIfEmpty
    guard appleBundleID != nil || googleClientID != nil else {
        fatalError("Define APPLE_BUNDLE_ID y/o GOOGLE_CLIENT_ID en el entorno para el login.")
    }
    // Audiencia esperada en los ID tokens (además se pasa explícita en cada verificación).
    app.jwt.apple.applicationIdentifier = appleBundleID
    app.jwt.google.applicationIdentifier = googleClientID

    // Fechas en ISO 8601 para la app iOS.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    let dbPath = Environment.get("DATABASE_PATH") ?? "db.sqlite"
    app.databases.use(.sqlite(dbPath == ":memory:" ? .memory : .file(dbPath)), as: .sqlite)

    app.migrations.add(CreateSchema())
    app.migrations.add(AddUsers())
    app.migrations.add(RemoveParticipantFamily())
    try await app.autoMigrate()

    try routes(app)
}
