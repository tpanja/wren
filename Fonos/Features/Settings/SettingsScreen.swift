import AVFoundation
import SwiftUI

struct SettingsScreen: View {
    @Environment(FonosEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fonos.appearance") private var appearance: Appearance = .light
    @State private var newPhrase = ""

    var body: some View {
        @Bindable var engine = engine
        @Bindable var voice = engine.voice
        NavigationStack {
            Form {
                Section {
                    Picker("Voice", selection: $voice.selectedVoiceID) {
                        ForEach(voice.voices) { v in
                            VStack(alignment: .leading) {
                                Text(v.name)
                                Text(v.detail).font(.ui(.footnote)).foregroundStyle(.secondary)
                            }
                            .tag(Optional(v.id))
                        }
                    }
                    .pickerStyle(.navigationLink)

                    if voice.personalVoiceStatus != .authorized {
                        Button("Use my Personal Voice") { voice.requestPersonalVoice() }
                    }

                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        Slider(value: $voice.rate, in: 0.3...0.7) {
                            Text("Speaking speed")
                        } minimumValueLabel: {
                            FonosIcon(.slow, size: 18).foregroundStyle(Theme.inkSecondary)
                        } maximumValueLabel: {
                            FonosIcon(.fast, size: 18).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button("Test voice") { engine.say("This is how Wren will sound.") }
                } header: {
                    Text("Voice").cardTitle()
                } footer: {
                    Text("A Personal Voice you've created in iPhone Settings sounds like you. Wren uses it when you allow it.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("Stop listening after", selection: $engine.autoStopSeconds) {
                        Text("I tap Done").tag(0.0)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                    }
                    Toggle("Speak translation automatically", isOn: $engine.speakAutomatically)
                } header: {
                    Text("Listening").cardTitle()
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(engine.quickPhrases, id: \.self) { Text($0) }
                        .onDelete { engine.quickPhrases.remove(atOffsets: $0) }
                        .onMove { engine.quickPhrases.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("Add a phrase", text: $newPhrase)
                            .submitLabel(.done)
                            .onSubmit(addPhrase)
                        Button("Add", action: addPhrase)
                            .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button("Restore default phrases") { engine.quickPhrases = FonosEngine.defaultPhrases }
                } header: {
                    Text("Quick phrases").cardTitle()
                } footer: {
                    Text("Swipe left to remove a phrase. Use Edit to reorder.")
                }
                .listRowBackground(Theme.card)

                Section {
                    NavigationLink {
                        ClinicSummaryView()
                    } label: {
                        Label { Text("Clinic summary") } icon: { FonosIcon(.report, size: 22) }
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Care team").cardTitle()
                } footer: {
                    Text("A two-page PDF of your speech trends and weekly checks for your neurologist or speech therapist.")
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(DemoClip.bundled) { clip in
                        if let file = clip.shareURL {
                            ShareLink(item: file) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(clip.text).foregroundStyle(Theme.ink)
                                        Text("Clip \(clip.id.filter(\.isNumber)) · \(clip.severity), \(clip.gender)")
                                            .font(.ui(.footnote))
                                            .foregroundStyle(Theme.inkSecondary)
                                    }
                                    Spacer()
                                    FonosIcon(.share, size: 20)
                                        .foregroundStyle(Theme.actionInk)
                                }
                            }
                            .accessibilityHint("Share or save this recording")
                        }
                    }
                    ShareLink(items: DemoClip.bundled.compactMap(\.shareURL)) {
                        Label { Text("Share all \(DemoClip.bundled.count) recordings") } icon: { FonosIcon(.share, size: 20) }
                            .foregroundStyle(Theme.actionInk)
                    }
                } header: {
                    Text("Demo recordings").cardTitle()
                } footer: {
                    Text("Save them to Files or AirDrop them to another device, then play one near this iPhone while Wren listens. They're also in Files under On My iPhone › Wren.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Appearance").cardTitle()
                }
                .listRowBackground(Theme.card)

                Section {
                    LabeledContent("Band", value: engine.bandMode == .simulated ? "Simulated" : "Wren Band over Bluetooth")
                    LabeledContent("Translator", value: "Demo recordings (\(DemoClip.bundled.count))")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                } header: {
                    Text("About").cardTitle()
                } footer: {
                    Text("Wren is not a medical device and does not diagnose.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .fonosScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func addPhrase() {
        let p = newPhrase.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !engine.quickPhrases.contains(p) else { return }
        engine.quickPhrases.append(p)
        newPhrase = ""
    }
}
