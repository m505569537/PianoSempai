import Foundation
import SwiftData

// 练习会话（practice.md 状态机：idle → counting → performing → finished）。
// 编排 ScoreFollowEngine / LoopService / TakeStore / MetronomeService；
// 本体不持有 SwiftData（落库走静态 persist，便于测试）；不依赖 SwiftUI。

struct TakeSummary: Equatable {
    var durationSec: Int = 0
    var noteCount: Int = 0
    var wrongNotes: [WrongNoteRecord] = []
    var tempoAvg: Int = 0
    var pedalEventCount: Int = 0
    var midiEventCount: Int = 0
    var marks: [Int] = [] // 标记点（秒）
    var measureFrom: Int?
    var measureTo: Int?
    var midiFileName: String = ""

    /// S13b：疑似谱错小节从错音数分子中扣除（规则引擎行为）
    func effectiveWrongCount(excludedMeasures: Set<Int>) -> Int {
        wrongNotes.filter { !excludedMeasures.contains($0.measure) }.count
    }
}

@MainActor
final class PracticeSession: ObservableObject {
    enum Phase: Equatable {
        case idle, counting, performing, finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var followState = ScoreFollowState()
    @Published private(set) var tempoState = LoopTempoState(bpm: 72, referenceBpm: 84)
    @Published var loopConfig = LoopConfig() {
        didSet {
            guard loopConfig != oldValue, phase == .idle else { return }
            reconfigureRegion()
        }
    }
    /// 标记点（秒）——"这里有问题"
    @Published private(set) var marks: [Int] = []
    /// 速度变化 toast（S11：居中半透明，2s 消失）
    @Published var toast: String?
    /// 时间到（自动保存）标志：弹完当前小节由视图收尾
    @Published private(set) var timeUp = false
    /// 演奏已进行的整秒数（每秒心跳驱动；进度条/计时读它才会刷新，而非现算 Date()）
    @Published private(set) var elapsedSec = 0
    /// 自由弹奏音符流（S14 卷帘：pitch + 相对秒）
    @Published private(set) var playedNotes: [(pitch: UInt8, sec: Double)] = []

    let isFreePlay: Bool
    private(set) var scoreName = ""
    private(set) var expectedPerMeasure: [[UInt8]] = []
    private(set) var startedAt: Date?
    private(set) var fileURL: URL?
    private(set) var interruptionStarts: [Int] = []
    private(set) var pedalCount = 0
    private(set) var midiEventCount = 0
    /// 断连期间不消费事件（判分暂停；已落盘数据不丢）
    private(set) var isConnected = true
    /// 会话时长上限（今日所选分钟数；nil = 不限时）。到点置 timeUp，由视图收尾自动保存
    var timeLimitSec: Int?
    private var timer: Timer?
    private var passStartWrongCount = 0

    init(isFreePlay: Bool = false) {
        self.isFreePlay = isFreePlay
    }

    // MARK: 配置

    func configure(scoreName: String, expectedPerMeasure: [[UInt8]], startBPM: Int) {
        self.scoreName = scoreName
        self.expectedPerMeasure = expectedPerMeasure
        tempoState = LoopTempoState(bpm: startBPM, referenceBpm: max(startBPM, 84))
        reconfigureRegion()
    }

    private func reconfigureRegion() {
        guard !expectedPerMeasure.isEmpty else { return }
        let clamped = LoopService.clamped(
            start: loopConfig.startMeasure, end: loopConfig.endMeasure,
            totalMeasures: expectedPerMeasure.count
        )
        loopConfig.startMeasure = clamped.start
        loopConfig.endMeasure = clamped.end
        followState = ScoreFollowEngine.initialState(
            expectedPerMeasure: expectedPerMeasure, startMeasureIndex: clamped.start - 1
        )
        passStartWrongCount = 0
    }

    // MARK: 生命周期

    /// metronomeOn：节拍器开关。预备拍也归它管——OFF 时直接进演奏，不打拍也不响；
    /// 否则预备拍打满一小节，结束经 metronome.onCountInFinished 回调 beginPerforming()。
    func start(metronome: MetronomeService, countIn: Bool, metronomeOn: Bool) {
        guard phase == .idle || phase == .finished else { return }
        startedAt = Date()
        marks = []
        playedNotes = []
        pedalCount = 0
        midiEventCount = 0
        timeUp = false
        elapsedSec = 0
        interruptionStarts = []
        fileURL = try? TakeStore.makeFileURL()
        passStartWrongCount = 0
        if isFreePlay {
            beginPerforming()
        } else if countIn && loopConfig.countIn && metronomeOn {
            phase = .counting
            metronome.start(bpm: tempoState.bpm, countInBars: 1)
        } else {
            beginPerforming()
        }
    }

    /// 节拍器开关切换（视图调用）。语义：开关管住全部节拍器声音，含预备拍。
    /// 关键不变量：绝不能把 phase 留在 .counting——那会让 onCountInFinished 永不触发，
    /// 会话无声且不判分，只能靠「结束并保存」退出（历史上真机无声的次要根因之一）。
    func toggleMetronome(on: Bool, metronome: MetronomeService) {
        switch phase {
        case .counting:
            if on {
                metronome.onCountInFinished = { [weak self] in self?.beginPerforming() }
                metronome.start(bpm: tempoState.bpm, countInBars: 1)
            } else {
                metronome.stop()
                beginPerforming() // 结束计数，直接进演奏，不卡死
            }
        case .performing:
            if on {
                metronome.start(bpm: tempoState.bpm, countInBars: 0)
            } else {
                metronome.stop()
            }
        case .idle, .finished:
            if !on { metronome.stop() }
        }
    }

