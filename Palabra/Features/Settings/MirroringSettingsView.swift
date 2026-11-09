import SwiftUI

/// Settings → Mirroring: pair a computer, see when the library was last sent, remove a computer, or forget everything.
struct MirroringSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showScanner = false
    @State private var pasted = ""
    @State private var linkProblem = false
    @State private var pending: PendingPairing?
    @State private var computerToRemove: MirrorComputer?
    @State private var confirmForget = false

    private struct PendingPairing: Identifiable {
        let id = UUID()
        let link: PairingLink
    }

    private var mirror: MirrorService { environment.mirror }

    var body: some View {
        Form {
            if mirror.isPaired { statusSection; computersSection }
            pairSection
            if mirror.isPaired { forgetSection }
            Section {} footer: {
                Text("Your words are encrypted on this phone before they are sent to your own Cloudflare Worker, which cannot read them. They are sent when you open Palabra and when you tap Sync Now, so a computer shows what the phone sent last. Audio, chats and your API key are never sent.")
            }
        }
        .navigationTitle("Mirroring")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showScanner) { scanner }
        .sheet(item: $pending) { item in
            PairingSheet(session: environment.mirror.makePairingSession(link: item.link)) { finished in
                if finished { environment.mirror.didPair(); Task { await environment.mirrorSyncIfEnabled(force: true) } }
            }
        }
        .confirmationDialog("Remove this computer?", isPresented: removeBinding, titleVisibility: .visible, presenting: computerToRemove) { computer in
            Button("Remove", role: .destructive) { Task { await mirror.remove(computerID: computer.id) } }
        } message: { _ in
            Text("It stops getting new words at once. Its saved copy stays on that computer until you clear the browser data.")
        }
        .confirmationDialog("Turn off Mirroring and forget everything?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Turn Off and Forget", role: .destructive) { mirror.turnOffAndForget() }
        } message: {
            Text("This phone forgets its keys and the paired computers. The encrypted copy stays on your Worker, unreadable without the keys.")
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        @Bindable var service = environment.mirror
        return Section("Status") {
            Toggle("Send my library to paired computers", isOn: $service.enabled)
                .accessibilityIdentifier("mirroringEnabledToggle")
            HStack {
                Text("Last sent")
                Spacer()
                if let last = mirror.lastSyncAt {
                    Text(last, style: .relative).foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("Never").foregroundStyle(Theme.inkSecondary)
                }
            }
            Button {
                Task { await environment.mirrorSyncIfEnabled(force: true) }
            } label: {
                HStack {
                    Text("Sync Now")
                    if mirror.syncing { Spacer(); ProgressView() }
                }
            }
            .disabled(mirror.syncing)
            .accessibilityIdentifier("mirrorSyncNow")
            if let error = mirror.lastError {
                Label { Text(Self.message(for: error)) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
                }
                .font(.footnote)
            }
        }
        .themedSection()
    }

    private var computersSection: some View {
        Section("Computers") {
            if mirror.computers.isEmpty {
                Text("No computer is paired yet.").foregroundStyle(Theme.inkSecondary)
            }
            ForEach(mirror.computers) { computer in
                HStack {
                    Image(systemName: "desktopcomputer").foregroundStyle(Theme.inkSecondary)
                    Text(verbatim: computer.name)
                    Spacer()
                    Button("Remove", role: .destructive) { computerToRemove = computer }
                        .buttonStyle(.borderless)
                }
            }
        }
        .themedSection()
    }

    private var pairSection: some View {
        Section {
            Button { showScanner = true } label: { Label("Pair a Computer", systemImage: "qrcode.viewfinder") }
                .accessibilityIdentifier("mirrorPairButton")
            TextField("Paste the pairing link", text: $pasted)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("mirrorPasteField")
                .onSubmit { open(pasted) }
            if !pasted.isEmpty {
                Button("Pair with This Link") { open(pasted) }
            }
            if linkProblem {
                Text("That is not a Palabra pairing link. Open your Worker's address on the computer and scan the code it shows.")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
            }
        } header: {
            Text("Pair a Computer")
        } footer: {
            Text("Open your Worker's address in the computer's browser. It shows a QR code and, after you scan it, a 4-digit code to compare.")
        }
        .themedSection()
    }

    private var forgetSection: some View {
        Section {
            Button("Turn Off and Forget", role: .destructive) { confirmForget = true }
        }
        .themedSection()
    }

    private var scanner: some View {
        NavigationStack {
            QRScannerView { code in open(code); showScanner = false }
                .navigationTitle("Scan the Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScanner = false } } }
        }
    }

    // MARK: Helpers

    private var removeBinding: Binding<Bool> {
        Binding(get: { computerToRemove != nil }, set: { if !$0 { computerToRemove = nil } })
    }

    private func open(_ text: String) {
        switch PairingLink.parse(text) {
        case .success(let link):
            linkProblem = false
            pasted = ""
            pending = PendingPairing(link: link)
        case .failure:
            linkProblem = true
        }
    }

    static func message(for error: MirrorSyncError) -> LocalizedStringKey {
        switch error {
        case .offline: return "You're offline. The library will be sent when you're back online."
        case .rejected: return "The Worker no longer accepts this phone. Turn Mirroring off and pair again."
        case .rateLimited: return "The Worker is busy. Try again in a few minutes."
        case .other: return "Couldn't send the library. Try again later."
        }
    }
}

/// One pairing: the code to compare, then Confirm or Cancel.
private struct PairingSheet: View {
    @State var session: MirrorPairingSession
    let finish: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    init(session: MirrorPairingSession, finish: @escaping (Bool) -> Void) {
        _session = State(initialValue: session)
        self.finish = finish
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                content
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("Pair a Computer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await session.start() }
        .interactiveDismissDisabled(session.phase == .finishing)
        // Swiping the sheet away after "paired" must still update the phone, so report here, not in the Done button.
        .onDisappear { finish(session.phase == .done) }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .idle, .joining, .finishing:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text(session.phase == .finishing ? "Pairing…" : "Joining…")
            }
        case .awaitingConfirmation(let code):
            VStack(spacing: Theme.Spacing.md) {
                Text(verbatim: code)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("mirrorMatchCode")
                Text("Check that this computer shows the same code.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.inkSecondary)
                Button("Confirm") { Task { await session.confirm() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("mirrorConfirmButton")
                Button("Cancel", role: .cancel) { Task { await session.cancel(); dismiss() } }
            }
        case .done:
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Theme.success)
                Text("The computer is paired.")
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        case .failed(let failure):
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(Theme.error)
                Text(Self.message(for: failure)).multilineTextAlignment(.center)
                Button("Close") { dismiss() }
            }
        case .cancelled:
            Color.clear.onAppear { dismiss() }
        }
    }

    static func message(for failure: MirrorPairingSession.Failure) -> LocalizedStringKey {
        switch failure {
        case .slotTaken: return "Another phone already answered this code. Refresh the computer's page and try again."
        case .expired: return "The code expired. Refresh the computer's page and scan the new one."
        case .offline: return "You're offline. Connect and try again."
        case .alreadyPairedElsewhere: return "This phone is already paired with a different Worker. Turn Mirroring off first."
        case .tooManyComputers: return "You've reached the limit of 8 computers. Remove one first."
        case .rateLimited: return "The Worker is busy. Try again in a few minutes."
        case .other: return "Pairing didn't work. Refresh the computer's page and try again."
        }
    }
}
