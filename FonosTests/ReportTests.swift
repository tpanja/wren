import XCTest
@testable import Fonos

final class ReportTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!

    func testSlopeOfExactLineHasZeroInterval() throws {
        // y = 10 + 0.1 per day, so +3.0 per 30 days.
        let pts = (0..<30).map { ClinicReport.Point(date: t0.addingTimeInterval(Double($0) * day), value: 10 + 0.1 * Double($0)) }
        let s = try XCTUnwrap(ClinicReport.slope(pts))
        XCTAssertEqual(s.perMonth, 3.0, accuracy: 1e-9)
        XCTAssertEqual(s.ci95, 0, accuracy: 1e-9)
        XCTAssertEqual(s.n, 30)
    }

    func testSlopeNeedsThreePointsOverSevenDays() {
        let short = (0..<5).map { ClinicReport.Point(date: t0.addingTimeInterval(Double($0) * day), value: Double($0)) }
        XCTAssertNil(ClinicReport.slope(short), "Spans only 4 days")
        let two = [0, 10].map { ClinicReport.Point(date: t0.addingTimeInterval(Double($0) * day), value: Double($0)) }
        XCTAssertNil(ClinicReport.slope(two), "Only 2 points")
    }

    func testSlopeIntervalWidensWithNoise() throws {
        let noisy = (0..<10).map { i in
            ClinicReport.Point(date: t0.addingTimeInterval(Double(i) * 3 * day), value: Double(i) + (i % 2 == 0 ? 1 : -1))
        }
        let s = try XCTUnwrap(ClinicReport.slope(noisy))
        XCTAssertGreaterThan(s.ci95, 0)
        // True slope is 1 per 3 days = 10 per 30 days; noise must not flip it.
        XCTAssertEqual(s.perMonth, 10, accuracy: 3)
    }

    func testTCritical() {
        XCTAssertEqual(ClinicReport.tCritical95(df: 1), 12.706, accuracy: 1e-3)
        XCTAssertEqual(ClinicReport.tCritical95(df: 10), 2.228, accuracy: 1e-3)
        XCTAssertEqual(ClinicReport.tCritical95(df: 500), 1.960, accuracy: 1e-3)
    }

    func testFirstReportCoversAllSessions() {
        let history = ToyHistory.make(now: now)
        let r = ClinicReport.make(sessions: history, patient: .init(), lastExport: nil, now: now)
        XCTAssertFalse(r.sinceLastExport)
        // Toy history schedules some of today's sessions later than `now`; those are not in the report yet.
        XCTAssertEqual(r.quality.sessions, history.filter { $0.date <= now }.count)
        XCTAssertTrue(r.isSample)
        XCTAssertEqual(r.rows.map(\.measure), ClinicReport.order)
    }

    func testLaterReportCoversOnlyNewSessions() {
        let history = ToyHistory.make(now: now)
        let cut = now.addingTimeInterval(-14 * day)
        let r = ClinicReport.make(sessions: history, patient: .init(), lastExport: cut, now: now)
        XCTAssertTrue(r.sinceLastExport)
        XCTAssertEqual(r.quality.sessions, history.filter { $0.date > cut && $0.date <= now }.count)
        XCTAssertEqual(r.periodStart, cut)
    }

    func testDecliningHistoryIsReportedUnfavorably() throws {
        let history = ToyHistory.make(now: now)
        let r = ClinicReport.make(sessions: history, patient: .init(), lastExport: now.addingTimeInterval(-30 * day), now: now)
        let pace = try XCTUnwrap(r.rows.first { $0.measure == .session(.pace) })
        XCTAssertEqual(pace.status, .unfavorable)
        XCTAssertLessThan(try XCTUnwrap(pace.change), -0.05)
        XCTAssertTrue(r.summary.contains("unfavorable direction"))
    }

    func testTooFewSessionsIsInsufficient() {
        let history = ToyHistory.make(now: now)
        let r = ClinicReport.make(sessions: history, patient: .init(), lastExport: now.addingTimeInterval(-3600), now: now)
        XCTAssertTrue(r.rows.allSatisfy { $0.status == .insufficient })
        XCTAssertTrue(r.summary.hasPrefix("Not enough data"))
    }

    // MARK: Weekly checks in the report

    func testReportIncludesCheckMeasuresGroupedBySystem() throws {
        let r = ClinicReport.make(sessions: ToyHistory.make(now: now), checks: ToyCheckHistory.make(now: now),
                                  patient: .init(), lastExport: nil, now: now)
        // Rows follow the speech systems in order.
        let systems = r.rows.map(\.system)
        XCTAssertEqual(systems, systems.sorted { SpeechSystem.allCases.firstIndex(of: $0)! < SpeechSystem.allCases.firstIndex(of: $1)! })
        let mpt = try XCTUnwrap(r.rows.first { $0.measure == .check(.mpt) })
        XCTAssertEqual(mpt.n, 13)
        XCTAssertEqual(mpt.status, .unfavorable)
        XCTAssertEqual(r.quality.checks, 13)
        XCTAssertEqual(r.quality.checkTasks, 52)
        XCTAssertEqual(r.quality.selfReports, 13)
        XCTAssertNotNil(r.checkBaselineEnd)
    }

    func testFatigueChangeIsInDecibels() throws {
        let r = ClinicReport.make(sessions: [], checks: ToyCheckHistory.make(now: now), patient: .init(), lastExport: nil, now: now)
        let row = try XCTUnwrap(r.rows.first { $0.measure == .check(.fatigue) })
        // Absolute dB difference, not a percentage of a near-zero baseline.
        XCTAssertLessThan(abs(try XCTUnwrap(row.change)), 3)
        XCTAssertTrue(ClinicReport.changePhrase(-1.2, .check(.fatigue)).hasPrefix("1.2 dB"))
    }

    func testChecksOnlyReportStillDescribesChange() {
        let r = ClinicReport.make(sessions: [], checks: ToyCheckHistory.make(now: now), patient: .init(), lastExport: nil, now: now)
        XCTAssertTrue(r.summary.contains("unfavorable direction"), r.summary)
        XCTAssertTrue(r.rows.filter { !$0.measure.isCheck }.allSatisfy { $0.status == .insufficient })
    }
}
