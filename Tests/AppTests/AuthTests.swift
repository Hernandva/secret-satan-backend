import XCTVapor
import Fluent
@testable import App

final class AuthTests: XCTestCase {
    private var app: Application!

    override func setUp() async throws {
        setenv("APPLE_BUNDLE_ID", "dev.test.secretsanta", 1)
        setenv("DATABASE_PATH", ":memory:", 1)
        app = try await Application.make(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    /// Crea un usuario con una sesión válida (simula un login ya verificado).
    private func login(_ subject: String, expiresIn: TimeInterval = 3600) async throws -> (User, String) {
        let user = User(provider: "apple", subject: subject, email: nil, name: subject)
        try await user.save(on: app.db)
        let token = Tokens.make()
        try await UserSession(
            userID: try user.requireID(), tokenHash: Tokens.hash(token),
            expiresAt: Date().addingTimeInterval(expiresIn)
        ).save(on: app.db)
        return (user, token)
    }

    private func createEvent(_ name: String, token: String) async throws -> EventDTO {
        var event: EventDTO?
        try await app.test(.POST, "events", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(CreateEventRequest(name: name, date: nil, budget: nil))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            event = try res.content.decode(EventDTO.self)
        })
        return try XCTUnwrap(event)
    }

    func testOrganizerAPIRequiresSession() async throws {
        try await app.test(.GET, "events") { res async throws in XCTAssertEqual(res.status, .unauthorized) }
        try await app.test(.GET, "events", headers: ["Authorization": "Bearer inventado"]) { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try await app.test(.GET, "auth/me") { res async throws in XCTAssertEqual(res.status, .unauthorized) }
    }

    func testExpiredSessionIsRejected() async throws {
        let (_, token) = try await login("caducado", expiresIn: -60)
        try await app.test(.GET, "events", headers: ["Authorization": "Bearer \(token)"]) { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testEventsAreIsolatedPerUser() async throws {
        let (_, tokenA) = try await login("ana")
        let (_, tokenB) = try await login("bruno")
        let event = try await createEvent("Navidad", token: tokenA)

        try await app.test(.GET, "events", headers: ["Authorization": "Bearer \(tokenA)"]) { res async throws in
            XCTAssertEqual(try res.content.decode([EventDTO].self).map(\.id), [event.id])
        }
        try await app.test(.GET, "events", headers: ["Authorization": "Bearer \(tokenB)"]) { res async throws in
            XCTAssertEqual(try res.content.decode([EventDTO].self).count, 0)
        }
        for method: HTTPMethod in [.GET, .DELETE] {
            try await app.test(method, "events/\(event.id)", headers: ["Authorization": "Bearer \(tokenB)"]) { res async throws in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testMeAndLogout() async throws {
        let (user, token) = try await login("carla")
        let auth: HTTPHeaders = ["Authorization": "Bearer \(token)"]
        try await app.test(.GET, "auth/me", headers: auth) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try res.content.decode(UserDTO.self).id, user.id)
        }
        try await app.test(.POST, "auth/logout", headers: auth) { res async throws in XCTAssertEqual(res.status, .noContent) }
        try await app.test(.GET, "events", headers: auth) { res async throws in XCTAssertEqual(res.status, .unauthorized) }
    }

    func testDeleteAccountRemovesEventsAndSessions() async throws {
        let (_, token) = try await login("diego")
        _ = try await createEvent("Reyes", token: token)
        try await app.test(.DELETE, "auth/me", headers: ["Authorization": "Bearer \(token)"]) { res async throws in
            XCTAssertEqual(res.status, .noContent)
        }
        let events = try await Event.query(on: app.db).count()
        let sessions = try await UserSession.query(on: app.db).count()
        XCTAssertEqual(events, 0)
        XCTAssertEqual(sessions, 0)
    }

    func testGoogleNotConfiguredAndBadBody() async throws {
        unsetenv("GOOGLE_CLIENT_ID")
        try await app.test(.POST, "auth/google", beforeRequest: { req async throws in
            try req.content.encode(SignInRequest(idToken: "x", nonce: nil, name: nil))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .serviceUnavailable)
        })
        try await app.test(.POST, "auth/apple", beforeRequest: { req async throws in
            try req.content.encode(["foo": "bar"])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    func testRevealLinksStayPublic() async throws {
        try await app.test(.GET, "r/token-que-no-existe") { res async throws in XCTAssertEqual(res.status, .notFound) }
        try await app.test(.GET, "health") { res async throws in XCTAssertEqual(res.status, .ok) }
    }
}
