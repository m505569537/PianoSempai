import Foundation
import SwiftData

// M7.2 月报 AI 观察（brief §1：PRD M8 + S22「Neko 的本月观察」）。
// 只做纯文字调用：ChainInput 不带任何附件（月报观察不涉及视频/图片，红线 3）；
// prompt/上下文全部由本地真实统计组装，禁止 AI 发明数字（红线 1）；
// 结果只回写 MonthlyReport 的观察三个字段，不回写任何练习/课程/计划状态。
// Runner / 服务商列表全部协议化可注入：单测用假 runner，不打网络、不读 Keychain。

// MARK: - 依赖协议

/// 一次观察的执行者。ProviderChainRunner 天然满足本协议（见文末 extension）。
protocol MonthlyObservationRunning: AnyObject {
    func run(providers: [AIProvider], input: ChainInput) async throws -> ChainResult
}

/// 服务商列表来源（与 ChatStore 同一范式：enabled 过滤由 runner 内部做，这里给全量）。
protocol MonthlyProviderSource: AnyObject {
    func currentProviders() -> [AIProvider]
}

/// SwiftData 实现：读全部服务商配置（非密配置；Key 只在 Keychain，不出本层）
final class SwiftDataMonthlyProviderSource: MonthlyProviderSource {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func currentProviders() -> [AIProvider] {
        (try? context.fetch(FetchDescriptor<AIProvider>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }
}

// MARK: - 结果

/// 一次观察的三段产物（providerModel 原样回写，可溯）
struct MonthlyObservation: Equatable {
    var title: String
    var body: String
    var providerModel: String
}

/// 观察生成器（协调器依赖协议；单测注入 fake）
protocol MonthlyObservationGenerating: AnyObject {
    func makeObservation(
        snapshot: MonthlyReportSnapshot,
        providers: [AIProvider],
        runner: any MonthlyObservationRunning
    ) async throws -> MonthlyObservation
}

// MARK: - 纯文案（可单测）

/// 观察 prompt 的组装与返回文本的拆解。数字全部来自 snapshot 真实值，缺数据明说「数据不足」，
/// 并明确告诉模型不要据此下结论（不编造）；无视频时显式禁止手型相关结论（红线 1/5）。
enum MonthlyObservationText {
    /// 固定问题句
    static let question = "请生成本月观察与下月建议"

    static func systemPrompt() -> String {
        """
        你是钢琴自学助教 Neko，正在给用户写「本月观察」。
        要求：
        1. 先指出本月一个最值得说的进步或现象，再给下月一个具体的小建议。
        2. 只依据上面给定的真实数字，禁止虚构没有出现的曲目、速度、小节或数据；数字不足就泛化到练习节奏和频率，不要编细节。
        3. 语气温柔、具体，不夸奖轰炸；建议要可执行，落到曲目类型、热身频率、速度上限这类。
        4. 输出格式：第一行是不超过 20 字的小标题，空一行，后面是 120-200 字正文；不要使用 Markdown 标记。
        """
    }

    /// 把 snapshot 的真实数字格式化成上下文块（无视频则不写手型行，并明确禁止手型结论）
    static func contextBlock(_ snapshot: MonthlyReportSnapshot) -> String {
        var lines: [String] = ["【本月统计快照 · \(snapshot.periodKey)】"]
        lines.append("有效练习 \(snapshot.validDays) 天，总时长 \(DurationText.hoursMinutes(snapshot.totalDurationSec))，take 共 \(snapshot.takeCount) 条，平均每周 \(MonthlyReportText.sessionsPerWeekText(snapshot.avgSessionsPerWeek)) 有效练习。")
        lines.append(routeLine(snapshot))
        lines.append(warmupLine(snapshot))
        lines.append(overrideLine(snapshot))
        lines.append(rhythmLine(snapshot))
        if snapshot.refsVideoCount == 0 {
            lines.append("本月没有视频或侧拍记录，不要写任何手型、姿势、录像相关结论。")
        }
        return lines.joined(separator: "\n")
    }

    /// 装配一次观察调用的输入：纯文字（systemPrompt + contextBlock + question），
    /// 不带任何附件字段、不带证据引用数组（观察的证据数由本地 chip 渲染，不靠 AI 文本）。
    static func input(snapshot: MonthlyReportSnapshot) -> ChainInput {
        ChainInput(
            question: question,
            systemPrompt: systemPrompt(),
            contextBlock: contextBlock(snapshot),
            evidenceRefs: []
        )
    }

    /// 按首个空行拆 title/body；拆不出（或无正文）→ 兜底标题 + 全文。trim。
    static func parse(_ text: String) -> (title: String, body: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "\\n[ \\t]*\\n", options: .regularExpression) else {
            return (MonthlyReportText.observationFallbackTitle, trimmed)
        }
        let title = String(trimmed[trimmed.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(trimmed[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else {
            return (MonthlyReportText.observationFallbackTitle, trimmed)
        }
        return (title, body)
    }

    // MARK: 上下文块分行

    private static func routeLine(_ snapshot: MonthlyReportSnapshot) -> String {
        let rows = MonthlyReportText.routeRows(snapshot).map { row -> String in
            row.detail.isEmpty ? row.title : "\(row.title) \(row.detail)"
        }
        return "教材路线当前值：\(rows.joined(separator: "，"))."
    }

    private static func warmupLine(_ snapshot: MonthlyReportSnapshot) -> String {
        guard let pct = snapshot.warmupCompletionPct else {
            return "热身完成率：本月暂无计划（无数据，不要据此下结论）。"
        }
        return "热身完成率：\(pct)%。"
    }

    private static func overrideLine(_ snapshot: MonthlyReportSnapshot) -> String {
        if snapshot.overrideCount == 0 {
            return "强开主菜：0 次。"
        }
        let chips = MonthlyReportText.overrideReasonChips(snapshot).joined(separator: "、")
        return "强开主菜 \(snapshot.overrideCount) 次（\(chips)）。"
    }

    private static func rhythmLine(_ snapshot: MonthlyReportSnapshot) -> String {
        switch MonthlyReportText.rhythm(snapshot) {
        case .insufficient:
            return "节奏稳定度：本月节奏分数据不足（无分析结果，不要据此下结论）。"
        case let .trend(weeks, first, last, delta):
            return "节奏稳定度：\(weeks) 周，首周 \(first) 分、末周 \(last) 分，变化 \(MonthlyReportText.signed(delta)) 分。"
        }
    }
}

// MARK: - 实现

final class MonthlyObservationService: MonthlyObservationGenerating {
    func makeObservation(
        snapshot: MonthlyReportSnapshot,
        providers: [AIProvider],
        runner: any MonthlyObservationRunning
    ) async throws -> MonthlyObservation {
        // 纯文字调用；全链失败让 ProviderChainFailure 原样抛出（由协调器转 observationStatus=failed）
        let result = try await runner.run(providers: providers, input: MonthlyObservationText.input(snapshot: snapshot))
        let parsed = MonthlyObservationText.parse(result.text)
        return MonthlyObservation(title: parsed.title, body: parsed.body, providerModel: result.providerModel)
    }
}

// MARK: - Runner 满足协议

extension ProviderChainRunner: MonthlyObservationRunning {}
