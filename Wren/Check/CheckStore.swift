import Foundation
import Observation

/// Holds weekly Speech check records in memory. Seeded with the sample
/// check history; checks done in the app (with the toy band) are appended.
@Observable
final class CheckStore {

    private(set) var checks: [SpeechCheckRecord]

    /// Days between checks. The check is weekly so every point is comparable.
    static let interval = 7

    init(checks: [SpeechCheckRecord] = ToyCheckHistory.make()) {
        self.checks = checks
    }

    var visible: [SpeechCheckRecord] { checks.sorted { $0.date < $1.date } }

    var latest: SpeechCheckRecord? { visible.last }

    /// When the next check is due: a week after the last one, or now.
    func nextDue(now: Date = .now, calendar: Calendar = .current) -> Date {
        guard let last = latest?.date else { return now }
        return calendar.date(byAdding: .day, value: Self.interval, to: calendar.startOfDay(for: last)) ?? now
    }

    func isDue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        nextDue(now: now, calendar: calendar) <= now
    }

    func add(_ record: SpeechCheckRecord) {
        checks.append(record)
    }
}

/// What one task produced. A task whose recording couldn't be measured
/// (too short, too quiet) has all results nil and `measured == false`.
struct TaskResult: Equatable {
    let task: CheckTask
    var vowel: TaskAnalysis.Vowel?
    var ddk: TaskAnalysis.DDK?
    var passage: TaskAnalysis.Passage?
    var seconds: Double

    var measured: Bool { vowel != nil || ddk != nil || passage != nil }

    static func analyze(_ task: CheckTask, frames: [SensorFrame]) -> TaskResult {
        var r = TaskResult(task: task, seconds: Double(frames.count) / 100)
        switch task {
        case .breath: r.vowel = TaskAnalysis.vowel(frames)
        case .amr, .smr: r.ddk = TaskAnalysis.ddk(frames)
        case .passage: r.passage = TaskAnalysis.passage(frames)
        }
        return r
    }

    /// The headline number for the results screen, in plain words.
    var headline: (measure: CheckMetric, value: Double)? {
        switch task {
        case .breath: vowel.map { (.mpt, $0.mpt) }
        case .amr: ddk.map { (.amrRate, $0.rate) }
        case .smr: ddk.map { (.smrRate, $0.rate) }
        case .passage: passage.map { (.readingRate, $0.rate) }
        }
    }
}

extension SpeechCheckRecord {
    /// Copies a task's measures into the record (or clears them if unmeasured).
    mutating func apply(_ r: TaskResult) {
        switch r.task {
        case .breath:
            mpt = r.vowel?.mpt
            hnr = r.vowel?.hnr
            vowelPitchVariation = r.vowel?.pitchVariation
        case .amr:
            amrRate = r.ddk?.rate
            amrRegularity = r.ddk?.regularity
        case .smr:
            smrRate = r.ddk?.rate
            smrRegularity = r.ddk?.regularity
        case .passage:
            readingRate = r.passage?.rate
            readingPauseShare = r.passage?.pauseShare
            syllablesPerBreathGroup = r.passage?.syllablesPerBreathGroup
            fatigueDb = r.passage?.fatigueDb
        }
    }

    func isMeasured(_ task: CheckTask) -> Bool {
        switch task {
        case .breath: mpt != nil
        case .amr: amrRate != nil
        case .smr: smrRate != nil
        case .passage: readingRate != nil
        }
    }
}
