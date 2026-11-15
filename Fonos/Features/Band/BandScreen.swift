import SwiftUI
import UIKit

/// The band: connecting it, its state, and its three raw streams.
///
/// Until a band is connected, the page is a setup guide with one large
/// Connect action. Once signal flows (from the real band, or the simulated
/// one), it shows the live sensors.
///
/// Performance note: this view never reads `engine.live` (which changes
/// 10 times a second). Only `MicLevel` and `BalanceCard` do, so only they
/// re-render; the live traces redraw themselves through their own timelines.
struct BandScreen: View {
    @Environment(FonosEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    BandHero()

                    if case .scanning = engine.link.state { NearbyBands() }

                    if engine.bandConnected {
                        if engine.bandMode == .simulated {
                            SampleBanner(text: "Simulated band. These signals are sample data, not your voice.")
                        }
                        sensors
                    } else {
                        SetupGuide()
                    }

                    ModeFooter()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .fonosScreen()
            .navigationTitle("Band")
        }
    }

    @ViewBuilder private var sensors: some View {
        let simulated = engine.bandMode == .simulated
        Text("Sensors")
            .font(.metric(.title2, weight: .bold))
            .tracking(-0.3)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .accessibilityAddTraits(.isHeader)

        SensorCard(title: "Contact microphone", icon: .mic, color: Theme.mic, ink: Theme.micInk, rate: "8 kHz",
                   contact: simulated ? true : nil) {
            StreamTrace(streams: engine.streams, channel: .mic, color: Theme.mic)
        } trailing: {
            MicLevel()
        }
        SensorCard(title: "Left piezo", icon: .piezoLeft, color: Theme.left, ink: Theme.leftInk, rate: "1 kHz",
                   contact: engine.bandStatus.leftContact) {
            StreamTrace(streams: engine.streams, channel: .left, color: Theme.left)
        }
        SensorCard(title: "Right piezo", icon: .piezoRight, color: Theme.right, ink: Theme.rightInk, rate: "1 kHz",
                   contact: engine.bandStatus.rightContact) {
            StreamTrace(streams: engine.streams, channel: .right, color: Theme.right)
        }

        BalanceCard()
    }
}

// MARK: - Hero

/// The band's identity and state, with the one action that matters now.
private struct BandHero: View {
    @Environment(FonosEngine.self) private var engine
    @State private var confirmForget = false

    private enum Badge { case live, searching, idle, problem }

