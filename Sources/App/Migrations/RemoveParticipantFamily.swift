import Fluent

/// Elimina la unidad familiar de los participantes: el sorteo ya no la usa
/// (para evitar que dos personas se toquen se usan las exclusiones).
struct RemoveParticipantFamily: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("participants").deleteField("family").update()
    }

    func revert(on db: Database) async throws {
        try await db.schema("participants").field("family", .string).update()
    }
}
