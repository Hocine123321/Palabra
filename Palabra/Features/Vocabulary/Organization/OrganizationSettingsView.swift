import SwiftUI

/// Settings for how the library is organized. Reachable from the library's
/// "…" menu, the re-organize sheet, and the main Settings screen.
struct OrganizationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    var body: some View {
        @Bindable var env = environment
        Form {
            Section {
                Toggle("Group Library into Sections", isOn: $env.organizerSettings.groupIntoSections)
                Toggle("Show Tags in List Layout", isOn: $env.organizerSettings.showTagsInList)
                Picker("Order Sections By", selection: $env.organizerSettings.sectionOrder) {
                    Text("Most Words").tag(OrganizerSettings.SectionOrder.largestFirst)
                    Text("A to Z").tag(OrganizerSettings.SectionOrder.alphabetical)
                    Text("Recently Added").tag(OrganizerSettings.SectionOrder.recentlyAdded)
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Organize New Words Automatically", isOn: $env.organizerSettings.autoOrganizeNewWords)
            } footer: {
                Text("When on, each word you save gets a section and tags right away. It costs one small extra request per word.")
            }

            Section {
                Picker("Number of Sections", selection: $env.organizerSettings.granularity) {
                    Text("Fewer, Broader").tag(OrganizerSettings.Granularity.broad)
                    Text("Balanced").tag(OrganizerSettings.Granularity.balanced)
                    Text("More, Specific").tag(OrganizerSettings.Granularity.detailed)
                }
                Stepper("Tags per Word: \(environment.organizerSettings.maxTagsPerWord)", value: $env.organizerSettings.maxTagsPerWord, in: 1...6)
            } header: {
                Text("AI Behavior")
            } footer: {
                Text("Applies the next time you re-organize, and to new words.")
            }

            Section {
                TextField("For example: group by topic, not part of speech", text: $env.organizerSettings.customInstructions, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Your Instructions")
            } footer: {
                Text("Optional. Guides how the AI names and groups sections.")
            }

            Section {
                Button("Remove All Sections and Tags", role: .destructive) { showClearConfirm = true }
            } footer: {
                Text("Your words are kept. You can organize again at any time.")
            }
        }
        .navigationTitle("Organization")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .confirmationDialog("Remove all sections and tags?", isPresented: $showClearConfirm) {
            Button("Remove", role: .destructive) { environment.repository.clearAllPlacements() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
