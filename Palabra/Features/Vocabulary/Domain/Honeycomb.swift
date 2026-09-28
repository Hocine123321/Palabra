import Foundation

/// Pure layout math for the Watch-style grid: alternating rows of `columns`
/// and `columns - 1` items, so every other row sits inset by half a tile.
enum Honeycomb {
    static func rows<T>(_ items: [T], columns: Int) -> [[T]] {
        precondition(columns > 1, "Honeycomb needs at least 2 columns")
        var result: [[T]] = []
        var index = items.startIndex
        var fullRow = true
        while index < items.endIndex {
            let width = fullRow ? columns : columns - 1
            let end = items.index(index, offsetBy: width, limitedBy: items.endIndex) ?? items.endIndex
            result.append(Array(items[index..<end]))
            index = end
            fullRow.toggle()
        }
        return result
    }
}
