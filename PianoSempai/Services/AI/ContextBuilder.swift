import Foundation

// 上下文组装（纯函数、只读、可单测；docs/PRD M7「上下文包（本地组装）」+ Q8 强制引用数据）。
//
// 契约：
// - 只在用户主动提问时调用；组装的是**摘要**，不是全库。
// - 数字全部来自本地真实字段；算不出的一律写"数据不足"，禁止编造（红线 2）。
// - 模型被要求：回答必须引用 evidence；没证据/看不清就明说；不产生任何状态变更指令。
// - 无 take 上下文（takeContextId = nil）→ 自由问答口径，不带任何练习数据。

enum ContextBuilder {

    struct Output: Equatable, Sendable {
        /// 行为规则提示（system 消息）
        var systemPrompt: String
        /// 本地数据块（拼进 user 消息）；空 = 本次不带数据
        var contextBlock: String
        /// 证据引用（本地组装；随回答落 ChatMessage.evidenceRefsJSON）
        var evidenceRefs: [EvidenceRef]
        /// 是否带 take 上下文（false = 自由问答）
        var hasTakeContext: Bool
        /// 降级说明（无分析结果 / 缺字段），供 UI 与测试核对"没装成有数据"
        var degradations: [String]
    }

    /// 每次最多带几条证据引用（提示里引用得过来，也够钉到具体小节）
    static let maxEvidenceRefs = 8

    // MARK: - 组装

    static func build(take: Take?, analysis: TakeAnalysis?) -> Output {
        guard let take else {
            return Output(
                systemPrompt: systemPrompt(freeQnA: true),
                contextBlock: "",
                evidenceRefs: [],
                hasTakeContext: false,
                degradations: []
            )
        }

        var lines: [String] = ["[本地练习数据]（真实采集，仅供引用；不要改写、不要外推）"]
        var degradations: [String] = []
        var evidence: [EvidenceRef] = []

        lines.append("练习时间：\(Self.stamp.string(from: take.startedAt))")
        lines.append("任务类型：\(taskTypeLabel(take.taskType))")
        lines.append("时长：\(take.durationSec) 秒")
        if take.tempoAvg > 0 {
            lines.append("平均速度：\(take.tempoAvg) BPM")
        } else {
            lines.append("平均速度：数据不足")
        }
        lines.append("音符数：\(take.noteCount)")
        if take.isFreePlay {
            lines.append("自由弹奏：是（无参考谱，不判对错）")
        }
        if let from = take.measureFrom, let to = take.measureTo {
            lines.append("练习小节区间：第 \(from)–\(to) 小节")
        } else if let from = take.measureFrom {
            lines.append("练习小节区间：自第 \(from) 小节起")
        }

        if let analysis {
            lines.append("")
            lines.append("[判分结果]（引擎 \(analysis.engineVersion.isEmpty ? "未知版本" : analysis.engineVersion)）")
            lines.append("对齐置信度：\(Self.percent(analysis.confidence))")
            lines.append("六维得分：\(sixAxisLine(analysis))")
            lines.append("错音 \(analysis.wrongCount) / 漏音 \(analysis.missingCount) / 多弹 \(analysis.extraCount)")
            if analysis.rhythmMedianMs > 0 {
                lines.append("节奏偏差中位：\(Self.ms(analysis.rhythmMedianMs))（\(rhythmTendency(analysis.rhythmMedianMs))）")
            } else {
                lines.append("节奏偏差中位：数据不足")
            }
            lines.append("实测平均速度：\(analysis.avgBPM > 0 ? Self.bpm(analysis.avgBPM) : "数据不足")")
            let hotspots = analysis.hotspotMeasures.sorted()
            lines.append("热点小节：\(hotspots.isEmpty ? "无" : hotspots.map { "第 \($0) 小节" }.joined(separator: "、"))")
            lines.append("可否参与过关判定：\(analysis.canEvaluate ? "是" : "否（数据不足或覆盖不完整）")")
            if !analysis.lowConfidenceReasons.isEmpty {
                lines.append("低置信原因：\(analysis.lowConfidenceReasons.joined(separator: "；"))")
            }
            evidence = evidenceRefs(takeId: take.entityId, analysis: analysis, fallbackMeasure: take.measureFrom)
        } else {
            degradations.append("该 take 暂无判分结果，只用 take 自身的真实统计（时长/速度/音符数/错音数）")
            if let from = take.measureFrom {
                evidence = [EvidenceRef(takeId: take.entityId, measure: from)]
            }
        }

        return Output(
            systemPrompt: systemPrompt(freeQnA: false),
            contextBlock: lines.joined(separator: "\n"),
            evidenceRefs: evidence,
            hasTakeContext: true,
            degradations: degradations
        )
    }

