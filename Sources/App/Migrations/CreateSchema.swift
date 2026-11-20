import Fluent

struct CreateSchema: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("events")
            .id()
            .field("name", .string, .required)
            .field("date", .datetime)
            .field("budget", .double)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .create()

        try await db.schema("participants")
            .id()
            .field("event_id", .uuid, .required, .references("events", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("phone", .string)
            .field("family", .string)
            .field("guardian_id", .uuid, .references("participants", "id", onDelete: .setNull))
            .create()

        try await db.schema("exclusions")
            .id()
            .field("event_id", .uuid, .required, .references("events", "id", onDelete: .cascade))
            .field("giver_id", .uuid, .required, .references("participants", "id", onDelete: .cascade))
            .field("receiver_id", .uuid, .required, .references("participants", "id", onDelete: .cascade))
            .unique(on: "giver_id", "receiver_id")
            .create()

        try await db.schema("assignments")
            .id()
            .field("event_id", .uuid, .required, .references("events", "id", onDelete: .cascade))
            .field("giver_id", .uuid, .required, .references("participants", "id", onDelete: .cascade))
            .field("receiver_id", .uuid, .required, .references("participants", "id", onDelete: .cascade))
            .unique(on: "giver_id")
            .create()

        try await db.schema("reveal_links")
            .id()
            .field("event_id", .uuid, .required, .references("events", "id", onDelete: .cascade))
            .field("giver_id", .uuid, .required, .references("participants", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("created_at", .datetime)
            .field("used_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema("reveal_links").delete()
        try await db.schema("assignments").delete()
        try await db.schema("exclusions").delete()
        try await db.schema("participants").delete()
        try await db.schema("events").delete()
    }
}