    /// 预备拍结束（metronome.onCountInFinished 回调）
    func beginPerforming() {
        phase = .performing
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(now: Date())
            }
        }
    }

    /// 每秒心跳（纯决策，可单测；Timer 只负责喂当前时间）：
    /// - 仅在 performing 且未到点时推进；
    /// - 用 startedAt 现算整秒写入 elapsedSec（@Published，驱动进度条/计时重绘）；
    /// - 达到时长上限则置 timeUp，由视图收尾。
    /// 关键：elapsedSec 必须在这里每秒发布，否则视图里现算 Date() 没有重绘触发，计时冻在 0:00。
    func tick(now: Date) {
        guard phase == .performing, !timeUp, let startedAt else { return }
        elapsedSec = Int(now.timeIntervalSince(startedAt))
        if let limit = timeLimitSec, elapsedSec >= limit {
            timeUp = true
        }
    }

    /// 结束（用户点"结束并生成报告"/ 时间到收尾）。幂等：重复调用返回同一 summary。
    func finish() -> TakeSummary {
        timer?.invalidate()
        timer = nil
        phase = .finished
        let duration = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        return TakeSummary(
            durationSec: duration,
            noteCount: followState.playedCount,
            wrongNotes: followState.wrongNotes,
            tempoAvg: tempoState.bpm,
            pedalEventCount: pedalCount,
            midiEventCount: midiEventCount,
            marks: marks,
            measureFrom: isFreePlay ? nil : loopConfig.startMeasure,
            measureTo: isFreePlay ? nil : loopConfig.endMeasure,
            midiFileName: fileURL?.lastPathComponent ?? ""
        )
    }

    // MARK: 事件消费（MIDIHub.onEvent）

    func handle(_ event: MIDIEvent) {
        guard phase == .performing, isConnected else { return } // 断连：判分暂停
        midiEventCount += 1
        if let url = fileURL {
            let record = RawMIDIEventRecord(
                t: event.timeNanos, k: Self.kindString(event.kind), c: event.channel,
                n: event.note ?? 64, v: Self.value(of: event), suspicious: event.isSuspicious
            )
            try? TakeStore.append(record, to: url)
        }

        switch event.kind {
        case let .noteOn(pitch, velocity):
            guard velocity > 0 else { return } // velocity=0 是 noteOff（双保险已在上游处理）
            let sec = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            if playedNotes.count < 2000 {
                playedNotes.append((pitch, sec))
            }
            if !isFreePlay {
                consumeFollow(pitch: pitch)
            }
        case .sustainPedal:
            pedalCount += 1
        case .noteOff:
            break
        }
    }

    private func consumeFollow(pitch: UInt8) {
        let endIndex = loopConfig.endMeasure - 1
        let beforeMeasure = followState.measureIndex
        followState = ScoreFollowEngine.consume(
            followState, pitch: pitch,
            expectedPerMeasure: expectedPerMeasure,
            endMeasureIndex: endIndex,
            loopEnabled: true
        )
        // 一遍循环完成：光标从终点 wrap 回起点
        if beforeMeasure == endIndex, followState.measureIndex == 0 {
            let passWrong = followState.wrongNotes.count - passStartWrongCount
            passStartWrongCount = followState.wrongNotes.count
            tempoState = LoopService.afterPass(tempoState, mode: loopConfig.mode, wrongNotesThisPass: passWrong)
            if let change = tempoState.lastChange {
                toast = LoopService.toastText(for: change)
            }
        }
    }

    private static func kindString(_ kind: MIDIEvent.Kind) -> String {
        switch kind {
        case .noteOn: "on"
        case .noteOff: "off"
        case .sustainPedal: "cc64"
        }
    }

    private static func value(of event: MIDIEvent) -> UInt8 {
        switch event.kind {
        case let .noteOn(_, v), let .noteOff(_, v), let .sustainPedal(v): v
        }
    }

    // MARK: 连接态（S11b：断连不算失败、不清零）

    func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        if !connected, phase == .performing, let startedAt {
            interruptionStarts.append(Int(Date().timeIntervalSince(startedAt)))
        }
    }

    // MARK: 控件

    func addMark() {
        guard let startedAt else { return }
        marks.append(Int(Date().timeIntervalSince(startedAt)))
    }

    func changeTempo(by delta: Int) {
        tempoState.bpm = min(max(40, tempoState.bpm + delta), tempoState.referenceBpm)
    }

    // MARK: 落库（Take 元数据；原始 MIDI 已在 handle 中只追加落盘）

    @discardableResult
    static func persist(
        _ summary: TakeSummary,
        taskType: String,
        isFreePlay: Bool,
        startedAt: Date,
        interruptions: [Int],
        title: String,
        pieceId: UUID? = nil,
        scoreFileId: UUID? = nil,
        in context: ModelContext
    ) -> Take {
        let take = Take(
            startedAt: startedAt,
            endedAt: Date(),
            durationSec: summary.durationSec,
            taskType: taskType,
            hasMidi: summary.midiEventCount > 0,
            isFreePlay: isFreePlay,
            midiFileURL: summary.midiFileName,
            measureFrom: summary.measureFrom,
            measureTo: summary.measureTo,
            tempoAvg: summary.tempoAvg,
            noteCount: summary.noteCount,
            wrongNoteCount: summary.effectiveWrongCount(excludedMeasures: []),
            pedalEventCount: summary.pedalEventCount,
            midiEventCount: summary.midiEventCount,
            interruptionRanges: interruptions,
            wrongNoteRecords: summary.wrongNotes.map { "\($0.measure):\($0.actualPitch)" },
            pieceId: pieceId,
            scoreFileId: scoreFileId,
            title: title
        )
        context.insert(take)
        return take
    }
}
