import Charts
import SwiftUI

/// The printed pages. US Letter (612 × 792 pt), always light, fixed point
/// sizes: this is a document for a clinic chart, not an app screen, so it
/// ignores Dynamic Type and dark mode on purpose.
///
/// Page 1: summary and the measures table, grouped by speech system.
/// Page 2: a trend chart per measure, data quality, and methods.
struct ClinicReportPage: View {
    let report: ClinicReport
    var page = 1

    static let size = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 40
    static let pageCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page == 1 {
                header
                patientBlock.padding(.top, 12)
                if report.isSample { sampleNotice.padding(.top, 10) }
                summaryBlock.padding(.top, 12)
                measuresTable.padding(.top, 12)
            } else {
                runningHeader
                trendGrid.padding(.top, 14)
                footBlocks.padding(.top, 14)
            }
            Spacer(minLength: 10)
            footer
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Paper.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Paper.accent).frame(height: 2.5)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FONOS")
                        .font(Paper.display(8.5, .semibold)).tracking(2.2)
                        .foregroundStyle(Paper.accent)
                    Text("Speech Monitoring Summary")
                        .font(Paper.display(18, .semibold))
                        .foregroundStyle(Paper.ink)
                    Text("Throat-band speech measures and weekly speech checks between clinic visits")
                        .font(Paper.text(8.5)).foregroundStyle(Paper.ink2)
                }
                Spacer()
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    meta("Report period", periodText)
                    meta("Generated", Paper.dateTime(report.generated))
                    meta("Report ID", report.reportID)
                }
            }
            .padding(.top, 10)
        }
    }

    /// Smaller header on page 2, so a loose page can still be identified.
    private var runningHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Paper.accent).frame(height: 1.5)
            HStack(alignment: .firstTextBaseline) {
                Text("FONOS").font(Paper.display(7.5, .semibold)).tracking(2).foregroundStyle(Paper.accent)
                Text("Speech Monitoring Summary").font(Paper.display(10, .semibold)).foregroundStyle(Paper.ink)
                Spacer()
                Text([report.patient.name.isEmpty ? nil : report.patient.name, periodText, report.reportID]
                        .compactMap { $0 }.joined(separator: "  ·  "))
                    .font(Paper.text(7.5)).monospacedDigit().foregroundStyle(Paper.ink2)
            }
            .padding(.top, 6)
        }
    }

    private func meta(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label.uppercased())
                .font(Paper.text(6.5, .semibold)).tracking(0.8).foregroundStyle(Paper.ink3)
                .gridColumnAlignment(.trailing)
            Text(value).font(Paper.text(8.5)).monospacedDigit().foregroundStyle(Paper.ink)
        }
    }

    private var periodText: String {
        "\(Paper.date(report.periodStart)) – \(Paper.date(report.periodEnd))"
    }

    // MARK: Patient

    private var patientBlock: some View {
        HStack(alignment: .top, spacing: 0) {
            field("Patient", report.patient.name.isEmpty ? nil : report.patient.name, width: 140)
            field("Date of birth", report.patient.dateOfBirth.map(Paper.date), width: 80)
            field("Baseline", baselineText, width: 200)
            field("Period", periodLength, width: nil)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Paper.rule(0.75) }
        .overlay(alignment: .bottom) { Paper.rule(0.6) }
    }

    private func field(_ label: String, _ value: String?, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Paper.text(6.5, .semibold)).tracking(0.8).foregroundStyle(Paper.ink3)
            if let value {
                Text(value).font(Paper.text(9, .semibold)).foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Blank line the clinic can fill in by hand.
                Rectangle().fill(Paper.ink3).frame(height: 0.75).padding(.top, 11).padding(.trailing, 14)
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private var baselineText: String {
        var parts: [String] = []
        if let s = report.baselineStart, let e = report.baselineEnd { parts.append("First 5 sessions, \(range(s, e))") }
        if let s = report.checkBaselineStart, let e = report.checkBaselineEnd { parts.append("first 3 checks, \(range(s, e))") }
        guard !parts.isEmpty else { return "Not yet set" }
        let text = parts.joined(separator: "; ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func range(_ s: Date, _ e: Date) -> String {
        let sameMonth = Calendar.current.isDate(s, equalTo: e, toGranularity: .month)
        let end = sameMonth ? "\(Calendar.current.component(.day, from: e))" : Paper.shortDate(e)
        return "\(Paper.shortDate(s))–\(end)"
    }

    private var periodLength: String {
        let q = report.quality
        let scope = report.sinceLastExport ? "since last summary" : "all data to date"
        return "\(q.periodDays) days, \(scope)"
    }

    // MARK: Notice + summary

    private var sampleNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("SAMPLE DATA").font(Paper.text(7, .bold)).tracking(1).foregroundStyle(Paper.brick)
            Text("Values come from a simulated band and synthetic session and check histories. They are not measurements of this patient.")
                .font(Paper.text(8)).foregroundStyle(Paper.ink2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paper.notice)
        .overlay(Rectangle().stroke(Paper.brick.opacity(0.55), lineWidth: 0.6))
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Paper.sectionTitle("Summary")
            Text(report.summary)
                .font(Paper.text(9.5)).foregroundStyle(Paper.ink)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Measures table

    private enum Col {
        static let measure: CGFloat = 150
        static let baseline: CGFloat = 56
        static let mean: CGFloat = 72
        static let change: CGFloat = 64
        static let slope: CGFloat = 108
        // status takes the rest (~80)
    }

    private var measuresTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Paper.sectionTitle("Measures by speech system").padding(.bottom, 5)
            HStack(alignment: .bottom, spacing: 0) {
                headerCell("Measure", Col.measure, .leading)
                headerCell("Baseline", Col.baseline, .trailing)
                headerCell("Period mean (n)", Col.mean, .trailing)
                headerCell("Change", Col.change, .trailing)
                headerCell("Slope / 30 days (95% CI)", Col.slope, .trailing)
                headerCell("Status", nil, .leading).padding(.leading, 12)
            }
            .padding(.bottom, 4)
            Paper.rule(0.75)
            ForEach(SpeechSystem.allCases) { sys in
                let rows = report.rows.filter { $0.system == sys }
                if !rows.isEmpty {
                    groupRow(sys)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        tableRow(row)
                        if i < rows.count - 1 { Paper.rule(0.5) }
                    }
                }
            }
            Paper.rule(0.75)
            Text("n counts sessions for conversation measures and weekly checks for check measures. Change is relative to baseline, except reading fatigue (dB) and self-ratings (points), which are absolute differences.")
                .font(Paper.text(6.5)).foregroundStyle(Paper.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func groupRow(_ sys: SpeechSystem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sys.title.uppercased()).font(Paper.text(7, .bold)).tracking(0.9).foregroundStyle(Paper.accent)
            Text(sys.reportNote).font(Paper.text(6.5)).foregroundStyle(Paper.ink3)
        }
        .padding(.top, 7).padding(.bottom, 2)
    }

    private func headerCell(_ title: String, _ width: CGFloat?, _ align: Alignment) -> some View {
        Text(title.uppercased())
            .font(Paper.text(6.5, .semibold)).tracking(0.6).foregroundStyle(Paper.ink3)
            .frame(width: width, alignment: align)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: align)
    }

    private func tableRow(_ r: ClinicReport.Row) -> some View {
        let m = r.measure
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(m.reportName).font(Paper.text(8.5, .semibold)).foregroundStyle(Paper.ink)
                Text(m.reportUnit).font(Paper.text(6)).foregroundStyle(Paper.ink3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: Col.measure, alignment: .leading)

            num(r.baseline.map(m.reportFormat) ?? "—", Col.baseline)
            num(r.periodMean.map { "\(m.reportFormat($0)) (\(r.n))" } ?? "— (\(r.n))", Col.mean)
            num(r.change.map { Paper.change($0, m) } ?? "—", Col.change, bold: r.status == .unfavorable)
            num(r.slope.map { "\(Paper.signed($0.perMonth, m)) ± \(m.reportFormat($0.ci95))" } ?? "—", Col.slope)

            Text(r.status.label)
                .font(Paper.text(8, r.status == .unfavorable ? .bold : .regular))
                .foregroundStyle(statusColor(r.status))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .padding(.vertical, 3.5)
    }

    private func num(_ s: String, _ width: CGFloat, bold: Bool = false) -> some View {
        Text(s)
            .font(Paper.display(8, bold ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(Paper.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: width, alignment: .trailing)
    }

    private func statusColor(_ s: ClinicReport.Status) -> Color {
        switch s {
        case .unfavorable: Paper.brick
        case .favorable: Paper.green
        case .stable: Paper.ink2
        case .insufficient: Paper.ink3
        }
    }

    // MARK: Trend grid

    private var trendGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Paper.sectionTitle("Trends in this period")
                Spacer()
                legend
            }
            // A plain Grid, not LazyVGrid: lazy containers don't draw in ImageRenderer.
            let rows = stride(from: 0, to: report.rows.count, by: 4).map { Array(report.rows[$0..<min($0 + 4, report.rows.count)]) }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        ForEach(rows[i]) { MiniTrend(row: $0) }
                        ForEach(0..<(4 - rows[i].count), id: \.self) { _ in Color.clear.frame(height: 1) }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Circle().fill(Paper.ink3).frame(width: 4, height: 4)
                Text("session or check").font(Paper.text(7)).foregroundStyle(Paper.ink2)
            }
            HStack(spacing: 3) {
                Rectangle().fill(Paper.accent).frame(width: 12, height: 1.5)
                Text("fitted slope").font(Paper.text(7)).foregroundStyle(Paper.ink2)
            }
            HStack(spacing: 3) {
                DashLine().stroke(Paper.ink3, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])).frame(width: 12, height: 1)
                Text("baseline").font(Paper.text(7)).foregroundStyle(Paper.ink2)
            }
        }
    }

    // MARK: Foot blocks

    private var footBlocks: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Paper.sectionTitle("Data quality")
                qualityGrid
            }
            .frame(width: 176, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Paper.sectionTitle("Methods")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ClinicReport.order) { m in
                        (Text(m.reportName + ". ").font(Paper.text(6.5, .semibold)) + Text(m.reportDefinition).font(Paper.text(6.5)))
                            .foregroundStyle(Paper.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Weekly check tasks: sustained /a/, /pa/ and /pataka/ repetition for 6 s, and a fixed reading passage (about 75 syllables). Baseline is the mean of the first 5 sessions, or of the first 3 weekly checks. Stable band: ±5% of baseline; 1 dB for reading fatigue; 0.5 points for self-ratings. Slope is an ordinary least-squares fit over time, scaled to 30 days, with a 95% confidence interval. Status needs 3 values in the period; slope needs 3 values spanning 7 days.")
                        .font(Paper.text(6.5)).foregroundStyle(Paper.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Paper.rule(0.5) }
    }

    private var qualityGrid: some View {
        let q = report.quality
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            qrow("Sessions", "\(q.sessions)")
            qrow("Days with a session", "\(q.activeDays) of \(q.periodDays)")
            qrow("Voiced speech, total", String(format: "%.0f min", q.voicedMinutes))
            qrow("Voiced speech, median", String(format: "%.0f s / session", q.medianVoicedSeconds))
            qrow("Longest gap", "\(q.longestGapDays) day\(q.longestGapDays == 1 ? "" : "s")")
            qrow("Piezo coverage", "\(q.piezoSessions) of \(q.sessions)")
            qrow("Translated speech", "\(q.translatedSessions) of \(q.sessions)")
            qrow("Weekly checks", "\(q.checks)")
            qrow("Check tasks recorded", "\(q.checkTasks) of \(q.checks * CheckTask.allCases.count)")
            qrow("Self-ratings", "\(q.selfReports) of \(q.checks)")
            qrow("Translator", report.isSample ? "Toy (scripted)" : "On-device")
        }
    }

    private func qrow(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).font(Paper.text(7.5)).foregroundStyle(Paper.ink2)
            Text(v).font(Paper.display(7.5)).monospacedDigit().foregroundStyle(Paper.ink)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Paper.rule(0.5)
            HStack(alignment: .firstTextBaseline) {
                Text("Descriptive measures from a wearable throat sensor and patient self-report. Not diagnostic, and not validated against clinical scales. Interpret alongside clinical assessment.")
                    .font(Paper.text(7)).foregroundStyle(Paper.ink2)
                Spacer(minLength: 12)
                Text("Fonos \(Paper.appVersion) · Page \(page) of \(Self.pageCount)")
                    .font(Paper.text(7)).foregroundStyle(Paper.ink3)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Small trend chart

private struct MiniTrend: View {
    let row: ClinicReport.Row

    var body: some View {
        let m = row.measure
        VStack(alignment: .leading, spacing: 2) {
            Text(m.reportName).font(Paper.text(7, .semibold)).foregroundStyle(Paper.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(m.reportUnit).font(Paper.text(6)).foregroundStyle(Paper.ink3).lineLimit(1)
                Spacer(minLength: 2)
                if let s = row.slope {
                    Text("\(Paper.signed(s.perMonth, m)) / 30 d")
                        .font(Paper.display(6)).monospacedDigit().foregroundStyle(Paper.ink2)
                        .fixedSize()
                }
            }
            chart.frame(height: 44)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var chart: some View {
        if row.points.count >= 2, let first = row.points.first?.date, let last = row.points.last?.date {
            let fit = fitLine(first: first, last: last)
            Chart {
                if let b = row.baseline {
                    RuleMark(y: .value("Baseline", b))
                        .foregroundStyle(Paper.ink3)
                        .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [2, 2]))
                }
                ForEach(row.points, id: \.date) { p in
                    PointMark(x: .value("Date", p.date), y: .value(m.reportName, p.value))
                        .symbolSize(5)
                        .foregroundStyle(Paper.ink3.opacity(0.75))
                }
                if let fit {
                    ForEach(fit, id: \.date) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Fit", p.value), series: .value("s", "fit"))
                            .foregroundStyle(Paper.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.4))
                    }
                }
            }
            .chartYScale(domain: domain(fit: fit))
            .chartXAxis {
                AxisMarks(values: [first, last]) { v in
                    AxisValueLabel(anchor: v.index == 0 ? .topLeading : .topTrailing) {
                        if let d = v.as(Date.self) { Text(Paper.shortDate(d)).font(Paper.text(6)).foregroundStyle(Paper.ink3) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(Paper.rule)
                    AxisValueLabel().font(Paper.display(6)).foregroundStyle(Paper.ink3)
                }
            }
            .chartPlotStyle { $0.border(Paper.rule, width: 0.4) }
        } else {
            Text("Too few values in this period")
                .font(Paper.text(7)).foregroundStyle(Paper.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().stroke(Paper.rule, lineWidth: 0.4))
        }
    }

    private var m: Measure { row.measure }

    /// Two points of the fitted line, drawn across the period.
    private func fitLine(first: Date, last: Date) -> [ClinicReport.Point]? {
        guard let s = row.slope else { return nil }
        let t0 = first
        let ts = row.points.map { $0.date.timeIntervalSince(t0) / 86_400 }
        let ys = row.points.map(\.value)
        let tm = ClinicReport.mean(ts), ym = ClinicReport.mean(ys)
        let b = s.perMonth / 30
        let a = ym - b * tm
        let tEnd = last.timeIntervalSince(t0) / 86_400
        return [ClinicReport.Point(date: first, value: a), ClinicReport.Point(date: last, value: a + b * tEnd)]
    }

    private func domain(fit: [ClinicReport.Point]?) -> ClosedRange<Double> {
        var v = row.points.map(\.value)
        if let b = row.baseline { v.append(b) }
        if let fit { v += fit.map(\.value) }
        let lo = v.min() ?? 0, hi = v.max() ?? 1
        let pad = max((hi - lo) * 0.12, abs(hi) * 0.01, 0.01)
        return (lo - pad)...(hi + pad)
    }
}

private struct DashLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}

