import Foundation

// P1 简化分析（brief：S13 报告先给时长/音符数/错音数/速度/踏板事件数/MIDI 事件数；
// 六维/热力/节奏偏差/弱总分 = P2 完整判分占位）。
// 纯函数、只读、不写任何课程状态（红线 3；测试断言）。
// 谱错剔除规则（S13b）：被标"疑似谱错"的小节从该 take 错音率分子中扣除；其他小节不受影响。
// 旧 take 只有错音总数（无逐音明细）→ 无法按小节剔除时如实标注，不假装剔除。

struct P1TakeAnalysis: Equatable {
    // 真实统计维度
    let durationSec: Int
    let noteCount: Int
    let pedalEventCount: Int
    let midiEventCount: Int
    let tempoAvg: Int
    /// 逐音错音明细（M6b 起的 take 才有；旧 take 为空）
    let wrongNotes: [WrongNoteRecord]
    /// 旧口径错音总数（无明细时的唯一真值）
    let wrongNoteTotal: Int
    let hasDetail: Bool

    /// S13b 已标记小节（从错音率分子扣除）
    let excludedMeasures: Set<Int>

    /// 剔除后的错音数（引擎规则；无明细时按总数，剔除不适用）
    var effectiveWrongCount: Int {
        hasDetail
            ? wrongNotes.filter { !excludedMeasures.contains($0.measure) }.count
            : wrongNoteTotal
    }

    /// 错音率（音符数为 0 时返回 nil——显示"没有音符"，不编 0%）
    var wrongNoteRate: Double? {
        noteCount > 0 ? Double(effectiveWrongCount) / Double(noteCount) : nil
    }

    /// 剔除是否实际生效（有明细且有被标小节）
    var exclusionApplied: Bool {
        hasDetail && !excludedMeasures.isEmpty
    }

    /// P1 真实可展示维度（S13 卡片标题用）
    var measuredDimensionNames: [String] {
        ["时长", "音符数", "错音数", "速度", "踏板事件", "MIDI 事件"]
    }
    /// P2 待补维度（占位声明用，绝不填假数字）
    var pendingDimensionNames: [String] {
        ["六维雷达", "小节热力", "节奏偏差", "弱总分"]
    }
}

enum TakeAnalysisService {

    /// 从 take 与谱错标记计算 P1 分析。只读：不改 take、不改任何模型（测试断言课程状态不变）。
    static func analyze(take: Take, errorMarks: [ScoreErrorMark]) -> P1TakeAnalysis {
        let excluded = Set(errorMarks.map(\.measure))
        let details = take.wrongNoteRecords.compactMap { record -> WrongNoteRecord? in
            // 存储格式 "measure:pitch"
            let parts = record.split(separator: ":")
            guard parts.count == 2, let m = Int(parts[0]), let p = UInt8(parts[1]) else { return nil }
            return WrongNoteRecord(measure: m, actualPitch: p)
        }
        return P1TakeAnalysis(
            durationSec: take.durationSec,
            noteCount: take.noteCount,
            pedalEventCount: take.pedalEventCount,
            midiEventCount: take.midiEventCount,
            tempoAvg: take.tempoAvg,
            wrongNotes: details,
            wrongNoteTotal: take.wrongNoteCount,
            hasDetail: !details.isEmpty,
            excludedMeasures: excluded
        )
    }
}
