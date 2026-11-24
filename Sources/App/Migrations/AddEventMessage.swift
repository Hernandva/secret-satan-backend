import Fluent

/// Mensaje opcional del organizador que se muestra al pie de la web del enlace.
struct AddEventMessage: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("events").field("message", .string).update()
    }

    func revert(on db: Database) async throws {
        try await db.schema("events").deleteField("message").update()
    }
}
