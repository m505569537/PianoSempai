import Foundation
import SheetMusicCore
import SheetMusicLoader
import SwiftData

// 视奏采集（S04 第 2 小步，简化评估态）：按 brief「仅采原始数据」，
// 期望音符取自内置样例谱的小节区间；命中率用音序简单匹配（P1 简化，非对齐算法，M5/P2 升级）。
// 所有数字均来自真实 MIDI 事件，无随机/伪造（红线 2）。

struct SightReadSegment {
    let title: String
    let measureRange: ClosedRange<Int> // 1-based 小节号（展示用）
    let expectedPitches: [UInt8] // 谱面期望音（两声部都计入，按出现顺序）
}

struct SightReadSegmentResult {
    let expected: Int
    let matched: Int
    let pauses: Int
    /// start→stop 真实用时（秒，四舍五入；G4 ADR-0004 判定口径）
    let elapsedSeconds: Int
    /// 音序简单匹配命中率 0-1；expected == 0 时返回 nil（不编数字）
    var hitRate: Double? {
        expected > 0 ? Double(matched) / Double(expected) : nil
    }
}

/// 一次视奏采集会话：挂到 MIDIHub.onEvent 上收集 played 音，结束时分段结算。
@MainActor
final class SightReadSession: ObservableObject {
    @Published private(set) var collectedPitches: [UInt8] = []
    @Published private(set) var isCollecting = false
    /// 最近一个音的音名（实时反馈用，诚实显示实际收到的音）
    @Published private(set) var lastNoteName: String?

    private var startNanos: UInt64 = 0
    private var lastNoteNanos: UInt64 = 0
    private var notes: [(pitch: UInt8, nanos: UInt64)] = []

    func start() {
        notes = []
        collectedPitches = []
        isCollecting = true
        startNanos = DispatchTime.now().uptimeNanoseconds
        lastNoteNanos = 0
    }

    func handle(_ event: MIDIEvent) {
        guard isCollecting, case let .noteOn(note, velocity) = event.kind, velocity > 0 else { return }
        let nanos = event.timeNanos
        notes.append((note, nanos))
        collectedPitches.append(note)
        lastNoteName = Self.noteName(note)
        lastNoteNanos = nanos
    }

    func stop(expectedPitches: [UInt8]) -> SightReadSegmentResult {
        isCollecting = false
        // 音序贪心匹配：期望序列逐个在 played 里找第一次出现（从上个匹配点之后）
        var pointer = 0
        var matched = 0
        for expected in expectedPitches {
            if let idx = collectedPitches[pointer...].firstIndex(of: expected) {
                matched += 1
                pointer = idx + 1
            }
        }
        // 停顿：相邻两音间隔 > 2s
        var pauses = 0
        if notes.count > 1 {
            for i in 1..<notes.count where notes[i].nanos - notes[i - 1].nanos > 2_000_000_000 {
                pauses += 1
            }
        }
        // 用时：start→stop 真实纳秒换算秒（四舍五入），补齐 G4 判定口径
        let elapsedSeconds = Int((Double(DispatchTime.now().uptimeNanoseconds &- startNanos) / 1_000_000_000).rounded())
        return SightReadSegmentResult(expected: expectedPitches.count, matched: matched, pauses: pauses, elapsedSeconds: elapsedSeconds)
    }

    /// MIDI 音高 → 音名（如 C4），实时反馈用。纯函数：非隔离，供 S13 呈现层复用
    nonisolated static func noteName(_ midi: UInt8) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[Int(midi) % 12] + "\(Int(midi) / 12 - 1)"
    }

    // MARK: - 期望音加载（G4 ADR-0004：泛化，不再绑死 SpikeSample32）

    /// 纯函数：score.parts.first 的**全部 staves**（两声部都计入，区别于 ScoreExpectedPitches.extract 的单 staff），
    /// 按 measures（1-based）过滤小节，收集 chord.notes.pitch。
    nonisolated static func expectedPitches(score: Score, measures: ClosedRange<Int>) -> [UInt8] {
        var pitches: [UInt8] = []
        for staff in score.parts.first?.staves ?? [] {
            for (idx, measure) in staff.measures.enumerated() where measures.contains(idx + 1) {
                for voice in measure.voices {
                    for element in voice.elements {
                        if case let .chord(chord) = element {
                            pitches.append(contentsOf: chord.notes.map { UInt8($0.pitch) })
                        }
                    }
                }
            }
        }
        return pitches
    }

    /// URL 版：谱解析失败返回空数组（诚实，不报错不伪造）
    nonisolated static func expectedPitches(url: URL, measures: ClosedRange<Int>) -> [UInt8] {
        guard let score = try? ScoreLoader.loadScore(contentsOf: url) else { return [] }
        return expectedPitches(score: score, measures: measures)
    }

    /// 教材轨便捷入口：BundledScore 同路径定位内置谱（拜厄/哈农）；谱缺失返回 []
    nonisolated static func loadExpectedPitches(book: String, number: Int, measures: ClosedRange<Int>) -> [UInt8] {
        guard let url = BundledScore.url(book: book, number: number) else { return [] }
        return expectedPitches(url: url, measures: measures)
    }

    /// S04 定级沿用：从内置样例谱取小节区间的期望音序列（真实解析，非硬编码音符）
    nonisolated static func loadExpectedPitches(measures: ClosedRange<Int>) -> [UInt8] {
        guard let url = Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml") else { return [] }
        return expectedPitches(url: url, measures: measures)
    }
}

