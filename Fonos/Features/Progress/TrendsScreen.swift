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
    @State private var showReport = false
    @State private var showCheck = false
    @AppStorage("fonos.voicebank.dismissed") private var voiceBankDismissed = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var sessions: [SessionRecord] { engine.store.visible }
    private var baseline: Baseline? { engine.store.baseline }
    private var checks: [SpeechCheckRecord] { engine.checks.visible }

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
                    WeeklyCheckCard(store: engine.checks) { showCheck = true }
                    if showVoiceBanking {
                        VoiceBankingCard { voiceBankDismissed = true }
                    }
                    SampleBanner()

                    ForEach(SpeechSystem.allCases) { sys in
                        systemSection(sys)
                    }

                    practiceCard.padding(.top, 8)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("Progress")
            .navigationDestination(for: Measure.self) { MeasureDetailScreen(measure: $0) }
            .fullScreenCover(isPresented: $showCheck) { SpeechCheckFlow() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        FonosIcon(.settings, size: 24, relativeTo: .title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showReport = true } label: {
                        FonosIcon(.report, size: 24, relativeTo: .title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clinic summary")
                    .accessibilityHint("Creates a one-page report for your care team")
                }
            }
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .sheet(isPresented: $showReport) {
                NavigationStack {
                    ClinicSummaryView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { showReport = false } }
                        }
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
            }
        }
        .padding(.vertical, 12)
    }

    private func ringLink(_ m: Metric, value: Double?, stacked: Bool) -> some View {
        NavigationLink(value: Measure.session(m)) {
            let label = HStack(spacing: 4) {
                Text(m.title).cardTitle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
        .accessibilityLabel(m.title)
        .accessibilityValue(value.map { "\(m.format($0)) \(m.unit == "%" ? "percent" : m.unit == "syl/s" ? "syllables per second" : m.unit)" } ?? "No data")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Insight

    /// Trends for every measure, from conversation and from the weekly check.
    private var allTrends: [MeasureTrend] {
        SpeechSystem.allCases.flatMap(\.measures).compactMap {
            MeasureTrend.compute($0, sessions: sessions, checks: checks, baseline: baseline)
        }
    }

    /// The single most notable change, written gently.
    private func headline(_ trends: [MeasureTrend]) -> (title: String, body: String)? {
        guard !trends.isEmpty else { return nil }
        if let t = trends.filter({ $0.direction == .lower }).max(by: { $0.severity < $1.severity }) {
            return ("\(t.phrase) since your baseline", t.measure.lowerHeadlineBody)
        }
        return ("Your speech is holding steady", "Your recent measures are close to your baseline across the board.")
    }

    /// Offer voice banking once speech starts to change: the patient's own
    /// rating drops, or articulation or rhythm measures trend lower. Hidden
    /// once dismissed or once a Personal Voice exists.
    private var showVoiceBanking: Bool {
        guard !voiceBankDismissed, !engine.voice.voices.contains(where: \.isPersonal) else { return false }
        if let s = checks.last(where: { $0.selfReport != nil })?.selfReport?.speech, s <= 3 { return true }
        return allTrends.contains { t in
            t.direction == .lower && [.articulation, .rhythm].contains(SpeechSystem.of(t.measure))
        }
    }

    // MARK: Sections by speech system

    private func systemSection(_ sys: SpeechSystem) -> some View {
        VStack(alignment: .leading, spacing: Theme.stack) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sys.title)
                    .font(.metric(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(sys.summary).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)

            ForEach(sys.measures) { m in
                NavigationLink(value: m) { MeasureSummaryCard(measure: m, sessions: sessions, checks: checks, baseline: baseline) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var insight: some View {
        if let h = headline(allTrends) {
            VStack(alignment: .leading, spacing: 8) {
                Text(h.title)
                    .font(.ui(.headline))
                    .foregroundStyle(Theme.ink)
                Text(h.body)
                    .font(.ui(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let since = baseline?.establishedOn {
                    Text("Baseline from your first sessions and first 3 weekly checks, through \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.ui(.footnote))
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
                            Circle().fill(on ? Theme.good : Color.clear)
                            Circle().stroke(on ? Color.clear : Theme.hairline, lineWidth: 1.5)
                            if on {
                                FonosIcon(.check, size: 15, relativeTo: .caption).foregroundStyle(Theme.ground)
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

struct MeasureSummaryCard: View {
    let measure: Measure
    let sessions: [SessionRecord]
    let checks: [SpeechCheckRecord]
    let baseline: Baseline?

    var body: some View {
        let recent = Array(measure.series(sessions: sessions, checks: checks, baseline: baseline).suffix(7))
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: measure.title, icon: measure.icon, color: measure.color,
                       detail: recent.last.map { relative($0.date) }, chevron: true)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let v = recent.last?.value {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(measure.format(v))
                                .font(.metric(.largeTitle, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(measure.unit).font(.ui(.subheadline, .medium)).foregroundStyle(Theme.inkSecondary)
                        }
                    } else {
                        Text("No data yet").font(.ui(.title3)).foregroundStyle(Theme.inkTertiary)
                    }
                    Text(measure.sourceLabel).font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
                }
                Spacer()
                MiniBars(values: recent.map(\.value), color: measure.color, highlightLast: true)
                    .frame(width: 92, height: 44)
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(measure.title)
        .accessibilityValue(recent.last.map { "Latest \(measure.format($0.value)) \(measure.unit), \(measure.sourceLabel.lowercased())" } ?? "No data")
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
