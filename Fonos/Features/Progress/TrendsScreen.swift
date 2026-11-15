import SwiftUI

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 84
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "3 Months"
        }
    }
    var caption: String {
        switch self {
        case .week: "this week"
        case .month: "this month"
        case .quarter: "last 3 months"
        }
    }
}

/// "Progress" tab. Named TrendsScreen to avoid clashing with SwiftUI.ProgressView.
struct TrendsScreen: View {
    @Environment(CoachEngine.self) private var engine
    @Binding var showSettings: Bool
    @State private var range: TrendRange = .week
    @Environment(\.dynamicTypeSize) private var typeSize

    private var store: TakeStore { engine.store }
    private var technical: Bool { engine.profile.isTechnical }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    rings
                    insight
                    rangeCard

                    ForEach(MetricGroup.allCases) { group in
                        let metrics = MetricID.allCases.filter {
                            $0.group == group && $0 != .range && $0 != .speakingPitch && (technical || $0.isBeginner)
                                && store.mean($0, days: max(range.rawValue, 30)) != nil
                        }
                        if !metrics.isEmpty {
                            Text(group.title)
                                .font(.metric(.title3, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 14)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(metrics) { m in
                                NavigationLink(value: m) { MeasureCard(metric: m, technical: technical) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    practiceCard.padding(.top, 8)
                    SampleBanner()
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("Progress")
            .navigationDestination(for: MetricID.self) { MetricDetailScreen(metric: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        FonosIcon(.settings, size: 24, relativeTo: .title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(Theme.ground, for: .navigationBar)
        }
    }

    // MARK: Rings

    private var rings: some View {
        let values = Dictionary(uniqueKeysWithValues: MetricID.rings.map { ($0, store.mean($0, days: range.rawValue)) })
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(MetricID.rings) { m in ringLink(m, value: values[m] ?? nil, stacked: false) }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(MetricID.rings) { m in ringLink(m, value: values[m] ?? nil, stacked: true) }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func ringLink(_ m: MetricID, value: Double?, stacked: Bool) -> some View {
        NavigationLink(value: m) {
            let label = HStack(spacing: 4) {
                Text(m.ringTitle).cardTitle().lineLimit(1).minimumScaleFactor(0.6)
                FonosIcon(.chevron, size: 12, relativeTo: .caption2).foregroundStyle(Theme.inkSecondary)
            }
            if stacked {
                VStack(spacing: 10) { MetricRing(metric: m, value: value); label }
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 16) { MetricRing(metric: m, value: value, diameter: 104); label; Spacer(minLength: 0) }
                    .card(padding: 14)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.ringTitle)
        .accessibilityValue(value.map { "\(m.ringLabel($0).value) \(m.ringLabel($0).unit == "st" ? "semitones" : "percent")" } ?? "No data")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Insight

    @ViewBuilder private var insight: some View {
        if let w = Insights.weekly(store) {
            VStack(alignment: .leading, spacing: 8) {
                Text(w.title).font(.ui(.headline)).foregroundStyle(Theme.ink)
                Text(w.body).font(.ui(.body)).foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Compared with your first sessions")
                    .font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary).padding(.top, 4)
            }
            .card(padding: 20)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Range

    private var rangeCard: some View {
        let now = store.rangeSpan(days: max(range.rawValue, 30))
        let before = store.previousRangeSpan(days: 30)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Voice range", icon: .range, color: Theme.rangeHue)
            VoiceRangeStrip(low: now?.low, high: now?.high, previousLow: before?.low, previousHigh: before?.high)
            if before != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).stroke(Theme.inkSecondary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                        .frame(width: 18, height: 10)
                    Text("Outline: the month before").font(.ui(.caption)).foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityHidden(true)
            }
        }
        .card()
    }

    // MARK: Practice days (WHOOP weekday row)

    private var practiceCard: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let used = store.practicedDays
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Days practiced").cardTitle()
                Spacer()
                Text("\(days.filter(used.contains).count) of 7")
                    .font(.ui(.footnote, .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            HStack {
                ForEach(days, id: \.self) { d in
                    let on = used.contains(d)
                    VStack(spacing: 8) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.metric(.caption, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(d == today ? Theme.ink : Theme.inkSecondary)
                        if on {
                            CheckDisc(color: Theme.good, size: 26)
                        } else {
                            Circle().stroke(Theme.hairline, lineWidth: 1.5).frame(width: 26, height: 26)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(d.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue(on ? "Practiced" : "No practice")
                }
            }
        }
        .card()
    }
}

// MARK: - Measure card (Apple Health style)

struct MeasureCard: View {
    let metric: MetricID
    let technical: Bool
    @Environment(CoachEngine.self) private var engine

    var body: some View {
        let store = engine.store
        let recent = store.daily(metric, days: 30).suffix(7).map(\.value)
        let latestTake = store.sorted.last { $0.value(metric) != nil }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CardHeader(title: metric.name(technical: technical), icon: metric.icon, color: metric.color,
                           detail: latestTake.map { relative($0.date) }, chevron: true)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let v = recent.last {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(metric.format(v))
                                .font(.metric(.largeTitle, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(metric.unit).font(.ui(.subheadline, .medium)).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    if metric.status == .exploratory { ExploratoryTag() }
                }
                Spacer()
                MiniBars(values: recent, color: metric.hasHue ? metric.color : Theme.action)
                    .frame(width: 92, height: 44)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name(technical: technical))
        .accessibilityValue(recent.last.map { "Latest \(metric.format($0)) \(metric.unit)" } ?? "No data")
        .accessibilityHint("Shows the trend")
    }

    private func relative(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Apple Health's small trailing bar chart: muted history, last value in color.
struct MiniBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        let lo = (values.min() ?? 0) * 0.85
        let hi = max(values.max() ?? 1, lo + 0.0001)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i == values.count - 1 ? color : Theme.hairline)
                    .frame(maxWidth: 9)
                    .frame(height: max(4, 44 * CGFloat((v - lo) / (hi - lo))))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