// MARK: - Print tokens

/// Fixed print palette and type for the report. Independent of the app's
/// dark theme: a clinic prints and files this page.
enum Paper {
    static let white = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x14181B)
    static let ink2 = Color(hex: 0x4A545C)
    static let ink3 = Color(hex: 0x6F7880)
    static let rule = Color(hex: 0xC9CED3)
    static let accent = Color(hex: 0x0A7C6E)
    static let brick = Color(hex: 0x9A3B2E)
    static let green = Color(hex: 0x2E6B3F)
    static let notice = Color(hex: 0xF7F3EE)

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(FonosType.text, fixedSize: size).weight(weight)
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(FonosType.display, fixedSize: size).weight(weight)
    }

    static func rule(_ width: CGFloat) -> some View {
        Rectangle().fill(width >= 0.75 ? ink.opacity(0.85) : Color(hex: 0xB4BBC1)).frame(height: width)
    }

    static func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(text(7.5, .bold)).tracking(1.1)
            .foregroundStyle(ink)
    }

    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year()) }
    static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }
    static func dateTime(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()) }

    static func signedPercent(_ v: Double) -> String {
        let p = v * 100
        return (p >= 0 ? "+" : "−") + String(format: "%.1f%%", abs(p))
    }

    static func signed(_ v: Double, _ m: Measure) -> String {
        (v >= 0 ? "+" : "−") + m.reportFormat(abs(v))
    }

    /// Relative change as a percentage, or an absolute difference with its unit.
    static func change(_ v: Double, _ m: Measure) -> String {
        m.changeIsAbsolute ? signed(v, m) + (m.unit == "of 4" ? " pt" : " " + m.unit) : signedPercent(v)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
