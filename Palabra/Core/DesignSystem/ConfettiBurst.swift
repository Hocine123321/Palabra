import SwiftUI

/// A short burst of paper cutouts for finishing something (a review session). Plays once when it appears,
/// draws nothing at all with Reduce Motion on, and never takes touches.
struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fired = false

    private struct Piece {
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let spin: Double
        let tint: Color
        let kind: CutoutKind
    }

    /// Fixed, not random: the same burst every time, so it is easy to test and to reason about.
    private let pieces: [Piece] = (0..<30).map { index in
        Piece(
            angle: -Double.pi + Double(index) / 29 * Double.pi + Double(index % 3) * 0.05,
            distance: CGFloat(120 + (index * 41) % 140),
            size: CGFloat(8 + (index % 4) * 3),
            spin: Double((index * 47) % 360),
            tint: Theme.tileTints[index % Theme.tileTints.count],
            kind: index % 3 == 0 ? .roundedSquare : (index % 3 == 1 ? .circle : .pill)
        )
    }

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    CutoutShape(kind: piece.kind)
                        .fill(piece.tint)
                        .frame(width: piece.size, height: piece.kind == .pill ? piece.size / 2 : piece.size)
                        .rotationEffect(.degrees(fired ? piece.spin : 0))
                        .offset(
                            x: fired ? CGFloat(cos(piece.angle)) * piece.distance : 0,
                            y: fired ? CGFloat(sin(piece.angle)) * piece.distance + 60 : 0
                        )
                        .opacity(fired ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            Motion.animate(.easeOut(duration: 1.2)) { fired = true }
        }
    }
}
