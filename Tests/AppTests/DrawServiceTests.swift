import XCTest
@testable import App

final class DrawServiceTests: XCTestCase {
    private func people(_ count: Int) -> [DrawService.Person] {
        (0..<count).map { _ in DrawService.Person(id: UUID()) }
    }

    func testNobodyDrawsThemselves() throws {
        let p = people(6)
        for _ in 0..<200 {
            let result = try DrawService.draw(people: p, forbidden: [])
            XCTAssertEqual(result.count, p.count)
            XCTAssertEqual(Set(result.values).count, p.count, "Cada persona recibe exactamente un regalo")
            for giver in p {
                XCTAssertNotEqual(result[giver.id], giver.id)
            }
        }
    }

    func testRespectsForbiddenPairs() throws {
        let p = people(4)
        let forbidden: Set<DrawService.Pair> = [
            .init(giver: p[0].id, receiver: p[1].id),
            .init(giver: p[1].id, receiver: p[0].id),
        ]
        for _ in 0..<200 {
            let result = try DrawService.draw(people: p, forbidden: forbidden)
            XCTAssertNotEqual(result[p[0].id], p[1].id)
            XCTAssertNotEqual(result[p[1].id], p[0].id)
        }
    }

    func testImpossibleWhenExclusionsBlockEveryone() {
        // Con 3 personas, si A no puede regalar a B ni a C, no hay solución.
        let p = people(3)
        let forbidden: Set<DrawService.Pair> = [
            .init(giver: p[0].id, receiver: p[1].id),
            .init(giver: p[0].id, receiver: p[2].id),
        ]
        XCTAssertThrowsError(try DrawService.draw(people: p, forbidden: forbidden))
    }

    func testNeedsTwoPeople() {
        XCTAssertThrowsError(try DrawService.draw(people: people(1), forbidden: []))
    }
}
