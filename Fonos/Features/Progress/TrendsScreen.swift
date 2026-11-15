import Charts
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
}

/// "Progress" tab. Named TrendsScreen to avoid clashing with SwiftUI.ProgressView.
struct TrendsScreen: View {
    @Environment(FonosEngine.self) private var engine
    @Binding var showSettings: Bool
    @State private var range: TrendRange = .week
    @Environment(\.dynamicTypeSize) private var typeSize

    private var sessions: [SessionRecord] { engine.store.visible }
    private var baseline: Baseline? { engine.store.baseline }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stack) {
                    SegmentedPicker(options: TrendRange.allCases, selection: $range, title: \.title)

                    rings
                    insight
                    SampleBanner()

                    Text("All measures")
                        .font(.metric(.title2, weight: .bold))
                        .tracking(-0.3)
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)

                    ForEach(Metric.allCases) { m in
                        NavigationLink(value: m) { MetricSummaryCard(metric: m, sessions: sessions, baseline: baseline) }
                            .buttonStyle(.tile)
                    }

                    practiceCard.padding(.top, 8)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 28)
            }
            .fonosScreen()
            .navigationTitle("Progress")
            .navigationDestination(for: Metric.self) { MetricDetailScreen(metric: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        FonosIcon(.settings, size: 24, relativeTo: .title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    // MARK: Rings

    private var rings: some View {
        let values = Dictionary(uniqueKeysWithValues: Metric.rings.map {
            ($0, Insights.mean($0, in: sessions, baseline: baseline, days: range.rawValue))
        })
        return Group {
            if typeSize.isAccessibilitySize {
                // Large text: one ring per row so labels never split mid-word.
                VStack(spacing: 10) {
                    ForEach(Metric.rings) { m in ringLink(m, value: values[m] ?? nil, stacked: false) }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Metric.rings) { m in ringLink(m, value: values[m] ?? nil, stacked: true) }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 6)
                .background { Surface() }
            }
        }
        .padding(.top, 4)
    }

    private func ringLink(_ m: Metric, value: Double?, stacked: Bool) -> some View {
        NavigationLink(value: m) {
            let label = HStack(spacing: 4) {
                Text(m.title).cardTitle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                FonosIcon(.chevron, size: 11, relativeTo: .caption2).foregroundStyle(Theme.inkTertiary)
            }
            if stacked {
                VStack(spacing: 12) { MetricRing(metric: m, value: value); label }
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 16) { MetricRing(metric: m, value: value, diameter: 104); label; Spacer(minLength: 0) }
                    .card(padding: 14)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.title)
        .accessibilityValue(value.map { "\(m.format($0)) \(m.unit == "%" ? "percent" : m.unit == "syl/s" ? "syllables per second" : m.unit)" } ?? "No data")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Insight

    @ViewBuilder private var insight: some View {
        let trends = Insights.trends(sessions, baseline: baseline)
        if let h = Insights.headline(trends) {
            VStack(alignment: .leading, spacing: 8) {
                Label { Text("Insight") } icon: { FonosIcon(.clarity, size: 15, relativeTo: .footnote) }
                    .cardTitle(Theme.action)
                    .padding(.bottom, 2)
                Text(h.title)
                    .font(.metric(.title3, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                Text(h.body)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let since = baseline?.establishedOn {
                    Text("Baseline from your first sessions, through \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Surface()
                    // A faint jade wash from the top corner marks the one card that interprets.
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.action.opacity(0.08), Theme.action.opacity(0)],
                                             startPoint: .topLeading, endPoint: .center))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Practice days (WHOOP journal row)

    private var practiceCard: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let used = Set(sessions.map { cal.startOfDay(for: $0.date) })
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Days with sessions").cardTitle()
                Spacer()
                Text("\(days.filter(used.contains).count) of 7")
                    .font(.ui(.footnote, .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            HStack {
                ForEach(days, id: \.self) { d in
                    let on = used.contains(d)
                    let isToday = d == today
                    VStack(spacing: 8) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.ui(.caption, .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(isToday ? Theme.ink : Theme.inkSecondary)
                        ZStack {
                            Circle().fill(on ? Theme.action : Theme.well)
                            if on {
                                FonosIcon(.check, size: 15, relativeTo: .caption).foregroundStyle(Theme.onAction)
                            }
                        }
                        .frame(width: 30, height: 30)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(d.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue(on ? "Session recorded" : "No session")
                }
            }
        }
        .card()
    }
}

// MARK: - Summary card (Apple Health style)

struct MetricSummaryCard: View {
    let metric: Metric
    let sessions: [SessionRecord]
    let baseline: Baseline?

    var body: some View {
        let recent = sessions.suffix(7).compactMap { s in metric.value(s, baseline: baseline).map { (s.date, $0) } }
        let latest = sessions.last
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: metric.title, icon: metric.icon, color: metric.color,
                       detail: latest.map { relative($0.date) }, chevron: true)
            HStack(alignment: .bottom) {
                if let v = recent.last?.1 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.format(v))
                            .font(.metric(.largeTitle, weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(Theme.ink)
                        Text(metric.unit).font(.ui(.subheadline, .medium)).foregroundStyle(Theme.inkTertiary)
                    }
                } else {
                    Text("No data yet").font(.ui(.title3)).foregroundStyle(Theme.inkTertiary)
                }
                Spacer()
                MiniBars(values: recent.map(\.1), color: metric.color, highlightLast: true)
                    .frame(width: 92, height: 44)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(recent.last.map { "Latest \(metric.format($0.1)) \(metric.unit)" } ?? "No data")
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
    var highlightLast = true

    var body: some View {
        let lo = (values.min() ?? 0) * 0.85
        let hi = max(values.max() ?? 1, lo + 0.0001)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let isLast = i == values.count - 1
                Capsule(style: .continuous)
                    .fill(isLast && highlightLast ? color : color.opacity(0.18))
                    .frame(maxWidth: 8)
                    .frame(height: max(4, 44 * CGFloat((v - lo) / (hi - lo))))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
