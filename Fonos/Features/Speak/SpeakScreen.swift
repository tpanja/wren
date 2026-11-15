import SwiftUI

struct SpeakScreen: View {
    @Environment(FonosEngine.self) private var engine
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    foldCard
                    transcriptCard
                    SpeakButton()
                        .padding(.top, 8)
                    phrases
                    if !engine.utterances.isEmpty { history }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .principal) {
                    StatusPill(text: statusText, color: statusColor, pulsing: engine.speakState == .listening)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    BatteryBadge(percent: engine.bandStatus.battery, charging: engine.bandStatus.isCharging)
                }
            }
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusText: String {
        switch engine.speakState {
        case .listening: "Listening"
        case .translating: "Translating"
        case .speaking: "Speaking"
        case .idle: engine.isStreaming ? "Band ready" : "Band paused"
        }
    }

    private var statusColor: Color {
        switch engine.speakState {
        case .listening: Theme.alert
        case .translating, .speaking: Theme.pace
        case .idle: engine.isStreaming ? Theme.good : Theme.inkTertiary
        }
    }

    // MARK: Fold

    private var foldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Throat signal").cardTitle()
                Spacer()
                Legend(items: [("Left", Theme.left), ("Mic", Theme.mic), ("Right", Theme.right)])
            }
            FoldView(streams: engine.streams)
                .frame(height: 150)
            Text("Sample signal from a simulated band")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
        }
        .card()
    }

    // MARK: Transcript

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch engine.speakState {
            case .listening, .translating:
                Text(engine.partialText.isEmpty ? "…" : engine.partialText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .accessibilityLabel(engine.partialText.isEmpty ? "Waiting for speech" : engine.partialText)
            default:
                if let last = engine.utterances.first {
                    HStack(alignment: .top, spacing: 12) {
                        Text(last.text)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { engine.say(last.text) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title3)
                                .frame(width: 52, height: 52)
                                .background(Theme.well, in: Circle())
                        }
                        .accessibilityLabel("Say it again")
                        .disabled(engine.speakState == .speaking)
                    }
                    if let c = last.confidence {
                        Text("Clarity \(Int(c * 100))%")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.clarity)
                    }
                } else {
                    Text("Tap Speak and talk normally. Fonos will say your words clearly.")
                        .font(.title3)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minHeight: 72, alignment: .topLeading)
        .card()
        .animation(.easeOut(duration: 0.2), value: engine.partialText)
    }

    // MARK: Phrases

    private var phrases: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick phrases").cardTitle().padding(.top, 12)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(engine.quickPhrases, id: \.self) { phrase in
                    Button { engine.say(phrase, asPhrase: true) } label: {
                        Text(phrase)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Speaks this phrase")
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Said today").cardTitle().padding(.bottom, 8)
            ForEach(engine.utterances.dropFirst().prefix(8)) { u in
                Button { engine.say(u.text) } label: {
                    HStack {
                        Text(u.text).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Text(u.date, style: .time).font(.footnote).foregroundStyle(Theme.inkTertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Says it again")
                Divider().overlay(Theme.hairline)
            }
        }
        .card()
        .padding(.top, 12)
    }
}

// MARK: - Speak button

/// The primary action: 132 pt, reachable with one imprecise tap. No holding required.
struct SpeakButton: View {
    @Environment(FonosEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        let state = engine.speakState
        VStack(spacing: 12) {
            Button(action: engine.primaryAction) {
                ZStack {
                    if state == .listening && !reduceMotion {
                        Circle()
                            .stroke(Theme.alert.opacity(0.5), lineWidth: 3)
                            .scaleEffect(breathe ? 1.18 : 1)
                            .opacity(breathe ? 0 : 1)
                            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: breathe)
                    }
                    Circle().fill(fill(state))
                    icon(state)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(state == .listening ? .white : Theme.onAction)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 132, height: 132)
                .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .disabled(state == .translating)
            .accessibilityLabel(label(state))
            .accessibilityHint(hint(state))
            .onChange(of: state) { _, s in breathe = s == .listening }

            Text(caption(state))
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .medium), trigger: state)
    }

    @ViewBuilder private func icon(_ s: FonosEngine.SpeakState) -> some View {
        switch s {
        case .idle: Image(systemName: "waveform")
        case .listening: Image(systemName: "stop.fill")
        case .translating: ProgressView().controlSize(.large).tint(Theme.onAction)
        case .speaking: Image(systemName: "speaker.wave.3.fill")
        }
    }

    private func fill(_ s: FonosEngine.SpeakState) -> Color {
        switch s {
        case .listening: Theme.alert
        case .translating, .speaking: Theme.pace
        case .idle: Theme.action
        }
    }

    private func caption(_ s: FonosEngine.SpeakState) -> String {
        switch s {
        case .idle: "Speak"
        case .listening: "Listening · tap when done"
        case .translating: "Translating"
        case .speaking: "Speaking · tap to stop"
        }
    }

    private func label(_ s: FonosEngine.SpeakState) -> String {
        switch s {
        case .idle: "Speak"
        case .listening: "Done speaking"
        case .translating: "Translating"
        case .speaking: "Stop speaking"
        }
    }

    private func hint(_ s: FonosEngine.SpeakState) -> String {
        switch s {
        case .idle: "Starts listening to your throat band"
        case .listening: "Translates what you said and speaks it aloud"
        default: ""
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Legend: View {
    let items: [(String, Color)]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.1).frame(width: 7, height: 7)
                    Text(item.0).font(.caption.weight(.medium)).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
