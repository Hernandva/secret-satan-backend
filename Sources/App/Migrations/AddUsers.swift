import Fluent

/// Usuarios (login con Apple/Google), sesiones y dueño de cada evento.
struct AddUsers: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("users")
            .id()
            .field("provider", .string, .required)
            .field("subject", .string, .required)
            .field("email", .string)
            .field("name", .string)
            .field("created_at", .datetime)
            .unique(on: "provider", "subject")
            .create()

        try await db.schema("user_sessions")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("created_at", .datetime)
            .field("expires_at", .datetime, .required)
            .unique(on: "token_hash")
            .create()

        // Nullable: los eventos anteriores al login quedan sin dueño (no accesibles por la API).
        try await db.schema("events")
            .field("owner_id", .uuid, .references("users", "id", onDelete: .cascade))
            .update()
    }

    func revert(on db: Database) async throws {
        try await db.schema("events").deleteField("owner_id").update()
        try await db.schema("user_sessions").delete()
        try await db.schema("users").delete()
    }
}
