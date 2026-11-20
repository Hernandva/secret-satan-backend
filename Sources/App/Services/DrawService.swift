import Foundation

enum DrawError: Error {
    case notEnoughPeople
    case impossible
}

/// Sorteo con restricciones mediante backtracking.
/// Reglas: nadie se toca a sí mismo, nadie toca a alguien de su misma unidad familiar
/// y se respetan los pares prohibidos.
enum DrawService {
    struct Person {
        let id: UUID
        let family: String?
    }

    struct Pair: Hashable {
        let giver: UUID
        let receiver: UUID
    }

    /// Devuelve un diccionario giver -> receiver.
    static func draw(
        people: [Person],
        forbidden: Set<Pair>,
        blockSameFamily: Bool = true
    ) throws -> [UUID: UUID] {
        guard people.count >= 2 else { throw DrawError.notEnoughPeople }

        func allowed(_ giver: Person, _ receiver: Person) -> Bool {
            if giver.id == receiver.id { return false }
            if blockSameFamily, let f = giver.family, !f.isEmpty, f == receiver.family { return false }
            return !forbidden.contains(Pair(giver: giver.id, receiver: receiver.id))
        }

        var candidates: [UUID: [Person]] = [:]
        for giver in people {
            candidates[giver.id] = people.filter { allowed(giver, $0) }.shuffled()
        }

        // Primero quien tiene menos opciones; el barajado previo rompe empates al azar.
        let order = people.shuffled().sorted {
            candidates[$0.id]!.count < candidates[$1.id]!.count
        }

        var used = Set<UUID>()
        var result: [UUID: UUID] = [:]

        func solve(_ index: Int) -> Bool {
            if index == order.count { return true }
            let giver = order[index]
            for receiver in candidates[giver.id]! where !used.contains(receiver.id) {
                used.insert(receiver.id)
                result[giver.id] = receiver.id
                if solve(index + 1) { return true }
                used.remove(receiver.id)
                result[giver.id] = nil
            }
            return false
        }

        guard solve(0) else { throw DrawError.impossible }
        return result
    }
}
