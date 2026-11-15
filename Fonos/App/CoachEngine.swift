import Foundation
import Observation
import os
import UIKit

/// The app's coordinator. Streams band frames into the display buffers and
/// the analyzer, and runs a take: count-in → singing → analysis → feedback
/// (local first, then Claude when the singer has turned it on).
@MainActor
@Observable
final class CoachEngine {

    enum Phase: Equatable {
        case idle
        /// Beats left in the count-in (3, 2, 1).
        case countIn(Int)
        case singing
        case feedback
    }

    // MARK: State

    private(set) var phase: Phase = .idle
    private(set) var plan: TakePlan?
    private(set) var currentTake: TakeRecord?
    private(set) var feedbackLoading = false
    private(set) var isStreaming = false
    private(set) var live = SingingAnalyzer.Live()
    private(set) var bandStatus = BandStatus()
    /// Shows the full-screen take flow.
    var takeIsPresented = false
    var message: String?

    // MARK: Collaborators

    let streams = StreamStore()
    let analyzer = SingingAnalyzer()
    let store = TakeStore()
    let profile = Profile()

    @ObservationIgnored private let band = ToyBand()
    @ObservationIgnored private let tone = ToneGenerator()
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var takeGeneration = 0

    init() {
        let streams = streams, analyzer = analyzer
        band.onFrame = { frame in
            streams.append(frame)
            analyzer.ingest(frame)
        }
    }

    // MARK: Streaming

    func startStreaming() {
        guard !isStreaming else { return }
        band.startStreaming()
        isStreaming = true
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stopStreaming() {
        if phase == .singing || phase != .idle && phase != .feedback { cancelTake() }
        band.stopStreaming()
        isStreaming = false
        pollTimer?.invalidate()
    }

    private func poll() {
        let l = analyzer.liveState
        if l != live { live = l }
        let s = band.status
        if s != bandStatus { bandStatus = s }
    }

    // MARK: Suggestions

    /// The exercise suggested on the Sing tab, with why.
    var suggestion: (kind: ExerciseKind, reason: String) {
        let today = store.today
        if today.isEmpty { return (.siren, "Start every session with a gentle warm-up.") }
        guard let last = today.last, let focus = last.feedback?.focusMetric else {
            return (.fiveNoteScale, "A short scale to settle your pitch.")
        }
        switch focus {
        case .onsetExcursion, .onsetSettle: return (.fiveNoteScale, "Your last focus was landing notes.")
        case .sustainStability, .levelStability, .hnr, .phraseDuration: return (.sustained, "Your last focus was holding notes steadily.")
        case .pitchAccuracy: return (last.kind == .fiveNoteScale ? .arpeggio : .fiveNoteScale, "Your last focus was singing in tune.")
        default: return (.songPhrase, "Put it together in a short phrase.")
        }
    }

    func takeNumber(for kind: ExerciseKind) -> Int {
        store.today.filter { $0.kind == kind }.count + 1
    }

    // MARK: Take flow

    func begin(_ kind: ExerciseKind) {
        if !isStreaming { startStreaming() }
        takeGeneration += 1
        let gen = takeGeneration
        let plan = kind.plan(range: profile.range)
        self.plan = plan
        currentTake = nil
        feedbackLoading = false
        takeIsPresented = true

        let beat = 0.6
        let countIn = profile.countIn ? beat * 3 : 0.6
        analyzer.begin(plan, countIn: countIn)
        band.sing(plan, after: countIn)
        if profile.referenceTone, let first = plan.notes.first {
            tone.play(midi: first.midi, duration: min(1.0, countIn))
        }

        Task { @MainActor in
            if profile.countIn {
                for n in stride(from: 3, through: 1, by: -1) {
                    guard gen == takeGeneration else { return }
                    phase = .countIn(n)
                    tone.click()
                    UIAccessibility.post(notification: .announcement, argument: "\(n)")
                    try? await Task.sleep(for: .seconds(beat))
                }
            } else {
                phase = .countIn(1)
                try? await Task.sleep(for: .seconds(countIn))
            }
            guard gen == takeGeneration else { return }
            phase = .singing
            if let first = plan.notes.first {
                UIAccessibility.post(notification: .announcement, argument: "Sing \(Music.spokenName(first.midi))")
            }
            try? await Task.sleep(for: .seconds(plan.duration + 0.3))
            guard gen == takeGeneration, phase == .singing else { return }
            finish()
        }
    }

    /// Ends the take now (Stop) or when the plan runs out.
    func finish() {
        guard phase == .singing || phase != .idle && phase != .feedback else { return }
        takeGeneration += 1
        band.stopSinging()
        tone.stop()
        guard let result = analyzer.finish() else {
            phase = .idle
            takeIsPresented = false
            message = "Fonos didn't hear enough singing to measure. Try again, a little louder."
            return
        }
        var take = TakeRecord(result: result, isSample: true)
        let takeNumber = takeNumber(for: take.kind)
        // A siren updates the comfortable range used to pitch exercises.
        if take.kind == .siren, let low = take.lowNote, let high = take.highNote, high - low >= 12 {
            profile.rangeLow = low
            profile.rangeHigh = high
        }
        take.feedback = LocalCoach.feedback(for: take, store: store, level: profile.level)
        store.add(take)
        currentTake = take
        phase = .feedback
        UIAccessibility.post(notification: .announcement, argument: take.feedback?.headline ?? "Feedback ready")

        guard profile.llmFeedback, FeedbackClient.isConfigured else { return }
        feedbackLoading = true
        let snapshot = take
        Task { @MainActor in
            defer { feedbackLoading = false }
            guard let refined = try? await FeedbackClient.request(take: snapshot, store: store, profile: profile, takeNumber: takeNumber),
                  currentTake?.id == snapshot.id else { return }
            var updated = snapshot
            updated.feedback = refined
            store.update(updated)
            currentTake = updated
        }
    }

    func cancelTake() {
        takeGeneration += 1
        band.stopSinging()
        tone.stop()
        analyzer.cancel()
        phase = .idle
    }

    func closeTake() {
        if phase != .feedback { cancelTake() }
        phase = .idle
        takeIsPresented = false
    }

    /// Show the feedback for an earlier take.
    func reopen(_ take: TakeRecord) {
        takeGeneration += 1
        currentTake = take
        plan = take.kind.plan(range: profile.range)
        phase = .feedback
        takeIsPresented = true
    }

    // MARK: Fit check

    func startFitCheck() {
        if !isStreaming { startStreaming() }
        band.setHumming(true)
    }

    func stopFitCheck() {
        band.setHumming(false)
    }

    func playReference(_ midi: Int) {
        tone.play(midi: midi, duration: 0.9)
    }

    // MARK: Lifecycle

    func didBecomeActive() { startStreaming() }
    func didEnterBackground() { stopStreaming() }
}
