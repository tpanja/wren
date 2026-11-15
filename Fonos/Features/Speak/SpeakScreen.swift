import SwiftUI

struct SpeakScreen: View {
    @Environment(FonosEngine.self) private var engine
    @Binding var showSettings: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    if typeSize.isAccessibilitySize {
                        // At the largest text sizes, keep Speak in the first viewport.
                        SpeakButton().padding(.vertical, 20)
                        transcriptCard
                        foldCard
                    } else {
                        foldCard
                        transcriptCard
                        SpeakButton().padding(.top, 22).padding(.bottom, 6)
                    }
                    phrases
                    if !engine.utterances.isEmpty { history }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .fonosScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        FonosIcon(.settings, size: 24, relativeTo: .title3)
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusText: String {
        switch engine.speakState {
        case .listening: "Listening"
        case .translating: "Translating"
        case .speaking: "Speaking"
        case .idle:
            if !engine.bandConnected {
                if case .waiting = engine.link.state { "Waiting for band" } else { "Band not connected" }
            } else { engine.isStreaming ? "Band ready" : "Band paused" }
        }
    }

    private var statusColor: Color {
        switch engine.speakState {
        case .listening: Theme.alert
        case .translating, .speaking: Theme.pace
        case .idle: !engine.bandConnected ? Theme.caution : engine.isStreaming ? Theme.good : Theme.inkTertiary
        }
    }

    // MARK: Fold

    private var foldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Throat signal").cardTitle()
                    Spacer()
                    Legend(items: [("Left", Theme.left), ("Mic", Theme.mic), ("Right", Theme.right)])
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Throat signal").cardTitle()
                    Legend(items: [("Left", Theme.left), ("Mic", Theme.mic), ("Right", Theme.right)])
                }
            }
            FoldView(streams: engine.streams)
                .frame(height: 150)
            Text(engine.bandMode == .simulated ? "Sample signal from a simulated band"
                 : engine.bandConnected ? "Live signal from your band" : "Band not connected. Connect it on the Band tab.")
                .font(.ui(.caption))
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
                    .font(.ui(.title2, .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .accessibilityLabel(engine.partialText.isEmpty ? "Waiting for speech" : engine.partialText)
            default:
                if let last = engine.utterances.first {
                    HStack(alignment: .top, spacing: 12) {
                        Text(last.text)
                            .font(.ui(.title2, .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { engine.say(last.text) } label: {
                            FonosIcon(.replay, size: 26, relativeTo: .title3)
                                .frame(width: 52, height: 52)
                                .background(Theme.well, in: Circle())
                        }
                        .accessibilityLabel("Say it again")
                        .disabled(engine.speakState == .speaking)
                    }
                    if let c = last.confidence {
                        Text("Clarity \(Int(c * 100))%")
                            .font(.ui(.footnote, .medium))
                            .foregroundStyle(Theme.leftInk)
                    }
                } else {
                    Text("Tap Speak and talk normally. Fonos will say your words clearly.")
                        .font(.ui(.title3))
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
            Text("Quick phrases").cardTitle().padding(.top, 14).padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(engine.quickPhrases, id: \.self) { phrase in
                    Button { engine.say(phrase, asPhrase: true) } label: {
                        Text(phrase)
                            .font(.ui(.body, .semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .padding(.horizontal, 16)
                            .background { Surface(radius: Theme.tileRadius, lift: 0.6) }
                            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                    }
                    .buttonStyle(.tile)
                    .accessibilityHint("Speaks this phrase")
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Said today").cardTitle().padding(.bottom, 6)
            ForEach(engine.utterances.dropFirst().prefix(8)) { u in
                Button { engine.say(u.text) } label: {
                    HStack {
                        Text(u.text).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Text(u.date, style: .time).font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
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
                            .stroke(Theme.alert.opacity(0.45), lineWidth: 2)
                            .scaleEffect(breathe ? 1.24 : 1)
                            .opacity(breathe ? 0 : 1)
                            .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: breathe)
                    }
                    Orb(color: fill(state))
                    icon(state)
                        .foregroundStyle(state == .listening ? .white : Theme.onAction)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .id(state)
                }
                .frame(width: 132, height: 132)
                .background {
                    // A quiet halo that frames the orb at rest.
                    Circle()
                        .fill(fill(state).opacity(0.07))
                        .overlay(Circle().strokeBorder(fill(state).opacity(0.16), lineWidth: 1))
                        .frame(width: 164, height: 164)
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: state)
                .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .disabled(state == .translating)
            .accessibilityLabel(label(state))
            .accessibilityHint(hint(state))
            .onChange(of: state) { _, s in breathe = s == .listening }

            Text(caption(state))
                .font(.metric(.headline, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.25), value: state)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .medium), trigger: state)
    }

    @ViewBuilder private func icon(_ s: FonosEngine.SpeakState) -> some View {
        switch s {
        case .idle: FonosIcon(.speak, size: 52, relativeTo: .largeTitle)
        case .listening: FonosIcon(.stop, size: 46, relativeTo: .largeTitle)
        case .translating: ProgressView().controlSize(.large).tint(Theme.onAction)
        case .speaking: FonosIcon(.replay, size: 52, relativeTo: .largeTitle)
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
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct Legend: View {
    let items: [(String, Color)]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    Capsule().fill(item.1).frame(width: 10, height: 4)
                    Text(item.0).font(.ui(.caption, .medium)).foregroundStyle(Theme.inkSecondary)
                        .fixedSize()
                }
            }
        }
        .accessibilityHidden(true)
    }
}