    var body: some View {
        let p = presentation
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                badge(p.badge)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title)
                        .font(.metric(.title3, weight: .semibold)).tracking(-0.2)
                        .foregroundStyle(Theme.ink)
                    Text(p.detail)
                        .font(.ui(.subheadline, .medium))
                        .foregroundStyle(p.detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if engine.bandConnected {
                    VStack(alignment: .trailing, spacing: 8) {
                        BatteryBadge(percent: engine.bandStatus.battery, charging: engine.bandStatus.isCharging)
                        if engine.bandMode == .bluetooth { SignalBars(rssi: engine.link.rssi) }
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if let note = p.note {
                Text(note)
                    .font(.ui(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = engine.link.lastError, engine.bandMode == .bluetooth {
                Label { Text(error) } icon: { FonosIcon(.warning, size: 18, relativeTo: .subheadline) }
                    .font(.ui(.subheadline, .medium))
                    .foregroundStyle(Theme.cautionInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .card(padding: 20)
        .animation(.smooth(duration: 0.3), value: engine.link.state)
        .confirmationDialog("Forget this band?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget band", role: .destructive) { engine.disconnectBand(forget: true) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Fonos will stop reconnecting to it. You can connect it again any time.")
        }
    }

    // MARK: Badge

    private func badge(_ b: Badge) -> some View {
        ZStack {
            if b == .searching { SearchRings(color: Theme.action) }
            switch b {
            case .live, .searching: Orb(color: Theme.action)
            case .idle: Circle().fill(Theme.well)
            case .problem: Orb(color: Theme.caution)
            }
            FonosIcon(b == .problem ? .bluetooth : .band, size: 28, relativeTo: .title3)
                .foregroundStyle(b == .idle ? Theme.inkTertiary : Theme.onAction)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        switch engine.bandMode {
        case .simulated:
            PrimaryButton(title: "Connect your band", icon: .bluetooth) { engine.setUpBand() }
            pauseButton
        case .bluetooth:
            switch engine.link.state {
            case .connected:
                HStack(spacing: 10) {
                    pauseButton
                    Button("Disconnect") { engine.disconnectBand(forget: false) }.buttonStyle(.well)
                }
            case .scanning:
                Button("Stop looking") { engine.stopFindingBands() }.buttonStyle(.well)
            case .connecting, .waiting:
                Button("Forget this band") { confirmForget = true }.buttonStyle(.well(Theme.inkSecondary))
            case .poweredOff, .unauthorized:
                PrimaryButton(title: "Open Settings", icon: .settings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .unsupported:
                EmptyView()
            case .notStarted, .idle:
                PrimaryButton(title: "Connect band", icon: .bluetooth) { engine.findBands() }
            }
        }
    }

    private var pauseButton: some View {
        Button(engine.isStreaming ? "Pause signal" : "Resume signal") {
            engine.isStreaming ? engine.stopStreaming() : engine.startStreaming()
        }
        .buttonStyle(.well)
    }

    // MARK: Words

    private struct Presentation {
        var badge: Badge
        var title: String
        var detail: String
        var detailColor: Color
        var note: String?
    }

    private var presentation: Presentation {
        let quiet = Theme.inkSecondary
        if engine.bandMode == .simulated {
            return Presentation(badge: engine.isStreaming ? .live : .idle, title: "Simulated band",
                                detail: engine.isStreaming ? "Streaming sample data" : "Paused",
                                detailColor: engine.isStreaming ? Theme.goodInk : quiet)
        }
        switch engine.link.state {
        case .connected(let name):
            let weak = engine.isStreaming && engine.link.framesPerSecond > 0 && engine.link.framesPerSecond < 85
            return Presentation(
                badge: engine.isStreaming ? .live : .idle, title: name,
                detail: !engine.isStreaming ? "Connected, paused" : weak ? "Connected, signal is patchy" : "Connected and streaming",
                detailColor: !engine.isStreaming ? quiet : weak ? Theme.cautionInk : Theme.goodInk,
                note: weak ? "Bring your iPhone closer to the band, within about an arm's length." : nil)
        case .scanning:
            return Presentation(badge: .searching, title: "Looking for your band", detail: "Make sure it's on and close by",
                                detailColor: Theme.actionInk)
        case .connecting(let name):
            return Presentation(badge: .searching, title: name, detail: "Connecting…", detailColor: Theme.actionInk)
        case .waiting(let name):
            return Presentation(badge: .searching, title: name, detail: "Waiting for your band",
                                detailColor: Theme.actionInk,
                                note: "Turn the band on and keep it near your iPhone. Fonos connects on its own when it finds it.")
        case .poweredOff:
            return Presentation(badge: .problem, title: "Bluetooth is off", detail: "Fonos needs Bluetooth to hear your band",
                                detailColor: Theme.cautionInk,
                                note: "Turn on Bluetooth in Control Center, or in Settings.")
        case .unauthorized:
            return Presentation(badge: .problem, title: "Bluetooth isn't allowed", detail: "Fonos can't look for your band",
                                detailColor: Theme.cautionInk,
                                note: "In Settings, open Fonos and turn on Bluetooth.")
        case .unsupported:
            return Presentation(badge: .problem, title: "No Bluetooth here", detail: "This device can't connect to the band",
                                detailColor: Theme.cautionInk,
                                note: "The iOS Simulator has no Bluetooth. Run Fonos on an iPhone to connect the band, or use the simulated band below.")
        case .notStarted, .idle:
            return Presentation(badge: .idle, title: "Fonos band", detail: "Not connected", detailColor: quiet)
        }
    }
}

/// Rings that radiate from the badge while Fonos looks for the band.
/// Still with Reduce Motion: a single soft ring says the same thing.
private struct SearchRings: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false

    var body: some View {
        ZStack {
            if reduceMotion {
                Circle().stroke(color.opacity(0.35), lineWidth: 2).scaleEffect(1.3)
            } else {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(color.opacity(0.5), lineWidth: 2)
                        .scaleEffect(go ? 1.9 : 1)
                        .opacity(go ? 0 : 1)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.9), value: go)
                }
            }
        }
        .onAppear { go = true }
    }
}

// MARK: - Nearby bands

/// Bands found while looking. With one band, Fonos connects on its own after
/// a moment; with more, the user picks by name and signal.
private struct NearbyBands: View {
    @Environment(FonosEngine.self) private var engine

    var body: some View {
        let found = engine.link.found
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Bands nearby", icon: .bluetooth, color: Theme.action, ink: Theme.actionInk)
            if found.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().tint(Theme.actionInk)
                    Text("Looking… This can take a few seconds.")
                        .font(.ui(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(minHeight: 44)
            } else {
                ForEach(found) { band in
                    Button { engine.connectBand(band.id) } label: {
                        HStack(spacing: 14) {
                            FonosIcon(.band, size: 24, relativeTo: .body).foregroundStyle(Theme.actionInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(band.name).font(.ui(.headline)).foregroundStyle(Theme.ink)
                                Text(signalWords(band.rssi)).font(.ui(.footnote)).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer(minLength: 8)
                            SignalBars(rssi: band.rssi)
                            FonosIcon(.chevron, size: 13, relativeTo: .footnote).foregroundStyle(Theme.inkTertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .background(Theme.well.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tile)
                    .accessibilityLabel("\(band.name), \(signalWords(band.rssi))")
                    .accessibilityHint("Connects to this band")
                }
                if found.count == 1 {
                    Text("Connecting to it in a moment, or tap it now.")
                        .font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
                }
            }
        }
        .card()
    }

    private func signalWords(_ rssi: Int) -> String {
        rssi > -65 ? "Close by" : rssi > -80 ? "In range" : "Far away, move closer"
    }
}

// MARK: - Setup guide

/// How to connect, in the order it happens. Shown until the band is connected.
private struct SetupGuide: View {
    @State private var troubleOpen = false

    private let steps: [(String, String)] = [
        ("Power the band", "Charge it, or plug it into a USB power bank. It's ready to connect a few seconds after it powers on."),
        ("Keep your iPhone close", "Within about an arm's length while connecting. After that, across a room is fine."),
        ("Tap Connect band", "Allow Bluetooth when your iPhone asks. Fonos finds the band and connects."),
        ("Put the band on", "Center the microphone at the front of your throat with a sensor on each side. Snug, but comfortable."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connecting your band")
                .font(.metric(.title3, weight: .semibold)).tracking(-0.2)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(i + 1)")
                            .font(.metric(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.actionInk)
                            .frame(width: 30, height: 30)
                            .background(Theme.action.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.0).font(.ui(.headline)).foregroundStyle(Theme.ink)
                            Text(step.1).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(i + 1). \(step.0). \(step.1)")
                }
            }

            Text("Fonos remembers your band and reconnects on its own next time.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.hairline)

            DisclosureGroup(isExpanded: $troubleOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    tip("Turn the band off and on again, then tap Connect band.")
                    tip("Check that Bluetooth is on in Control Center.")
                    tip("Don't pair the band in iPhone Settings. It connects from Fonos only, and won't appear there.")
                    tip("Check the band has power: unplug it and plug it back in. If it still doesn't appear, its firmware may need flashing.")
                    tip("Still stuck? Ask whoever set up your band to check it against the Fonos firmware guide.")
                }
                .padding(.top, 12)
            } label: {
                Text("Band not showing up?")
                    .font(.ui(.headline))
                    .foregroundStyle(Theme.actionInk)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .tint(Theme.actionInk)
        }
        .card(padding: 20)
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Theme.inkTertiary).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            Text(text).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Mode footer

/// Switching between the real band and the simulated one.
private struct ModeFooter: View {
    @Environment(FonosEngine.self) private var engine

    var body: some View {
        VStack(spacing: 6) {
            if engine.bandMode == .bluetooth {
                Button("Use the simulated band instead") { engine.use(.simulated) }
                    .font(.ui(.subheadline, .semibold))
                    .foregroundStyle(Theme.actionInk)
                    .frame(minHeight: 44)
                Text("Shows sample signals, so you can try Fonos without the band.")
            } else if BluetoothBand.remembered != nil {
                Button("Go back to your band") { engine.use(.bluetooth) }
                    .font(.ui(.subheadline, .semibold))
                    .foregroundStyle(Theme.actionInk)
                    .frame(minHeight: 44)
            }
        }
        .font(.ui(.footnote))
        .foregroundStyle(Theme.inkTertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Shared

/// The page's one filled action: 60 pt, the green wire.
private struct PrimaryButton: View {
    let title: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { FonosIcon(icon, size: 22, relativeTo: .headline) }
                .font(.ui(.headline))
                .foregroundStyle(Theme.onAction)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Theme.actionInk, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressScale())
    }
}

/// Live mic level in dBFS. Isolated so only this text refreshes at 10 Hz.
private struct MicLevel: View {
    @Environment(FonosEngine.self) private var engine
    var body: some View {
        Text("\(Int(engine.live.micDb)) dBFS")
            .font(.ui(.subheadline, .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// Live left/right share. Isolated so only this card refreshes at 10 Hz.
private struct BalanceCard: View {
    @Environment(FonosEngine.self) private var engine

    var body: some View {
        let l = engine.live.leftLevel, r = engine.live.rightLevel
        let total = l + r
        let leftShare = total > 0.005 ? Double(l / total) : 0.5
        let leftPct = Int((leftShare * 100).rounded())
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Left / right balance", icon: .symmetry, color: Theme.symmetry, ink: Theme.rightInk)
            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule().fill(Theme.left).frame(width: max(0, geo.size.width * leftShare - 1.5))
                    Capsule().fill(Theme.right)
                }
                .animation(.smooth(duration: 0.25), value: leftShare)
            }
            .frame(height: 12)
            HStack {
                Text("Left \(leftPct)%").foregroundStyle(Theme.leftInk)
                Spacer()
                Text("Right \(100 - leftPct)%").foregroundStyle(Theme.rightInk)
            }
            .font(.ui(.subheadline, .bold))
            .monospacedDigit()
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Left right balance")
        .accessibilityValue("Left \(leftPct) percent, right \(100 - leftPct) percent")
    }
}

struct SensorCard<Trace: View, Trailing: View>: View {
    let title: String
    let icon: Icon
    let color: Color
    let ink: Color
    let rate: String
    /// Nil when the band doesn't report skin contact.
    let contact: Bool?
    @ViewBuilder let trace: Trace
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, icon: icon, color: color, ink: ink, detail: rate)
            trace
                .frame(height: 64)
                .padding(.vertical, 4)
                .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            HStack(spacing: 8) {
                switch contact {
                case true?: CheckDisc(color: Theme.good, size: 20)
                case false?: FonosIcon(.warning, size: 20, relativeTo: .subheadline).foregroundStyle(Theme.caution)
                case nil: EmptyView()
                }
                if let contact {
                    Text(contact ? "Good skin contact" : "No contact. Adjust the band.")
                        .font(.ui(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                trailing
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

extension SensorCard where Trailing == EmptyView {
    init(title: String, icon: Icon, color: Color, ink: Color, rate: String, contact: Bool?, @ViewBuilder trace: () -> Trace) {
        self.init(title: title, icon: icon, color: color, ink: ink, rate: rate, contact: contact, trace: trace, trailing: { EmptyView() })
    }
}
