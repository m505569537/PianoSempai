import Foundation
import SwiftData

// G6 听音辨音程核心层（ADR-0008，Stage A）：音程定义、随拜厄解锁、出题、判定、
// 轮次留痕与趋势。纯 Swift 逻辑 + SwiftData 存储，零音频依赖（AVAudio 只在 Stage B）、
// 零 UI（入口也在 Stage B）。不写 Take/TakeAnalysis、不碰 Piece.status（只由
// CourseEngine 写）、不触发过关/课程推进/streak/铺路（红线，同既有各 G）。

// MARK: - 音程定义

/// 一个八度内的上行旋律音程，按半音数标识（1...12）。
/// 理论上半音数 6 有「增四度/减五度」两个名称，但二者同响，选择题只能有一个正确答案，
/// 故听辨统一用单一标签「三全音」（ADR-0008 §7）。因此可选项为 12 个唯一标签
/// （「13 种」指含等音异名的理论名称，题面不拆成两个）。
enum IntervalID: Int, CaseIterable, Identifiable, Codable {
    case minorSecond = 1   // 小二度
    case majorSecond = 2   // 大二度
    case minorThird = 3    // 小三度
    case majorThird = 4    // 大三度
    case perfectFourth = 5 // 纯四度
    case tritone = 6       // 三全音（增四/减五，单标签）
    case perfectFifth = 7  // 纯五度
    case minorSixth = 8    // 小六度
    case majorSixth = 9    // 大六度
    case minorSeventh = 10 // 小七度
    case majorSeventh = 11 // 大七度
    case perfectOctave = 12 // 纯八度

    var id: Int { rawValue }

    /// 中文显示名（按上表逐字返回；半音数 ↔ 名称一一对应，标签互异）
    var displayName: String {
        switch self {
        case .minorSecond: return "小二度"
        case .majorSecond: return "大二度"
        case .minorThird: return "小三度"
        case .majorThird: return "大三度"
        case .perfectFourth: return "纯四度"
        case .tritone: return "三全音"
        case .perfectFifth: return "纯五度"
        case .minorSixth: return "小六度"
        case .majorSixth: return "大六度"
        case .minorSeventh: return "小七度"
        case .majorSeventh: return "大七度"
        case .perfectOctave: return "纯八度"
        }
    }
}

// MARK: - 随拜厄进度解锁（纯函数）

enum IntervalUnlock {

    /// 按拜厄当前条目号（CoursePathState.currentBeyer，Int；无进度时 0）返回已解锁半音数集合。
    /// 入门（≤30）：最协和最常见 {2,3,4,7,12}
    /// 进阶（31...60）：+{1,5,9,10}
    /// 后期（>60）：+{6,8,11}（全开 1...12）
    /// 边界严格按 ≤30 / 31...60 / >60（30 归入门、31 进阶、60 进阶、61 全开）。
    static func allowedSemitones(currentBeyer: Int) -> Set<Int> {
        if currentBeyer <= 30 {
            return [2, 3, 4, 7, 12]
        } else if currentBeyer <= 60 {
            return [1, 2, 3, 4, 5, 7, 9, 10, 12]
        } else {
            return Set(1...12)
        }
    }
}

// MARK: - 出题（确定性，随机源可注入）

/// 一道听音辨音程题：根音 + 正确音程 + 已打乱的 4 选项（UI 直接按序渲染）。
struct IntervalQuestion: Equatable {
    /// 根音 MIDI 音高
    let rootMIDINote: Int
    /// 正确音程半音数（1...12）；冠音 = rootMIDINote + answerSemitones
    let answerSemitones: Int
    /// 4 个选项（半音数），恰含 1 个正确 + 3 个干扰；顺序已打乱
    let options: [Int]

    var topMIDINote: Int { rootMIDINote + answerSemitones }
}

enum IntervalQuiz {

    /// 根音窗口：MIDI 55...67（G3 ~ G4），保证冠音 root+12 ≤ 79，集中在中央 C 附近一个八度。
    static let rootRange = 55...67

    /// 从已解锁集合出题。随机源可注入（测试固定种子 → 结果序列确定）。
    /// 前置条件：allowed.count >= 4（解锁最早档即 5 个，恒满足）；违反属编程错误，precondition。
    static func makeQuestion<G: RandomNumberGenerator>(allowed: Set<Int>, using generator: inout G) -> IntervalQuestion {
        precondition(allowed.count >= 4, "解锁集至少 4 个音程才能出 4 选项题（最早入门档有 5 个，应由调用方保证）")
        // 半音数互异即 displayName 互异，无需按名去重
        let pool = allowed.sorted()
        let answer = pool.randomElement(using: &generator)!
        let distractors = Array(pool.filter { $0 != answer }.shuffled(using: &generator).prefix(3))
        var options = distractors + [answer]
        options.shuffle(using: &generator)
        let root = Int.random(in: rootRange, using: &generator)
        return IntervalQuestion(rootMIDINote: root, answerSemitones: answer, options: options)
    }
}

// MARK: - 判定

enum IntervalJudging {

    /// 选中半音数 == 正确半音数（半音数唯一映射标签，无需再比名称）
    static func isCorrect(selected: Int, question: IntervalQuestion) -> Bool {
        selected == question.answerSemitones
    }
}

// MARK: - 轮次留痕与趋势（对齐 SightReadDrillStore / SightReadTrend 范式）

@MainActor
enum EarTrainingStore {

    /// 写入一轮（10 题）留痕（不写 Take/TakeAnalysis，不触发过关）。
    /// hitRate = total > 0 ? Double(correct)/Double(total) : nil（total==0 不编数）。
    @discardableResult
    static func save(kind: String = "interval", correct: Int, total: Int,
                     in context: ModelContext, createdAt: Date = Date()) -> EarTrainingRound {
        let round = EarTrainingRound(
            kind: kind, correctCount: correct, totalCount: total,
            hitRate: total > 0 ? Double(correct) / Double(total) : nil,
            createdAt: createdAt)
        context.insert(round)
        return round
    }
}

/// 听音练耳趋势聚合（纯函数；数据不足时诚实留 nil，由未来 UI 留白）
struct EarTrainingTrendSummary {
    /// 最近轮次命中率（时间升序，左旧右新）
    let hitRates: [Double]
    /// 均值；有效样本 < 3 时 nil（对齐 G4，不编趋势）
    let mean: Double?
    /// 参与统计的轮次总数（窗口内，含 hitRate 为 nil 的轮次）
    let totalCount: Int
}

enum EarTrainingTrend {

    /// 只统计 kind == kind 参数（默认 "interval"）的轮次；最近 limit（默认 20）轮，
    /// 先按时间降序截取再反转为升序（走势图左旧右新）。
    static func summarize(rounds: [EarTrainingRound], kind: String = "interval",
                          limit: Int = 20) -> EarTrainingTrendSummary {
        let recent = Array(rounds.filter { $0.kind == kind }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit))
        let hitRates = Array(recent.compactMap(\.hitRate).reversed())
        return EarTrainingTrendSummary(hitRates: hitRates, mean: mean(hitRates), totalCount: recent.count)
    }

    /// 有效样本 < 3 → nil（不编趋势）
    private static func mean(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
