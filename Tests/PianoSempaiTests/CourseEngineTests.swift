import SwiftData
import XCTest
@testable import PianoSempai

/// CourseEngine 规则表单测：查表确定性 + 数字可解释（brief M3：算法写死集中一处）。
final class CourseEngineTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: AppSettings.self, PlacementSelfReport.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self, DailyPlan.self, PracticeTask.self,
            Piece.self, // ADR-0003：finalizePlacement 定级后补建 waived/notStarted 条目
            configurations: config
        )
    }

    func testRuleTableDeterminism() {
        // 同一输入必须产出同一插入点（查表，无随机）
        let a = CourseEngine.beyerEntry(averageHitRate: 0.9, yearsExperience: "约 2 年")
        let b = CourseEngine.beyerEntry(averageHitRate: 0.9, yearsExperience: "约 2 年")
        XCTAssertEqual(a, b)
        // 高命中 + 2 年经验 → 拜厄 45（规则表首档）
        XCTAssertEqual(a, 45)
        // 低命中 → 从第 1 条
        XCTAssertLessThanOrEqual(CourseEngine.beyerEntry(averageHitRate: 0.1, yearsExperience: "半年内"), 8)
        // 命中率 0.9 → 599 预计 8 周
        XCTAssertEqual(CourseEngine.projected599Weeks(averageHitRate: 0.9), 8)
        // 哈农 P1 恒从第 1 条
        XCTAssertEqual(CourseEngine.hanonEntry(averageHitRate: 0.9), 1)
    }

    func testScoreComputationFromRealData() {
        // 音准 = 命中率×100：12/20 = 60
        XCTAssertEqual(CourseEngine.accuracyScore(hitRates: [0.5, 0.7]), 60)
        // 连贯 = 100 − 停顿×10：3 次停顿 = 70
        XCTAssertEqual(CourseEngine.continuityScore(pauseCounts: [1, 2]), 70)
        // 停顿 12 次 → 下限 0，不为负
        XCTAssertEqual(CourseEngine.continuityScore(pauseCounts: [12]), 0)
        // 综合参考只纳入真实算出的两维：(60+70)/2 = 65
        XCTAssertEqual(CourseEngine.overallReferenceScore(hitRates: [0.5, 0.7], pauseCounts: [1, 2]), 65)
    }

    func testFinalizePlacementWritesCourseState() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let report = PlacementSelfReport()
        report.yearsExperience = "约 2 年"
        context.insert(report)

        let result = CourseEngine.finalizePlacement(
            report: report,
            hitRates: [0.8, 0.6],
            expected: [32, 32],
            matched: [26, 19],
            pauseCounts: [0, 2],
            calibration: nil,
            elapsedSeconds: 600,
            in: context
        )
        try context.save()

        // 结果字段与规则表一致（avg 0.7 → 30 条档；599 = 12 周）
        XCTAssertEqual(result.entryBeyer, 30)
        XCTAssertEqual(result.projected599Weeks, 12)
        XCTAssertEqual(result.overallReferenceScore, 75) // 音准 70 / 连贯 80

        // CoursePathState 单例被写入（唯一写手）
        let paths = try context.fetch(FetchDescriptor<CoursePathState>())
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths.first?.currentBeyer, 30)
        XCTAssertEqual(paths.first?.projected599Week, 12)
        XCTAssertEqual(paths.first?.weekNumber, 1)
    }

    func testGenerateFirstWeekPlanCreatesTasks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let result = PlacementResult()
        result.entryBeyer = 45
        result.entryHanon = 1
        context.insert(result)

        let plan = CourseEngine.generateFirstWeekPlan(result: result, in: context)
        try context.save()

        XCTAssertEqual(plan.generatedFromRulesVersion, CourseEngine.rulesVersion)
        let tasks = try context.fetch(FetchDescriptor<PracticeTask>())
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.contains { $0.type == "warmup" && $0.book == "哈农" && $0.number == 1 })
        XCTAssertTrue(tasks.contains { $0.type == "main" && $0.book == "拜厄" && $0.number == 45 })
    }

    // MARK: 主菜小节区间（PRD §M5 热点分段；S07 真值主卡副行「17–24 小节」）

    /// 带 Take/TakeAnalysis 的容器（热点区间要查 take→analysis 链）
    private func makeContainerWithTakes() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: AppSettings.self, PlacementSelfReport.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self, DailyPlan.self, PracticeTask.self,
            Piece.self, Take.self, TakeAnalysis.self,
            configurations: config
        )
    }

    /// 定级完成的最小夹具（todayPlan 只有在 CoursePathState.placementResultId 非空时才生成）
    private func insertPlacement(context: ModelContext, beyer: Int = 45) throws {
        let result = PlacementResult()
        result.entryBeyer = beyer
        result.entryHanon = 1
        context.insert(result)
        let pathState = CoursePathState()
        pathState.placementResultId = result.entityId
        pathState.currentBeyer = beyer
        pathState.currentHanon = 1
        context.insert(pathState)
    }

    private func mainTask(in context: ModelContext) throws -> PracticeTask {
        try XCTUnwrap(
            context.fetch(FetchDescriptor<PracticeTask>()).first { $0.type == "main" },
            "todayPlan 应生成主菜任务"
        )
    }

    func testTodayPlanMainTaskCarriesHotspotMeasureRange() throws {
        let container = try makeContainerWithTakes()
        let context = ModelContext(container)
        try insertPlacement(context: context)

        // 曲目 + take + 分析：热点 0-based [16,17,18,23] → 1-based 17–24（真值同款区间）
        let piece = CourseEngine.resolveRoomPiece(book: "拜厄", number: 45, in: context)
        piece?.totalMeasures = 32
        let take = Take(durationSec: 120, taskType: "main", hasMidi: true, pieceId: piece?.entityId)
        context.insert(take)
        context.insert(TakeAnalysis(takeId: take.entityId, engineVersion: "test", hotspotMeasures: [16, 17, 18, 23]))
        try context.save()

        XCTAssertNotNil(CourseEngine.todayPlan(in: context))
        let main = try mainTask(in: context)
        XCTAssertEqual(main.measureFrom, 17, "热点 0-based [16,23] → 1-based 17（LoopService.hotspotRange 口径）")
        XCTAssertEqual(main.measureTo, 24)
        // 只有主菜写区间，热身不带
        let warmup = try XCTUnwrap(
            context.fetch(FetchDescriptor<PracticeTask>()).first { $0.type == "warmup" }
        )
        XCTAssertNil(warmup.measureFrom)
        XCTAssertNil(warmup.measureTo)
    }

    func testTodayPlanMainTaskStaysNilWithoutAnalysis() throws {
        let container = try makeContainerWithTakes()
        let context = ModelContext(container)
        try insertPlacement(context: context)
        try context.save()
        // 无 take、无分析：区间双 nil（诚实：没有热点数据就不写，不编区间）

        XCTAssertNotNil(CourseEngine.todayPlan(in: context))
        let main = try mainTask(in: context)
        XCTAssertNil(main.measureFrom)
        XCTAssertNil(main.measureTo)
    }
}
