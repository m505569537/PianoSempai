import Foundation
import SwiftData
import XCTest

@testable import PianoSempai

/// M7.2 月报 Snapshot ↔ @Model 映射（PRD M8 快照冻结语义；JSON round-trip、损坏安全回落）。
/// 内存 ModelContainer，不碰磁盘；两个结构化字段（overrideReasons / weeklyRhythmScores）走 JSON 编解码。
@MainActor
final class MonthlyReportModelMappingTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    private let generatedAt = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: MonthlyReport.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    /// 一份字段齐全的 9 月快照：覆盖全部字段，含 nil 周与真实原因分布
    private func makeSnapshot() -> MonthlyReportSnapshot {
        MonthlyReportSnapshot(
            year: 2026,
            month: 9,
            validDays: 14,
            totalDurationSec: 30_600,
            takeCount: 47,
            avgSessionsPerWeek: 3.2,
            beyerCurrent: 48,
            hanonCurrent: 4,
            unlocked599: false,
            projected599Week: 44,
            warmupCompletionPct: 79,
            overrideCount: 3,
            overrideReasons: ["时间不够": 2, "other": 1],
            rhythmFirstWeekScore: 52,
            rhythmLastWeekScore: 71,
            weeklyRhythmScores: [52, nil, 63, 71],
            observationTitle: "",
            observationBody: "",
            observationProviderModel: nil,
            refsTakeCount: 47,
            refsVideoCount: 0,
            observationStatus: "pending",
            generatedAt: generatedAt
        )
    }

    // MARK: Snapshot → 模型 → Snapshot

    func testInitFromSnapshotRoundTripsEveryField() {
        let snapshot = makeSnapshot()
        let report = MonthlyReport(snapshot: snapshot)
        XCTAssertEqual(report.periodKey, "2026-09", "periodKey 由 year/month 推导（零填充）")
        XCTAssertEqual(report.snapshot, snapshot, "全字段一致（含 overrideReasons / weeklyRhythmScores JSON round-trip）")
        XCTAssertTrue(report.weeklyRhythmScoresJSON.contains("null"), "无分析周以 null 落库")
    }

    func testRoundTripThroughModelContainer() throws {
        let snapshot = makeSnapshot()
        context.insert(MonthlyReport(snapshot: snapshot))
        try context.save()
        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<MonthlyReport>()).first)
        XCTAssertEqual(fetched.periodKey, "2026-09")
        XCTAssertEqual(fetched.snapshot.validDays, snapshot.validDays)
        XCTAssertEqual(fetched.snapshot.totalDurationSec, snapshot.totalDurationSec)
        XCTAssertEqual(fetched.snapshot.takeCount, snapshot.takeCount)
        XCTAssertEqual(fetched.snapshot.avgSessionsPerWeek ?? -1, 3.2, accuracy: 1e-9)
        XCTAssertEqual(fetched.snapshot.overrideReasons, ["时间不够": 2, "other": 1])
        XCTAssertEqual(fetched.snapshot.weeklyRhythmScores, [52, nil, 63, 71])
        XCTAssertEqual(fetched.snapshot.warmupCompletionPct, 79)
        XCTAssertEqual(fetched.snapshot.observationStatus, "pending")
        XCTAssertEqual(fetched.snapshot.refsTakeCount, 47)
        XCTAssertEqual(fetched.snapshot.generatedAt.timeIntervalSince1970, generatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWeeklyRhythmScoresNilElementsRoundTrip() {
        let report = MonthlyReport(snapshot: MonthlyReportSnapshot(year: 2026, month: 2, weeklyRhythmScores: [nil, nil]))
        XCTAssertEqual(report.snapshot.weeklyRhythmScores, [nil, nil], "全 nil 周不塌成空数组")
        XCTAssertNil(report.snapshot.rhythmFirstWeekScore)
        XCTAssertNil(report.snapshot.rhythmLastWeekScore)
    }

    func testEmptyStructuresRoundTrip() {
        let report = MonthlyReport(
            snapshot: MonthlyReportSnapshot(year: 2026, month: 1, overrideReasons: [:], weeklyRhythmScores: [])
        )
        XCTAssertEqual(report.snapshot.overrideReasons, [:])
        XCTAssertEqual(report.snapshot.weeklyRhythmScores, [])
    }

    // MARK: 损坏 JSON 安全回落（不崩溃）

    func testCorruptedJSONFallsBackToSafeEmptyValues() {
        let malformed = MonthlyReport(
            periodKey: "2026-09",
            overrideReasonsJSON: "{ 不是 JSON",
            weeklyRhythmScoresJSON: "[52, null"
        )
        XCTAssertEqual(malformed.snapshot.overrideReasons, [:])
        XCTAssertEqual(malformed.snapshot.weeklyRhythmScores, [])

        // 类型不符（值是字符串而非 Int）
        let wrongTypes = MonthlyReport(overrideReasonsJSON: "{\"a\": \"b\"}", weeklyRhythmScoresJSON: "[{\"x\": 1}]")
        XCTAssertEqual(wrongTypes.snapshot.overrideReasons, [:])
        XCTAssertEqual(wrongTypes.snapshot.weeklyRhythmScores, [])

        // 空串
        let empty = MonthlyReport(overrideReasonsJSON: "", weeklyRhythmScoresJSON: "")
        XCTAssertEqual(empty.snapshot.overrideReasons, [:])
        XCTAssertEqual(empty.snapshot.weeklyRhythmScores, [])
    }

    func testCorruptedJSONKeepsOtherFieldsIntact() {
        let report = MonthlyReport(
            periodKey: "2026-09",
            validDays: 14,
            takeCount: 47,
            overrideReasonsJSON: "坏",
            weeklyRhythmScoresJSON: "坏"
        )
        let snapshot = report.snapshot
        XCTAssertEqual(snapshot.validDays, 14, "坏一行 JSON 不等于坏整份月报")
        XCTAssertEqual(snapshot.takeCount, 47)
        XCTAssertEqual(snapshot.periodKey, "2026-09")
        XCTAssertEqual(snapshot.overrideReasons, [:])
        XCTAssertEqual(snapshot.weeklyRhythmScores, [])
    }

    // MARK: 默认 init = 空月报安全形态

    func testDefaultInitIsEmptyMonthSafeShape() {
        let report = MonthlyReport()
        XCTAssertEqual(report.periodKey, "")
        XCTAssertEqual(report.overrideReasonsJSON, "{}")
        XCTAssertEqual(report.weeklyRhythmScoresJSON, "[]")
        XCTAssertEqual(report.observationStatus, "pending")
        XCTAssertEqual(report.refsVideoCount, 0)
        XCTAssertEqual(report.snapshot.overrideReasons, [:])
        XCTAssertEqual(report.snapshot.weeklyRhythmScores, [])
        XCTAssertNil(report.snapshot.warmupCompletionPct)
        XCTAssertNil(report.snapshot.avgSessionsPerWeek)
    }
}
