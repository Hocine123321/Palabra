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
                StatusPill(systemImage: "wifi.slash", text: "Waiting for a connection…", tint: Theme.error)
                    .transition(.opacity)
            } else if let retrying = center.retrying {
                StatusPill(systemImage: "arrow.triangle.2.circlepath", text: retryText(retrying), tint: Theme.accent)
                    .transition(.opacity)
            } else if let notice = center.notice {
                StatusPill(systemImage: notice.isWarning ? "key.fill" : "checkmark.circle", text: LocalizedStringKey(notice.text), tint: notice.isWarning ? Theme.error : Theme.accent)
                    .onTapGesture { center.dismissNotice() }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .animation(Motion.standard, value: center.pendingDecision?.id)
        .animation(Motion.quick, value: center.retrying)
        .animation(Motion.quick, value: center.isOffline)
    }

    private func retryText(_ r: ResilienceCenter.Retrying) -> LocalizedStringKey {
        let key = r.usingFallbackKey ? " (backup key)" : ""
        if r.secondsLeft > 0 {
            return "\(r.reason.shortReason)\(key). Retrying in \(r.secondsLeft)s (\(r.attempt) of \(r.of))"
        }
        return "\(r.reason.shortReason)\(key). Retrying now… (\(r.attempt) of \(r.of))"
    }
}

private struct StatusPill: View {
    let systemImage: String
    let text: LocalizedStringKey
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .accessibilityElement(children: .combine)
    }
}

/// Shown when automatic retries did not work. The choices depend on the error, since
/// "wait longer" is pointless for a spent quota and "try the backup key" needs a backup.
private struct DecisionCard: View {
    let decision: ResilienceCenter.Decision
    var onChoose: (RetryDecision) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(LocalizedStringKey(decision.error.headline), systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Theme.ink)
            Text(LocalizedStringKey(decision.error.explanation(tried: decision.attempts, hasBackupKey: environment.hasFallbackKey)))
                .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Spacing.sm) {
                if decision.error.canBenefitFromWaiting {
                    Button { onChoose(.retryNow) } label: { Text("Try Again").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    Button { onChoose(.retryPatiently) } label: { Text("Retry with Longer Waits").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                } else {
                    Button { onChoose(.retryNow) } label: { Text("Try Again").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                if decision.error.recovery == .openSettings {
                    Button {
                        onChoose(.stop)
                        environment.router.openSettings()
                    } label: { Text(decision.error.settingsButtonTitle).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                Button(role: .cancel) { onChoose(.stop) } label: { Text("Stop").frame(maxWidth: .infinity) }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.error.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
        .accessibilityIdentifier("resilienceDecisionCard")
    }
}
