import SwiftUI

struct SingScreen: View {
    @Environment(CoachEngine.self) private var engine
    @Binding var showSettings: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    todayCard
                    throatCard
                    upNextCard
                    exercises
                    if !earlierToday.isEmpty { earlierCard }
                    SampleBanner().padding(.top, 8)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        FonosIcon(.settings, size: 24, relativeTo: .title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .principal) {
                    StatusPill(text: statusText, color: statusColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    BatteryBadge(percent: engine.bandStatus.battery, charging: engine.bandStatus.isCharging)
                }
            }
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var fitOK: Bool { engine.bandStatus.leftContact && engine.bandStatus.rightContact }
    private var statusText: String { !engine.isStreaming ? "Band paused" : fitOK ? "Band ready" : "Check band fit" }
    private var statusColor: Color { !engine.isStreaming ? Theme.inkTertiary : fitOK ? Theme.good : Theme.caution }

    // MARK: Today

    private var todayCard: some View {
        let takes = engine.store.today
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").cardTitle()
                Spacer()
                Text(takes.isEmpty ? "Ready when you are" : "\(takes.count) take\(takes.count == 1 ? "" : "s") · \(engine.store.minutesToday) min")
                    .font(.ui(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: 0) {
                ForEach(MetricID.rings) { m in
                    VStack(spacing: 6) {
                        MetricRing(metric: m, value: todayValue(m), diameter: 64, lineWidth: 6, compact: true)
                        Text(m.ringTitle)
                            .font(.ui(.caption, .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(m.ringTitle) today")
                    .accessibilityValue(todayValue(m).map { "\(m.ringLabel($0).value) \(m.ringLabel($0).unit == "st" ? "semitones" : "percent")" } ?? "No takes yet")
                }
            }
        }
        .card()
    }

    private func todayValue(_ m: MetricID) -> Double? {
        if m == .range {
            let today = engine.store.today
            guard let lo = today.compactMap(\.lowNote).min(), let hi = today.compactMap(\.highNote).max(), hi > lo else { return nil }
            return Double(hi - lo)
        }
        let v = engine.store.today.compactMap { $0.value(m) }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    // MARK: Throat strip

    private var throatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Throat").cardTitle()
                Spacer()
                Legend(items: [("Left", Theme.left), ("Mic", Theme.mic), ("Right", Theme.right)])
            }
            FoldView(streams: engine.streams)
                .frame(height: 72)
            Text("Hum any note to check the band is fitted evenly.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.inkSecondary)
        }
        .card()
    }

    // MARK: Up next

    private var upNextCard: some View {
        let s = engine.suggestion
        return VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Up next").cardTitle()
                HStack(spacing: 10) {
                    FonosIcon(s.kind.icon, size: 26, relativeTo: .title3).foregroundStyle(Theme.action)
                    Text(s.kind.title).font(.metric(.title3, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                Text(s.reason).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { engine.begin(s.kind) } label: {
                ZStack {
                    Circle().fill(Theme.action)
                    VStack(spacing: 4) {
                        FonosIcon(.sing, size: 44, relativeTo: .largeTitle)
                        Text("Sing").font(.metric(.headline, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onAction)
                }
                .frame(width: 132, height: 132)
                .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Sing \(s.kind.title)")
            .accessibilityHint(s.kind.instruction)
        }
        .card(padding: 20)
    }

    // MARK: Exercises

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises")
                .font(.metric(.title3, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ExerciseKind.allCases) { kind in
                    Button { engine.begin(kind) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            FonosIcon(kind.icon, size: 24, relativeTo: .body).foregroundStyle(Theme.action)
                            Text(kind.title)
                                .font(.ui(.body, .semibold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Text(kind.purpose)
                                .font(.ui(.footnote))
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressScale())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(kind.instruction)
                }
            }
        }
    }

    // MARK: Earlier today

    private var earlierToday: [TakeRecord] { engine.store.today.reversed() }

    private var earlierCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Earlier today").cardTitle().padding(.bottom, 8)
            ForEach(earlierToday.prefix(6)) { take in
                Button { engine.reopen(take) } label: {
                    HStack(spacing: 12) {
                        FonosIcon(take.kind.icon, size: 20).foregroundStyle(Theme.inkSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(take.feedback?.headline ?? take.kind.title)
                                .font(.ui(.body, .medium))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Text("\(take.kind.title) · \(take.date.formatted(date: .omitted, time: .shortened))")
                                .font(.ui(.footnote))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        Spacer(minLength: 8)
                        FonosIcon(.chevron, size: 14, relativeTo: .footnote).foregroundStyle(Theme.inkTertiary)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if take.id != earlierToday.prefix(6).last?.id { Divider().overlay(Theme.hairline) }
            }
        }
        .card()
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
                    Text(item.0).font(.ui(.caption, .medium)).foregroundStyle(Theme.inkSecondary).fixedSize()
                }
            }
        }
        .accessibilityHidden(true)
    }
}
