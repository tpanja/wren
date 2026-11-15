import AVFoundation
import SwiftUI

struct SettingsScreen: View {
    @Environment(FonosEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fonos.appearance") private var appearance: Appearance = .dark
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

                    Button("Test voice") { engine.say("This is how Fonos will sound.") }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("A Personal Voice you've created in iPhone Settings sounds like you. Fonos uses it when you allow it.")
                }
                .listRowBackground(Theme.card)

                Section("Listening") {
                    Picker("Stop listening after", selection: $engine.autoStopSeconds) {
                        Text("I tap Done").tag(0.0)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                    }
                    Toggle("Speak translation automatically", isOn: $engine.speakAutomatically)
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
                    Text("Quick phrases")
                } footer: {
                    Text("Swipe left to remove a phrase. Use Edit to reorder.")
                }
                .listRowBackground(Theme.card)

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.card)

                Section {
                    LabeledContent("Data source", value: "Simulated band")
                    LabeledContent("Translator", value: "Toy translator")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                } header: {
                    Text("About")
                } footer: {
                    Text("Fonos is not a medical device and does not diagnose. All data shown is sample data from a simulated band.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
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
