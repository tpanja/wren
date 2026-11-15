import SwiftUI

/// The weekly Speech check: four short tasks, three optional questions,
/// then a summary. About three minutes. Every step has one large primary
/// action, and every task can be skipped.
struct SpeechCheckFlow: View {
    @Environment(FonosEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable {
        case intro
        case task(CheckTask)
        case question(BulbarSelfReport.Item)
        case results
    }

    @State private var step: Step = .intro
    @State private var draft = SpeechCheckRecord(date: .now, isSample: true)
    @State private var answers: [BulbarSelfReport.Item: Int] = [:]
    @State private var confirmQuit = false
    /// When the step last changed. Taps in the first moments after a change
    /// are ignored, so a double tap or a tremor can't skip a task or answer
    /// the next question with the button that took the previous one's place.
    @State private var stepChanged = Date.distantPast
    /// The last saved check when the flow opened. Captured once, so saving
    /// doesn't make the results compare this check with itself while dismissing.
    @State private var previous: SpeechCheckRecord?
    @State private var capturedPrevious = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intro: CheckIntro(start: { go(.task(.breath)) })
                case .task(let t): TaskStep(task: t, settled: settled, onResult: { record($0) }, onNext: { next(after: t) })
                case .question(let q): QuestionStep(item: q, selected: answers[q]) { answer(q, $0) } skipAll: { if settled() { go(.results) } }
                case .results: CheckResults(draft: draftWithAnswers, previous: previous, save: save)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .background(Theme.ground)
            .navigationTitle("Speech check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .intro ? "Close" : "Quit") {
                        if step == .intro { dismiss() } else { confirmQuit = true }
                    }
                }
                if let p = progress {
                    ToolbarItem(placement: .principal) {
                        Text(p).font(.ui(.subheadline, .semibold)).foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .confirmationDialog("Quit the check?", isPresented: $confirmQuit, titleVisibility: .visible) {
                Button("Quit without saving", role: .destructive) { engine.cancelTask(); dismiss() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("What you've done so far won't be saved.")
            }
        }
        .interactiveDismissDisabled(step != .intro)
        .onAppear {
            guard !capturedPrevious else { return }
            previous = engine.checks.latest
            capturedPrevious = true
        }
        .onDisappear { engine.cancelTask() }
    }

    private var progress: String? {
        switch step {
        case .task(let t): "Task \(t.rawValue + 1) of \(CheckTask.allCases.count)"
        case .question(let q): "Question \((BulbarSelfReport.Item.allCases.firstIndex(of: q) ?? 0) + 1) of 3"
        default: nil
        }
    }

    private var draftWithAnswers: SpeechCheckRecord {
        var d = draft
        let items = BulbarSelfReport.Item.allCases
        if items.allSatisfy({ answers[$0] != nil }) {
            d.selfReport = BulbarSelfReport(speech: answers[.speech]!, salivation: answers[.salivation]!, swallowing: answers[.swallowing]!)
        }
        return d
    }

    private func go(_ s: Step) {
        engine.clearTask()
        step = s
        stepChanged = .now
    }

    private func settled() -> Bool { Date.now.timeIntervalSince(stepChanged) > 0.8 }

    private func record(_ r: TaskResult) { draft.apply(r) }

    private func next(after t: CheckTask) {
        guard settled() else { return }
        if let n = CheckTask(rawValue: t.rawValue + 1) { go(.task(n)) } else { go(.question(.speech)) }
    }

    private func answer(_ q: BulbarSelfReport.Item, _ score: Int) {
        guard settled() else { return }
        answers[q] = score
        let items = BulbarSelfReport.Item.allCases
        if let i = items.firstIndex(of: q), i + 1 < items.count { go(.question(items[i + 1])) } else { go(.results) }
    }

    private func save() {
        var d = draftWithAnswers
        d.date = .now
        engine.saveCheck(d)
        dismiss()
    }
}

// MARK: - Intro

private struct CheckIntro: View {
    let start: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                Text("Your weekly speech check")
                    .font(.metric(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                Text("Four short tasks and three questions, about 3 minutes. Doing the same tasks each week shows changes that everyday conversation can hide.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(CheckTask.allCases) { t in
                        HStack(spacing: 14) {
                            FonosIcon(t.icon, size: 26, relativeTo: .title3)
                                .foregroundStyle(Theme.action)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.ui(.headline)).foregroundStyle(Theme.ink)
                                Text(t.measures).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        if t != CheckTask.allCases.last { Divider().overlay(Theme.hairline) }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("For comparable results").font(.ui(.headline)).foregroundStyle(Theme.ink)
                    ForEach(["Sit upright in a quiet room.",
                             "Check that the band sits snugly and centered.",
                             "Have a sip of water first.",
                             "Try to do it at about the same time each week."], id: \.self) { tip in
                        Label { Text(tip) } icon: { FonosIcon(.check, size: 16, relativeTo: .body).foregroundStyle(Theme.good) }
                            .font(.ui(.body))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .card()

                Text("Skip any task that is tiring or uncomfortable. Stop whenever you need to.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.inkTertiary)
                SampleBanner(text: "Sample data. The simulated band performs each task, so results are not measurements of your voice.")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryBar(title: "Start", icon: .speak, action: start)
        }
    }
}

// MARK: - Task

private struct TaskStep: View {
    let task: CheckTask
    let settled: () -> Bool
    let onResult: (TaskResult) -> Void
    let onNext: () -> Void
    @Environment(FonosEngine.self) private var engine

    var body: some View {
        let state = engine.taskState
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                HStack(spacing: 10) {
                    FonosIcon(task.icon, size: 28, relativeTo: .title2).foregroundStyle(Theme.action)
                    Text(task.title).font(.metric(.title, weight: .bold)).foregroundStyle(Theme.ink)
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Text(task.measures).cardTitle(Theme.inkSecondary)

                Text(task.instruction)
                    .font(.ui(.title3))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if task == .passage {
                    Text(CheckTask.passageText)
                        .font(.ui(.title2))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .card(padding: 20)
                        .accessibilityLabel("Passage: \(CheckTask.passageText)")
                }

                switch state {
                case .idle:
                    Button {
                        engine.voice.speak(task.instruction)
                    } label: {
                        Label { Text("Read instructions aloud") } icon: { FonosIcon(.replay, size: 18, relativeTo: .subheadline) }
                    }
                    .buttonStyle(.well)
                case .recording(let t) where t == task:
                    RecordingCard(task: task, elapsed: engine.taskElapsed, level: engine.taskLevel)
                case .done(let r) where r.task == task:
                    ResultCard(result: r)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { actions(state) }
        .onChange(of: state) { _, s in
            if case .done(let r) = s, r.task == task { onResult(r) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: state)
    }

    @ViewBuilder private func actions(_ state: FonosEngine.TaskState) -> some View {
        switch state {
        case .recording:
            if task.stopsOnSilence {
                PrimaryBar(title: "Done", icon: .stop, tint: Theme.alert) { engine.stopTask() }
            } else {
                PrimaryBar(title: "Recording…", icon: .stop, tint: Theme.alert, disabled: true) {}
            }
        case .done(let r) where r.task == task:
            VStack(spacing: 8) {
                PrimaryBar(title: task == .passage ? "Continue" : "Next task", icon: .chevron, action: onNext)
                Button("Try again") { engine.startTask(task) }
                    .font(.ui(.headline))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(Theme.ground.opacity(0.97).ignoresSafeArea(edges: .bottom))
        default:
            VStack(spacing: 8) {
                PrimaryBar(title: "Start", icon: .speak) {
                    guard settled() else { return }
                    engine.voice.stop()
                    engine.startTask(task)
                }
                Button("Skip this task") { onNext() }
                    .font(.ui(.headline))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityHint("Moves on without recording \(task.title)")
            }
            .background(Theme.ground.opacity(0.97).ignoresSafeArea(edges: .bottom))
        }
    }
}

/// While recording: elapsed time (or a countdown for timed tasks) and a live level.
private struct RecordingCard: View {
    let task: CheckTask
    let elapsed: Double
    let level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusPill(text: "Recording", color: Theme.alert, pulsing: true)
                Spacer()
                Text(timeText)
                    .font(.metric(.title, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.well)
                    Capsule().fill(Theme.mic).frame(width: max(8, g.size.width * level))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            Text(hint).font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        task.stopsOnSilence ? String(format: "%.0f s", elapsed) : String(format: "%.0f", max(0, ceil(task.maxSeconds - elapsed)))
    }

    private var hint: String {
        switch task {
        case .breath: "Keep going until you run out of breath. Fonos stops when you do."
        case .amr, .smr: "Keep going. Fonos stops you after \(Int(task.maxSeconds)) seconds."
        case .passage: "Tap Done when you finish, or Fonos stops when you go quiet."
        }
    }
}

private struct ResultCard: View {
    let result: TaskResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let h = result.headline {
                HStack(spacing: 8) {
                    CheckDisc(color: Theme.good, size: 22)
                    Text("Recorded").font(.ui(.headline)).foregroundStyle(Theme.ink)
                }
                Text(h.measure.title).cardTitle(Theme.inkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(h.measure.format(h.value)).font(.metric(.largeTitle, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(h.measure.unit).font(.ui(.headline)).foregroundStyle(Theme.inkSecondary)
                }
            } else {
                HStack(spacing: 8) {
                    FonosIcon(.warning, size: 22, relativeTo: .headline).foregroundStyle(Theme.caution)
                    Text("Fonos couldn't measure that one").font(.ui(.headline)).foregroundStyle(Theme.ink)
                }
                Text("It may have been too short or too quiet. Try again, or skip it this week.")
                    .font(.ui(.body)).foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Questions

private struct QuestionStep: View {
    let item: BulbarSelfReport.Item
    let selected: Int?
    let choose: (Int) -> Void
    let skipAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                Text(item.question)
                    .font(.metric(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose the one that fits best.")
                    .font(.ui(.body)).foregroundStyle(Theme.inkSecondary)

                ForEach(Array(item.options.enumerated()), id: \.offset) { i, text in
                    let score = 4 - i
                    Button { choose(score) } label: {
                        HStack(spacing: 12) {
                            Text(text).font(.ui(.body, .medium)).foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if selected == score { CheckDisc(color: Theme.action, size: 22) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected == score ? Theme.action : Color.clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityAddTraits(selected == score ? .isSelected : [])
                }

                Button("Skip the questions") { skipAll() }
                    .font(.ui(.headline))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.top, 4)
                Text("Based on the speech, saliva, and swallowing questions ALS clinics use (ALSFRS-R), in plain words. Not the official form.")
                    .font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Results

private struct CheckResults: View {
    let draft: SpeechCheckRecord
    let previous: SpeechCheckRecord?
    let save: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                Text(draft.completedTasks == 0 ? "No tasks recorded" : "Check complete")
                    .font(.metric(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                Text(previous == nil
                     ? "This is your first check. Next week's will be compared with it."
                     : "Compared with your last check on \(previous!.date.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.ui(.body)).foregroundStyle(Theme.inkSecondary)

                ForEach(SpeechSystem.allCases) { sys in
                    let rows = sys.measures.compactMap { m -> (CheckMetric, Double)? in
                        guard case .check(let c) = m, let v = c.value(draft) else { return nil }
                        return (c, v)
                    }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: sys.title, icon: rows[0].0.icon, color: sys.color)
                            ForEach(rows, id: \.0) { c, v in
                                ResultRow(metric: c, value: v, previous: previous.flatMap(c.value))
                                if c != rows.last?.0 { Divider().overlay(Theme.hairline) }
                            }
                        }
                        .card()
                    }
                }

                let skipped = CheckTask.allCases.filter { !draft.isMeasured($0) }
                if !skipped.isEmpty, draft.completedTasks > 0 {
                    Text("Not recorded this week: \(skipped.map(\.title).joined(separator: ", ")).")
                        .font(.ui(.subheadline)).foregroundStyle(Theme.inkSecondary)
                }
                Text("One check can vary for many reasons, like tiredness or a cold. Trends over several weeks say more.")
                    .font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                SampleBanner()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryBar(title: "Save check", icon: .check, disabled: draft.completedTasks == 0 && draft.selfReport == nil, action: save)
        }
    }
}

private struct ResultRow: View {
    let metric: CheckMetric
    let value: Double
    let previous: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.title).font(.ui(.body)).foregroundStyle(Theme.ink)
            Spacer()
            if let previous { Text(change(previous)).font(.ui(.footnote)).foregroundStyle(Theme.inkSecondary) }
            Text("\(metric.format(value)) \(metric.unit)")
                .font(.metric(.body, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    /// Plain words, no colors for better or worse: one week is noise.
    private func change(_ p: Double) -> String {
        let d = value - p
        if metric.format(abs(d)) == metric.format(0) { return "same as last week" }
        return "\(d > 0 ? "up" : "down") \(metric.format(abs(d)))"
    }
}

// MARK: - Shared

/// Full-width bottom action, 60 pt tall, in the Speak button's color.
struct PrimaryBar: View {
    let title: String
    let icon: Icon
    var tint: Color = Theme.action
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { FonosIcon(icon, size: 22, relativeTo: .headline) }
                .font(.ui(.headline))
                .foregroundStyle(tint == Theme.alert ? Color.white : Theme.onAction)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(disabled ? tint.opacity(0.55) : tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScale())
        .disabled(disabled)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.ground.opacity(0.97).ignoresSafeArea(edges: .bottom))
    }
}
