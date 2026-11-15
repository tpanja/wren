import Foundation

/// Everything the one-page clinic summary shows, computed from session
/// records. Pure and deterministic so it can be unit tested; the page view
/// only lays it out.
struct ClinicReport: Equatable {

    struct Patient: Equatable {
        var name: String = ""
        var dateOfBirth: Date?
    }

    enum Status: Equatable {
        /// Fewer than 3 sessions in the period, or no baseline yet.
        case insufficient
        /// Period mean within ±5% of baseline.
        case stable
        /// Beyond ±5% in the measure's good direction.
        case favorable
        /// Beyond ±5% in the measure's worse direction.
        case unfavorable

        var label: String {
            switch self {
            case .insufficient: "Not enough data"
            case .stable: "Stable"
            case .favorable: "Favorable change"
            case .unfavorable: "Unfavorable change"
            }
        }
    }

    /// Ordinary least squares slope of value against time.
    struct Slope: Equatable {
        /// Change per 30 days, in the measure's display unit.
        var perMonth: Double
        /// Half-width of the 95% confidence interval, same unit.
        var ci95: Double
        var n: Int
    }

    struct Row: Equatable, Identifiable {
        let metric: Metric
        var baseline: Double?
        var periodMean: Double?
        var n: Int
        /// Relative change of the period mean against baseline.
        var change: Double?
        var slope: Slope?
        var status: Status
        /// Session values in the period, for the small chart.
        var points: [Point]
        var id: Metric { metric }
    }

    struct Point: Equatable {
        var date: Date
        var value: Double
    }

    struct Quality: Equatable {
        var sessions: Int
        var activeDays: Int
        var periodDays: Int
        var voicedMinutes: Double
        var medianVoicedSeconds: Double
        var piezoSessions: Int
        var translatedSessions: Int
        var longestGapDays: Int
    }

    var patient: Patient
    var periodStart: Date
    var periodEnd: Date
    var generated: Date
    /// True when this period follows an earlier shared summary.
    var sinceLastExport: Bool
    var baselineStart: Date?
    var baselineEnd: Date?
    var rows: [Row]
    var quality: Quality
    var isSample: Bool
    var reportID: String

    static let steadyBand = 0.05

    /// Measures in the order a clinician reads them: outcome first, then
    /// rate and timing, then voice production.
    static let order: [Metric] = [.clarity, .pace, .pauses, .strength, .steadiness, .symmetry]

    // MARK: Build

