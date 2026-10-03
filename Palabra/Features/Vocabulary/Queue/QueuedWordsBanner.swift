import SwiftUI

/// Shown above the library content whenever `AppEnvironment.wordQueue` has
/// items: words added while offline, waiting for `WordQueueProcessor` to
/// generate them. A failed row (a setup problem, not connectivity) shows
/// why and offers Retry; any row can be removed.
struct QueuedWordsBanner: View {
    let items: [WordQueueItem]
    var onRetry: (UUID) -> Void
    var onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                // Written as literal `Text` cases (not a precomputed String) so each
                // one goes through LocalizedStringKey's own %lld-style substitution.
                if items.count == 1 {
                    Text("1 word queued")
                } else {
                    Text("\(items.count) words queued")
                }
            } icon: {
                Image(systemName: "wifi.slash")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(items, id: \.id) { item in
                    row(for: item)
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder
    private func row(for item: WordQueueItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.inputWord.capitalized)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                statusText(for: item)
                    .font(.caption)
                    .foregroundStyle(item.status == .failed ? Theme.error : Theme.inkSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if item.status == .failed {
                Button("Retry") { onRetry(item.id) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
            }
            Button {
                onRemove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.inputWord) from queue")
        }
    }

    /// `.failed`'s message is a runtime `AIError.userMessage` `String`, not a literal,
    /// so — like `ErrorBanner` elsewhere — it's intentionally left unlocalized; see the
    /// note above the AIError entries in Localizable.strings.
    @ViewBuilder
    private func statusText(for item: WordQueueItem) -> some View {
        switch item.status {
        case .pending: Text("Waiting for connection…")
        case .processing: Text("Generating…")
        case .failed: Text(item.lastErrorMessage ?? "Couldn't generate this word.")
        }
    }
}
