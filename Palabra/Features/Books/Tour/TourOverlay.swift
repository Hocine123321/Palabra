import SwiftUI

/// What the footage shows on top of the scene: a caption for the step and a ring where the scripted finger is. It is part
/// of the app's own view tree, so a screen recording contains it.
struct TourOverlay: View {
    let runner: TourRunner

    var body: some View {
        ZStack {
            if let p = runner.ringPoint {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .background(Circle().fill(Color.black.opacity(0.18)))
                    .frame(width: 44, height: 44)
                    .position(p)
                    .allowsHitTesting(false)
            }
            VStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(verbatim: "\(runner.stepNumber)/\(runner.stepCount)  \(runner.caption)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Button {
                        runner.stop()
                    } label: {
                        Image(systemName: "stop.fill").font(.footnote).foregroundStyle(Color.white)
                    }
                    .accessibilityLabel(Text("Stop the test"))
                    .accessibilityIdentifier("tourStop")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .padding(.top, Theme.Spacing.sm)
                Spacer()
            }
            .accessibilityIdentifier("tourBanner")
        }
    }
}

/// The result of a finished tour: what passed, what did not, and the files to share.
struct TourResultView: View {
    let runner: TourRunner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let report = runner.report {
                    Section {
                        Text("\(report.passedCount) of \(report.steps.count) steps passed")
                            .font(.headline)
                            .accessibilityIdentifier("tourSummary")
                        if let note = runner.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    }
                    let failed = report.failedSteps
                    if !failed.isEmpty {
                        Section("Needs a look") {
                            ForEach(failed, id: \.id) { step in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.caption).font(.subheadline.weight(.semibold))
                                    Text(step.reason ?? "").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section("Share") {
                        if let video = runner.videoURL { ShareLink(item: video) { Label("Video", systemImage: "film") } }
                        if let log = runner.reportURL { ShareLink(item: log) { Label("Log", systemImage: "doc.text") } }
                    }
                }
            }
            .navigationTitle("Test result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        runner.dismissResult()
                        dismiss()
                    }
                    .accessibilityIdentifier("tourDone")
                }
            }
        }
    }
}
