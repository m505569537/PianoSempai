import Foundation
import XCTest

@testable import PianoSempai

/// M7.2 月报 AI 观察（brief §1）：prompt/上下文只吃真实统计、纯文字无附件、
/// 首空行拆 title/body、全链失败原样抛出。假 runner + 假服务商源，不打网络。
final class MonthlyObservationServiceTests: XCTestCase {

    // MARK: 假依赖

    private final class FakeRunner: MonthlyObservationRunning {
        private(set) var inputs: [ChainInput] = []
        private(set) var providerCounts: [Int] = []
        var resultText = "本月稳住了练习节奏\n\n正文：有效练习 14 天，节奏保持得不错。"
        var failure: ProviderChainFailure?

        func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult {
            inputs.append(input)
            providerCounts.append(providers.count)
            if let failure { throw failure }
            return ChainResult(
                text: resultText,
                providerModel: "百炼 qwen3-max",
                evidenceRefs: [],
                attempts: []
            )
        }
    }

    // MARK: 夹具

    /// 一份字段齐全的 9 月快照（含已解锁 599、强开原因、节奏首末周分）
    private func makeSnapshot() -> MonthlyReportSnapshot {
        MonthlyReportSnapshot(
            year: 2026,
            month: 9,
            validDays: 14,
            totalDurationSec: 30_720, // 8 小时 32 分
            takeCount: 47,
            avgSessionsPerWeek: 3.2,
            beyerCurrent: 48,
            hanonCurrent: 4,
            unlocked599: true,
            current599: 5,
            projected599Week: 44,
            warmupCompletionPct: 79,
            overrideCount: 3,
            overrideReasons: ["时间不够": 2, "other": 1],
            rhythmFirstWeekScore: 52,
            rhythmLastWeekScore: 71,
            weeklyRhythmScores: [52, nil, 63, 71],
            refsTakeCount: 47,
            refsVideoCount: 0,
            observationStatus: "pending",
            generatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    // MARK: 输入：真实数字 + 纯文字

    func testContextBlockCarriesRealSnapshotNumbers() async throws {
        let input = MonthlyObservationText.input(snapshot: makeSnapshot())

        XCTAssertEqual(input.question, "请生成本月观察与下月建议")
        XCTAssertTrue(input.systemPrompt.contains("钢琴自学助教"))
        XCTAssertTrue(input.systemPrompt.contains("禁止虚构"))
        for needle in [
            "2026-09", "14 天", "8 小时 32 分", "47 条", "3.2次",
            "拜厄 当前 48", "哈农 当前 4", "车尔尼599 已开始 第 5 首",
            "79%", "强开主菜 3 次", "时间不够×2", "其他×1",
            "首周 52 分", "末周 71 分", "+19 分",
        ] {
            XCTAssertTrue(input.contextBlock.contains(needle), "上下文块应含真实值：\(needle)")
        }
        // 无视频：显式禁止手型结论（红线 1）
        XCTAssertTrue(input.contextBlock.contains("没有视频或侧拍记录"))
    }

    func testInputHasNoAttachmentFields() async throws {
        let input = MonthlyObservationText.input(snapshot: makeSnapshot())

        // 观察是纯文字调用：不带任何附件/证据字段
        XCTAssertTrue(input.evidenceRefs.isEmpty)
        let fields = Mirror(reflecting: input).children.compactMap { $0.label?.lowercased() }
        for field in fields {
            for needle in ["attach", "video", "image", "url"] {
                XCTAssertFalse(field.contains(needle), "观察输入不得带附件字段：\(field)")
            }
        }
    }

    func testContextBlockDegradesWhenDataMissing() {
        // 无计划 / 无强开 / 无节奏分 / 未解锁 599 且无预计周
        let snapshot = MonthlyReportSnapshot(
            year: 2026, month: 8, validDays: 2, totalDurationSec: 1200, takeCount: 3,
            avgSessionsPerWeek: 0.6, beyerCurrent: 43, hanonCurrent: 1, unlocked599: false,
            projected599Week: 0, warmupCompletionPct: nil, overrideCount: 0,
            rhythmFirstWeekScore: nil, rhythmLastWeekScore: nil, weeklyRhythmScores: [nil, nil],
            refsTakeCount: 3, refsVideoCount: 0
        )
        let block = MonthlyObservationText.contextBlock(snapshot)
        XCTAssertTrue(block.contains("本月暂无计划"), "无计划如实说，不填 0%")
        XCTAssertTrue(block.contains("强开主菜：0 次"))
        XCTAssertTrue(block.contains("节奏分数据不足"))
        XCTAssertTrue(block.contains("车尔尼599 🔒"))
        XCTAssertFalse(block.contains("预计"), "projected599Week = 0 不编预计月份")
    }

    func testMakeObservationReturnsTitleBodyAndProviderModel() async throws {
        let runner = FakeRunner()
        let providers = [AIProvider(providerId: "bailian", displayName: "百炼", baseURL: "https://x/v1", modelIds: ["qwen3-max"])]
        let observation = try await MonthlyObservationService().makeObservation(
            snapshot: makeSnapshot(), providers: providers, runner: runner
        )
        XCTAssertEqual(observation.title, "本月稳住了练习节奏")
        XCTAssertTrue(observation.body.hasPrefix("正文："))
        XCTAssertEqual(observation.providerModel, "百炼 qwen3-max", "命中服务商·模型原样回写（可溯）")
        XCTAssertEqual(runner.providerCounts, [1])
    }

    // MARK: 解析规则

    func testParseSplitsOnFirstBlankLine() {
        let parsed = MonthlyObservationText.parse("小标题\n\n第一段\n第二段")
        XCTAssertEqual(parsed.title, "小标题")
        XCTAssertEqual(parsed.body, "第一段\n第二段")
    }

    func testParseTrimsAndHandlesMultipleBlankLines() {
        let parsed = MonthlyObservationText.parse("\n  小标题  \n\n\n  正文  \n")
        XCTAssertEqual(parsed.title, "小标题")
        XCTAssertEqual(parsed.body, "正文")
    }

    func testParseFallsBackWhenNoBlankLine() {
        let parsed = MonthlyObservationText.parse("只有一段正文，没有空行")
        XCTAssertEqual(parsed.title, MonthlyReportText.observationFallbackTitle)
        XCTAssertEqual(parsed.body, "只有一段正文，没有空行")
    }

    func testParseFallsBackWhenTitleOrBodyMissing() {
        let noBody = MonthlyObservationText.parse("只有标题\n\n   ")
        XCTAssertEqual(noBody.title, MonthlyReportText.observationFallbackTitle)
        XCTAssertEqual(noBody.body, "只有标题")

        let noTitle = MonthlyObservationText.parse("  \n\n正文")
        XCTAssertEqual(noTitle.title, MonthlyReportText.observationFallbackTitle)
        XCTAssertEqual(noTitle.body, "正文")
    }

    func testParseEmptyTextDoesNotCrash() {
        let parsed = MonthlyObservationText.parse("   \n\n  ")
        XCTAssertEqual(parsed.title, MonthlyReportText.observationFallbackTitle)
        XCTAssertTrue(parsed.body.isEmpty)
    }

    // MARK: 失败：原样抛出（由协调器决定状态）

    func testChainFailureIsRethrownAsIs() async {
        let runner = FakeRunner()
        runner.failure = ProviderChainFailure(attempts: [
            ProviderChainFailure.Attempt(providerId: "ark", providerDisplayName: "方舟", modelId: "m1", errorSummary: "401"),
        ])
        do {
            _ = try await MonthlyObservationService().makeObservation(
                snapshot: makeSnapshot(), providers: [], runner: runner
            )
            XCTFail("全链失败应原样抛出 ProviderChainFailure")
        } catch let failure as ProviderChainFailure {
            XCTAssertEqual(failure.attempts.count, 1)
            XCTAssertEqual(failure.attempts.first?.errorSummary, "401")
        } catch {
            XCTFail("抛出的应是 ProviderChainFailure，实际：\(error)")
        }
    }

    func testEmptyProviderListThrowsEmptyAttempts() async {
        let runner = FakeRunner()
        runner.failure = ProviderChainFailure(attempts: [])
        do {
            _ = try await MonthlyObservationService().makeObservation(
                snapshot: makeSnapshot(), providers: [], runner: runner
            )
            XCTFail("一个服务商都没配也应失败")
        } catch let failure as ProviderChainFailure {
            XCTAssertTrue(failure.attempts.isEmpty)
        } catch {
            XCTFail("抛出的应是 ProviderChainFailure，实际：\(error)")
        }
    }
}
