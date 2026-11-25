import SwiftUI

// Small things the library tiles and rows share: the values the library hands down, the mastery ring,
// the press feel, the long-press preview and the undo toast.

private struct WordMasteryKey: EnvironmentKey { static let defaultValue: [UUID: Double] = [:] }
private struct PinnedWordIDsKey: EnvironmentKey { static let defaultValue: Set<UUID> = [] }

extension EnvironmentValues {
    /// Flashcard progress per word (0...1), set by the library; words without a started card are absent.
    var wordMastery: [UUID: Double] {
        get { self[WordMasteryKey.self] }
        set { self[WordMasteryKey.self] = newValue }
    }

    /// The ids pinned to the top, set by the library.
    var pinnedWordIDs: Set<UUID> {
        get { self[PinnedWordIDsKey.self] }
        set { self[PinnedWordIDsKey.self] = newValue }
    }
}

/// A thin progress arc that follows a cutout's outline, starting at the top.
struct MasteryRing: View {
    var kind: CutoutKind
    var fraction: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            CutoutShape(kind: kind).stroke(Theme.onTint.opacity(0.12), lineWidth: lineWidth)
            CutoutShape(kind: kind)
                .trim(from: 0, to: fraction)
                .stroke(Theme.onTint.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(-90))
        .accessibilityHidden(true)
    }
}

/// Presses in a little and springs back; honours Reduce Motion.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.reduced(Motion.quick), value: configuration.isPressed)
    }
}

/// What the long-press menu shows above its actions: the word on its own cutout.
struct WordPreviewCard: View {
    let word: Word
    var tints = WordTintSettings()

    var body: some View {
        CutoutCard(tint: tints.color(key: word.key, partOfSpeech: word.partOfSpeech)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if !word.partOfSpeech.isEmpty {
                    Chip(text: word.partOfSpeech, tint: Color.white.opacity(0.45))
                }
                Text(verbatim: word.spanish)
                    .font(Theme.Font.display)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if !word.translation.isEmpty {
                    Text(verbatim: word.translation).font(.headline)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 280, alignment: .leading)
        }
    }
}

/// "Deleted … Undo": a word is hidden at once and removed for good a few seconds later unless this is tapped.
struct UndoToast: View {
    let title: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("Deleted \"\(title)\"")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accentDeep)
                .accessibilityIdentifier("undoDeleteButton")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .glassCapsule()
        .padding(.horizontal, Theme.Spacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
