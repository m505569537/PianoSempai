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
}