// MARK: - 纯选片逻辑（G4 ADR-0004；不碰 Bundle 与 DB，随机源可注入）

/// 一次视奏训练的选片结果
struct SightReadDrillPick: Equatable {
    let book: String
    let pieceNumber: Int
    /// 片段起点小节（1-based）
    let measureStart: Int
    let measureCount: Int
    /// 复习性视奏（候选带耗尽后复用历史条目）true
    let isReview: Bool
}

enum SightReadPicker {

    /// 选一条今日视奏片段。
    /// - 游标：每轨 practicing/notStarted 的最小 number；一条都没有 → 通关值（拜厄 107 / 哈农 21，
    ///   与 CourseEngine.derivedCursor 同口径，只读其公开常量不改可见性）。
    /// - 候选带：拜厄 [cb+1 ... min(cb+6,106)]，哈农 [ch+1 ... min(ch+6,20)]，两轨合并。
    /// - totalMeasures<=0 的条目不可用，跳过；measureCount=min(4,total)，measureStart=1。
    /// - 去重：history 存在同 (book,pieceNumber,measureStart) 即已视奏；
    ///   有未视奏候选 → rand 随机选 1（isReview=false）；全视奏过 → 最久未视奏者优先复用（isReview=true）。
    /// - 两轨候选带皆空 → 全 history 最久未视奏条目复用（isReview=true）；history 也空 → nil。
    /// - rand：传入候选下标区间 `0..<count`，返回所选下标；默认系统随机。
    static func pick(pieces: [Piece],
                     history: [SightReadDrillRecord],
                     rand: (Range<Int>) -> Int = { Int.random(in: $0) }) -> SightReadDrillPick? {
        let beyerCursor = cursor(book: "拜厄", pieces: pieces, completedValue: 107)
        let hanonCursor = cursor(book: "哈农", pieces: pieces, completedValue: 21)

        var candidates: [SightReadDrillPick] = []
        candidates.append(contentsOf: band(book: "拜厄", cursor: beyerCursor, upperBound: 106, pieces: pieces))
        candidates.append(contentsOf: band(book: "哈农", cursor: hanonCursor, upperBound: 20, pieces: pieces))

        guard !candidates.isEmpty else {
            // 两轨候选带皆空（游标到底）：从全部 history 取最久未视奏条目复用
            guard let oldest = history.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return SightReadDrillPick(book: oldest.book, pieceNumber: oldest.pieceNumber,
                                      measureStart: oldest.measureStart, measureCount: oldest.measureCount,
                                      isReview: true)
        }

        func playedIndex(_ pick: SightReadDrillPick) -> Date? {
            history
                .filter { $0.book == pick.book && $0.pieceNumber == pick.pieceNumber && $0.measureStart == pick.measureStart }
                .map(\.createdAt)
                .max()
        }

        let unplayed = candidates.filter { playedIndex($0) == nil }
        if !unplayed.isEmpty {
            let idx = rand(0..<unplayed.count)
            let chosen = unplayed[idx]
            return SightReadDrillPick(book: chosen.book, pieceNumber: chosen.pieceNumber,
                                      measureStart: chosen.measureStart, measureCount: chosen.measureCount,
                                      isReview: false)
        }
        // 候选全部视奏过：取最久未视奏（最近一次视奏 createdAt 最早）者，isReview=true
        guard let oldest = candidates.min(by: { (playedIndex($0) ?? .distantPast) < (playedIndex($1) ?? .distantPast) }) else { return nil }
        return SightReadDrillPick(book: oldest.book, pieceNumber: oldest.pieceNumber,
                                  measureStart: oldest.measureStart, measureCount: oldest.measureCount,
                                  isReview: true)
    }

