import SwiftUI

/// Full-screen take flow: count-in → live singing → feedback.
struct TakeFlowView: View {
    @Environment(CoachEngine.self) private var engine

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            switch engine.phase {
            case .countIn, .singing:
                if let plan = engine.plan { LiveTakeView(plan: plan) }
            case .feedback:
                if let take = engine.currentTake { FeedbackView(take: take) }
            case .idle:
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.25), value: engine.phase)
    }
}

// MARK: - Live take

struct LiveTakeView: View {
    let plan: TakePlan
    @Environment(CoachEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pulse = false

    private var live: SingingAnalyzer.Live { engine.live }

    var body: some View {
        VStack(spacing: 12) {
            header
            if plan.kind == .speakingCheck {
                scriptCard
            } else {
                targetBlock
            }
            ZStack {
                PitchLane(analyzer: engine.analyzer, plan: plan)
                    .padding(.vertical, 8)
                if case .countIn(let n) = engine.phase {
                    Text("\(n)")
                        .font(.custom(FonosType.display, size: 96, relativeTo: .largeTitle).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel("Count-in \(n)")
                }
            }
            .frame(maxHeight: .infinity)
            .frame(minHeight: 180)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

            FoldView(streams: engine.streams)
                .frame(height: 76)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
        .sensoryFeedback(trigger: live.inTune) { old, new in
            engine.profile.tuneHaptics && new && !old ? .impact(weight: .light) : nil
        }
        .onAppear { pulse = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.kind.title).font(.metric(.headline, weight: .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    if engine.phase == .singing {
                        Circle().fill(Theme.recording).frame(width: 9, height: 9)
                            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.35))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
                            .accessibilityHidden(true)
                    }
                    Text(engine.phase == .singing ? "Recording · take \(engine.takeNumber(for: plan.kind))" : "Get ready")
                        .font(.ui(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            Button {
                engine.phase == .singing ? engine.finish() : engine.closeTake()
            } label: {
                HStack(spacing: 6) {
                    FonosIcon(engine.phase == .singing ? .stop : .chevron, size: 18, relativeTo: .headline)
                    Text(engine.phase == .singing ? "Stop" : "Cancel").font(.ui(.headline))
                }
                .foregroundStyle(engine.phase == .singing ? Theme.onAction : Theme.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 60)
                .background(engine.phase == .singing ? Theme.recording : Theme.well, in: Capsule())
            }
            .accessibilityLabel(engine.phase == .singing ? "Stop and get feedback" : "Cancel take")
        }
        .padding(.top, 8)
    }

    private var currentTarget: Int? {
        if let t = live.target { return Int(t.rounded()) }
        return plan.notes.first?.midi
    }

    private var nextNote: Int? {
        guard let now = engine.analyzer.takeTime else { return nil }
        return plan.notes.first(where: { $0.start > now + 0.05 }).map(\.midi)
    }

    private var targetBlock: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(plan.glide ? "Glide" : "Sing")
                    .font(.ui(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                if let midi = currentTarget {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Music.letter(midi))
                            .font(.custom(FonosType.display, size: 84, relativeTo: .largeTitle).weight(.semibold))
                        Text("\(Music.octave(midi))")
                            .font(.custom(FonosType.display, size: 34, relativeTo: .title).weight(.medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Target note \(Music.spokenName(midi))")
                }
                if let next = nextNote, !plan.glide {
                    Text("Next \(Music.name(next))").font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                TuningNeedle(cents: live.cents, inTune: live.inTune)
                    .frame(width: typeSize.isAccessibilitySize ? 150 : 170, height: 92)
                Text(tuningWords)
                    .font(.ui(.subheadline, .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(height: 22)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var tuningWords: String {
        guard let c = live.cents else { return engine.phase == .singing ? "" : plan.kind.instruction.components(separatedBy: ".").first ?? "" }
        if abs(c) <= 25 { return "In tune" }
        return c < 0 ? "A little low" : "A little high"
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read aloud").cardTitle(Theme.inkSecondary)
            Text(plan.script ?? "")
                .font(.ui(.title2, .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

// MARK: - Feedback

struct FeedbackView: View {
    let take: TakeRecord
    @Environment(CoachEngine.self) private var engine
    @State private var showDrill = false
    @State private var showTechnical = false

    private var feedback: Feedback? { take.feedback }
    private var technical: Bool { engine.profile.isTechnical }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                header
                if let f = feedback {
                    if f.confidence == "low" || take.quality.advice != nil, let advice = take.quality.advice {
                        notice(advice)
                    }
                    Text(f.summary)
                        .font(.ui(.body))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !f.wins.isEmpty { winsCard(f) }
                    focusCard(f)
                    targetRow(f)
                    if technical { technicalCard(f) }
                    provenance(f)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showDrill) {
            if let f = feedback { DrillSheet(focus: f.focus, startNote: engine.plan?.notes.first?.midi) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label { Text(take.kind.title) } icon: { FonosIcon(take.kind.icon, size: 18, relativeTo: .subheadline) }
                    .font(.ui(.subheadline, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Button { engine.closeTake() } label: {
                    Text("Done").font(.ui(.headline)).foregroundStyle(Theme.action)
                        .frame(minWidth: 60, minHeight: 44)
                }
            }
            Text(feedback?.headline ?? "Take recorded")
                .font(.metric(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if engine.feedbackLoading {
                ProgressView().progressViewStyle(.linear).tint(Theme.action)
                    .accessibilityLabel("Refining feedback")
            }
            let rings = MetricID.rings.filter { take.value($0) != nil }
            if !rings.isEmpty {
                HStack(spacing: 0) {
                    ForEach(rings) { m in
                        VStack(spacing: 6) {
                            MetricRing(metric: m, value: take.value(m), diameter: 78, lineWidth: 7, compact: true)
                            Text(m.ringTitle).font(.ui(.caption, .semibold)).foregroundStyle(Theme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(m.ringTitle)
                        .accessibilityValue(take.value(m).map { "\(m.ringLabel($0).value) \(m.ringLabel($0).unit == "st" ? "semitones" : "percent")" } ?? "")
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FonosIcon(.warning, size: 20, relativeTo: .subheadline).foregroundStyle(Theme.caution)
            Text(text).font(.ui(.subheadline)).foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func winsCard(_ f: Feedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Went well").cardTitle()
            ForEach(f.wins, id: \.observation) { win in
                HStack(alignment: .top, spacing: 10) {
                    CheckDisc(color: Theme.good, size: 22)
                    if let m = MetricID(payloadName: win.metric) {
                        FonosIcon(m.icon, size: 20).foregroundStyle(m.color)
                    }
                    Text(win.observation).font(.ui(.body)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func focusCard(_ f: Feedback) -> some View {
        let drill = Drill.library[f.focus.drillId]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Focus").cardTitle(Theme.action)
            Text(f.focus.observation)
                .font(.ui(.title3, .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(f.focus.why)
                .font(.ui(.body))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.hairline)
            Label { Text(drill?.name ?? "Drill") } icon: { FonosIcon(.drill, size: 20, relativeTo: .headline) }
                .font(.ui(.headline))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(f.focus.drillSteps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(.metric(.subheadline, weight: .bold)).foregroundStyle(Theme.action)
                        Text(step).font(.ui(.body)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("Try the drill") { showDrill = true }
                .buttonStyle(.well(Theme.action))
        }
        .card(padding: 18)
    }

    private func targetRow(_ f: Feedback) -> some View {
        let m = f.targetMetric
        let value = m.map { $0.format(f.nextTarget.target) } ?? f.nextTarget.target.formatted()
        return HStack(spacing: 12) {
            if let m { FonosIcon(m.icon, size: 22).foregroundStyle(m.color) }
            Text("Next time: aim for \(value) \(f.nextTarget.unit == "note" ? "" : f.nextTarget.unit)")
                .font(.ui(.body, .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .card()
    }

    private func technicalCard(_ f: Feedback) -> some View {
        DisclosureGroup(isExpanded: $showTechnical) {
            VStack(alignment: .leading, spacing: 10) {
                if let note = f.technicalNote {
                    Text(note).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !take.worstNotes.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Note"); Text("Cents"); Text("Settle")
                        }
                        .font(.ui(.caption, .semibold)).foregroundStyle(Theme.inkTertiary)
                        ForEach(take.worstNotes, id: \.self) { n in
                            GridRow {
                                Text(Music.name(n.midi))
                                Text(n.cents > 0 ? "+\(n.cents)" : "\(n.cents)")
                                Text("\(n.settleMs) ms")
                            }
                            .font(.ui(.subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                        }
                    }
                }
                if let onset = take.onsetType {
                    HStack(spacing: 8) {
                        Text("Onset: \(onset.beginnerLabel.lowercased())").font(.ui(.subheadline)).foregroundStyle(Theme.ink)
                        ExploratoryTag()
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Technical detail").font(.ui(.headline)).foregroundStyle(Theme.ink)
        }
        .tint(Theme.inkSecondary)
        .card()
    }

    private func provenance(_ f: Feedback) -> some View {
        Text(f.source == .claude
             ? "Feedback by Claude from your measurements. Your audio stayed on this iPhone."
             : "Quick feedback, made on this iPhone. Your audio stayed here.")
            .font(.ui(.footnote))
            .foregroundStyle(Theme.inkTertiary)
            .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { engine.begin(take.kind) } label: {
                Text("Sing again").font(.ui(.headline)).foregroundStyle(Theme.onAction)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { engine.begin(engine.suggestion.kind) } label: {
                Text("Next exercise").font(.ui(.headline)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .background(Theme.ground)
    }
}

/// The drill, large and step by step, with the starting note to play.
struct DrillSheet: View {
    let focus: Feedback.Focus
    let startNote: Int?
    @Environment(CoachEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(focus.why).font(.ui(.body)).foregroundStyle(Theme.inkSecondary)
                    ForEach(Array(focus.drillSteps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)")
                                .font(.metric(.title2, weight: .bold))
                                .foregroundStyle(Theme.action)
                                .frame(width: 32, alignment: .leading)
                            Text(step).font(.ui(.title3)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let startNote {
                        Button { engine.playReference(startNote) } label: {
                            Label { Text("Play starting note \(Music.name(startNote))") } icon: { FonosIcon(.play, size: 20, relativeTo: .headline) }
                        }
                        .buttonStyle(.well(Theme.action))
                        .padding(.top, 8)
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ground)
            .navigationTitle(Drill.library[focus.drillId]?.name ?? "Drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
