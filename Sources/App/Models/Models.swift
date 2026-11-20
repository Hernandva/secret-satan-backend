import Fluent
import Vapor

final class Event: Model, @unchecked Sendable {
    static let schema = "events"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @OptionalField(key: "date") var date: Date?
    @OptionalField(key: "budget") var budget: Double?
    /// "draft" (aún sin sortear) o "drawn" (sorteado)
    @Field(key: "status") var status: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, date: Date?, budget: Double?) {
        self.id = id
        self.name = name
        self.date = date
        self.budget = budget
        self.status = "draft"
    }
}

final class Participant: Model, @unchecked Sendable {
    static let schema = "participants"

    @ID(key: .id) var id: UUID?
    @Parent(key: "event_id") var event: Event
    @Field(key: "name") var name: String
    /// Los niños pequeños no tienen teléfono: reciben el enlace a través de su tutor.
    @OptionalField(key: "phone") var phone: String?
    /// Unidad familiar: quienes comparten valor no se tocan entre sí.
    @OptionalField(key: "family") var family: String?
    @OptionalParent(key: "guardian_id") var guardian: Participant?

    init() {}

    init(id: UUID? = nil, eventID: UUID, name: String, phone: String?, family: String?, guardianID: UUID?) {
        self.id = id
        self.$event.id = eventID
        self.name = name
        self.phone = phone
        self.family = family
        self.$guardian.id = guardianID
    }
}

final class Exclusion: Model, @unchecked Sendable {
    static let schema = "exclusions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "event_id") var event: Event
    @Parent(key: "giver_id") var giver: Participant
    @Parent(key: "receiver_id") var receiver: Participant

    init() {}

    init(id: UUID? = nil, eventID: UUID, giverID: UUID, receiverID: UUID) {
        self.id = id
        self.$event.id = eventID
        self.$giver.id = giverID
        self.$receiver.id = receiverID
    }
}

final class Assignment: Model, @unchecked Sendable {
    static let schema = "assignments"

    @ID(key: .id) var id: UUID?
    @Parent(key: "event_id") var event: Event
    @Parent(key: "giver_id") var giver: Participant
    @Parent(key: "receiver_id") var receiver: Participant

    init() {}

    init(id: UUID? = nil, eventID: UUID, giverID: UUID, receiverID: UUID) {
        self.id = id
        self.$event.id = eventID
        self.$giver.id = giverID
        self.$receiver.id = receiverID
    }
}

final class RevealLink: Model, @unchecked Sendable {
    static let schema = "reveal_links"

    @ID(key: .id) var id: UUID?
    @Parent(key: "event_id") var event: Event
    @Parent(key: "giver_id") var giver: Participant
    /// Solo se guarda el hash SHA-256 del token; el token en claro solo existe en el enlace.
    @Field(key: "token_hash") var tokenHash: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @OptionalField(key: "used_at") var usedAt: Date?

    init() {}

    init(id: UUID? = nil, eventID: UUID, giverID: UUID, tokenHash: String) {
        self.id = id
        self.$event.id = eventID
        self.$giver.id = giverID
        self.tokenHash = tokenHash
    }
}