    /// 同 derivedCursor 口径：该轨 practicing/notStarted 的最小 number；一条都没有 → 通关值
    private static func cursor(book: String, pieces: [Piece], completedValue: Int) -> Int {
        let active = pieces
            .filter { $0.book == book && ($0.status == CourseEngine.statusPracticing || $0.status == CourseEngine.statusNotStarted) }
            .map(\.number)
        return active.min() ?? completedValue
    }

    /// 候选带 [cursor+1 ... min(cursor+6, upperBound)] → 可用片段（totalMeasures>=1）
    private static func band(book: String, cursor: Int, upperBound: Int, pieces: [Piece]) -> [SightReadDrillPick] {
        let upper = min(cursor + 6, upperBound)
        guard cursor + 1 <= upper else { return [] } // 游标到底（如 106）→ 候选带为空，勿构造反区间
        return ((cursor + 1)...upper).compactMap { number in
            guard let piece = pieces.first(where: { $0.book == book && $0.number == number }),
                  piece.totalMeasures >= 1 else { return nil }
            return SightReadDrillPick(book: book, pieceNumber: number,
                                      measureStart: 1, measureCount: min(4, piece.totalMeasures),
                                      isReview: false)
        }
    }
}

// MARK: - 记录写入与趋势聚合（G4 ADR-0004；不碰过关链路）

enum SightReadDrillStore {

    /// 写入一次视奏留痕（不写 Take/TakeAnalysis，不触发过关）。hitRate 由 expected>0 决定否则 nil。
    @discardableResult
    static func save(book: String, pieceNumber: Int, measureStart: Int, measureCount: Int,
                     expected: Int, matched: Int, pauses: Int, elapsedSeconds: Int, isReview: Bool,
                     in context: ModelContext) -> SightReadDrillRecord {
        let record = SightReadDrillRecord(
            book: book, pieceNumber: pieceNumber, measureStart: measureStart, measureCount: measureCount,
            expected: expected, matched: matched, pauses: pauses,
            hitRate: expected > 0 ? Double(matched) / Double(expected) : nil,
            elapsedSeconds: elapsedSeconds, isReview: isReview
        )
        context.insert(record)
        return record
    }

    /// 便捷入口：选片结果 + 会话结算 → 留痕
    @discardableResult
    static func save(pick: SightReadDrillPick, result: SightReadSegmentResult, in context: ModelContext) -> SightReadDrillRecord {
        save(book: pick.book, pieceNumber: pick.pieceNumber, measureStart: pick.measureStart, measureCount: pick.measureCount,
             expected: result.expected, matched: result.matched, pauses: result.pauses,
             elapsedSeconds: result.elapsedSeconds, isReview: pick.isReview, in: context)
    }
}

/// 视奏趋势聚合（纯函数；数据不足时诚实留 nil，由未来 UI 留白）
struct SightReadTrendSummary {
    /// 首见（isReview=false）命中率序列（时序升序；expected==0 的记录不产生命中率，不进序列）
    let firstHitRates: [Double]
    /// 首见命中率均值；有效样本 < 3 时 nil
    let firstMean: Double?
    /// 复习命中率均值；有效样本 < 3 时 nil
    let reviewMean: Double?
    /// 参与统计的总次数（含 expected==0 与复习）
    let totalCount: Int
}

enum SightReadTrend {

    /// 最近 limit 条（默认 20）的命中率走势与均值
    static func summarize(records: [SightReadDrillRecord], limit: Int = 20) -> SightReadTrendSummary {
        // 先降序截取"最近" limit 条，再反转为时间升序（走势图左旧右新）
        let recent = Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        let firstRates = Array(recent.filter { !$0.isReview }.compactMap(\.hitRate).reversed())
        let reviewRates = Array(recent.filter { $0.isReview }.compactMap(\.hitRate).reversed())
        return SightReadTrendSummary(firstHitRates: firstRates,
                                     firstMean: mean(firstRates),
                                     reviewMean: mean(reviewRates),
                                     totalCount: recent.count)
    }

    /// 有效样本 < 3 → nil（不编趋势）
    private static func mean(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
