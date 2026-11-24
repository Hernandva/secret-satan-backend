import Fluent
import Vapor

/// Organizador que ha iniciado sesión con Apple o Google.
final class User: Model, Authenticatable, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    /// "apple" o "google"
    @Field(key: "provider") var provider: String
    /// Identificador estable del usuario en el proveedor (claim `sub`).
    @Field(key: "subject") var subject: String
    @OptionalField(key: "email") var email: String?
    @OptionalField(key: "name") var name: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, provider: String, subject: String, email: String?, name: String?) {
        self.id = id
        self.provider = provider
        self.subject = subject
        self.email = email
        self.name = name
    }
}

/// Sesión propia del servidor, emitida tras verificar el token de Apple o Google.
final class UserSession: Model, @unchecked Sendable {
    static let schema = "user_sessions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    /// Solo se guarda el hash SHA-256 del token de sesión.
    @Field(key: "token_hash") var tokenHash: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Field(key: "expires_at") var expiresAt: Date

    init() {}

    init(id: UUID? = nil, userID: UUID, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.$user.id = userID
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }
}

final class Event: Model, @unchecked Sendable {
    static let schema = "events"

    @ID(key: .id) var id: UUID?
    /// Organizador dueño del evento. Los eventos creados antes del login no tienen dueño.
    @OptionalParent(key: "owner_id") var owner: User?
    @Field(key: "name") var name: String
    @OptionalField(key: "date") var date: Date?
    @OptionalField(key: "budget") var budget: Double?
    /// "draft" (aún sin sortear) o "drawn" (sorteado)
    @Field(key: "status") var status: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, ownerID: UUID, name: String, date: Date?, budget: Double?) {
        self.id = id
        self.$owner.id = ownerID
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
    @OptionalParent(key: "guardian_id") var guardian: Participant?

    init() {}

    init(id: UUID? = nil, eventID: UUID, name: String, phone: String?, guardianID: UUID?) {
        self.id = id
        self.$event.id = eventID
        self.name = name
        self.phone = phone
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

extension Event {
    /// "24 de diciembre de 2026", o nil si el evento no tiene fecha.
    var formattedDate: String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "d 'de' MMMM 'de' y"
        return f.string(from: date)
    }

    /// "Nombre del evento · 24 de diciembre de 2026" (sin fecha si el evento no la tiene).
    var label: String {
        formattedDate.map { "\(name) · \($0)" } ?? name
    }
}
