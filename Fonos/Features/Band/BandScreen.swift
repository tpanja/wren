import SwiftUI

/// The band's state and its three raw streams. Driven by the simulated band
/// until the hardware link is built.
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
                    deviceCard
                    SampleBanner(text: "Simulated band. The Bluetooth link to the real band isn't built yet.")

                    Text("Sensors")
                        .font(.metric(.title2, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)

                    SensorCard(title: "Contact microphone", icon: .mic, color: Theme.mic, ink: Theme.micInk, rate: "8 kHz", contact: true) {
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
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .fonosScreen()
            .navigationTitle("Band")
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    if engine.isStreaming {
                        Orb(color: Theme.action)
                    } else {
                        Circle().fill(Theme.well)
                    }
                    FonosIcon(.band, size: 28, relativeTo: .title3)
                        .foregroundStyle(engine.isStreaming ? Theme.onAction : Theme.inkTertiary)
                }
                .frame(width: 56, height: 56)
                .animation(.smooth(duration: 0.3), value: engine.isStreaming)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fonos band").font(.metric(.title3, weight: .semibold)).tracking(-0.2).foregroundStyle(Theme.ink)
                    Text(engine.isStreaming ? "Streaming sample data" : "Paused")
                        .font(.ui(.subheadline, .medium))
                        .foregroundStyle(engine.isStreaming ? Theme.goodInk : Theme.inkSecondary)
                }
                Spacer(minLength: 8)
                BatteryBadge(percent: engine.bandStatus.battery, charging: engine.bandStatus.isCharging)
            }
            Button(engine.isStreaming ? "Pause signal" : "Resume signal") {
                engine.isStreaming ? engine.stopStreaming() : engine.startStreaming()
            }
            .buttonStyle(.well)
        }
        .card(padding: 20)
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
    let contact: Bool
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
                if contact {
                    CheckDisc(color: Theme.good, size: 20)
                } else {
                    FonosIcon(.warning, size: 20, relativeTo: .subheadline).foregroundStyle(Theme.caution)
                }
                Text(contact ? "Good skin contact" : "No contact. Adjust the band.")
                    .font(.ui(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                trailing
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

extension SensorCard where Trailing == EmptyView {
    init(title: String, icon: Icon, color: Color, ink: Color, rate: String, contact: Bool, @ViewBuilder trace: () -> Trace) {
        self.init(title: title, icon: icon, color: color, ink: ink, rate: rate, contact: contact, trace: trace, trailing: { EmptyView() })
    }
}