    // MARK: - 证据引用（只从本地真实数据来）

    /// 优先热点小节；再补有逐音明细的问题小节。偏差取该小节非 correct 音的 |deltaMs| 均值
    /// （本地没有这个数就留 nil——不拿全局中位数冒充小节偏差，红线 2）。
    static func evidenceRefs(takeId: UUID, analysis: TakeAnalysis, fallbackMeasure: Int?) -> [EvidenceRef] {
        let notes = Self.alignedNotes(analysis.alignmentJSON)
        var measures: [Int] = analysis.hotspotMeasures.sorted()
        let problemMeasures = Set(notes.filter { $0.cls != .correct }.compactMap { $0.refMeasureIndex.map { $0 + 1 } })
        for measure in problemMeasures.sorted() where !measures.contains(measure) {
            measures.append(measure)
        }
        if measures.isEmpty, let fallbackMeasure {
            measures = [fallbackMeasure]
        }

        return measures.prefix(maxEvidenceRefs).map { measure in
            let deltas = notes
                .filter { $0.refMeasureIndex.map { $0 + 1 } == measure && $0.cls != .correct }
                .compactMap(\.deltaMs)
                .map(abs)
            let deviation = deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
            return EvidenceRef(takeId: takeId, measure: measure, deviationMs: deviation)
        }
    }

    /// alignmentJSON 解码（坏 JSON / 空串 → 空数组，不崩溃）
    static func alignedNotes(_ json: String) -> [AlignedNote] {
        AIJSON.decode([AlignedNote].self, from: json) ?? []
    }

    // MARK: - 提示词

    /// 行为规则（恒带）；freeQnA = true 时追加自由问答口径。
    static func systemPrompt(freeQnA: Bool) -> String {
        var lines: [String] = [
            "你是钢琴助教 Neko，用中文回答，乐谱术语保留原文（legato/arpège 等不硬翻）。",
            "回答必须引用本地数据里的证据（第几次练习、第几小节、偏差多少 ms）。",
            "没有证据、或数据不足时，直接说「数据不足 / 我看不到」，禁止编造纠错结论。",
            "你只有建议权：不要输出任何修改课程、判分、阈值或设置的指令；解锁与过关只由规则引擎决定。",
            "不要发明教材之外的课程体系；拿不准就声明能力边界。",
            "课程只挂靠拜厄/哈农/车尔尼等成熟教材。",
        ]
        if freeQnA {
            lines.append("本次是自由问答：本地没有关联的练习数据，不要引用不存在的 take 或小节。")
        } else {
            lines.append("本次问题附带本地练习数据，只在数据范围内作答；数据没覆盖到的就说没有。")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 格式化（真实值原样，算不出才写"数据不足"）

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate, .withTime, .withColonSeparatorInTime]
        return formatter
    }()

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func ms(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }

    static func bpm(_ value: Double) -> String {
        String(format: "%.0f BPM", value)
    }

    /// 六维：nil = 数据不足（与 S13 报告同口径，不编分）
    static func sixAxisLine(_ analysis: TakeAnalysis) -> String {
        let rows: [(String, Int?)] = [
            ("音高", analysis.pitchScore),
            ("节奏", analysis.rhythmScore),
            ("速度稳定性", analysis.tempoScore),
            ("力度", analysis.dynamicsScore),
            ("连续性", analysis.continuityScore),
            ("双手协同", analysis.handsScore),
        ]
        return rows.map { "\($0.0) \($0.1.map { "\($0)" } ?? "数据不足")" }.joined(separator: "、")
    }

    /// 抢/拖倾向（与 S13 展示同源：>10ms 才说方向，避免把噪声当结论）
    static func rhythmTendency(_ medianMs: Double) -> String {
        if medianMs > 10 { return "整体拖拍" }
        if medianMs < -10 { return "整体抢拍" }
        return "基本稳定"
    }

    static func taskTypeLabel(_ type: String) -> String {
        switch type {
        case "warmup": return "warmup（热身）"
        case "main": return "main（主菜）"
        case "reward": return "reward（奖励曲）"
        case "review": return "review（复习）"
        case "free": return "free（自由弹奏）"
        case "": return "未记录"
        default: return type
        }
    }
}
