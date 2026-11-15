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

    private var sessions: [SessionRecord] { engine.store.visible }
    private var baseline: Baseline? { engine.store.baseline }

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
                    SampleBanner()

                    Text("All measures")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)

                    ForEach(Metric.allCases) { m in
                        NavigationLink(value: m) { MetricSummaryCard(metric: m, sessions: sessions, baseline: baseline) }
                            .buttonStyle(.plain)
                    }

                    practiceCard.padding(.top, 8)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("Progress")
            .navigationDestination(for: Metric.self) { MetricDetailScreen(metric: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle").font(.title2).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(Theme.ground, for: .navigationBar)
        }
    }

    // MARK: Rings

    private var rings: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Metric.rings) { m in
                NavigationLink(value: m) {
                    VStack(spacing: 10) {
                        MetricRing(metric: m, value: Insights.mean(m, in: sessions, baseline: baseline, days: range.rawValue))
                        HStack(spacing: 2) {
                            Text(m.title).cardTitle()
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(m.title)
                .accessibilityValue(Insights.mean(m, in: sessions, baseline: baseline, days: range.rawValue)
                    .map { "\(m.format($0)) \(m.unit == "%" ? "percent" : m.unit == "syl/s" ? "syllables per second" : m.unit)" } ?? "No data")
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Insight

    @ViewBuilder private var insight: some View {
        let trends = Insights.trends(sessions, baseline: baseline)
        if let h = Insights.headline(trends) {
            VStack(alignment: .leading, spacing: 8) {
                Text(h.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(h.body)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let since = baseline?.establishedOn {
                    Text("Baseline from your first sessions, through \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 4)
                }
            }
            .card(padding: 20)
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
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            }
            HStack {
                ForEach(days, id: \.self) { d in
                    let on = used.contains(d)
                    let isToday = d == today
                    VStack(spacing: 8) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(isToday ? Theme.ink : Theme.inkSecondary)
                        ZStack {
                            Circle().fill(on ? Theme.good : Color.clear)
                            Circle().stroke(on ? Color.clear : Theme.hairline, lineWidth: 1.5)
                            if on {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.ground)
                            }
                        }
                        .frame(width: 26, height: 26)
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
            CardHeader(title: metric.title, symbol: metric.symbol, color: metric.color,
                       detail: latest.map { relative($0.date) }, chevron: true)
            HStack(alignment: .bottom) {
                if let v = recent.last?.1 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.format(v))
                            .font(.metric(.largeTitle, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(metric.unit).font(.subheadline.weight(.medium)).foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    Text("No data yet").font(.title3).foregroundStyle(Theme.inkTertiary)
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
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isLast && highlightLast ? color : Theme.hairline)
                    .frame(maxWidth: 9)
                    .frame(height: max(4, 44 * CGFloat((v - lo) / (hi - lo))))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
