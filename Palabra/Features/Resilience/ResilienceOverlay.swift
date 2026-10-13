import SwiftUI

/// Sits above every screen and makes AI trouble visible: a quiet status while the app
/// retries on its own, and a clear question when it needs the person to decide.
struct ResilienceOverlay: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let center = environment.resilience
        VStack(spacing: Theme.Spacing.sm) {
            if let decision = center.pendingDecision {
                DecisionCard(decision: decision) { center.answer($0) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if center.isOffline {
                StatusPill(systemImage: "wifi.slash", text: Text("Waiting for a connection…"), tint: Theme.error)
                    .transition(.opacity)
            } else if let retrying = center.retrying {
                StatusPill(systemImage: "arrow.triangle.2.circlepath", text: retryText(retrying), tint: Theme.accentDeep)
                    .transition(.opacity)
            } else if let notice = center.notice {
                StatusPill(systemImage: notice.isWarning ? "key.fill" : "checkmark.circle", text: Text(LocalizedStringKey(notice.text)), tint: notice.isWarning ? Theme.error : Theme.accentDeep)
                    .onTapGesture { center.dismissNotice() }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .animation(Motion.reduced(Motion.standard), value: center.pendingDecision?.id)
        .animation(Motion.reduced(Motion.quick), value: center.retrying)
        .animation(Motion.reduced(Motion.quick), value: center.isOffline)
    }

    /// "<reason> (backup key). Retrying in 4s (1 of 3)", built from separately translated parts
    /// so the reason and the countdown both follow the app language.
    private func retryText(_ r: ResilienceCenter.Retrying) -> Text {
        var text = Text(LocalizedStringKey(r.reason.shortReason))
        if r.usingFallbackKey { text = text + Text(" ") + Text("(backup key)") }
        text = text + Text(". ")
        if r.secondsLeft > 0 {
            return text + Text("Retrying in \(r.secondsLeft)s (\(r.attempt) of \(r.of))")
        }
        return text + Text("Retrying now… (\(r.attempt) of \(r.of))")
    }
}

private struct StatusPill: View {
    let systemImage: String
    let text: Text
    let tint: Color

    var body: some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
            .glassCapsule()
            .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

/// Shown when automatic retries did not work. The choices depend on the error, since
/// "wait longer" is pointless for a spent quota and "try the backup key" needs a backup.
private struct DecisionCard: View {
    let decision: ResilienceCenter.Decision
    var onChoose: (RetryDecision) -> Void
    @Environment(AppEnvironment.self) private var environment

    /// "I tried 3 times already. <advice>", each part translated on its own.
    private var explanation: Text {
        var text = Text("")
        if decision.error.mentionsAttempts, decision.attempts > 0 {
            text = decision.attempts == 1 ? Text("I tried 1 time already.") : Text("I tried \(decision.attempts) times already.")
            text = text + Text(" ")
        }
        if case .modelUnavailable(let id) = decision.error {
            return text + Text("The model \"\(id)\" no longer exists. Choose another one in Settings.")
        }
        return text + Text(LocalizedStringKey(decision.error.advice(hasBackupKey: environment.hasFallbackKey)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(LocalizedStringKey(decision.error.headline), systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Theme.ink)
            explanation
                .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Spacing.sm) {
                if decision.error.canBenefitFromWaiting {
                    Button { onChoose(.retryNow) } label: { Text("Try Again") }
                        .buttonStyle(.primary)
                    Button { onChoose(.retryPatiently) } label: { Text("Retry with Longer Waits").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassAction)
                } else {
                    Button { onChoose(.retryNow) } label: { Text("Try Again").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassAction)
                }
                if decision.error.recovery == .openSettings {
                    Button {
                        onChoose(.stop)
                        environment.router.openSettings()
                    } label: { Text(LocalizedStringKey(decision.error.settingsButtonTitle)).frame(maxWidth: .infinity) }
                        .buttonStyle(.glassAction)
                }
                Button(role: .cancel) { onChoose(.stop) } label: { Text("Stop").frame(maxWidth: .infinity) }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard(cornerRadius: Theme.Radius.card)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.error.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("resilienceDecisionCard")
    }
}
