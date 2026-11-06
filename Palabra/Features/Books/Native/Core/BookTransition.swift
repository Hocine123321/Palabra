import Foundation

/// The timing of opening and closing a book, in one place so the pieces stay in step and the invariants can be tested.
///
/// The old close ran as a chain: leaves turn back (camera held), then the lid closes, then the book glides home, with the camera
/// on its own clock. Nothing visible happened for the first half second, the camera was only half way when the book was home,
/// and the end was a cut. Here every part is placed on one timeline and the move ends when the last part lands.
struct BookTransition: Equatable {
    /// Seconds from the tap to the moment the book is open (reading) or shut and home (menu).
    var total: Double
    /// When the camera starts and how long it moves (it ends exactly at `total`).
    var cameraDelay: Double
    var cameraDuration: Double
    /// How far along the straight line (0...1) the camera passes over the book.
    var cameraWaypoint: Double
    /// The lid: starts, lasts.
    var lidDelay: Double
    var lidDuration: Double
    /// The book sliding between its slot on the desk and the centre.
    var bookDelay: Double
    var bookDuration: Double
    /// The leaves turning back (close only): the gap between neighbours and how long each takes.
    var leafStagger: Double
    var leafDuration: Double

    var cameraEnd: Double { cameraDelay + cameraDuration }
    var lidEnd: Double { lidDelay + lidDuration }
    var bookEnd: Double { bookDelay + bookDuration }

    /// Opening: the book slides to the centre while the camera comes in; the lid lifts as the book arrives.
    static let open = BookTransition(
        total: 1.6, cameraDelay: 0, cameraDuration: 1.6, cameraWaypoint: 0.6,
        lidDelay: 0.45, lidDuration: 1.15, bookDelay: 0, bookDuration: 0.8,
        leafStagger: 0, leafDuration: 0
    )

    /// Closing for `turned` leaves that are turned over: they flip back first, the lid follows them closely, the book glides
    /// home while the lid is still settling, and the camera pulls back through all of it.
    static func close(turnedLeaves turned: Int) -> BookTransition {
        let stagger = 0.04, leaf = 0.4
        let leavesDone = turned == 0 ? 0 : min(0.4, Double(turned - 1) * stagger) + leaf
        // The lid starts when the last leaf is about 60% of the way down.
        let lidDelay = turned == 0 ? 0 : max(0, leavesDone - leaf * 0.4)
        let lid = 0.8
        let bookDelay = lidDelay + lid * 0.35
        let book = 0.9
        let total = max(lidDelay + lid, bookDelay + book)
        return BookTransition(
            total: total, cameraDelay: 0, cameraDuration: total, cameraWaypoint: 0.5,
            lidDelay: lidDelay, lidDuration: lid, bookDelay: bookDelay, bookDuration: book,
            leafStagger: stagger, leafDuration: leaf
        )
    }

    /// True when every part of the move has landed by `total` and none starts before the tap.
    var isConsistent: Bool {
        let tolerance = 1e-9
        return cameraEnd <= total + tolerance && lidEnd <= total + tolerance && bookEnd <= total + tolerance
            && cameraDelay >= 0 && lidDelay >= 0 && bookDelay >= 0 && cameraWaypoint > 0 && cameraWaypoint < 1
    }
}