    static func make(
        sessions all: [SessionRecord],
        patient: Patient,
        lastExport: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ClinicReport {
        let sorted = all.sorted { $0.date < $1.date }
        let baseline = Baseline.from(sorted)
        let baselineSessions = Array(sorted.prefix(5))

        let start = lastExport ?? sorted.first?.date ?? now
        // First summary: everything so far. Later ones: only what is new since the last share.
        let inPeriod = lastExport == nil
            ? sorted.filter { $0.date <= now }
            : sorted.filter { $0.date > start && $0.date <= now }

        let rows: [Row] = order.map { m in
            let pts = inPeriod.compactMap { s in m.value(s, baseline: baseline).map { Point(date: s.date, value: $0) } }
            let baseValues = baselineSessions.compactMap { m.value($0, baseline: baseline) }
            let base = baseline == nil || baseValues.isEmpty ? nil : mean(baseValues)
            let pm = pts.isEmpty ? nil : mean(pts.map(\.value))
            var change: Double?
            if let base, let pm, base != 0 { change = (pm - base) / abs(base) }
            let status: Status
            if pts.count < 3 || change == nil {
                status = .insufficient
            } else if abs(change!) < steadyBand {
                status = .stable
            } else {
                status = (change! > 0) == m.higherIsBetter ? .favorable : .unfavorable
            }
            return Row(metric: m, baseline: base, periodMean: pm, n: pts.count, change: change,
                       slope: slope(pts), status: status, points: pts)
        }

        let days = Set(inPeriod.map { calendar.startOfDay(for: $0.date) })
        let periodDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                           to: calendar.startOfDay(for: now)).day ?? 0) + 1)
        let voiced = inPeriod.map { $0.speakingSeconds * (1 - $0.pauseRatio) }
        var gap = 0
        for (a, b) in zip(inPeriod, inPeriod.dropFirst()) {
            gap = max(gap, calendar.dateComponents([.day], from: calendar.startOfDay(for: a.date),
                                                   to: calendar.startOfDay(for: b.date)).day ?? 0)
        }
        let quality = Quality(
            sessions: inPeriod.count,
            activeDays: days.count,
            periodDays: periodDays,
            voicedMinutes: voiced.reduce(0, +) / 60,
            medianVoicedSeconds: median(voiced),
            piezoSessions: inPeriod.filter { $0.symmetry != nil }.count,
            translatedSessions: inPeriod.filter { $0.clarity != nil }.count,
            longestGapDays: gap
        )

        return ClinicReport(
            patient: patient, periodStart: start, periodEnd: now, generated: now,
            sinceLastExport: lastExport != nil,
            baselineStart: baselineSessions.first?.date, baselineEnd: baseline?.establishedOn,
            rows: rows, quality: quality,
            isSample: inPeriod.contains(where: \.isSample) || inPeriod.isEmpty,
            reportID: reportID(now: now, count: inPeriod.count)
        )
    }

    /// The one-sentence summary at the top of the page. Factual, never diagnostic.
    var summary: String {
        let measured = rows.filter { $0.status != .insufficient }
        guard !measured.isEmpty else {
            return "Not enough sessions in this period to describe a change. At least 3 sessions are needed per measure."
        }
        let unfavorable = measured.filter { $0.status == .unfavorable }
        if let top = unfavorable.max(by: { abs($0.change ?? 0) < abs($1.change ?? 0) }), let c = top.change {
            let pct = Int((abs(c) * 100).rounded())
            return "\(unfavorable.count) of \(measured.count) measures moved beyond ±5% of baseline in the unfavorable direction. "
                + "The largest is \(top.metric.reportName.lowercased()), \(pct)% \(c > 0 ? "higher" : "lower") than baseline."
        }
        return "All \(measured.count) measures with enough data are within ±5% of baseline or changed in the favorable direction."
    }

    // MARK: Statistics

    static func mean(_ x: [Double]) -> Double { x.reduce(0, +) / Double(max(x.count, 1)) }

    static func median(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        let s = x.sorted(), m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    /// OLS slope of value on time in days, scaled to 30 days, with a 95% CI
    /// from the t distribution. Needs 3 points spanning at least 7 days.
    static func slope(_ pts: [Point]) -> Slope? {
        guard pts.count >= 3, let t0 = pts.first?.date else { return nil }
        let t = pts.map { $0.date.timeIntervalSince(t0) / 86_400 }
        guard (t.max() ?? 0) - (t.min() ?? 0) >= 7 else { return nil }
        let y = pts.map(\.value)
        let tm = mean(t), ym = mean(y)
        var sxx = 0.0, sxy = 0.0
        for (a, b) in zip(t, y) { sxx += (a - tm) * (a - tm); sxy += (a - tm) * (b - ym) }
        guard sxx > 0 else { return nil }
        let b = sxy / sxx
        let a = ym - b * tm
        var sse = 0.0
        for (ti, yi) in zip(t, y) { let r = yi - (a + b * ti); sse += r * r }
        let df = pts.count - 2
        let se = df > 0 ? (sse / Double(df) / sxx).squareRoot() : 0
        return Slope(perMonth: b * 30, ci95: tCritical95(df: df) * se * 30, n: pts.count)
    }

    /// Two-sided 95% critical value of Student's t.
    static func tCritical95(df: Int) -> Double {
        let table: [Double] = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
                               2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
                               2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]
        guard df >= 1 else { return .infinity }
        if df <= table.count { return table[df - 1] }
        if df <= 60 { return 2.000 }
        if df <= 120 { return 1.980 }
        return 1.960
    }

    static func reportID(now: Date, count: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        f.timeZone = .current
        return "FN-\(f.string(from: now))-\(count)"
    }
}

extension Metric {
    /// Name used in clinical text: plainer and more precise than the in-app title.
    var reportName: String {
        switch self {
        case .clarity: "Clarity"
        case .strength: "Strength"
        case .pace: "Pace"
        case .symmetry: "Symmetry"
        case .steadiness: "Pitch variation"
        case .pauses: "Pauses"
        }
    }

    /// Unit as printed in the report.
    var reportUnit: String {
        switch self {
        case .clarity, .symmetry, .pauses: "%"
        case .strength: "% of baseline"
        case .pace: "syl/s"
        case .steadiness: "% of mean F0"
        }
    }

    /// One-line definition for the report's methods block.
    var reportDefinition: String {
        switch self {
        case .clarity: "Mean translator confidence per translated phrase."
        case .strength: "Mean voiced mic level, as amplitude relative to baseline."
        case .pace: "Syllable nuclei per second of voiced time."
        case .pauses: "Share of the speaking span that is unvoiced."
        case .steadiness: "Mean change between consecutive 20 ms F0 estimates, relative to mean F0."
        case .symmetry: "Left/right piezo amplitude balance over voiced frames (100% = equal)."
        }
    }

    /// Fixed decimals so the table's columns line up.
    func reportFormat(_ v: Double) -> String {
        switch self {
        case .pace: String(format: "%.2f", v)
        case .steadiness: String(format: "%.2f", v)
        default: String(format: "%.1f", v)
        }
    }
}
