import Foundation

/// Everything the clinic summary shows, computed from conversation
/// sessions and weekly Speech checks. Pure and deterministic so it can be
/// unit tested; the page views only lay it out.
struct ClinicReport: Equatable {

    struct Patient: Equatable {
        var name: String = ""
        var dateOfBirth: Date?
    }

    enum Status: Equatable {
        /// Fewer than 3 values in the period, or no baseline yet.
        case insufficient
        /// Period mean within the measure's stable band of baseline.
        case stable
        /// Beyond the stable band in the measure's good direction.
        case favorable
        /// Beyond the stable band in the measure's worse direction.
        case unfavorable

        var label: String {
            switch self {
            case .insufficient: "Too few data"
            case .stable: "Stable"
            case .favorable: "Favorable"
            case .unfavorable: "Unfavorable"
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
        let measure: Measure
        var baseline: Double?
        var periodMean: Double?
        var n: Int
        /// Change of the period mean against baseline: relative, or an
        /// absolute difference for `measure.changeIsAbsolute`.
        var change: Double?
        var slope: Slope?
        var status: Status
        /// Values in the period, for the small chart.
        var points: [Point]
        var id: String { measure.id }
        var system: SpeechSystem { SpeechSystem.of(measure) }
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
        var checks: Int = 0
        /// Tasks recorded across the checks, out of 4 per check.
        var checkTasks: Int = 0
        var selfReports: Int = 0
    }

    var patient: Patient
    var periodStart: Date
    var periodEnd: Date
    var generated: Date
    /// True when this period follows an earlier shared summary.
    var sinceLastExport: Bool
    var baselineStart: Date?
    var baselineEnd: Date?
    var checkBaselineStart: Date?
    var checkBaselineEnd: Date?
    var rows: [Row]
    var quality: Quality
    var isSample: Bool
    var reportID: String

    /// Measures grouped by speech system: breathing, voice, articulation,
    /// rhythm and intelligibility, then the patient's own rating.
    static let order: [Measure] = SpeechSystem.allCases.flatMap(\.measures)

    // MARK: Build

    static func make(
        sessions all: [SessionRecord],
        checks allChecks: [SpeechCheckRecord] = [],
        patient: Patient,
        lastExport: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ClinicReport {
        let sorted = all.sorted { $0.date < $1.date }
        let sortedChecks = allChecks.sorted { $0.date < $1.date }
        let baseline = Baseline.from(sorted)
        let baselineSessions = Array(sorted.prefix(5))
        let baselineChecks = Array(sortedChecks.prefix(3))

        let first = [sorted.first?.date, sortedChecks.first?.date].compactMap { $0 }.min()
        let start = lastExport ?? first ?? now
        // First summary: everything so far. Later ones: only what is new since the last share.
        func inRange(_ d: Date) -> Bool { lastExport == nil ? d <= now : d > start && d <= now }
        let inPeriod = sorted.filter { inRange($0.date) }
        let checksInPeriod = sortedChecks.filter { inRange($0.date) }

        let rows: [Row] = order.map { m in
            let all = m.series(sessions: sorted, checks: sortedChecks, baseline: baseline)
            let pts = all.filter { inRange($0.date) }
            let base: Double? = {
                switch m {
                case .session(let metric):
                    let v = baselineSessions.compactMap { metric.value($0, baseline: baseline) }
                    return baseline == nil || v.isEmpty ? nil : mean(v)
                case .check: return m.baselineValue(all)
                }
            }()
            let pm = pts.isEmpty ? nil : mean(pts.map(\.value))
            var change: Double?
            if let base, let pm {
                if m.changeIsAbsolute { change = pm - base } else if base != 0 { change = (pm - base) / abs(base) }
            }
            let status: Status
            if pts.count < 3 || change == nil {
                status = .insufficient
            } else if abs(change!) < m.steadyBand {
                status = .stable
            } else {
                status = (change! > 0) == m.higherIsBetter ? .favorable : .unfavorable
            }
            return Row(measure: m, baseline: base, periodMean: pm, n: pts.count, change: change,
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
            longestGapDays: gap,
            checks: checksInPeriod.count,
            checkTasks: checksInPeriod.map(\.completedTasks).reduce(0, +),
            selfReports: checksInPeriod.filter { $0.selfReport != nil }.count
        )

        return ClinicReport(
            patient: patient, periodStart: start, periodEnd: now, generated: now,
            sinceLastExport: lastExport != nil,
            baselineStart: baselineSessions.first?.date, baselineEnd: baseline?.establishedOn,
            checkBaselineStart: baselineChecks.first?.date,
            checkBaselineEnd: baselineChecks.count >= 2 ? baselineChecks.last?.date : nil,
            rows: rows, quality: quality,
            isSample: inPeriod.contains(where: \.isSample) || checksInPeriod.contains(where: \.isSample)
                || (inPeriod.isEmpty && checksInPeriod.isEmpty),
            reportID: reportID(now: now, count: inPeriod.count + checksInPeriod.count)
        )
    }

    /// The summary at the top of the page. Factual, never diagnostic.
    var summary: String {
        let measured = rows.filter { $0.status != .insufficient }
        guard !measured.isEmpty else {
            return "Not enough data in this period to describe a change. Each measure needs at least 3 sessions or weekly checks."
        }
        let unfavorable = measured.filter { $0.status == .unfavorable }
        if let top = unfavorable.max(by: { Self.severity($0) < Self.severity($1) }), let c = top.change {
            let systems = SpeechSystem.allCases.filter { sys in unfavorable.contains { $0.system == sys } }
            return "\(unfavorable.count) of \(measured.count) measures moved beyond their stable band in the unfavorable direction"
                + " (\(systems.map { $0.reportTitle.lowercased() }.joined(separator: ", "))). "
                + "The largest is \(top.measure.reportName), \(Self.changePhrase(c, top.measure)) than baseline."
        }
        return "All \(measured.count) measures with enough data are within their stable band of baseline or changed in the favorable direction."
    }

    static func severity(_ r: Row) -> Double { abs(r.change ?? 0) / r.measure.severityScale }

    /// "12% lower" or "1.5 dB lower".
    static func changePhrase(_ c: Double, _ m: Measure) -> String {
        let dir = c > 0 ? "higher" : "lower"
        if m.changeIsAbsolute { return "\(m.reportFormat(abs(c))) \(m.unit == "of 4" ? "points" : m.unit) \(dir)" }
        return "\(Int((abs(c) * 100).rounded()))% \(dir)"
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
