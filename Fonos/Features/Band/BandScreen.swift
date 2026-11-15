import SwiftUI

/// The band's state and its three raw streams. Driven by the simulated band
/// until the hardware link is built.
struct BandScreen: View {
    @Environment(FonosEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    deviceCard
                    SampleBanner(text: "Simulated band. The Bluetooth link to the real band isn't built yet.")

                    Text("Sensors")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)

                    SensorCard(title: "Contact microphone", symbol: "mic", color: Theme.mic,
                               rate: "8 kHz", level: engine.live.micDb, contact: true,
                               trace: StreamTrace(streams: engine.streams, channel: .mic, color: Theme.mic))
                    SensorCard(title: "Left piezo", symbol: "l.circle", color: Theme.left,
                               rate: "1 kHz", level: nil, contact: engine.bandStatus.leftContact,
                               trace: StreamTrace(streams: engine.streams, channel: .left, color: Theme.left))
                    SensorCard(title: "Right piezo", symbol: "r.circle", color: Theme.right,
                               rate: "1 kHz", level: nil, contact: engine.bandStatus.rightContact,
                               trace: StreamTrace(streams: engine.streams, channel: .right, color: Theme.right))

                    balanceCard
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("Band")
            .toolbarBackground(Theme.ground, for: .navigationBar)
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(engine.isStreaming ? Theme.action : Theme.inkTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fonos band").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(engine.isStreaming ? "Streaming sample data" : "Paused")
                        .font(.subheadline)
                        .foregroundStyle(engine.isStreaming ? Theme.good : Theme.inkSecondary)
                }
                Spacer()
                BatteryBadge(percent: engine.bandStatus.battery, charging: engine.bandStatus.isCharging)
            }
            Button(engine.isStreaming ? "Pause signal" : "Resume signal") {
                engine.isStreaming ? engine.stopStreaming() : engine.startStreaming()
            }
            .buttonStyle(.well)
        }
        .card(padding: 20)
    }

    private var balanceCard: some View {
        let l = engine.live.leftLevel, r = engine.live.rightLevel
        let total = l + r
        let leftShare = total > 0.005 ? Double(l / total) : 0.5
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Left / right balance", symbol: "arrow.left.and.right", color: Theme.symmetry)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Theme.left).frame(width: geo.size.width * leftShare)
                    Rectangle().fill(Theme.right)
                }
                .clipShape(Capsule())
                .animation(.easeOut(duration: 0.2), value: leftShare)
            }
            .frame(height: 14)
            HStack {
                Text("Left \(Int(leftShare * 100))%").foregroundStyle(Theme.left)
                Spacer()
                Text("Right \(100 - Int(leftShare * 100))%").foregroundStyle(Theme.right)
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Left right balance")
        .accessibilityValue("Left \(Int(leftShare * 100)) percent, right \(100 - Int(leftShare * 100)) percent")
    }
}

struct SensorCard<Trace: View>: View {
    let title: String
    let symbol: String
    let color: Color
    let rate: String
    let level: Float?
    let contact: Bool
    let trace: Trace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, symbol: symbol, color: color, detail: rate)
            trace.frame(height: 64)
            HStack(spacing: 6) {
                Image(systemName: contact ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(contact ? Theme.good : Theme.caution)
                Text(contact ? "Good skin contact" : "No contact. Adjust the band.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                if let level {
                    Text("\(Int(level)) dB").font(.subheadline.weight(.medium)).monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
