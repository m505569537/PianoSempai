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
        // paused = 用户主动暂停（S11 主圆钮「暂停/继续」），与 S11b 断连覆盖层区分：
        // 断连只把 isConnected 置 false、phase 仍是 performing；暂停则真的停下心跳与判分。
        case idle, counting, performing, paused, finished
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
    /// 已完成遍数：区间 wrap 回起点（consumeFollow 内一遍结束）时 +1。
    /// 只服务交互层进度展示（顶栏副行 / 循环格 badge），不参与过关判定。
    /// 弹满 loopConfig.targetLoopCount（>0）时自动 finish()；计数在 start() 归零，每会话独立。
    @Published private(set) var completedLoopCount: Int = 0

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
    /// 暂停记账（S11）：pauseStartedAt 为正在进行的暂停起点，totalPaused 为已累计暂停秒数。
    /// 两者只服务于「活跃时间」= now - startedAt - 暂停；addMark()/playedNotes 仍按墙上时钟 startedAt。
    private var pauseStartedAt: Date?
    private(set) var totalPaused: TimeInterval = 0
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
        // 遍数进度每会话独立：上一会话弹了几遍不带进这一次（finish() 不清零，这里清）
        completedLoopCount = 0
        pauseStartedAt = nil
        totalPaused = 0
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
        case .idle, .finished, .paused:
            // 暂停中节拍器由视图停（Stage B 恢复时再起）；这里只保证关开关时一定静音。
            if !on { metronome.stop() }
        }
    }

    /// 预备拍结束（metronome.onCountInFinished 回调）
    func beginPerforming() {
        phase = .performing
        startTimer()
    }

    /// 1 秒心跳。beginPerforming() 与 resume() 共用同一只 Timer（暂停期间必须停表，恢复时重启）。
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(now: Date())
            }
        }
    }

    /// 用户暂停（S11 主圆钮）。仅 performing 有效；counting 期间的暂停不在本期范围。
    /// 停表并把暂停起点记下来，让 elapsedSec / finish() 时长把这段墙上时间排除掉。
    func pause(now: Date = Date()) {
        guard phase == .performing else { return }
        phase = .paused
        pauseStartedAt = now
        timer?.invalidate()
        timer = nil
    }

    /// 继续（S11 主圆钮）。仅 paused 有效；就地续弹——startedAt/marks/playedNotes/
    /// followState/计数器/elapsedSec 一律不动，只把暂停区间累加进 totalPaused 后重启心跳。
    func resume(now: Date = Date()) {
        guard phase == .paused, let pauseStart = pauseStartedAt else { return }
        phase = .performing
        totalPaused += now.timeIntervalSince(pauseStart)
        pauseStartedAt = nil
        startTimer()
    }

    /// 活跃时间（秒）：墙上时间扣掉暂停。暂停进行中也把这段算进去，公式保持防御性一致。
    private func activeElapsed(now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        var paused = totalPaused
        if let pauseStart = pauseStartedAt {
            paused += now.timeIntervalSince(pauseStart)
        }
        return max(0, now.timeIntervalSince(startedAt) - paused)
    }

    /// 每秒心跳（纯决策，可单测；Timer 只负责喂当前时间）：
    /// - 仅在 performing 且未到点时推进（paused 期间没有 Timer，tick 被 phase 挡掉）；
    /// - 用 startedAt 现算「活跃」整秒写入 elapsedSec（@Published，驱动进度条/计时重绘）；
    /// - 达到时长上限则置 timeUp，由视图收尾。暂停时间不烧倒计时。
    /// 关键：elapsedSec 必须在这里每秒发布，否则视图里现算 Date() 没有重绘触发，计时冻在 0:00。
    func tick(now: Date) {
        guard phase == .performing, !timeUp, startedAt != nil else { return }
        elapsedSec = Int(activeElapsed(now: now))
        if let limit = timeLimitSec, elapsedSec >= limit {
            timeUp = true
        }
    }

    /// 结束（用户点"结束并生成报告"/ 时间到收尾 / 弹满目标遍数自动收尾）。幂等：重复调用返回同一 summary。
    /// 时长同样只算活跃时间——暂停的几分钟不计入 take duration。
    /// 遍数清零不在这里做：归 start() 管，收尾后面板仍能显示「完成/目标」。
    func finish(now: Date = Date()) -> TakeSummary {
        timer?.invalidate()
        timer = nil
        phase = .finished
        let duration = startedAt == nil ? 0 : Int(activeElapsed(now: now))
        let summary = TakeSummary(
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
        return summary
    }

    // MARK: 事件消费（MIDIHub.onEvent）

    func handle(_ event: MIDIEvent) {
        // 断连：判分暂停。用户暂停（.paused）同样不判分——phase == .performing 已把 .paused 排除在外，
        // 暂停期间弹的音一律忽略；resume 后从保留的 followState 继续判分。
        guard phase == .performing, isConnected else { return }
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
            // 遍数进度只在这里自增：引擎的 wrap 判定是唯一真源，交互层不另起一套计数
            completedLoopCount += 1
            // 弹满目标遍数 → 自动收尾（只走 finish()：不触发通关/解锁/streak/铺路/矫正）
            if loopConfig.targetLoopCount > 0, completedLoopCount >= loopConfig.targetLoopCount {
                _ = finish(now: Date())
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

    /// 直接设置速度（点数字输入用；超界自动收进 [40, referenceBpm]，口径同 changeTempo）
    func setTempo(_ bpm: Int) {
        tempoState.bpm = min(max(40, bpm), tempoState.referenceBpm)
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
