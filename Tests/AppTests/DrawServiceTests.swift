import XCTest
@testable import App

final class DrawServiceTests: XCTestCase {
    private func people(_ families: [String?]) -> [DrawService.Person] {
        families.map { DrawService.Person(id: UUID(), family: $0) }
    }

    func testNobodyDrawsThemselvesOrOwnFamily() throws {
        let p = people(["A", "A", "B", "B", "C", nil])
        for _ in 0..<200 {
            let result = try DrawService.draw(people: p, forbidden: [])
            XCTAssertEqual(result.count, p.count)
            XCTAssertEqual(Set(result.values).count, p.count, "Cada persona recibe exactamente un regalo")
            for giver in p {
                let receiver = p.first { $0.id == result[giver.id] }!
                XCTAssertNotEqual(giver.id, receiver.id)
                if let f = giver.family { XCTAssertNotEqual(f, receiver.family) }
            }
        }
    }

    func testRespectsForbiddenPairs() throws {
        let p = people([nil, nil, nil, nil])
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

    func testImpossibleWhenEveryoneIsSameFamily() {
        let p = people(["A", "A", "A"])
        XCTAssertThrowsError(try DrawService.draw(people: p, forbidden: []))
    }

    func testNeedsTwoPeople() {
        XCTAssertThrowsError(try DrawService.draw(people: people([nil]), forbidden: []))
    }
}
