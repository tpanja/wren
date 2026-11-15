import Charts
import SwiftUI

struct MetricDetailScreen: View {
    let metric: Metric
    @Environment(FonosEngine.self) private var engine
    @State private var range: TrendRange = .month
    @State private var selected: Date?

    private struct DayPoint: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    private var points: [DayPoint] {
        let cal = Calendar.current
        let baseline = engine.store.baseline
        let cutoff = cal.date(byAdding: .day, value: -range.rawValue, to: .now)!
        let grouped = Dictionary(grouping: engine.store.visible.filter { $0.date >= cutoff }) { cal.startOfDay(for: $0.date) }
        return grouped.compactMap { day, list in
            let vals = list.compactMap { metric.value($0, baseline: baseline) }
            guard !vals.isEmpty else { return nil }
            return DayPoint(day: day, value: vals.reduce(0, +) / Double(vals.count))
        }
        .sorted { $0.day < $1.day }
    }

    private var baselineValue: Double? {
        let base = engine.store.visible.prefix(5).compactMap { metric.value($0, baseline: engine.store.baseline) }
        return base.isEmpty ? nil : base.reduce(0, +) / Double(base.count)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(shown == nil ? "Average" : shown!.day.formatted(date: .abbreviated, time: .omitted))
                        .cardTitle(Theme.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text((shown?.value ?? avg).map(metric.format) ?? "–")
                            .font(.metric(.largeTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text(metric.unit).font(.headline).foregroundStyle(Theme.inkSecondary)
                    }
                    if let trend = Insights.trends(engine.store.visible, baseline: engine.store.baseline).first(where: { $0.metric == metric }) {
                        Text(trend.phrase + " vs baseline")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(trend.direction == .lower ? Theme.caution : Theme.inkSecondary)
                    }
                }
                .padding(.top, 8)

                chart(pts)
                    .frame(height: 240)
                    .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("About \(metric.title.lowercased())").font(.headline).foregroundStyle(Theme.ink)
                    Text(metric.explanation).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Theme.hairline)
                    Label(metric.howMeasured, systemImage: "sensor.tag.radiowaves.forward")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .card()

                SampleBanner()
                Text("Fonos describes changes in your speech. It does not diagnose. Talk with your care team about what these trends mean for you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
    }

    private func chart(_ pts: [DayPoint]) -> some View {
        Chart {
            if let b = baselineValue {
                RuleMark(y: .value("Baseline", b))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Baseline").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                    }
            }
            ForEach(pts) { p in
                AreaMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [metric.color.opacity(0.25), metric.color.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(metric.color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            if let s = selected, let p = pts.min(by: { abs($0.day.timeIntervalSince(s)) < abs($1.day.timeIntervalSince(s)) }) {
                RuleMark(x: .value("Selected", p.day, unit: .day)).foregroundStyle(Theme.hairline)
                PointMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                    .foregroundStyle(metric.color).symbolSize(80)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.inkSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel().foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityLabel("\(metric.title) by day")
    }
}
