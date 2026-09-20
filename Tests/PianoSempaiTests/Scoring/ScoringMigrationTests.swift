import SwiftData
import XCTest
@testable import PianoSempai

/// P2 M4：SwiftData 迁移冒烟（旧默认值容器可打开、新字段有默认）+ TakeAnalysis 幂等 upsert。
final class ScoringMigrationTests: XCTestCase {

    /// 全模型 schema（与 PianoSempaiApp 注册一致）
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AppSettings.self, PlacementSelfReport.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self, DailyPlan.self, PracticeTask.self,
            GateEvent.self, Take.self, Piece.self, ScoreFile.self, ScoreErrorMark.self,
            TakeAnalysis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// 旧 take（无新字段时代的默认值语义）：新容器打开后新字段有默认值
    @MainActor
    func testLegacyTakeOpensWithNewFieldDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let legacy = Take(startedAt: Date(), durationSec: 60, taskType: "main", hasMidi: true)
        context.insert(legacy)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Take>())
        XCTAssertEqual(fetched.count, 1)
        let take = try XCTUnwrap(fetched.first)
        XCTAssertNil(take.pieceId, "旧 take pieceId 默认 nil")
        XCTAssertNil(take.scoreFileId)
        XCTAssertNil(take.analysisId)
        XCTAssertFalse(take.isPassEligible, "旧 take 默认不参与过关判定")
        XCTAssertTrue(take.wrongNoteRecords.isEmpty)
        // M5b 新增字段：旧行默认 0（错音率分母不可编造）
        let legacyAnalysis = TakeAnalysis(takeId: take.entityId, engineVersion: "P2-scoring-1.0")
        context.insert(legacyAnalysis)
        XCTAssertEqual(legacyAnalysis.referenceNoteCount, 0, "旧分析行默认分母 0")
    }

    /// TakeAnalysis 幂等 upsert：同 takeId+engineVersion 重算不产生重复行
    @MainActor
    func testAnalysisUpsertIsIdempotentPerTakeAndVersion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let take = Take(durationSec: 60, taskType: "main", hasMidi: true)
        context.insert(take)

        let takeId = take.entityId
        let version = "P2-scoring-1.0"

        // 首算：建
        var analysis = TakeAnalysis(takeId: takeId, engineVersion: version, confidence: 0.9)
        context.insert(analysis)
        try context.save()

        // 重算：按 takeId+engineVersion 找到旧行 → 原地更新（upsert 语义）
        let descriptor = FetchDescriptor<TakeAnalysis>(
            predicate: #Predicate { $0.takeId == takeId && $0.engineVersion == version }
        )
        let existing = try context.fetch(descriptor)
        XCTAssertEqual(existing.count, 1)
        analysis = existing[0]
        analysis.confidence = 0.8
        analysis.canEvaluate = true
        try context.save()

        let after = try context.fetch(FetchDescriptor<TakeAnalysis>())
        XCTAssertEqual(after.count, 1, "重算必须幂等（不产生重复行）")
        XCTAssertEqual(after.first?.confidence ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertTrue(after.first?.canEvaluate ?? false)
    }

    /// 引擎版本切换（升级重算）：不同 engineVersion 各占一行（保证可比性历史）
    @MainActor
    func testDifferentEngineVersionsCoexist() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let take = Take(durationSec: 60, taskType: "main", hasMidi: true)
        context.insert(take)
        context.insert(TakeAnalysis(takeId: take.entityId, engineVersion: "P2-scoring-1.0", confidence: 0.9))
        context.insert(TakeAnalysis(takeId: take.entityId, engineVersion: "P2-scoring-2.0", confidence: 0.95))
        try context.save()
        let rows = try context.fetch(FetchDescriptor<TakeAnalysis>())
        XCTAssertEqual(rows.count, 2, "不同引擎版本的分析共存（升级重算可对比）")
    }
}
