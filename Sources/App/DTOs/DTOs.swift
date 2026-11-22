import Vapor

// MARK: - Auth

/// Body de `POST /auth/apple` y `POST /auth/google`.
struct SignInRequest: Content {
    /// ID token (JWT) que la app recibe de Apple (`identityToken`) o Google (`idToken`).
    var idToken: String
    /// Nonce en claro; el token debe llevar su SHA-256 en hex. Opcional pero recomendado.
    var nonce: String?
    /// Nombre a mostrar (Apple solo lo entrega a la app en el primer login).
    var name: String?
}

struct UserDTO: Content {
    var id: UUID
    var provider: String
    var email: String?
    var name: String?

    init(_ u: User) throws {
        self.id = try u.requireID()
        self.provider = u.provider
        self.email = u.email
        self.name = u.name
    }
}

struct SessionDTO: Content {
    /// Token de sesión: enviarlo como `Authorization: Bearer <token>`.
    var token: String
    var expiresAt: Date
    var user: UserDTO
}

// MARK: - Eventos

struct CreateEventRequest: Content {
    var name: String
    var date: Date?
    var budget: Double?
}

/// Body de `PATCH /events/:id`. Solo cambia lo que se envía:
/// - campo ausente → se deja como está
/// - `"date": null` → se quita la fecha
struct UpdateEventRequest: Content {
    var name: String?
    var date: Date?
    /// true si el JSON incluía la clave `date` (aunque fuera null).
    var hasDate: Bool

    enum CodingKeys: String, CodingKey { case name, date }

    init(name: String? = nil, date: Date? = nil, hasDate: Bool = false) {
        self.name = name
        self.date = date
        self.hasDate = hasDate || date != nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        hasDate = c.contains(.date)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        if hasDate { try c.encode(date, forKey: .date) }
    }
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
