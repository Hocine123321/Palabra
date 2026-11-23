import Foundation

/// Picks a word for the library's shuffle button.
enum RandomWord {
    /// A random id from `ids`, never the one just shown (`last`) unless it is the only choice.
    static func pick<G: RandomNumberGenerator>(from ids: [UUID], excluding last: UUID?, using generator: inout G) -> UUID? {
        let pool = ids.count > 1 ? ids.filter { $0 != last } : ids
        return pool.randomElement(using: &generator)
    }

    static func pick(from ids: [UUID], excluding last: UUID?) -> UUID? {
        var generator = SystemRandomNumberGenerator()
        return pick(from: ids, excluding: last, using: &generator)
    }
}
