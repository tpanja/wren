import Charts
import SwiftUI

/// Trend for any measure: from conversation (averaged per day) or from the
/// weekly check (one point per check).
struct MeasureDetailScreen: View {
    let measure: Measure
    @Environment(FonosEngine.self) private var engine
    @State private var range: TrendRange
    @State private var selected: Date?

    init(measure: Measure) {
        self.measure = measure
        _range = State(initialValue: measure.isCheck ? .quarter : .month)
    }

    private struct DayPoint: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    private var ranges: [TrendRange] { measure.isCheck ? [.month, .quarter] : TrendRange.allCases }

    private var allPoints: [ClinicReport.Point] {
        measure.series(sessions: engine.store.visible, checks: engine.checks.visible, baseline: engine.store.baseline)
    }

    private var points: [DayPoint] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -range.rawValue, to: .now)!
        let grouped = Dictionary(grouping: allPoints.filter { $0.date >= cutoff }) { cal.startOfDay(for: $0.date) }
        return grouped.map { day, list in DayPoint(day: day, value: list.map(\.value).reduce(0, +) / Double(list.count)) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        let pts = points
        let all = allPoints
        let baselineValue = measure.baselineValue(all)
        let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        let shown = selected.flatMap { s in pts.min { abs($0.day.timeIntervalSince(s)) < abs($1.day.timeIntervalSince(s)) } }
        let trend = MeasureTrend.compute(measure, sessions: engine.store.visible, checks: engine.checks.visible,
                                         baseline: engine.store.baseline)
        let system = SpeechSystem.of(measure)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                Picker("Range", selection: $range) {
                    ForEach(ranges) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Text(shown == nil ? (measure.isCheck ? "Average of checks" : "Average") : shown!.day.formatted(date: .abbreviated, time: .omitted))
                        .cardTitle(Theme.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text((shown?.value ?? avg).map(measure.format) ?? "–")
                            .font(.metric(.largeTitle, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text(measure.unit).font(.ui(.headline)).foregroundStyle(Theme.inkSecondary)
                    }
                    if let trend {
                        Text(trend.phrase + " vs baseline")
                            .font(.ui(.subheadline, .medium))
                            .foregroundStyle(trend.direction == .lower ? Theme.caution : Theme.inkSecondary)
                    }
                }
                .padding(.top, 8)

                chart(pts, baseline: baselineValue)
                    .frame(height: 240)
                    .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("About \(measure.title.lowercased())").font(.ui(.headline)).foregroundStyle(Theme.ink)
                    Text(measure.explanation).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Theme.hairline)
                    Label { Text(measure.howMeasured) } icon: { FonosIcon(measure.isCheck ? .checklist : .band, size: 20, relativeTo: .subheadline) }
                        .font(.ui(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                    Label { Text("\(system.title): \(system.summary.lowercased())") } icon: { FonosIcon(measure.icon, size: 20, relativeTo: .subheadline) }
                        .font(.ui(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .card()

                SampleBanner()
                Text("Fonos describes changes in your speech. It does not diagnose. Talk with your care team about what these trends mean for you.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .navigationTitle(measure.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
    }

    /// Y range fitted to the data and baseline with 15% headroom, so a real
    /// change is visible instead of flattened against a zero baseline.
    private func domain(_ pts: [DayPoint], baseline: Double?) -> ClosedRange<Double> {
        var values = pts.map(\.value)
        if let baseline { values.append(baseline) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, abs(hi) * 0.02, 0.1)
        return (lo - pad)...(hi + pad)
    }

    private func chart(_ pts: [DayPoint], baseline: Double?) -> some View {
        let yDomain = domain(pts, baseline: baseline)
        let color = measure.color
        return Chart {
            if let b = baseline {
                RuleMark(y: .value("Baseline", b))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Baseline").font(.ui(.caption2, .semibold)).foregroundStyle(Theme.inkTertiary)
                    }
            }
            ForEach(pts) { p in
                AreaMark(x: .value("Day", p.day, unit: .day),
                         yStart: .value("Floor", yDomain.lowerBound),
                         yEnd: .value(measure.title, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.25), color.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(measure.title, p.value))
                    .interpolationMethod(measure.isCheck ? .linear : .monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if measure.isCheck {
                    // Weekly checks are few; mark each one.
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value(measure.title, p.value))
                        .foregroundStyle(color).symbolSize(36)
                }
            }
            if let s = selected, let p = pts.min(by: { abs($0.day.timeIntervalSince(s)) < abs($1.day.timeIntervalSince(s)) }) {
                RuleMark(x: .value("Selected", p.day, unit: .day)).foregroundStyle(Theme.hairline)
                PointMark(x: .value("Day", p.day, unit: .day), y: .value(measure.title, p.value))
                    .foregroundStyle(color).symbolSize(80)
            }
        }
        .chartYScale(domain: yDomain)
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
        .accessibilityLabel(measure.isCheck ? "\(measure.title) by weekly check" : "\(measure.title) by day")
    }
}
