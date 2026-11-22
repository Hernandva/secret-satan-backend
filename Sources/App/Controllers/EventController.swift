import Vapor
import Fluent

struct EventController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")
        events.get(use: list)
        events.post(use: create)

        events.group(":eventID") { e in
            e.get(use: detail)
            e.delete(use: delete)

            e.post("participants", use: addParticipant)
            e.put("participants", ":participantID", use: updateParticipant)
            e.delete("participants", ":participantID", use: deleteParticipant)

            e.post("exclusions", use: addExclusion)
            e.delete("exclusions", ":exclusionID", use: deleteExclusion)

            e.post("draw", use: draw)

            // Genera (o regenera) los enlaces de un solo uso.
            e.post("links", use: allLinks)
            e.post("participants", ":participantID", "link", use: oneLink)
        }
    }

    // MARK: - Eventos

    @Sendable func list(req: Request) async throws -> [EventDTO] {
        let userID = try req.auth.require(User.self).requireID()
        let events = try await Event.query(on: req.db)
            .filter(\.$owner.$id == userID).sort(\.$createdAt, .descending).all()
        return try await events.asyncMap { try await eventDTO($0, db: req.db) }
    }

    @Sendable func create(req: Request) async throws -> EventDTO {
        let body = try req.content.decode(CreateEventRequest.self)
        guard !body.name.trimmed.isEmpty else { throw Abort(.badRequest, reason: "El nombre es obligatorio.") }
        let userID = try req.auth.require(User.self).requireID()
        let event = Event(ownerID: userID, name: body.name.trimmed, date: body.date, budget: body.budget)
        try await event.save(on: req.db)
        return try await eventDTO(event, db: req.db)
    }

    @Sendable func detail(req: Request) async throws -> EventDetailDTO {
        let event = try await findEvent(req)
        let id = try event.requireID()
        let participants = try await Participant.query(on: req.db)
            .filter(\.$event.$id == id).sort(\.$name).all()
        let exclusions = try await Exclusion.query(on: req.db).filter(\.$event.$id == id).all()
        return EventDetailDTO(
            event: try await eventDTO(event, db: req.db),
            participants: participants.map(ParticipantDTO.init),
            exclusions: try exclusions.map {
                ExclusionDTO(id: try $0.requireID(), giverId: $0.$giver.id, receiverId: $0.$receiver.id)
            }
        )
    }

    @Sendable func delete(req: Request) async throws -> HTTPStatus {
        let event = try await findEvent(req)
        try await event.delete(on: req.db)
        return .noContent
    }

    // MARK: - Participantes

    @Sendable func addParticipant(req: Request) async throws -> ParticipantDTO {
        let event = try await findEvent(req)
        let eventID = try event.requireID()
        guard event.status == "draft" else {
            throw Abort(.conflict, reason: "El sorteo ya se hizo; no se pueden añadir participantes. Repite el sorteo si hace falta.")
        }
        let body = try req.content.decode(ParticipantRequest.self)
        try await validate(body, eventID: eventID, selfID: nil, db: req.db)
        let p = Participant(
            eventID: eventID,
            name: body.name.trimmed,
            phone: body.phone.nilIfEmpty,
            family: body.family.nilIfEmpty,
            guardianID: body.guardianId
        )
        try await p.save(on: req.db)
        return ParticipantDTO(p)
    }

    @Sendable func updateParticipant(req: Request) async throws -> ParticipantDTO {
        let event = try await findEvent(req)
        let eventID = try event.requireID()
        let p = try await findParticipant(req, eventID: eventID)
        let body = try req.content.decode(ParticipantRequest.self)
        try await validate(body, eventID: eventID, selfID: try p.requireID(), db: req.db)
        p.name = body.name.trimmed
        p.phone = body.phone.nilIfEmpty
        p.family = body.family.nilIfEmpty
        p.$guardian.id = body.guardianId
        try await p.save(on: req.db)
        return ParticipantDTO(p)
    }

    @Sendable func deleteParticipant(req: Request) async throws -> HTTPStatus {
        let event = try await findEvent(req)
        guard event.status == "draft" else {
            throw Abort(.conflict, reason: "El sorteo ya se hizo; no se pueden quitar participantes.")
        }
        let p = try await findParticipant(req, eventID: try event.requireID())
        try await p.delete(on: req.db)
        return .noContent
    }

    // MARK: - Exclusiones

    /// Crea la exclusión en ambos sentidos (A no regala a B y B no regala a A).
    @Sendable func addExclusion(req: Request) async throws -> [ExclusionDTO] {
        let event = try await findEvent(req)
        let eventID = try event.requireID()
        guard event.status == "draft" else {
            throw Abort(.conflict, reason: "El sorteo ya se hizo; no se pueden cambiar las exclusiones.")
        }
        let body = try req.content.decode(ExclusionRequest.self)
        guard body.giverId != body.receiverId else { throw Abort(.badRequest, reason: "Elige dos personas distintas.") }

        let ids = [body.giverId, body.receiverId]
        let count = try await Participant.query(on: req.db)
            .filter(\.$event.$id == eventID).filter(\.$id ~~ ids).count()
        guard count == 2 else { throw Abort(.badRequest, reason: "Los participantes deben ser del evento.") }

        var created: [ExclusionDTO] = []
        for (g, r) in [(body.giverId, body.receiverId), (body.receiverId, body.giverId)] {
            let exists = try await Exclusion.query(on: req.db)
                .filter(\.$giver.$id == g).filter(\.$receiver.$id == r).count() > 0
            if exists { continue }
            let x = Exclusion(eventID: eventID, giverID: g, receiverID: r)
            try await x.save(on: req.db)
            created.append(ExclusionDTO(id: try x.requireID(), giverId: g, receiverId: r))
        }
        return created
    }

    @Sendable func deleteExclusion(req: Request) async throws -> HTTPStatus {
        let event = try await findEvent(req)
        guard event.status == "draft" else {
            throw Abort(.conflict, reason: "El sorteo ya se hizo; no se pueden cambiar las exclusiones.")
        }
        guard let x = try await Exclusion.find(req.parameters.get("exclusionID"), on: req.db),
              x.$event.id == (try event.requireID()) else { throw Abort(.notFound) }
        // Quita también el sentido contrario.
        try await Exclusion.query(on: req.db)
            .filter(\.$giver.$id == x.$receiver.id).filter(\.$receiver.$id == x.$giver.id).delete()
        try await x.delete(on: req.db)
        return .noContent
    }

    // MARK: - Sorteo

    @Sendable func draw(req: Request) async throws -> DrawResultDTO {
        let event = try await findEvent(req)
        let eventID = try event.requireID()
        let redraw = (try? req.query.get(Bool.self, at: "redraw")) ?? false
        if event.status == "drawn" && !redraw {
            throw Abort(.conflict, reason: "Este evento ya está sorteado. Usa ?redraw=true para repetirlo (invalida los enlaces anteriores).")
        }

        let participants = try await Participant.query(on: req.db).filter(\.$event.$id == eventID).all()
        let exclusions = try await Exclusion.query(on: req.db).filter(\.$event.$id == eventID).all()
        let forbidden = Set(exclusions.map { DrawService.Pair(giver: $0.$giver.id, receiver: $0.$receiver.id) })
        let people = try participants.map { DrawService.Person(id: try $0.requireID(), family: $0.family) }

        let result: [UUID: UUID]
        do {
            result = try DrawService.draw(people: people, forbidden: forbidden)
        } catch DrawError.notEnoughPeople {
            throw Abort(.unprocessableEntity, reason: "Hacen falta al menos 2 participantes.")
        } catch {
            throw Abort(.unprocessableEntity, reason: "No existe un sorteo válido con estas restricciones. Prueba a quitar alguna exclusión.")
        }

        try await req.db.transaction { db in
            try await Assignment.query(on: db).filter(\.$event.$id == eventID).delete()
            try await RevealLink.query(on: db).filter(\.$event.$id == eventID).delete()
            for (giver, receiver) in result {
                try await Assignment(eventID: eventID, giverID: giver, receiverID: receiver).save(on: db)
            }
            event.status = "drawn"
            try await event.save(on: db)
        }
        return DrawResultDTO(status: "drawn", assignments: result.count)
    }

    // MARK: - Enlaces

    @Sendable func allLinks(req: Request) async throws -> [LinkDTO] {
        let event = try await findEvent(req)
        try requireDrawn(event)
        let participants = try await Participant.query(on: req.db)
            .filter(\.$event.$id == (try event.requireID())).sort(\.$name).all()
        var links: [LinkDTO] = []
        for p in participants {
            links.append(try await makeLink(for: p, event: event, db: req.db))
        }
        return links
    }

    @Sendable func oneLink(req: Request) async throws -> LinkDTO {
        let event = try await findEvent(req)
        try requireDrawn(event)
        let p = try await findParticipant(req, eventID: try event.requireID())
        return try await makeLink(for: p, event: event, db: req.db)
    }

    private func requireDrawn(_ event: Event) throws {
        guard event.status == "drawn" else {
            throw Abort(.conflict, reason: "Haz el sorteo antes de generar enlaces.")
        }
    }

    private func makeLink(for p: Participant, event: Event, db: Database) async throws -> LinkDTO {
        let pid = try p.requireID()
        // Un enlace nuevo invalida el anterior (usado o no).
        try await RevealLink.query(on: db).filter(\.$giver.$id == pid).delete()
        let token = Tokens.make()
        try await RevealLink(eventID: try event.requireID(), giverID: pid, tokenHash: Tokens.hash(token)).save(on: db)

        let base = Environment.get("BASE_URL") ?? "https://secretsanta.hdvillamil.dev"
        let url = "\(base)/r/\(token)"

        let guardian = try await p.$guardian.get(on: db)
        let deliverName = (p.phone.nilIfEmpty == nil ? guardian?.name : nil) ?? p.name
        let deliverPhone = p.phone.nilIfEmpty ?? guardian?.phone

        let message = "🎁 Amigo secreto de \(p.name) (\(event.name)). Abre el enlace tú solo: funciona una única vez.\n\(url)"
        return LinkDTO(
            participantId: pid,
            name: p.name,
            url: url,
            message: message,
            deliverToName: deliverName,
            deliverToPhone: deliverPhone
        )
    }

    // MARK: - Utilidades

    /// Busca el evento solo entre los del usuario autenticado (404 si es de otro).
    private func findEvent(_ req: Request) async throws -> Event {
        let userID = try req.auth.require(User.self).requireID()
        guard let eventID = req.parameters.get("eventID", as: UUID.self),
              let event = try await Event.query(on: req.db)
                .filter(\.$id == eventID).filter(\.$owner.$id == userID).first() else {
            throw Abort(.notFound)
        }
        return event
    }

    private func findParticipant(_ req: Request, eventID: UUID) async throws -> Participant {
        guard let pid = req.parameters.get("participantID", as: UUID.self),
              let p = try await Participant.query(on: req.db)
                .filter(\.$id == pid).filter(\.$event.$id == eventID).first() else {
            throw Abort(.notFound)
        }
        return p
    }

    private func validate(_ body: ParticipantRequest, eventID: UUID, selfID: UUID?, db: Database) async throws {
        guard !body.name.trimmed.isEmpty else { throw Abort(.badRequest, reason: "El nombre es obligatorio.") }
        if body.phone.nilIfEmpty == nil && body.guardianId == nil {
            throw Abort(.badRequest, reason: "Indica un teléfono o un tutor que reciba el enlace.")
        }
        if let gid = body.guardianId {
            guard gid != selfID,
                  let g = try await Participant.query(on: db)
                    .filter(\.$id == gid).filter(\.$event.$id == eventID).first(),
                  g.phone.nilIfEmpty != nil else {
                throw Abort(.badRequest, reason: "El tutor debe ser del mismo evento y tener teléfono.")
            }
        }
    }

    private func eventDTO(_ e: Event, db: Database) async throws -> EventDTO {
        let id = try e.requireID()
        let count = try await Participant.query(on: db).filter(\.$event.$id == id).count()
        return EventDTO(id: id, name: e.name, date: e.date, budget: e.budget, status: e.status, participantCount: count)
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        for element in self { values.append(try await transform(element)) }
        return values
    }
}
