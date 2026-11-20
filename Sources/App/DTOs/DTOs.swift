import Vapor

struct CreateEventRequest: Content {
    var name: String
    var date: Date?
    var budget: Double?
}

struct ParticipantRequest: Content {
    var name: String
    var phone: String?
    var family: String?
    var guardianId: UUID?
}

struct ExclusionRequest: Content {
    var giverId: UUID
    var receiverId: UUID
}

struct EventDTO: Content {
    var id: UUID
    var name: String
    var date: Date?
    var budget: Double?
    var status: String
    var participantCount: Int
}

struct ParticipantDTO: Content {
    var id: UUID
    var name: String
    var phone: String?
    var family: String?
    var guardianId: UUID?

    init(_ p: Participant) {
        self.id = p.id!
        self.name = p.name
        self.phone = p.phone
        self.family = p.family
        self.guardianId = p.$guardian.id
    }
}

struct ExclusionDTO: Content {
    var id: UUID
    var giverId: UUID
    var receiverId: UUID
}

struct EventDetailDTO: Content {
    var event: EventDTO
    var participants: [ParticipantDTO]
    var exclusions: [ExclusionDTO]
}

struct DrawResultDTO: Content {
    var status: String
    var assignments: Int
}

/// Enlace listo para compartir desde la app (hoja "Compartir" de iOS).
struct LinkDTO: Content {
    var participantId: UUID
    var name: String
    var url: String
    /// Texto sugerido para el mensaje.
    var message: String
    /// A quién se le envía: el propio participante o, si es un niño, su tutor.
    var deliverToName: String
    var deliverToPhone: String?
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmed, !value.isEmpty else { return nil }
        return value
    }
}
