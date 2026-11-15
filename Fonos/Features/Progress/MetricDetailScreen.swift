import Charts
import SwiftUI

struct MetricDetailScreen: View {
    let metric: MetricID
    @Environment(CoachEngine.self) private var engine
    @State private var range: TrendRange = .month
    @State private var selected: Date?

    private struct DayPoint: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    private var technical: Bool { engine.profile.isTechnical }

    private var points: [DayPoint] {
        if metric == .range {
            // Range per day from that day's sirens.
            let cal = Calendar.current
            let grouped = Dictionary(grouping: engine.store.takes(days: range.rawValue)) { cal.startOfDay(for: $0.date) }
            return grouped.compactMap { day, list in
                guard let lo = list.compactMap(\.lowNote).min(), let hi = list.compactMap(\.highNote).max(), hi > lo else { return nil }
                return DayPoint(day: day, value: Double(hi - lo))
            }
            .sorted { $0.day < $1.day }
        }
        return engine.store.daily(metric, days: range.rawValue).map { DayPoint(day: $0.day, value: $0.value) }
    }

    private var baselineValue: Double? {
        guard let b = engine.store.baseline(metric) else { return nil }
        return metric.display(b, baseline: b)
    }

    var body: some View {
        let pts = points
        let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        let shown = selected.flatMap { s in pts.min { abs($0.day.timeIntervalSince(s)) < abs($1.day.timeIntervalSince(s)) } }

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                // Value first; the period caption follows it (no label stacked above the number).
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text((shown?.value ?? avg).map(metric.format) ?? "–")
                            .font(.metric(.largeTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text(metric.unit).font(.ui(.headline)).foregroundStyle(Theme.inkSecondary)
                    }
                    Text(shown.map { "on \($0.day.formatted(date: .abbreviated, time: .omitted))" } ?? "average \(range.caption)")
                        .font(.ui(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                    if let avg, let b = baselineValue, b != 0, metric.better != .none {
                        trend(avg, b)
                    }
                    if metric.status == .exploratory { ExploratoryTag().padding(.top, 2) }
                }
                .padding(.top, 8)

                chart(pts)
                    .frame(height: 240)
                    .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("What this means").font(.ui(.headline)).foregroundStyle(Theme.ink)
                    Text(metric.explanation).font(.ui(.body)).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Theme.hairline)
                    Text("How it's measured").font(.ui(.headline)).foregroundStyle(Theme.ink)
                    HStack(alignment: .top, spacing: 10) {
                        HStack(spacing: 4) {
                            ForEach(metric.howMeasured.sensors, id: \.self) { icon in
                                FonosIcon(icon, size: 20).foregroundStyle(sensorColor(icon))
                            }
                        }
                        Text(metric.howMeasured.text).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if metric.status == .exploratory {
                        Divider().overlay(Theme.hairline)
                        Text("Why this is exploratory").font(.ui(.headline)).foregroundStyle(Theme.ink)
                        Text(MetricID.exploratoryNote).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()

                SampleBanner()
                Text("Fonos describes your singing. It isn't a medical device and doesn't diagnose.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .navigationTitle(metric.name(technical: technical))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
    }

    private func sensorColor(_ icon: Icon) -> Color {
        switch icon {
        case .mic: Theme.mic
        case .accelLeft: Theme.left
        case .accelRight: Theme.right
        default: Theme.inkSecondary
        }
    }

    /// "↑ 9% better than your first sessions", in ink with an arrow.
    private func trend(_ value: Double, _ base: Double) -> some View {
        let change = (value - base) / abs(base)
        let better: Bool
        switch metric.better {
        case .higher: better = change > 0
        case .lower: better = change < 0
        case .nearZero: better = abs(value) < abs(base)
        case .none: better = true
        }
        let pct = Int((abs(change) * 100).rounded())
        let steady = pct < 5
        return TrendText(text: steady ? "About the same as your first sessions" : "\(pct)% \(better ? "better" : "less good") than your first sessions",
                         direction: steady ? 0 : (change > 0 ? 1 : -1))
    }

    private func chart(_ pts: [DayPoint]) -> some View {
        var values = pts.map(\.value)
        if let b = baselineValue { values.append(b) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, abs(hi) * 0.02, 0.1)
        let domain = (lo - pad)...(hi + pad)
        return Chart {
            if let b = baselineValue {
                RuleMark(y: .value("Baseline", b))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Your start").font(.ui(.caption2, .semibold)).foregroundStyle(Theme.inkTertiary)
                    }
            }
            ForEach(pts) { p in
                // Monotone line with marked points: no invented peaks between days.
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                    .foregroundStyle(lineColor)
                    .symbolSize(18)
            }
            if let s = selected, let p = pts.min(by: { abs($0.day.timeIntervalSince(s)) < abs($1.day.timeIntervalSince(s)) }) {
                RuleMark(x: .value("Selected", p.day, unit: .day)).foregroundStyle(Theme.hairline)
                PointMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                    .foregroundStyle(lineColor).symbolSize(90)
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.ui(.caption)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel().font(.ui(.caption)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityLabel("\(metric.title) by day")
    }

    private var lineColor: Color { metric.hasHue ? metric.color : Theme.action }
}
