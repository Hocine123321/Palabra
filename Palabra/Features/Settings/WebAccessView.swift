import SwiftUI

/// Settings → Web Access: the switch, the relay address, and pairing a browser. Phase 1 has no web UI behind it yet;
/// it proves the link (pairing on this Wi-Fi, the relay and an encrypted ping).
struct WebAccessView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var relayText = ""
    @State private var codeText = ""
    @State private var relayError = false

    private var web: WebLinkController { environment.webLink }

    var body: some View {
        Form {
            Section {
                Toggle("Web Access", isOn: Binding(get: { web.isEnabled }, set: { web.setEnabled($0) }))
                    .accessibilityIdentifier("webAccessToggle")
                if web.isEnabled {
                    Label("Web access is on", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Theme.accentDeep)
                        .accessibilityIdentifier("webAccessOnLabel")
                }
            } footer: {
                Text("Keeps this phone awake while it is on, which uses more battery. The link only works while Palabra is open on screen.")
            }
            .themedSection()

            if web.isEnabled {
                Section {
                    TextField("wss://your-relay.workers.dev", text: $relayText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit(saveRelay)
                        .accessibilityIdentifier("webAccessRelayField")
                    if relayError {
                        Text("Use a wss:// address with no path.").foregroundStyle(Theme.error)
                    }
                } header: {
                    Text("Relay")
                } footer: {
                    Text("Your own relay. It only passes scrambled messages along and keeps nothing.")
                }
                .themedSection()

                Section {
                    statusRow
                    if web.isPaired {
                        Button("Forget This Browser", role: .destructive) { web.revoke() }
                    }
                    if web.isPairingOpen { pairingOpen } else {
                        TextField("Choose a code (6 or more digits)", text: $codeText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("webAccessCodeField")
                        Button(web.isPaired ? "Pair Another Browser" : "Pair a Browser") {
                            web.openPairing(code: codeText)
                            relayError = false
                        }
                        .disabled(!PairingService.isAcceptableCode(codeText) || !WebLinkSettings.isValidRelayURL(web.relayURL))
                        .accessibilityIdentifier("webAccessPairButton")
                        if let error = web.pairingError { Text(error).foregroundStyle(Theme.error) }
                    }
                } header: {
                    Text("Browser")
                } footer: {
                    Text("Pairing only works from the same Wi-Fi as the browser. After 5 wrong codes, pairing locks for a while.")
                }
                .themedSection()
            }
        }
        .glassScreen()
        .navigationTitle("Web Access")
        .onAppear { relayText = web.relayURL }
        .onDisappear { web.closePairing() }
    }

    private var statusRow: some View {
        LabeledContent("Status") {
            switch web.link {
            case .off: Text("Off")
            case .needsPairing: Text("Not paired")
            case .waitingForBrowser: Text("Waiting for the browser")
            case .linked: Text("Linked")
            case .failed(let message): Text(message).foregroundStyle(Theme.error)
            }
        }
        .accessibilityIdentifier("webAccessStatus")
    }

    private var pairingOpen: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Open the Palabra web file on your computer, on this Wi-Fi, and type:")
            Text(verbatim: web.pairingCode ?? "").font(Theme.Font.display).monospacedDigit()
                .accessibilityIdentifier("webAccessCode")
            Text(verbatim: "\(localAddress ?? "this phone's address"):\(LocalPairingListener.port.rawValue)")
                .font(.footnote).foregroundStyle(Theme.inkSecondary)
            if web.lockedSeconds > 0 {
                Text("Too many wrong codes. Try again in \(web.lockedSeconds) seconds.").foregroundStyle(Theme.error)
            }
            Button("Stop Pairing") { web.closePairing(); codeText = "" }.buttonStyle(.glassAction)
        }
        .task(id: web.isPairingOpen) {
            while web.isPairingOpen { web.updateLocked(); try? await Task.sleep(for: .seconds(1)) }
        }
    }

    private var localAddress: String? { LocalAddress.wifiIPv4() }

    private func saveRelay() { relayError = !web.setRelayURL(relayText) }
}
