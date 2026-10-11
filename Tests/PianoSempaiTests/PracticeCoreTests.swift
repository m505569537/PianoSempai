import SheetMusicCore
import SheetMusicLoader
import SwiftData
import XCTest
@testable import PianoSempai

/// M6a 验收（Hermes）：跟弹匹配/光标推进、循环边界校验、TakeStore 往返、断连记 interruption、MIDI 空洞不崩。
final class PracticeCoreTests: XCTestCase {

    // MARK: ScoreFollowEngine — 匹配与光标推进

    private let region: [[UInt8]] = [
        [60, 64], // 小节 0
        [67, 72], // 小节 1
        [65],     // 小节 2
    ]

    private func consume(_ state: ScoreFollowState, _ pitches: [UInt8], end: Int = 2, loop: Bool = true) -> ScoreFollowState {
        var s = state
        for p in pitches {
            s = ScoreFollowEngine.consume(s, pitch: p, expectedPerMeasure: region, endMeasureIndex: end, loopEnabled: loop)
        }
        return s
    }

    func testMatchingConsumesExpectedAndAdvancesCursor() {
        let s0 = ScoreFollowEngine.initialState(expectedPerMeasure: region)
        let s1 = consume(s0, [60, 64])
        XCTAssertEqual(s1.measureIndex, 1, "小节 0 期望耗尽 → 推进到小节 1")
        XCTAssertEqual(s1.matchedCount, 2)
        XCTAssertTrue(s1.wrongNotes.isEmpty)

        let s2 = consume(s1, [67])
        XCTAssertEqual(s2.measureIndex, 1)
        XCTAssertEqual(s2.matchedCount, 3)
    }

    func testWrongNoteCountedWithoutLosingCursor() {
        let s0 = ScoreFollowEngine.initialState(expectedPerMeasure: region)
        // 弹错音（当前小节没有 72）→ 记错音，光标不动（PRD：错音不丢光标）
        let s1 = consume(s0, [72])
        XCTAssertEqual(s1.wrongNotes.count, 1)
        XCTAssertEqual(s1.wrongNotes.first?.measure, 1, "错音记录展示小节号（1-based）")
        XCTAssertEqual(s1.wrongNotes.first?.actualPitch, 72)
        XCTAssertEqual(s1.measureIndex, 0, "光标不因错音打断")
        XCTAssertEqual(s1.matchedCount, 0)
    }

    func testLoopWrapResetsRemainingAndPassCompletes() {
        let s0 = ScoreFollowEngine.initialState(expectedPerMeasure: region)
        // 走完全部三小节（65 是终点小节最后一音 → 立即 wrap）
        var s = consume(s0, [60, 64, 67, 72, 65])
        XCTAssertEqual(s.matchedCount, 5)
        XCTAssertEqual(s.measureIndex, 0, "终点耗尽即 wrap 回小节 0")
        XCTAssertEqual(s.remaining[0]?.count, 2, "wrap 后 region 期望整体重置")
        // 回到起点后继续消耗
        s = ScoreFollowEngine.consume(s, pitch: 60, expectedPerMeasure: region, endMeasureIndex: 2, loopEnabled: true)
        XCTAssertEqual(s.measureIndex, 0)
        XCTAssertEqual(s.remaining[0]?.count, 1, "wrap 后小节 0 剩余期望（60 已消耗）")
    }

    func testDuplicateNoteBeyondExpectationCountsWrong() {
        let s0 = ScoreFollowEngine.initialState(expectedPerMeasure: region)
        // 小节 0 只有 [60, 64]：60 弹两次，第二次计错音（多弹）
        let s1 = consume(s0, [60, 60])
        XCTAssertEqual(s1.matchedCount, 1)
        XCTAssertEqual(s1.wrongNotes.count, 1)
    }

    // MARK: LoopService — 边界校验（非法区间拒绝/钳制）与速度自适应

    func testLoopRangeValidation() {
        // 合法
        XCTAssertTrue(LoopService.isValid(start: 17, end: 24, totalMeasures: 32))
        // 非法：起点 < 1 / 起 ≥ 止 / 止 > 总数
        XCTAssertFalse(LoopService.isValid(start: 0, end: 24, totalMeasures: 32))
        XCTAssertFalse(LoopService.isValid(start: 24, end: 24, totalMeasures: 32))
        XCTAssertFalse(LoopService.isValid(start: 17, end: 33, totalMeasures: 32))
        // 钳制：越界输入 → 合法区间
        let clamped = LoopService.clamped(start: 0, end: 99, totalMeasures: 32)
        XCTAssertEqual(clamped.start, 1)
        XCTAssertEqual(clamped.end, 32)
        XCTAssertEqual(LoopService.clamped(start: 24, end: 24, totalMeasures: 32).end, 25, "起=止 时止至少 +1")
    }

    func testAdaptiveUpAfterTwoCleanPasses() {
        var state = LoopTempoState(bpm: 72, referenceBpm: 84)
        state = LoopService.afterPass(state, mode: .adaptiveUp, wrongNotesThisPass: 0)
        XCTAssertEqual(state.bpm, 72, "第一遍干净只累计，不提速")
        state = LoopService.afterPass(state, mode: .adaptiveUp, wrongNotesThisPass: 0)
        XCTAssertEqual(state.bpm, 77, "连续两遍干净 +5")
        XCTAssertEqual(state.lastChange, TempoChange(direction: .up, newBpm: 77))
        XCTAssertEqual(LoopService.toastText(for: state.lastChange!), "很稳，速度提到 ♩=77")
        // 有错音 → 连胜清零，不提速
        state = LoopService.afterPass(state, mode: .adaptiveUp, wrongNotesThisPass: 3)
        XCTAssertEqual(state.bpm, 77)
        XCTAssertEqual(state.consecutiveCleanPasses, 0)
    }

    func testAdaptiveDownAndRestSuggestion() {
        var state = LoopTempoState(bpm: 72, referenceBpm: 84)
        state = LoopService.afterPass(state, mode: .adaptiveDown, wrongNotesThisPass: 2)
        XCTAssertEqual(state.bpm, 67, "崩一遍 −5")
        XCTAssertEqual(LoopService.toastText(for: state.lastChange!), "慢一点，回到 ♩=67")
        state = LoopService.afterPass(state, mode: .adaptiveDown, wrongNotesThisPass: 4)
        XCTAssertEqual(state.bpm, 62)
        XCTAssertTrue(state.shouldSuggestRest, "连崩 2 遍提示休息")
        XCTAssertEqual(state.consecutiveBadPasses, 0, "提示后重置")
    }

    // MARK: LoopService — 错误热点区间与查询（G2）

    func testHotspotRangeEmptyReturnsNil() {
        XCTAssertNil(LoopService.hotspotRange(hotspotMeasures: [], totalMeasures: 32))
    }

    func testHotspotRangeSingleMeasureExtendsEnd() {
        // 0-based [2] → 1-based 起 3；单热点终点 +1 保 start<end → (3, 4)
        let range = LoopService.hotspotRange(hotspotMeasures: [2], totalMeasures: 32)
        XCTAssertEqual(range?.start, 3)
        XCTAssertEqual(range?.end, 4)
    }

    func testHotspotRangeMultipleMeasuresSpan() {
        // [2, 5] → 连续跨度 (3, 6)；乱序输入同样按 min...max
        let range = LoopService.hotspotRange(hotspotMeasures: [2, 5], totalMeasures: 32)
        XCTAssertEqual(range?.start, 3)
        XCTAssertEqual(range?.end, 6)
        let unsorted = LoopService.hotspotRange(hotspotMeasures: [5, 2], totalMeasures: 32)
        XCTAssertEqual(unsorted?.start, 3)
        XCTAssertEqual(unsorted?.end, 6)
    }

    func testHotspotRangeSingleMeasureAtEndClamps() {
        // 末小节单热点 [31]：起 32、止 33 → 钳制回 (31, 32)
        let range = LoopService.hotspotRange(hotspotMeasures: [31], totalMeasures: 32)
        XCTAssertEqual(range?.start, 31)
        XCTAssertEqual(range?.end, 32)
    }

    func testHotspotRangeBeyondTotalClampsToLegalOrNil() {
        // 越界热点 [35]（total 32）：起 36、止 37 → 钳制后仍是合法区间
        let range = LoopService.hotspotRange(hotspotMeasures: [35], totalMeasures: 32)
        XCTAssertEqual(range?.start, 31)
        XCTAssertEqual(range?.end, 32)
        XCTAssertTrue(LoopService.isValid(start: range!.start, end: range!.end, totalMeasures: 32))
    }

    func testHotspotRangeTotalTooSmallReturnsNil() {
        // total=1 时 clamped 会产出 (0, 1)——start<1 不合法，必须 nil
        XCTAssertNil(LoopService.hotspotRange(hotspotMeasures: [0], totalMeasures: 1))
    }

    func testLatestHotspotMeasuresEmptyAndNilPiece() {
        let take = Take(entityId: UUID(), pieceId: UUID())
        let analysis = TakeAnalysis(takeId: take.entityId, hotspotMeasures: [0, 3])
        XCTAssertEqual(LoopService.latestHotspotMeasures(pieceId: nil, takes: [take], analyses: [analysis]), [])
        XCTAssertEqual(LoopService.latestHotspotMeasures(pieceId: UUID(), takes: [take], analyses: [analysis]), [])
    }

    func testLatestHotspotMeasuresFiltersByPiece() {
        let myPiece = UUID()
        let otherPiece = UUID()
        let myTake = Take(entityId: UUID(), pieceId: myPiece)
        let otherTake = Take(entityId: UUID(), pieceId: otherPiece)
        let mine = TakeAnalysis(takeId: myTake.entityId, hotspotMeasures: [2])
        let other = TakeAnalysis(takeId: otherTake.entityId, hotspotMeasures: [9])
        XCTAssertEqual(
            LoopService.latestHotspotMeasures(pieceId: myPiece, takes: [myTake, otherTake], analyses: [mine, other]),
            [2]
        )
    }

    func testLatestHotspotMeasuresPrefersNewerNonEmptyHotspots() {
        let piece = UUID()
        let take = Take(entityId: UUID(), pieceId: piece)
        // 较旧的分析有热点；较新的分析热点为空——取「有热点的分析里最新」，不被空热点抹掉
        let older = TakeAnalysis(takeId: take.entityId, analyzedAt: Date(timeIntervalSince1970: 100), hotspotMeasures: [1, 4])
        let newer = TakeAnalysis(takeId: take.entityId, analyzedAt: Date(timeIntervalSince1970: 200), hotspotMeasures: [])
        XCTAssertEqual(
            LoopService.latestHotspotMeasures(pieceId: piece, takes: [take], analyses: [older, newer]),
            [1, 4]
        )
        // 两条都有热点时取 analyzedAt 最新
        let newest = TakeAnalysis(takeId: take.entityId, analyzedAt: Date(timeIntervalSince1970: 300), hotspotMeasures: [7])
        XCTAssertEqual(
            LoopService.latestHotspotMeasures(pieceId: piece, takes: [take], analyses: [older, newer, newest]),
            [7]
        )
    }

    // MARK: TakeStore — 只追加落盘往返

    func testTakeStoreRoundTrip() throws {
        let url = try TakeStore.makeFileURL()
        let events = [
            RawMIDIEventRecord(t: 1_000, k: "on", c: 0, n: 60, v: 88, suspicious: false),
            RawMIDIEventRecord(t: 2_000, k: "cc64", c: 0, n: 64, v: 127, suspicious: false),
            RawMIDIEventRecord(t: 3_000, k: "off", c: 0, n: 60, v: 0, suspicious: true),
        ]
        for e in events {
            try TakeStore.append(e, to: url)
        }
        let read = try TakeStore.readEvents(from: url)
        XCTAssertEqual(read, events, "追加后读取必须逐条一致（JSON Lines 往返）")
    }

    func testTakeStoreAppendOnlyPreservesEarlierContent() throws {
        let url = try TakeStore.makeFileURL()
        try TakeStore.append(RawMIDIEventRecord(t: 1, k: "on", c: 0, n: 60, v: 90, suspicious: false), to: url)
        let afterFirst = try TakeStore.readEvents(from: url)
        try TakeStore.append(RawMIDIEventRecord(t: 2, k: "off", c: 0, n: 60, v: 0, suspicious: false), to: url)
        let afterSecond = try TakeStore.readEvents(from: url)
        XCTAssertEqual(afterSecond.count, afterFirst.count + 1, "只追加：后写不覆盖先写")
        XCTAssertEqual(afterSecond.first, afterFirst.first)
    }

    // MARK: PracticeSession — 断连记 interruption + MIDI 空洞不崩

    @MainActor
    func testDisconnectMarksInterruptionAndPausesJudging() throws {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        let metronome = MetronomeService()
        session.start(metronome: metronome, countIn: false, metronomeOn: false)
        session.beginPerforming()

        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 90), channel: 0, timeNanos: 1))
        XCTAssertEqual(session.midiEventCount, 1)

        // 断连 → 事件不消费（判分暂停），且记录断点
        session.setConnected(false)
        session.handle(MIDIEvent(kind: .noteOn(note: 64, velocity: 90), channel: 0, timeNanos: 2))
        XCTAssertEqual(session.midiEventCount, 1, "断连期间不消费事件")
        XCTAssertEqual(session.interruptionStarts.count, 1, "断连标记 interruption 起点")

        // 重连 → 续录，会话状态不清零
        session.setConnected(true)
        session.handle(MIDIEvent(kind: .noteOn(note: 64, velocity: 90), channel: 0, timeNanos: 3))
        XCTAssertEqual(session.midiEventCount, 2, "重连后从断点继续")
        XCTAssertEqual(session.interruptionStarts.count, 1, "重连不新增断点")

        let summary = session.finish()
        XCTAssertEqual(summary.midiEventCount, 2)
        XCTAssertEqual(summary.noteCount, 2)
    }

    @MainActor
    func testNoCrashOnMIDIGapsAndOddSequences() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        session.beginPerforming()

        // 空洞/乱序/velocity=0 noteOn/重复 off/超界音高——只求不崩、计数正确
        session.handle(MIDIEvent(kind: .noteOff(note: 60, velocity: 0), channel: 0, timeNanos: 1))
        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 0), channel: 0, timeNanos: 2)) // 视为 off
        session.handle(MIDIEvent(kind: .noteOn(note: 200, velocity: 90), channel: 9, timeNanos: 3))
        session.handle(MIDIEvent(kind: .sustainPedal(value: 0), channel: 0, timeNanos: 4))
        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 100), channel: 0, timeNanos: 5))
        session.handle(MIDIEvent(kind: .noteOn(note: 60, velocity: 100), channel: 0, timeNanos: 6))

        let summary = session.finish()
        XCTAssertEqual(summary.midiEventCount, 6, "全部事件计数（含被跳过判分的）")
        // 音符数 = 实际弹的（velocity>0 的 noteOn，含弹错的）；错音 = 不在期望内的（超界 200 + 多弹的重复 60）
        XCTAssertEqual(summary.noteCount, 3)
        XCTAssertEqual(summary.wrongNotes.count, 2)
        XCTAssertEqual(summary.pedalEventCount, 1)
    }

    // MARK: PracticeSession.persist — Take 落库

    @MainActor
    func testPersistWritesTakeMetadata() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Take.self, configurations: config)
        let context = ModelContext(container)

        var summary = TakeSummary()
        summary.durationSec = 134
        summary.noteCount = 132
        summary.wrongNotes = [WrongNoteRecord(measure: 21, actualPitch: 62)]
        summary.tempoAvg = 72
        summary.pedalEventCount = 4
        summary.midiEventCount = 1284
        summary.midiFileName = "take-test.jsonl"

        let take = PracticeSession.persist(
            summary, taskType: "main", isFreePlay: false,
            startedAt: Date(), interruptions: [47], title: "",
            in: context
        )
        try context.save()
        _ = take

        let all = try context.fetch(FetchDescriptor<Take>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.durationSec, 134)
        XCTAssertEqual(all.first?.wrongNoteCount, 1)
        XCTAssertEqual(all.first?.interruptionRanges, [47])
        XCTAssertEqual(all.first?.hasMidi, true)
    }

    // MARK: G4 SightReading — 纯选片（候选带 / 跨轨 / 去重 / 教材末尾；rand 注入确定性）

    /// 拜厄 1...count 条目：n <= passedUntil 为 passed，n == practicingAt 为 practicing，其余 notStarted
    private func makeBeyerPieces(count: Int, passedUntil: Int, practicingAt: Int, totalMeasures: Int = 16) -> [Piece] {
        (1...count).map { n in
            let status: String
            if n <= passedUntil { status = CourseEngine.statusPassed }
            else if n == practicingAt { status = CourseEngine.statusPracticing }
            else { status = CourseEngine.statusNotStarted }
            return Piece(book: "拜厄", number: n, totalMeasures: totalMeasures, status: status)
        }
    }

    private func makeDrillRecord(book: String, number: Int, createdAt: Date, isReview: Bool = false,
                                 measureStart: Int = 1, measureCount: Int = 4,
                                 expected: Int = 10, matched: Int = 8) -> SightReadDrillRecord {
        SightReadDrillRecord(book: book, pieceNumber: number, measureStart: measureStart, measureCount: measureCount,
                             expected: expected, matched: matched,
                             hitRate: expected > 0 ? Double(matched) / Double(expected) : nil,
                             isReview: isReview, createdAt: createdAt)
    }

    func testPickerStaysInsideCandidateBand() {
        // 当前拜厄 practicing 第 11 条（1...10 已 passed）→ 候选带只允许 [12...17]
        let pieces = makeBeyerPieces(count: 20, passedUntil: 10, practicingAt: 11)
        let first = SightReadPicker.pick(pieces: pieces, history: [], rand: { _ in 0 })
        XCTAssertEqual(first?.book, "拜厄")
        XCTAssertEqual(first?.pieceNumber, 12, "rand 恒 0 → 选候选带首条")
        XCTAssertEqual(first?.measureStart, 1)
        XCTAssertEqual(first?.measureCount, 4, "min(4, 16)")
        XCTAssertEqual(first?.isReview, false)

        let last = SightReadPicker.pick(pieces: pieces, history: [], rand: { $0.upperBound - 1 })
        XCTAssertEqual(last?.pieceNumber, 17, "rand 恒取末位 → 候选带末条，不越到更远处")

        // 已练条（passed 的 1...10）与 practicing 条本身（11）都不该出现
        for chosen in [first, last].compactMap({ $0 }) {
            XCTAssertGreaterThan(chosen.pieceNumber, 11, "不会选到已练条或游标处")
        }
    }

    func testPickerMergesTracksAndClampsToBookEnd() throws {
        var pieces = makeBeyerPieces(count: 106, passedUntil: 102, practicingAt: 103)
        pieces.append(contentsOf: (1...20).map { n in
            Piece(book: "哈农", number: n, totalMeasures: 8,
                  status: n <= 17 ? CourseEngine.statusPassed : CourseEngine.statusNotStarted)
        })
        // 候选带合并：拜厄 [104,105,106]（3 条，106 封顶不越界）+ 哈农 [19,20]（2 条）= 5 条
        let first = SightReadPicker.pick(pieces: pieces, history: [], rand: { _ in 0 })
        XCTAssertEqual(first?.pieceNumber, 104)
        XCTAssertEqual(first?.book, "拜厄")

        let last = SightReadPicker.pick(pieces: pieces, history: [], rand: { $0.upperBound - 1 })
        XCTAssertEqual(last?.book, "哈农")
        XCTAssertEqual(last?.pieceNumber, 20, "哈农到 20 封顶，不越界到 21")

        // 拜厄全通关（游标到底 107 → 候选带空）→ 只剩哈农带
        var beyerDone = makeBeyerPieces(count: 106, passedUntil: 106, practicingAt: 0)
        beyerDone.append(contentsOf: (1...20).map { n in
            Piece(book: "哈农", number: n, totalMeasures: 8,
                  status: n <= 16 ? CourseEngine.statusPassed : CourseEngine.statusNotStarted)
        })
        let onlyHanon = SightReadPicker.pick(pieces: beyerDone, history: [], rand: { _ in 0 })
        XCTAssertEqual(onlyHanon?.book, "哈农")
        XCTAssertEqual(onlyHanon?.pieceNumber, 18, "哈农 1...16 passed、17...20 notStarted → 游标 17，候选带 18...20")
    }

    func testPickerPrefersUnplayedAndFallsBackToOldestReview() {
        let pieces = makeBeyerPieces(count: 20, passedUntil: 8, practicingAt: 9)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // 候选带 [10...15]：10/11/12 已视奏（createdAt 递增），13/14/15 未视奏
        let history = [
            makeDrillRecord(book: "拜厄", number: 10, createdAt: base),
            makeDrillRecord(book: "拜厄", number: 11, createdAt: base.addingTimeInterval(60)),
            makeDrillRecord(book: "拜厄", number: 12, createdAt: base.addingTimeInterval(120)),
        ]
        let fresh = SightReadPicker.pick(pieces: pieces, history: history, rand: { _ in 0 })
        XCTAssertEqual(fresh?.pieceNumber, 13, "有未视奏候选 → 优先，且不回头选已视奏条")
        XCTAssertEqual(fresh?.isReview, false)

        // 全部视奏过 → 最久未视奏（createdAt 最早 = 第 10 条）复用，isReview=true
        let allPlayed = history + [
            makeDrillRecord(book: "拜厄", number: 13, createdAt: base.addingTimeInterval(180)),
            makeDrillRecord(book: "拜厄", number: 14, createdAt: base.addingTimeInterval(240)),
            makeDrillRecord(book: "拜厄", number: 15, createdAt: base.addingTimeInterval(300)),
        ]
        let review = SightReadPicker.pick(pieces: pieces, history: allPlayed, rand: { _ in 0 })
        XCTAssertEqual(review?.pieceNumber, 10, "候选全视奏过 → 最久未视奏者优先")
        XCTAssertEqual(review?.isReview, true, "复用必须诚实标记复习，不伪装首见")
    }

    func testPickerExhaustedReusesOldestHistoryOrNil() {
        // 两轨到底：pieces 为空 → 游标取通关值 107/21 → 候选带皆空
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [
            makeDrillRecord(book: "哈农", number: 5, createdAt: base.addingTimeInterval(60), measureStart: 1, measureCount: 4),
            makeDrillRecord(book: "拜厄", number: 50, createdAt: base, measureStart: 5, measureCount: 4),
        ]
        let reused = SightReadPicker.pick(pieces: [], history: history, rand: { _ in 0 })
        XCTAssertEqual(reused?.book, "拜厄", "两轨到底 → 复用全部 history 中 createdAt 最早者")
        XCTAssertEqual(reused?.pieceNumber, 50)
        XCTAssertEqual(reused?.measureStart, 5)
        XCTAssertEqual(reused?.isReview, true)

        XCTAssertNil(SightReadPicker.pick(pieces: [], history: [], rand: { _ in 0 }), "到底且无历史 → nil，不编造")
    }

    func testPickerSkipsInvalidTotalMeasuresAndClampsCount() {
        // 游标 10：候选带 [11...16]，但 11/12 totalMeasures<=0 不可用、15/16 无条目 → 只剩 13/14
        var pieces = makeBeyerPieces(count: 10, passedUntil: 9, practicingAt: 10)
        pieces.append(Piece(book: "拜厄", number: 11, totalMeasures: 0, status: CourseEngine.statusNotStarted))
        pieces.append(Piece(book: "拜厄", number: 12, totalMeasures: -3, status: CourseEngine.statusNotStarted))
        pieces.append(Piece(book: "拜厄", number: 13, totalMeasures: 3, status: CourseEngine.statusNotStarted))
        pieces.append(Piece(book: "拜厄", number: 14, totalMeasures: 16, status: CourseEngine.statusNotStarted))

        let first = SightReadPicker.pick(pieces: pieces, history: [], rand: { _ in 0 })
        XCTAssertEqual(first?.pieceNumber, 13)
        XCTAssertEqual(first?.measureCount, 3, "measureCount = min(4, total)")

        let last = SightReadPicker.pick(pieces: pieces, history: [], rand: { $0.upperBound - 1 })
        XCTAssertEqual(last?.pieceNumber, 14)
        XCTAssertEqual(last?.measureCount, 4, "min(4, 16)")

        // 候选带内全部不可用 → 无候选（无历史）→ nil
        var allInvalid = makeBeyerPieces(count: 10, passedUntil: 9, practicingAt: 10)
        allInvalid.append(Piece(book: "拜厄", number: 11, totalMeasures: 0, status: CourseEngine.statusNotStarted))
        XCTAssertNil(SightReadPicker.pick(pieces: allInvalid, history: [], rand: { _ in 0 }),
                     "totalMeasures<=0 的条目视为不可用，不可用尽后不得伪造候选")
    }

    // MARK: G4 SightReading — 期望音加载（两声部口径 + 1-based 过滤）

    func testExpectedPitchesCoversAllStavesAndOneBasedMeasures() throws {
        guard let url = Bundle.main.url(forResource: "beyer_01", withExtension: "musicxml") else {
            return XCTFail("测试宿主 app bundle 缺少 beyer_01.musicxml")
        }
        let score = try ScoreLoader.loadScore(contentsOf: url)
        let staves = try XCTUnwrap(score.parts.first?.staves, "谱至少要有 staff")
        XCTAssertGreaterThan(staves.count, 0)

        // 口径 oracle：逐 staff 全量收集（与实现同规则，但独立写在测试侧作对照）
        func pitches(staffIndexes: [Int], measures: ClosedRange<Int>) -> [UInt8] {
            var result: [UInt8] = []
            for i in staffIndexes {
                for (idx, measure) in staves[i].measures.enumerated() where measures.contains(idx + 1) {
                    for voice in measure.voices {
                        for element in voice.elements {
                            if case let .chord(chord) = element {
                                result.append(contentsOf: chord.notes.map { UInt8($0.pitch) })
                            }
                        }
                    }
                }
            }
            return result
        }

        let all = SightReadSession.expectedPitches(score: score, measures: 1...4)
        XCTAssertFalse(all.isEmpty, "beyer_01 前 4 小节应有期望音")
        let oracleAll = pitches(staffIndexes: Array(staves.indices), measures: 1...4)
        XCTAssertEqual(all, oracleAll, "遍历全部 staves，顺序 = staff 依次拼接")

        // 两声部口径：多 staff 时，只取第一个 staff 的结果必须是全量结果的前缀
        if staves.count > 1 {
            let firstStaffOnly = pitches(staffIndexes: [0], measures: 1...4)
            XCTAssertFalse(firstStaffOnly.isEmpty)
            XCTAssertEqual(Array(all.prefix(firstStaffOnly.count)), firstStaffOnly,
                           "实现按 staff 顺序拼接：第一 staff 在前，后面的 staff 也计入")
            XCTAssertGreaterThan(all.count, firstStaffOnly.count, "第二 staff 的音也被计入（两声部口径）")
        }

        // 1-based 过滤：区间结果 = 各单小节结果按序拼接
        let perMeasure = (1...4).map { SightReadSession.expectedPitches(score: score, measures: $0...$0) }
        XCTAssertEqual(all, perMeasure.flatMap { $0 }, "measures 为 1-based 小节号")

        // 越界小节 → 空数组（诚实）
        XCTAssertTrue(SightReadSession.expectedPitches(score: score, measures: 999...1_000).isEmpty)
    }

    func testLoadExpectedPitchesByBookNumberIsHonestWhenMissing() {
        XCTAssertFalse(SightReadSession.loadExpectedPitches(book: "拜厄", number: 1, measures: 1...2).isEmpty,
                       "拜厄内置谱存在 → 真实解析出期望音")
        XCTAssertTrue(SightReadSession.loadExpectedPitches(book: "车尔尼599", number: 1, measures: 1...2).isEmpty,
                      "无内置谱 → 空数组，不冒充别的谱")
        XCTAssertTrue(SightReadSession.loadExpectedPitches(book: "哈农", number: 21, measures: 1...2).isEmpty,
                      "越教材上限 → 空数组")
    }

    // MARK: G4 SightReading — 记录写入（hitRate 诚实）与趋势聚合

    private func makeDrillContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SightReadDrillRecord.self, configurations: config)
    }

    func testSaveComputesHitRateHonestly() throws {
        let context = ModelContext(try makeDrillContainer())

        let zero = SightReadDrillStore.save(book: "拜厄", pieceNumber: 12, measureStart: 1, measureCount: 4,
                                            expected: 0, matched: 0, pauses: 0, elapsedSeconds: 12,
                                            isReview: false, in: context)
        XCTAssertNil(zero.hitRate, "expected==0 → hitRate 必须为 nil，禁止编造")
        XCTAssertGreaterThanOrEqual(zero.elapsedSeconds, 0)

        let normal = SightReadDrillStore.save(book: "拜厄", pieceNumber: 13, measureStart: 1, measureCount: 4,
                                              expected: 4, matched: 3, pauses: 1, elapsedSeconds: 45,
                                              isReview: false, in: context)
        XCTAssertEqual(normal.hitRate ?? -1, 0.75, accuracy: 0.0001, "hitRate = matched/expected 真实比值")

        // 便捷入口：pick + result → 记录字段一致
        let pick = SightReadDrillPick(book: "哈农", pieceNumber: 7, measureStart: 1, measureCount: 4, isReview: true)
        let result = SightReadSegmentResult(expected: 8, matched: 2, pauses: 0, elapsedSeconds: 30)
        let saved = SightReadDrillStore.save(pick: pick, result: result, in: context)
        XCTAssertEqual(saved.book, "哈农")
        XCTAssertEqual(saved.pieceNumber, 7)
        XCTAssertEqual(saved.isReview, true)
        XCTAssertEqual(saved.hitRate ?? -1, 0.25, accuracy: 0.0001)

        let all = try context.fetch(FetchDescriptor<SightReadDrillRecord>())
        XCTAssertEqual(all.count, 3)
    }

    func testDrillRecordSwiftDataRoundTrip() throws {
        // 前证：in-memory + .mainContext 在测试确定性 EXC_BREAKPOINT → 一律 ModelContext(container)
        let context = ModelContext(try makeDrillContainer())
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SightReadDrillRecord(book: "哈农", pieceNumber: 9, measureStart: 1, measureCount: 4,
                                          expected: 24, matched: 20, pauses: 2, hitRate: 20.0 / 24.0,
                                          elapsedSeconds: 96, isReview: true, createdAt: createdAt)
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SightReadDrillRecord>())
        XCTAssertEqual(fetched.count, 1)
        let r = try XCTUnwrap(fetched.first)
        XCTAssertEqual(r.book, "哈农")
        XCTAssertEqual(r.pieceNumber, 9)
        XCTAssertEqual(r.measureStart, 1)
        XCTAssertEqual(r.measureCount, 4)
        XCTAssertEqual(r.expected, 24)
        XCTAssertEqual(r.matched, 20)
        XCTAssertEqual(r.pauses, 2)
        XCTAssertEqual(r.hitRate ?? -1, 20.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(r.elapsedSeconds, 96)
        XCTAssertEqual(r.isReview, true)
        XCTAssertEqual(r.createdAt, createdAt)
    }

    func testTrendSummarizeRecent20AndHonestMeans() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var records: [SightReadDrillRecord] = []
        // 25 条首见（hitRate = i/100，时序递增）+ 5 条复习（时间都在首见之后）
        for i in 0..<25 {
            records.append(makeDrillRecord(book: "拜厄", number: 10 + i,
                                           createdAt: base.addingTimeInterval(Double(i)),
                                           expected: 100, matched: i))
        }
        for i in 0..<5 {
            records.append(makeDrillRecord(book: "拜厄", number: 10 + i,
                                           createdAt: base.addingTimeInterval(Double(100 + i)),
                                           isReview: true, expected: 10, matched: 5))
        }
        let summary = SightReadTrend.summarize(records: records)
        XCTAssertEqual(summary.totalCount, 20, "只取最近 20 条")
        XCTAssertEqual(summary.firstHitRates.count, 15, "最近 20 条 = 5 复习 + 15 首见（i=10...24；i=9 在第 21 位被截掉）")
        XCTAssertEqual(summary.firstHitRates.first ?? -1, 0.10, accuracy: 0.0001, "首见序列时间升序（窗口内最早的 i=10）")
        XCTAssertEqual(summary.firstHitRates.last ?? -1, 0.24, accuracy: 0.0001)
        XCTAssertEqual(summary.firstMean ?? -1, (0.10 + 0.24) / 2, accuracy: 0.0001,
                       "15 个有效样本 0.10...0.24 等差 → 均值 = 首尾平均")
        XCTAssertEqual(summary.reviewMean ?? -1, 0.5, accuracy: 0.0001)

        // 首见有效样本 < 3 → 均值 nil（诚实留白）
        let sparse = SightReadTrend.summarize(records: Array(records.prefix(2)))
        XCTAssertNil(sparse.firstMean)
        XCTAssertEqual(sparse.totalCount, 2)

        // expected==0 的记录不产生命中率：不进序列、不污染均值，但计入总次数
        var polluted = records
        for i in 0..<20 {
            polluted.append(makeDrillRecord(book: "拜厄", number: 99,
                                            createdAt: base.addingTimeInterval(Double(1_000 + i)),
                                            expected: 0, matched: 0))
        }
        let withZeros = SightReadTrend.summarize(records: polluted)
        XCTAssertEqual(withZeros.totalCount, 20, "expected==0 的记录保留计数（最近 20 条全为无效命中率样本）")
        XCTAssertEqual(withZeros.firstHitRates.count, 0, "expected==0 不进命中率序列")
        XCTAssertNil(withZeros.firstMean, "有效样本不足 → 均值 nil，不编趋势")
        XCTAssertNil(withZeros.reviewMean)
    }

    // MARK: G4 clipping — 谱片段裁剪与首小节回填（Stage B）

    /// 最小 Score fixture：N 小节单 staff 单 voice，第 i 小节（0-based）chord 音 = 60 + i；
    /// 可选在指定 0-based 小节声明 keySignature / timeSignature / clef。
    private func makeMiniScore(measureCount: Int,
                               keyAt: [Int: Int] = [:],
                               timeAt: [Int: (Int, Int)] = [:],
                               clefAt: [Int: String] = [:],
                               defaultClefType: String? = nil) -> Score {
        var measures: [Measure] = []
        for i in 0..<measureCount {
            var elements: [VoiceElement] = []
            if let k = keyAt[i] { elements.append(.keySignature(KeySignature(concertKey: k))) }
            if let t = timeAt[i] { elements.append(.timeSignature(TimeSignature(numerator: t.0, denominator: t.1))) }
            if let c = clefAt[i] { elements.append(.clef(Clef(concertClefType: c))) }
            elements.append(.chord(Chord(duration: .quarter, notes: ChordNotes([Note(pitch: 60 + i, tpc: 21)]))))
            measures.append(Measure(voices: [Voice(elements: elements)]))
        }
        let staff = Staff(defaultClefType: defaultClefType, measures: measures)
        let part = Part(id: "P1", instrument: Instrument(id: "piano"), staves: IdentifiedArray([staff]))
        return Score(division: 480,
                     parts: IdentifiedArray([part]),
                     systemMeasures: IdentifiedArray(Array(repeating: SystemMeasure(), count: measureCount)))
    }

    /// 逐小节取首个 chord 的音高（fixture 内容断言用）
    private func chordPitches(of score: Score) -> [Int] {
        (score.parts.first?.staves.first?.measures ?? []).map { measure in
            measure.voices.first?.elements.compactMap { element -> Int? in
                if case let .chord(chord) = element { return chord.notes.first?.pitch }
                return nil
            }.first ?? -1
        }
    }

    func testClippedScoreKeepsOnlyRequestedMeasures() throws {
        let score = makeMiniScore(measureCount: 6)
        let clipped = SightReadSession.clippedScore(of: score, measures: 2...4)
        let staff = try XCTUnwrap(clipped.parts.first?.staves.first)
        XCTAssertEqual(staff.measures.count, 3, "只保留指定 3 小节")
        XCTAssertEqual(clipped.systemMeasures.count, 3, "systemMeasures 与 staff 同步")
        XCTAssertEqual(chordPitches(of: clipped), [61, 62, 63], "内容对应原第 2...4 小节（0-based 61/62/63）")
        XCTAssertEqual(clipped.division, 480, "division 不变")
    }

    func testClippedScoreClampsRangeAndNeverCrashes() {
        let score = makeMiniScore(measureCount: 3)
        // 部分越界 → clamp 到实际可裁 2...3
        let partial = SightReadSession.clippedScore(of: score, measures: 2...10)
        XCTAssertEqual(partial.parts.first?.staves.first?.measures.count, 2)
        // 完全越界 → 空壳，不崩
        let empty = SightReadSession.clippedScore(of: score, measures: 5...10)
        XCTAssertEqual(empty.parts.count, 0)
        XCTAssertEqual(empty.systemMeasures.count, 0)
    }

    func testClippedScoreBackfillsKeyTimeClefAtCutStart() throws {
        // 全曲开头（第 1 小节）声明 1 升号 / 3 拍 / G 谱号；从第 3 小节起裁剪 → 首小节须被回填
        let score = makeMiniScore(measureCount: 4, keyAt: [0: 1], timeAt: [0: (3, 4)], clefAt: [0: "G"])
        let clipped = SightReadSession.clippedScore(of: score, measures: 3...4)
        let elements = try XCTUnwrap(clipped.parts.first?.staves.first?.measures.first?.voices.first?.elements)

        let keys = elements.compactMap { e -> Int? in if case let .keySignature(k) = e { return k.concertKey }; return nil }
        XCTAssertEqual(keys, [1], "裁剪首小节回填生效调号")
        if case let .timeSignature(t)? = elements.first(where: { if case .timeSignature = $0 { return true }; return false }) {
            XCTAssertEqual(t.numerator, 3, "回填生效拍号分子")
            XCTAssertEqual(t.denominator, 4, "回填生效拍号分母")
        } else {
            XCTFail("裁剪首小节应回填 3/4 拍号")
        }
        let clefs = elements.compactMap { e -> String? in if case let .clef(c) = e { return c.concertClefType }; return nil }
        XCTAssertEqual(clefs, ["G"], "回填生效谱号")
        // 回填属性在最前，原 chord 保留
        XCTAssertTrue(elements.contains { if case .chord = $0 { return true }; return false },
                      "回填后 chord 仍在首小节内")
        XCTAssertEqual(chordPitches(of: clipped), [62, 63], "音符内容不变")
    }

    func testClippedScoreDoesNotDuplicateExistingDeclarations() throws {
        // 裁剪起点（第 3 小节）自带 key 声明 → 用它，不重复插入开头声明
        let score = makeMiniScore(measureCount: 4, keyAt: [0: 1, 2: -1])
        let clipped = SightReadSession.clippedScore(of: score, measures: 3...4)
        let elements = try XCTUnwrap(clipped.parts.first?.staves.first?.measures.first?.voices.first?.elements)
        let keys = elements.compactMap { e -> Int? in if case let .keySignature(k) = e { return k.concertKey }; return nil }
        XCTAssertEqual(keys, [-1], "起点已声明 → 不重复（只此一份）")
    }

    func testClippedScoreNoDeclarationsIsReasonable() throws {
        // 全曲无任何声明（无显式调号）→ 不造属性、不崩、chords 保留
        let score = makeMiniScore(measureCount: 3)
        let clipped = SightReadSession.clippedScore(of: score, measures: 2...3)
        let elements = try XCTUnwrap(clipped.parts.first?.staves.first?.measures.first?.voices.first?.elements)
        XCTAssertFalse(elements.contains { if case .keySignature = $0 { return true }; return false },
                       "全曲无声明 → 不回填（默认即 C 大调）")
        XCTAssertTrue(elements.contains { if case .chord = $0 { return true }; return false })
    }

    func testExpectedPitchesOnClipMatchesFullScoreRange() {
        // 渲染片段与判定口径绑定：裁剪片段从头数 == 整条谱同源区间
        let score = makeMiniScore(measureCount: 6, keyAt: [0: 1])
        let clipped = SightReadSession.clippedScore(of: score, measures: 2...4)
        XCTAssertEqual(
            SightReadSession.expectedPitches(score: clipped, measures: 1...3),
            SightReadSession.expectedPitches(score: score, measures: 2...4),
            "同源口径：片段期望音与整条谱对应区间一致"
        )
    }

    // MARK: G3 Correction Prescription（ADR-0005：错误类型 → 矫正处方核心层）

    /// 分类器最小信号：默认全 nil / 无逐音 / 无节奏速度信号，只填关心的字段
    private func makeCorrectionSignals(
        alignedNotes: [AlignedNote] = [],
        pitchScore: Int? = nil,
        rhythmScore: Int? = nil,
        tempoScore: Int? = nil,
        dynamicsScore: Int? = nil,
        continuityScore: Int? = nil,
        handsScore: Int? = nil,
        rhythmMedianMs: Double = 0,
        avgBPM: Double = 0,
        tempoTargetHit: Bool = false,
        timingWindowMs: Double = 120,
        maxRhythmMedianMs: Double = 100,
        targetTempoRatio: Double = 0.8,
        hotspotMeasures: [Int] = []
    ) -> CorrectionSignals {
        CorrectionSignals(
            alignedNotes: alignedNotes, pitchScore: pitchScore, rhythmScore: rhythmScore,
            tempoScore: tempoScore, dynamicsScore: dynamicsScore, continuityScore: continuityScore,
            handsScore: handsScore, rhythmMedianMs: rhythmMedianMs, avgBPM: avgBPM,
            tempoTargetHit: tempoTargetHit, timingWindowMs: timingWindowMs,
            maxRhythmMedianMs: maxRhythmMedianMs, targetTempoRatio: targetTempoRatio,
            hotspotMeasures: hotspotMeasures
        )
    }

    /// 逐音 fixture：extra 无参考侧、missing 无演奏侧（与真实对齐口径一致）
    private func makeAlignedNote(cls: NoteMatchClass, deltaMs: Double? = nil) -> AlignedNote {
        AlignedNote(
            refID: cls == .extra ? nil : 0,
            refMeasureIndex: cls == .extra ? nil : 0,
            refBeatInMeasure: cls == .extra ? nil : 0.0,
            refPitch: cls == .extra ? nil : 60,
            playedPitch: cls == .missing ? nil : 61,
            deltaMs: deltaMs,
            cls: cls,
            hand: .right
        )
    }

    /// 可评分析：默认可评、高置信、不过（G3 触发口径的最常见形态）
    private func makeCorrectionAnalysis(
        analyzedAt: Date,
        canEvaluate: Bool = true,
        passesHardMetrics: Bool = false,
        confidence: Double = 0.9,
        hotspotMeasures: [Int] = [],
        alignmentJSON: String = "[]",
        pitchScore: Int? = nil,
        rhythmScore: Int? = nil,
        tempoScore: Int? = nil,
        dynamicsScore: Int? = nil,
        continuityScore: Int? = nil,
        handsScore: Int? = nil,
        rhythmMedianMs: Double = 0,
        avgBPM: Double = 0,
        tempoTargetHit: Bool = false
    ) -> TakeAnalysis {
        TakeAnalysis(
            analyzedAt: analyzedAt, confidence: confidence,
            pitchScore: pitchScore, rhythmScore: rhythmScore, tempoScore: tempoScore,
            dynamicsScore: dynamicsScore, continuityScore: continuityScore, handsScore: handsScore,
            rhythmMedianMs: rhythmMedianMs, tempoTargetHit: tempoTargetHit, avgBPM: avgBPM,
            hotspotMeasures: hotspotMeasures, canEvaluate: canEvaluate,
            passesHardMetrics: passesHardMetrics, alignmentJSON: alignmentJSON
        )
    }

    private func makeOutcome(canEvaluate: Bool = true, passes: Bool = false,
                             confidence: Double = 0.9) -> CorrectionEngine.EvaluableOutcome {
        .init(canEvaluate: canEvaluate, passesHardMetrics: passes, confidence: confidence)
    }

    private func makeCorrectionContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema([Piece.self, TakeAnalysis.self, CorrectionPrescription.self]),
            configurations: config
        )
    }

    private func makeCorrectionPiece(book: String = "拜厄", number: Int = 12) -> Piece {
        Piece(entityId: UUID(), title: "G3 测试曲", book: book, number: number, totalMeasures: 16)
    }

    func testClassifyOnlyWrongPitchFromNotes() {
        let signals = makeCorrectionSignals(alignedNotes: [makeAlignedNote(cls: .wrongPitch)])
        XCTAssertEqual(CorrectionEngine.classify(signals), Set([.wrongPitch]),
                       "逐音错音 → 只判 wrongPitch，其余维 nil 不判")
    }

    func testClassifyOnlyMissingAndExtraFromNotes() {
        let missing = CorrectionEngine.classify(
            makeCorrectionSignals(alignedNotes: [makeAlignedNote(cls: .missing)]))
        XCTAssertEqual(missing, Set([.missing]), "漏音只来自逐音信号")
        let extra = CorrectionEngine.classify(
            makeCorrectionSignals(alignedNotes: [makeAlignedNote(cls: .extra)]))
        XCTAssertEqual(extra, Set([.extra]), "多弹只来自逐音信号")
    }

    func testClassifyOnlyRhythmFromOutOfWindowDelta() {
        let signals = makeCorrectionSignals(
            alignedNotes: [makeAlignedNote(cls: .correct, deltaMs: 150)],
            timingWindowMs: 120)
        XCTAssertEqual(CorrectionEngine.classify(signals), Set([.rhythm]),
                       "|deltaMs| 超容差窗 → 只判 rhythm")
    }

    func testClassifyOnlyTempo() {
        let signals = makeCorrectionSignals(avgBPM: 50, tempoTargetHit: false)
        XCTAssertEqual(CorrectionEngine.classify(signals), Set([.tempo]),
                       "实测有速度但未达目标 → 只判 tempo")
    }

    func testClassifyScoreDimensionsOnly() {
        // dynamics：分数低、其余全 nil → 只判 dynamics（六维分数类逐一验证）
        XCTAssertEqual(CorrectionEngine.classify(makeCorrectionSignals(dynamicsScore: 40)),
                       Set([.dynamics]))
        XCTAssertEqual(CorrectionEngine.classify(makeCorrectionSignals(continuityScore: 10)),
                       Set([.continuity]))
        XCTAssertEqual(CorrectionEngine.classify(makeCorrectionSignals(handsScore: 55)),
                       Set([.hands]))
    }

    func testClassifyHonestWhenSignalsMissing() {
        // 全空信号 → 集合为空：算不出的维度不判，禁止编错（红线 1）
        XCTAssertEqual(CorrectionEngine.classify(makeCorrectionSignals()), Set<CorrectionErrorType>([]))
        // avgBPM == 0 = 速度维算不出：即使 tempoTargetHit 默认 false 也不判 tempo
        XCTAssertFalse(CorrectionEngine.classify(makeCorrectionSignals(avgBPM: 0, tempoTargetHit: false)).contains(.tempo))
        // pitchScore nil + 无逐音 → 不判 wrongPitch
        XCTAssertFalse(CorrectionEngine.classify(makeCorrectionSignals(pitchScore: nil)).contains(.wrongPitch))
        // 刚过线的分数（≥ 60）不算低
        XCTAssertFalse(CorrectionEngine.classify(makeCorrectionSignals(dynamicsScore: 60)).contains(.dynamics))
    }

    func testClassifyHitsMultipleTypesAtOnce() {
        // 逐音错音（且带超窗 delta）+ 连续性低分 → 三类同时命中
        let signals = makeCorrectionSignals(
            alignedNotes: [makeAlignedNote(cls: .wrongPitch, deltaMs: 200)],
            continuityScore: 20,
            timingWindowMs: 120)
        XCTAssertEqual(CorrectionEngine.classify(signals),
                       Set([.wrongPitch, .rhythm, .continuity]))
    }

    func testClassifyRhythmWindowBoundaries() {
        // 恰好在窗上（== timingWindowMs）不算超窗（判定是严格 >）
        let onWindow = makeCorrectionSignals(
            alignedNotes: [makeAlignedNote(cls: .correct, deltaMs: 120)], timingWindowMs: 120)
        XCTAssertFalse(CorrectionEngine.classify(onWindow).contains(.rhythm))
        // 超 0.5ms 即判
        let justOver = makeCorrectionSignals(
            alignedNotes: [makeAlignedNote(cls: .correct, deltaMs: 120.5)], timingWindowMs: 120)
        XCTAssertTrue(CorrectionEngine.classify(justOver).contains(.rhythm))
        // 中位数恰好等于阈值不算超；刚超 0.5 判
        let medianOn = makeCorrectionSignals(rhythmMedianMs: 100, maxRhythmMedianMs: 100)
        XCTAssertFalse(CorrectionEngine.classify(medianOn).contains(.rhythm))
        let medianOver = makeCorrectionSignals(rhythmMedianMs: 100.5, maxRhythmMedianMs: 100)
        XCTAssertTrue(CorrectionEngine.classify(medianOver).contains(.rhythm))
    }

    func testShouldPrescribeConsecutiveEvaluableFails() {
        XCTAssertFalse(CorrectionEngine.shouldPrescribe([]), "空数组 → false")
        XCTAssertFalse(CorrectionEngine.shouldPrescribe([makeOutcome(passes: false)]),
                       "只有 1 次可评不过 → 还不触发")
        XCTAssertTrue(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: false), makeOutcome(passes: false),
        ]), "连续 2 次可评不过 → 触发")
        XCTAssertTrue(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: false), makeOutcome(passes: false), makeOutcome(passes: false),
        ]), "3 次连续不过仍触发")
    }

    func testShouldPrescribeIgnoresUnevaluableAndLowConfidence() {
        // 不可评 / 低置信不计入、也不打断：可评序列 [fail, fail] 仍连续
        XCTAssertTrue(CorrectionEngine.shouldPrescribe([
            makeOutcome(canEvaluate: false, passes: false),
            makeOutcome(passes: false, confidence: 0.5), // 低置信
            makeOutcome(passes: false),
            makeOutcome(passes: false),
        ]))
        // 不可评夹在中间也不打断
        XCTAssertTrue(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: false), makeOutcome(canEvaluate: false),
            makeOutcome(passes: false),
        ]))
    }

    func testShouldPrescribeResetsOnPass() {
        XCTAssertFalse(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: false), makeOutcome(passes: true),
        ]), "最近可评通过 → 清零")
        XCTAssertFalse(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: false), makeOutcome(passes: false), makeOutcome(passes: true),
        ]), "两次不过后通过 → false")
        XCTAssertFalse(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: false), makeOutcome(passes: false),
            makeOutcome(passes: true), makeOutcome(passes: false, confidence: 0.5),
        ]), "通过后的低置信不计入，最近可评仍是通过 → false")
        XCTAssertTrue(CorrectionEngine.shouldPrescribe([
            makeOutcome(passes: true), makeOutcome(passes: false), makeOutcome(passes: false),
        ]), "更早的通过不阻断：最近两个可评不过 → true")
    }

    func testRemedyTableCoversAllEightTypes() throws {
        let table = CorrectionEngine.remedyTable()
        XCTAssertEqual(table.count, CorrectionErrorType.allCases.count, "8 类每类都有练习法")
        for type in CorrectionErrorType.allCases {
            let remedy = try XCTUnwrap(table[type])
            XCTAssertFalse(remedy.goal.isEmpty, "\(type.rawValue) 的中文目标非空")
            XCTAssertGreaterThan(remedy.tempoRatio, 0, "\(type.rawValue) tempoRatio 下界")
            XCTAssertLessThanOrEqual(remedy.tempoRatio, 1, "\(type.rawValue) tempoRatio 上界（慢练不快于参考速）")
        }
    }

    func testPrescriptionHotspotsEmptyMeansWholePiece() {
        // hotspot 为空 → 返回空，调用方走整曲级练习法，不造小节（ADR-0005 决策二）
        XCTAssertEqual(CorrectionEngine.prescriptionHotspots([]), [])
        XCTAssertEqual(CorrectionEngine.prescriptionHotspots([1, 3]), [1, 3], "非空原样透传")
    }

    @MainActor
    func testCorrectionPrescriptionSwiftDataRoundTrip() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let remedy = Remedy(tempoRatio: 0.6, separateHands: true, useMetronome: false, goal: "双手对齐")
        let remedyJSON = String(data: try JSONEncoder().encode(["hands": remedy]), encoding: .utf8)!
        let prescribedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let pieceId = UUID()
        let prescription = CorrectionPrescription(
            pieceId: pieceId, book: "拜厄", number: 12,
            errorTypes: ["hands", "rhythm"], remedyJSON: remedyJSON,
            hotspotMeasures: [3, 5], prescribedAt: prescribedAt)
        context.insert(prescription)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CorrectionPrescription>())
        XCTAssertEqual(fetched.count, 1)
        let r = try XCTUnwrap(fetched.first)
        XCTAssertEqual(r.pieceId, pieceId)
        XCTAssertEqual(r.book, "拜厄")
        XCTAssertEqual(r.number, 12)
        XCTAssertEqual(r.errorTypes, ["hands", "rhythm"])
        XCTAssertEqual(r.hotspotMeasures, [3, 5])
        XCTAssertEqual(r.prescribedAt, prescribedAt)
        XCTAssertNil(r.completedAt, "默认未完成")
        XCTAssertNil(r.resolvedAt, "默认未结")
        XCTAssertEqual(r.remedies, [.hands: remedy], "快照 rawValue 键解码还原练习法")
    }

    @MainActor
    func testPrescribeIfNeededNotTriggeredInsertsNothing() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let piece = makeCorrectionPiece()
        context.insert(piece)
        // 只 1 次可评不过 → 不触发
        let result = CorrectionPrescriptionStore.prescribeIfNeeded(
            piece: piece, analyses: [makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 100))],
            in: context)
        XCTAssertNil(result)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CorrectionPrescription>()).count, 0,
                       "不满足不插库")
    }

    @MainActor
    func testPrescribeIfNeededCreatesPrescriptionWithSnapshot() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let piece = makeCorrectionPiece() // 拜厄 → beginner 容差 120ms / 中位数 100ms
        context.insert(piece)
        // 两次可评不过；最新一次：逐音错音（带超窗 delta）+ 连续性低分 + hotspot [2,4]
        let note = makeAlignedNote(cls: .wrongPitch, deltaMs: 200)
        let alignmentJSON = String(data: try JSONEncoder().encode([note]), encoding: .utf8)!
        let older = makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 100))
        let newer = makeCorrectionAnalysis(
            analyzedAt: Date(timeIntervalSince1970: 200),
            hotspotMeasures: [2, 4], alignmentJSON: alignmentJSON, continuityScore: 30)

        let prescription = try XCTUnwrap(CorrectionPrescriptionStore.prescribeIfNeeded(
            piece: piece, analyses: [newer, older], in: context))

        XCTAssertEqual(prescription.pieceId, piece.entityId)
        XCTAssertEqual(prescription.book, "拜厄")
        XCTAssertEqual(prescription.number, 12)
        XCTAssertEqual(prescription.errorTypes, ["continuity", "rhythm", "wrongPitch"],
                       "三类命中且 rawValue 排序存储")
        XCTAssertEqual(prescription.hotspotMeasures, [2, 4], "hotspot 原样进入处方")
        XCTAssertNil(prescription.resolvedAt)
        XCTAssertNil(prescription.completedAt)
        // 快照：命中类的练习法与 remedyTable 一致，未命中类不进快照
        let table = CorrectionEngine.remedyTable()
        XCTAssertEqual(prescription.remedies.count, 3)
        for type in [CorrectionErrorType.wrongPitch, .rhythm, .continuity] {
            XCTAssertEqual(prescription.remedies[type], table[type], "\(type.rawValue) 快照与表一致")
        }
        XCTAssertNil(prescription.remedies[.tempo], "未命中类不进快照")
        // 确实落库
        XCTAssertEqual(try context.fetch(FetchDescriptor<CorrectionPrescription>()).count, 1)
    }

    @MainActor
    func testPrescribeIfNeededDoesNotDuplicateUnresolved() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let piece = makeCorrectionPiece()
        context.insert(piece)
        let analyses = [
            makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 100)),
            makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 200)),
        ]
        let first = try XCTUnwrap(
            CorrectionPrescriptionStore.prescribeIfNeeded(piece: piece, analyses: analyses, in: context))
        let second = CorrectionPrescriptionStore.prescribeIfNeeded(piece: piece, analyses: analyses, in: context)
        XCTAssertEqual(second?.entityId, first.entityId, "已有未结处方 → 返回既有，不重复创建")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CorrectionPrescription>()).count, 1)
    }

    @MainActor
    func testPrescribeIfNeededIgnoresResolvedOldPrescription() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let piece = makeCorrectionPiece()
        context.insert(piece)
        let analyses = [
            makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 100)),
            makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 200)),
        ]
        let old = try XCTUnwrap(
            CorrectionPrescriptionStore.prescribeIfNeeded(piece: piece, analyses: analyses, in: context))
        // 旧处方已结（如上次通过清零）→ 不阻断再次创建
        old.resolvedAt = Date()
        try context.save()
        let fresh = try XCTUnwrap(
            CorrectionPrescriptionStore.prescribeIfNeeded(piece: piece, analyses: analyses, in: context))
        XCTAssertNotEqual(fresh.entityId, old.entityId, "已结旧处方不影响新建判定")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CorrectionPrescription>()).count, 2)
    }

    @MainActor
    func testMarkCompletedIsIdempotent() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let prescription = CorrectionPrescription(pieceId: UUID(), book: "拜厄", number: 12)
        context.insert(prescription)
        try context.save()

        CorrectionPrescriptionStore.markCompleted(prescription, in: context)
        let first = try XCTUnwrap(prescription.completedAt, "首次标记 → completedAt 落值")
        CorrectionPrescriptionStore.markCompleted(prescription, in: context)
        XCTAssertEqual(prescription.completedAt, first, "幂等：已有 completedAt 不改写")
    }

    @MainActor
    func testResolveIfPassedOnlyOnEvaluablePass() throws {
        let context = ModelContext(try makeCorrectionContainer())
        let piece = makeCorrectionPiece()
        context.insert(piece)
        let prescription = CorrectionPrescription(pieceId: piece.entityId, book: "拜厄", number: 12)
        context.insert(prescription)
        try context.save()

        // 未通过（可评但不过）→ 不 resolve
        CorrectionPrescriptionStore.resolveIfPassed(
            piece: piece,
            latestAnalysis: makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 100),
                                                   passesHardMetrics: false),
            in: context)
        XCTAssertNil(prescription.resolvedAt)
        // 低置信通过 → 不 resolve（不算清零）
        CorrectionPrescriptionStore.resolveIfPassed(
            piece: piece,
            latestAnalysis: makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 200),
                                                   passesHardMetrics: true, confidence: 0.5),
            in: context)
        XCTAssertNil(prescription.resolvedAt)
        // 不可评通过 → 不 resolve
        CorrectionPrescriptionStore.resolveIfPassed(
            piece: piece,
            latestAnalysis: makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 300),
                                                   canEvaluate: false, passesHardMetrics: true),
            in: context)
        XCTAssertNil(prescription.resolvedAt)
        // 可评 + 高置信 + 通过硬指标 → resolve 落值
        CorrectionPrescriptionStore.resolveIfPassed(
            piece: piece,
            latestAnalysis: makeCorrectionAnalysis(analyzedAt: Date(timeIntervalSince1970: 400),
                                                   passesHardMetrics: true),
            in: context)
        XCTAssertNotNil(prescription.resolvedAt, "通过硬指标 → 处方清零")
        // latestAnalysis 为 nil → 不崩、无操作
        let another = makeCorrectionPiece(number: 13)
        context.insert(another)
        CorrectionPrescriptionStore.resolveIfPassed(piece: another, latestAnalysis: nil, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CorrectionPrescription>())
            .filter { $0.resolvedAt == nil }.count, 0)
    }

    @MainActor
    func testMakeSignalsPreservesNilScoresAndCorruptJSON() throws {
        // 六维 nil 原样保留（诚实），损坏 alignmentJSON → 空逐音不崩
        let corrupt = makeCorrectionAnalysis(
            analyzedAt: Date(timeIntervalSince1970: 100),
            hotspotMeasures: [1],
            alignmentJSON: "not-json{{",
            rhythmMedianMs: 88, avgBPM: 72, tempoTargetHit: true)
        let corruptSignals = CorrectionPrescriptionStore.makeSignals(
            from: corrupt, timingWindowMs: 120, maxRhythmMedianMs: 100, targetTempoRatio: 0.8)
        XCTAssertTrue(corruptSignals.alignedNotes.isEmpty, "坏 JSON → 空逐音，不得崩、不得编")
        XCTAssertNil(corruptSignals.pitchScore)
        XCTAssertNil(corruptSignals.rhythmScore)
        XCTAssertNil(corruptSignals.tempoScore)
        XCTAssertNil(corruptSignals.dynamicsScore)
        XCTAssertNil(corruptSignals.continuityScore)
        XCTAssertNil(corruptSignals.handsScore)
        XCTAssertEqual(corruptSignals.rhythmMedianMs, 88)
        XCTAssertEqual(corruptSignals.avgBPM, 72)
        XCTAssertEqual(corruptSignals.hotspotMeasures, [1])

        // 好的 alignmentJSON → 逐音还原；非 nil 分数原样透传
        let note = makeAlignedNote(cls: .wrongPitch, deltaMs: 150)
        let goodJSON = String(data: try JSONEncoder().encode([note]), encoding: .utf8)!
        let good = makeCorrectionAnalysis(
            analyzedAt: Date(timeIntervalSince1970: 200),
            alignmentJSON: goodJSON, pitchScore: 45, handsScore: 70,
            rhythmMedianMs: 66, avgBPM: 90, tempoTargetHit: false)
        let goodSignals = CorrectionPrescriptionStore.makeSignals(
            from: good, timingWindowMs: 80, maxRhythmMedianMs: 70, targetTempoRatio: 0.9)
        XCTAssertEqual(goodSignals.alignedNotes, [note], "逐音信号从 alignmentJSON 还原")
        XCTAssertEqual(goodSignals.pitchScore, 45)
        XCTAssertEqual(goodSignals.handsScore, 70)
        XCTAssertEqual(goodSignals.timingWindowMs, 80, "容差窗透传")
        XCTAssertEqual(goodSignals.maxRhythmMedianMs, 70)
        XCTAssertEqual(goodSignals.targetTempoRatio, 0.9)
    }

    // MARK: - G3 Stage B：initialLoopRange / initialTempoRatio / displayName

    func testInitialLoopRangeEmptyHotspotsCoversWholePiece() {
        // 空 hotspot = 整曲级 → (1, total)
        let range = CorrectionEngine.initialLoopRange(hotspots: [], totalMeasures: 20)
        XCTAssertEqual(range.start, 1)
        XCTAssertEqual(range.end, 20)
    }

    func testInitialLoopRangeSingleHotspotExtendsToNeighbor() {
        // 单热点钳制后保证 start < end（终点自然顶到相邻下一小节）
        let range = CorrectionEngine.initialLoopRange(hotspots: [0], totalMeasures: 20)
        XCTAssertEqual(range.start, 1)
        XCTAssertEqual(range.end, 2)
    }

    func testInitialLoopRangeUsesBoundingBoxOfHotspots() {
        // 非空 → min/max 0-based +1 转 1-based
        let range = CorrectionEngine.initialLoopRange(hotspots: [2, 5], totalMeasures: 20)
        XCTAssertEqual(range.start, 3)
        XCTAssertEqual(range.end, 6)
    }

    func testInitialLoopRangeOutOfBoundsClampsLegal() {
        // 越界 hotspot → 钳到合法且 start < end、end ≤ total
        let range = CorrectionEngine.initialLoopRange(hotspots: [18, 19], totalMeasures: 20)
        XCTAssertGreaterThanOrEqual(range.start, 1)
        XCTAssertLessThan(range.start, range.end)
        XCTAssertLessThanOrEqual(range.end, 20)
    }

    func testInitialLoopRangeDisjointHotspotsStillBoundingBox() {
        // 不连续热点 → 包围盒收（不聚类）
        let range = CorrectionEngine.initialLoopRange(hotspots: [0, 2, 5], totalMeasures: 20)
        XCTAssertEqual(range.start, 1)
        XCTAssertEqual(range.end, 6)
    }

    func testInitialLoopRangeZeroTotalDoesNotCrash() {
        // totalMeasures <= 0 → (1,1) 诚实兜底，不崩、不编区间
        let range = CorrectionEngine.initialLoopRange(hotspots: [0], totalMeasures: 0)
        XCTAssertEqual(range.start, 1)
        XCTAssertEqual(range.end, 1)
    }

    func testInitialTempoRatioEmptyIsOne() {
        // 空练习法 → 1.0（不降速）
        XCTAssertEqual(CorrectionEngine.initialTempoRatio([:]), 1.0)
    }

    func testInitialTempoRatioTakesMostConservative() throws {
        // 取最慢的那个（hands 0.6 < continuity 0.7 → 0.6）
        let table = CorrectionEngine.remedyTable()
        let remedies: [CorrectionErrorType: Remedy] = [
            .hands: try XCTUnwrap(table[.hands]),
            .continuity: try XCTUnwrap(table[.continuity]),
        ]
        XCTAssertEqual(CorrectionEngine.initialTempoRatio(remedies), 0.6)
    }

    func testInitialTempoRatioClampsToLegalBand() {
        // 病态极慢值夹在 0.3...1.0
        let slow = Remedy(tempoRatio: 0.1, separateHands: true, useMetronome: false, goal: "测试")
        XCTAssertEqual(CorrectionEngine.initialTempoRatio([.wrongPitch: slow]), 0.3)
        let fast = Remedy(tempoRatio: 1.5, separateHands: false, useMetronome: true, goal: "测试")
        XCTAssertEqual(CorrectionEngine.initialTempoRatio([.tempo: fast]), 1.0)
    }

    func testDisplayNameCoversAllEightTypes() {
        // 8 个 rawValue 全部能取到中文名、非空；逐类断言映射
        XCTAssertEqual(CorrectionErrorType.allCases.count, 8)
        XCTAssertEqual(CorrectionErrorType.wrongPitch.displayName, "错音")
        XCTAssertEqual(CorrectionErrorType.missing.displayName, "漏音")
        XCTAssertEqual(CorrectionErrorType.extra.displayName, "多弹")
        XCTAssertEqual(CorrectionErrorType.rhythm.displayName, "节奏偏差")
        XCTAssertEqual(CorrectionErrorType.tempo.displayName, "速度不足")
        XCTAssertEqual(CorrectionErrorType.dynamics.displayName, "力度")
        XCTAssertEqual(CorrectionErrorType.continuity.displayName, "连续性中断")
        XCTAssertEqual(CorrectionErrorType.hands.displayName, "双手配合")
        for type in CorrectionErrorType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type.rawValue) 展示名非空")
        }
    }

    // MARK: - G5 Stage A：奖励曲静态难度 / 三档定级 / 难点窗口 / 铺路选择（ADR-0006）

    /// 多 chord fixture：每小节给一组 chord（每 chord 一组 MIDI pitch），单 staff 单 voice
    private func makeChordScore(chordsPerMeasure: [[[Int]]]) -> Score {
        var measures: [Measure] = []
        for chords in chordsPerMeasure {
            var elements: [VoiceElement] = []
            for pitches in chords {
                let notes = pitches.map { Note(pitch: $0, tpc: 21) }
                elements.append(.chord(Chord(duration: .quarter, notes: ChordNotes(notes))))
            }
            measures.append(Measure(voices: [Voice(elements: elements)]))
        }
        let staff = Staff(defaultClefType: nil, measures: measures)
        let part = Part(id: "P1", instrument: Instrument(id: "piano"), staves: IdentifiedArray([staff]))
        return Score(division: 480,
                     parts: IdentifiedArray([part]),
                     systemMeasures: IdentifiedArray(Array(repeating: SystemMeasure(), count: chordsPerMeasure.count)))
    }

    /// 指定难度的 MeasureDifficulty（难点窗口测试用，绕开分量计算）
    private func makeMeasure(score: Double) -> RewardDifficulty.MeasureDifficulty {
        RewardDifficulty.MeasureDifficulty(blackKeyRatio: 0, density: 0,
                                           maxIntervalJump: 0, maxChordThickness: 0, score: score)
    }

    private func makePavingCandidate(title: String, difficulty: Double, baseline: Double,
                                     lastPavedAt: Date?) -> RewardDifficulty.PavingCandidate {
        RewardDifficulty.PavingCandidate(pieceId: UUID(), title: title, difficulty: difficulty,
                                         baseline: baseline, lastPavedAt: lastPavedAt)
    }

    private func makeRewardContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema([Piece.self, ScoreFile.self, RewardDifficultyAssessment.self, RewardPavingCard.self]),
            configurations: config
        )
    }

    private func makeImportedPiece(title: String = "导入曲", number: Int = 1) -> Piece {
        Piece(entityId: UUID(), title: title, book: "导入", number: number, totalMeasures: 8)
    }

    // isBlackKey：黑键集合 [1,3,6,8,10]（pitch class 口径，跨八度一致）

    func testIsBlackKeyBeginnerPitchClassRule() {
        XCTAssertFalse(RewardDifficulty.isBlackKey(60), "C4 白键")
        XCTAssertTrue(RewardDifficulty.isBlackKey(61), "C#4 黑键")
        XCTAssertFalse(RewardDifficulty.isBlackKey(62), "D4 白键")
        XCTAssertTrue(RewardDifficulty.isBlackKey(66), "F#4 黑键")
        XCTAssertTrue(RewardDifficulty.isBlackKey(70), "A#4 黑键")
        XCTAssertFalse(RewardDifficulty.isBlackKey(71), "B4 白键")
        XCTAssertTrue(RewardDifficulty.isBlackKey(73), "高八度 C#5 仍是黑键（pitch class 口径）")
        XCTAssertFalse(RewardDifficulty.isBlackKey(72), "C5 白键")
    }

    // extractChords：[measure][chord][pitch]，保留分组与出现序

    func testExtractChordsKeepsChordGroupingAndOrder() {
        let score = makeChordScore(chordsPerMeasure: [
            [[60], [64, 67, 71]],
            [[72]],
            [],
        ])
        let extracted = RewardDifficulty.extractChords(score: score)
        XCTAssertEqual(extracted.count, 3, "逐小节一层")
        XCTAssertEqual(extracted[0], [[60], [64, 67, 71]], "chord 分组与出现序保留（不去重）")
        XCTAssertEqual(extracted[1], [[72]])
        XCTAssertEqual(extracted[2], [], "空小节 = 空 chord 序列")
        for measure in extracted {
            for chord in measure {
                XCTAssertFalse(chord.isEmpty)
                for pitch in chord {
                    XCTAssertGreaterThanOrEqual(pitch, 0)
                    XCTAssertLessThanOrEqual(pitch, 127, "MIDI 0...127")
                }
            }
        }
        // 空谱（无 parts）→ 空，不崩
        XCTAssertTrue(RewardDifficulty.extractChords(score: Score(division: 480)).isEmpty)
    }

    // measureDifficulty：空/单音/跳度/厚度/黑键比例

    func testMeasureDifficultyEmptyIsAllZero() {
        let empty = RewardDifficulty.measureDifficulty([])
        XCTAssertEqual(empty.blackKeyRatio, 0)
        XCTAssertEqual(empty.density, 0)
        XCTAssertEqual(empty.maxIntervalJump, 0)
        XCTAssertEqual(empty.maxChordThickness, 0)
        XCTAssertEqual(empty.score, 0, "空小节全 0，不编")
        let allEmptyChords = RewardDifficulty.measureDifficulty([[], []])
        XCTAssertEqual(allEmptyChords.score, 0)
    }

    func testMeasureDifficultySingleNote() {
        let m = RewardDifficulty.measureDifficulty([[60]])
        XCTAssertEqual(m.density, 1)
        XCTAssertEqual(m.maxChordThickness, 1)
        XCTAssertEqual(m.maxIntervalJump, 0, "单音无跳")
        XCTAssertEqual(m.blackKeyRatio, 0)
        XCTAssertGreaterThan(m.score, 0)
    }

    func testMeasureDifficultyMelodyJumpAcrossChords() {
        let m = RewardDifficulty.measureDifficulty([[60], [72]])
        XCTAssertEqual(m.maxIntervalJump, 12, "相邻旋律音（chord 代表音）差 = 跳度")
        XCTAssertEqual(m.maxChordThickness, 1)
        XCTAssertEqual(m.density, 2)
    }

    func testMeasureDifficultyChordThicknessAndBlackKeyRatio() {
        let chord = RewardDifficulty.measureDifficulty([[60, 64, 67]])
        XCTAssertEqual(chord.maxChordThickness, 3, "同 chord 三音 = 厚度 3")
        XCTAssertEqual(chord.density, 3, "同时音计入密度")
        XCTAssertEqual(chord.maxIntervalJump, 0, "同一 chord 内不算跳")
        let black = RewardDifficulty.measureDifficulty([[61]])
        XCTAssertEqual(black.blackKeyRatio, 1, accuracy: 0.0001, "C# 单音 → 黑键占比 1")
        let mixed = RewardDifficulty.measureDifficulty([[60, 61]])
        XCTAssertEqual(mixed.blackKeyRatio, 0.5, accuracy: 0.0001)
    }

    // overallDifficulty：均值 + 峰值加权

    func testOverallDifficultyEmptyIsZero() {
        XCTAssertEqual(RewardDifficulty.overallDifficulty([]), 0, "空曲 → 0")
    }

    func testOverallDifficultyUniformMeasuresEqualsSingleMeasureScore() {
        let measures = Array(repeating: RewardDifficulty.measureDifficulty([[60], [67]]), count: 5)
        XCTAssertEqual(RewardDifficulty.overallDifficulty(measures), measures[0].score,
                       accuracy: 0.0001, "全相等小节 mean=max → 整体分 = 小节分（权重和为 1）")
    }

    func testOverallDifficultyWithPeakLiesBetweenMeanAndMax() {
        let low = RewardDifficulty.measureDifficulty([[60]])
        let high = RewardDifficulty.measureDifficulty([[55, 58, 62, 65, 69], [72], [84]])
        let measures = [low, low, low, high]
        let mean = measures.map(\.score).reduce(0, +) / Double(measures.count)
        let peak = measures.map(\.score).max() ?? 0
        let overall = RewardDifficulty.overallDifficulty(measures)
        XCTAssertGreaterThan(overall, mean, "峰值项使其高于纯均值")
        XCTAssertLessThan(overall, peak, "均值项使其低于纯峰值")
    }

    func testRewardDifficultyWeightsAndCapsAreSane() {
        // 分量权重和为 1（合成分仍是 0-1 口径）
        XCTAssertEqual(RewardDifficulty.wBlackKeyRatio + RewardDifficulty.wDensity
            + RewardDifficulty.wIntervalJump + RewardDifficulty.wChordThickness, 1.0, accuracy: 0.0001)
        XCTAssertEqual(RewardDifficulty.wMean + RewardDifficulty.wMax, 1.0, accuracy: 0.0001)
        XCTAssertLessThan(RewardDifficulty.kPlay, RewardDifficulty.kFar, "三档阈值有序")
        XCTAssertGreaterThan(RewardDifficulty.densityCap, 0)
        XCTAssertGreaterThan(RewardDifficulty.intervalCap, 0)
        XCTAssertGreaterThan(RewardDifficulty.chordThicknessCap, 0)
    }

    // hardestWindow：难点连续窗口（确定性）

    func testHardestWindowEmptyAndTooFewMeasures() {
        XCTAssertEqual(RewardDifficulty.hardestWindow([]), [], "空曲 → []")
        XCTAssertEqual(RewardDifficulty.hardestWindow([makeMeasure(score: 0.5)]), [0], "仅 1 小节 → 全部小节")
        // 2 小节：唯一合法窗口 [0,1]（长度钳制到实际小节数）
        let two = [makeMeasure(score: 0.1), makeMeasure(score: 0.9)]
        XCTAssertEqual(RewardDifficulty.hardestWindow(two), [0, 1])
    }

    func testHardestWindowPicksHighestContiguousSegment() {
        // 0.9+0.8 段：所有含它们的更大窗口分数都不更高 → [2,3]；同分取更短
        let scores: [Double] = [0.0, 0.0, 0.9, 0.8, 0.0, 0.0]
        let measures = scores.map { makeMeasure(score: $0) }
        XCTAssertEqual(RewardDifficulty.hardestWindow(measures), [2, 3])
        XCTAssertEqual(RewardDifficulty.hardestWindow(measures), RewardDifficulty.hardestWindow(measures),
                       "确定性：重复运行结果一致")
    }

    func testHardestWindowPrefersLongerWindowWhenSumWins() {
        // [1..4] 和 2.9 唯一最高（>任何 2/3 窗）→ 长度 4；index4=0.2 消除与 [0..3] 的对称平局
        let scores: [Double] = [0.1, 0.9, 0.9, 0.9, 0.2, 0.1]
        XCTAssertEqual(RewardDifficulty.hardestWindow(scores.map { makeMeasure(score: $0) }), [1, 2, 3, 4])
    }

    func testHardestWindowTieBreaksShorterThenEarlier() {
        // 所有窗口和同为 1.0 → 严格 > 才替换 → 首个发现者（最短、起点最靠前）[0,1]
        let scores: [Double] = [0.5, 0.5, 0.0, 0.0, 0.5, 0.5]
        XCTAssertEqual(RewardDifficulty.hardestWindow(scores.map { makeMeasure(score: $0) }), [0, 1])
        // 固定窗长 2：同和取起点更靠前
        let two = [0.0, 0.4, 0.4, 0.0, 0.4, 0.4]
        XCTAssertEqual(RewardDifficulty.hardestWindow(two.map { makeMeasure(score: $0) },
                                                      minSize: 2, maxSize: 2), [1, 2])
    }

    // grade：三档边界（≤）

    func testGradeBoundariesRelativeToBaseline() {
        XCTAssertEqual(RewardDifficulty.grade(difficulty: 100, baseline: 100), .play)
        XCTAssertEqual(RewardDifficulty.grade(difficulty: 115, baseline: 100), .play, "边界等值归属用 ≤ kPlay")
        XCTAssertEqual(RewardDifficulty.grade(difficulty: 116, baseline: 100), .stretch)
        XCTAssertEqual(RewardDifficulty.grade(difficulty: 180, baseline: 100), .stretch, "边界等值归属用 ≤ kFar")
        XCTAssertEqual(RewardDifficulty.grade(difficulty: 181, baseline: 100), .far)
        XCTAssertNil(RewardDifficulty.grade(difficulty: 50, baseline: 0), "baseline=0 无法相对定级 → nil")
        XCTAssertNil(RewardDifficulty.grade(difficulty: 50, baseline: -1), "负基准同样无法定级")
    }

    // baselineScore：当前条目谱取较高者

    func testBaselineScoreBothNilIsZero() {
        XCTAssertEqual(RewardDifficulty.baselineScore(currentBeyerScore: nil, currentHanonScore: nil), 0)
    }

    func testBaselineScoreTakesHigherOfCurrentEntries() {
        let easy = makeChordScore(chordsPerMeasure: [[[60]], [[61]]])
        let hard = makeChordScore(chordsPerMeasure: [[[60, 64, 67]], [[72, 76, 79]], [[55, 59, 62, 66]]])
        func overall(of score: Score) -> Double {
            RewardDifficulty.overallDifficulty(
                RewardDifficulty.extractChords(score: score).map { RewardDifficulty.measureDifficulty($0) })
        }
        XCTAssertEqual(RewardDifficulty.baselineScore(currentBeyerScore: easy, currentHanonScore: nil),
                       overall(of: easy), accuracy: 0.0001, "单边 → 该条目分")
        XCTAssertEqual(RewardDifficulty.baselineScore(currentBeyerScore: easy, currentHanonScore: hard),
                       overall(of: hard), accuracy: 0.0001, "取较高者（当下上限）")
        XCTAssertEqual(RewardDifficulty.baselineScore(currentBeyerScore: hard, currentHanonScore: easy),
                       overall(of: hard), accuracy: 0.0001, "与传入顺序无关")
    }

    // pickDailyPaving：每日 1 条铺路选择（确定性）

    func testPickDailyPavingEmptyOrNoStretchReturnsNil() {
        XCTAssertNil(RewardDifficulty.pickDailyPaving([]), "空 → nil")
        let far = makePavingCandidate(title: "远超", difficulty: 500, baseline: 100, lastPavedAt: nil)
        let play = makePavingCandidate(title: "能弹", difficulty: 90, baseline: 100, lastPavedAt: nil)
        XCTAssertNil(RewardDifficulty.pickDailyPaving([far, play]), "仅 stretch 档进入候选（决策七）")
    }

    func testPickDailyPavingRanksByExceedRatioThenLastPavedThenTitle() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // 超出基准比例降序：1.6 > 1.4 > 1.25（均在 stretch 带内）
        let lowRatio = makePavingCandidate(title: "甲", difficulty: 125, baseline: 100, lastPavedAt: nil)
        let highRatio = makePavingCandidate(title: "乙", difficulty: 160, baseline: 100, lastPavedAt: base)
        let mid = makePavingCandidate(title: "丙", difficulty: 140, baseline: 100, lastPavedAt: base)
        XCTAssertEqual(RewardDifficulty.pickDailyPaving([lowRatio, highRatio, mid])?.pieceId,
                       highRatio.pieceId, "超出基准比例最高者优先")
        // 同比例：从未铺路（nil）排最前；同为 nil → title 升序（确定性，禁随机）。
        // 用 ASCII 标题：原生 String 比较是 Unicode 码位序，ASCII 才能跨 locale 确定地表达升序。
        let neverA = makePavingCandidate(title: "A", difficulty: 150, baseline: 100, lastPavedAt: nil)
        let neverB = makePavingCandidate(title: "B", difficulty: 150, baseline: 100, lastPavedAt: nil)
        let paved = makePavingCandidate(title: "C", difficulty: 150, baseline: 100, lastPavedAt: base)
        let pick = RewardDifficulty.pickDailyPaving([paved, neverB, neverA])
        XCTAssertEqual(pick?.title, "A", "从未铺路优先，再按 title 升序 tie-break")
        XCTAssertEqual(RewardDifficulty.pickDailyPaving([paved, neverB, neverA])?.title, pick?.title,
                       "确定性：重复运行结果一致")
        // 同比例、都有铺路时间 → lastPavedAt 更早者优先
        let older = makePavingCandidate(title: "A", difficulty: 150, baseline: 100,
                                        lastPavedAt: base.addingTimeInterval(-100))
        let newer = makePavingCandidate(title: "B", difficulty: 150, baseline: 100, lastPavedAt: base)
        XCTAssertEqual(RewardDifficulty.pickDailyPaving([newer, older])?.title, "A", "最久未铺路优先")
        // 当天已有未完成卡（调用方传入排除集）的 piece 不选
        XCTAssertEqual(
            RewardDifficulty.pickDailyPaving([highRatio, lowRatio],
                                             excludedPieceIds: [highRatio.pieceId])?.pieceId,
            lowRatio.pieceId, "被排除的 piece 跳过，取次优")
        // 全部被排除 → nil
        XCTAssertNil(RewardDifficulty.pickDailyPaving([highRatio], excludedPieceIds: [highRatio.pieceId]))
    }

    // @MainActor 涉库：assessAndUpsert 幂等 upsert / 当天去重 / 完成幂等 / 升档关闭

    @MainActor
    func testAssessAndUpsertUpsertsOncePerPieceAndSkipsWhenBaselineMissing() throws {
        let context = ModelContext(try makeRewardContainer())
        let piece = makeImportedPiece()
        piece.sourceScoreId = UUID()
        context.insert(piece)
        let beyer = makeChordScore(chordsPerMeasure: [[[60]], [[61]]])
        // 导入曲明显难于基准（5 键厚和弦 + 十二度大跳）→ stretch
        let importHard = makeChordScore(chordsPerMeasure: [
            [[55, 58, 62, 65, 69]],
            [[72], [84]],
        ])
        let first = try XCTUnwrap(RewardPavingStore.assessAndUpsert(
            piece: piece, score: importHard, currentBeyerScore: beyer, currentHanonScore: nil, in: context))
        XCTAssertEqual(first.pieceId, piece.entityId)
        XCTAssertEqual(first.grade, .stretch, "厚和弦+大跳导入曲相对单音基准 → 偏难")
        XCTAssertEqual(first.scoreFileId, piece.sourceScoreId)
        XCTAssertEqual(first.engineVersion, RewardDifficulty.engineVersion)
        XCTAssertEqual(first.difficultyScore,
                       RewardDifficulty.overallDifficulty(
                           RewardDifficulty.extractChords(score: importHard).map { RewardDifficulty.measureDifficulty($0) }),
                       accuracy: 0.0001, "difficultyScore 与纯函数同源")
        XCTAssertEqual(first.baselineScore,
                       RewardDifficulty.baselineScore(currentBeyerScore: beyer, currentHanonScore: nil),
                       accuracy: 0.0001)
        XCTAssertNotNil(first.reasons, "有可陈述技术点 → 简述非空")

        // 重新评估（谱变简单 → play）→ 更新同一条，不新增（幂等 upsert）
        let importEasy = makeChordScore(chordsPerMeasure: [[[60]]])
        let second = try XCTUnwrap(RewardPavingStore.assessAndUpsert(
            piece: piece, score: importEasy, currentBeyerScore: beyer, currentHanonScore: nil, in: context))
        XCTAssertEqual(second.entityId, first.entityId, "同 piece upsert 更新而非新增")
        XCTAssertEqual(second.grade, .play)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardDifficultyAssessment>()).count, 1)

        // baseline 缺失（当前条目谱都拿不到）→ nil 且不落库（诚实，不编档位）
        let other = makeImportedPiece(title: "无基准")
        context.insert(other)
        XCTAssertNil(RewardPavingStore.assessAndUpsert(
            piece: other, score: importEasy, currentBeyerScore: nil, currentHanonScore: nil, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardDifficultyAssessment>()).count, 1,
                       "无法定级不落库")
    }

    @MainActor
    func testRewardAssessmentGradeRawDecodesAndCorruptIsNil() throws {
        let context = ModelContext(try makeRewardContainer())
        let assessment = RewardDifficultyAssessment(pieceId: UUID(), gradeRaw: "stretch",
                                                    difficultyScore: 1.2, baselineScore: 1.0)
        context.insert(assessment)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<RewardDifficultyAssessment>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.grade, .stretch, "rawValue 还原三档")
        let fetchedScore = try XCTUnwrap(fetched.first?.difficultyScore)
        XCTAssertEqual(fetchedScore, 1.2, accuracy: 0.0001)
        XCTAssertNil(RewardDifficultyAssessment(pieceId: UUID(), gradeRaw: "nonsense").grade,
                     "坏 rawValue → nil，不崩")
    }

    @MainActor
    func testUpsertDailyPavingDeduplicatesWithinDay() throws {
        let context = ModelContext(try makeRewardContainer())
        let piece = makeImportedPiece()
        context.insert(piece)
        // candidate.pieceId 必须绑定 piece.entityId（实现据此关联卡与曲目）
        let candidate = RewardDifficulty.PavingCandidate(
            pieceId: piece.entityId, title: piece.title, difficulty: 150, baseline: 100, lastPavedAt: nil)
        // 正午时刻（2025-06-15 12:00 +0800）：+3600 不跨当地午夜，+86400 确定是次日
        let now = Date(timeIntervalSince1970: 1_749_960_000)
        let first = try XCTUnwrap(RewardPavingStore.upsertDailyPaving(
            for: candidate, piece: piece, hotspots: [2, 3], in: context, now: now))
        XCTAssertEqual(first.pieceId, piece.entityId)
        XCTAssertEqual(first.book, "导入")
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(first.hotspotMeasures, [2, 3], "难点小节快照落卡（0-based）")
        XCTAssertEqual(first.prescribedAt, now)
        XCTAssertNil(first.completedAt, "默认未完成")
        XCTAssertNil(first.closedAt, "默认未结")
        // 当天再来 → 返回既有（当天去重；含已完成但未关闭的情形）
        let second = RewardPavingStore.upsertDailyPaving(
            for: candidate, piece: piece, hotspots: [2, 3], in: context, now: now.addingTimeInterval(3_600))
        XCTAssertEqual(second?.entityId, first.entityId)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardPavingCard>()).count, 1)
        // 次日（昨日卡未结不阻断新一天）→ 新卡
        let nextDay = RewardPavingStore.upsertDailyPaving(
            for: candidate, piece: piece, hotspots: [2, 3], in: context, now: now.addingTimeInterval(86_400))
        XCTAssertNotEqual(nextDay?.entityId, first.entityId)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardPavingCard>()).count, 2)
    }

    @MainActor
    func testMarkPavingCompletedIsIdempotent() throws {
        let context = ModelContext(try makeRewardContainer())
        let card = RewardPavingCard(pieceId: UUID(), book: "导入", number: 1,
                                    hotspotMeasures: [0, 1], prescribedAt: Date())
        context.insert(card)
        try context.save()
        RewardPavingStore.markPavingCompleted(card, in: context)
        let first = try XCTUnwrap(card.completedAt, "首次标记 → completedAt 落值")
        RewardPavingStore.markPavingCompleted(card, in: context)
        XCTAssertEqual(card.completedAt, first, "幂等：已有 completedAt 不改写")
    }

    @MainActor
    func testCloseIfGradedClosesOnlyOnPlay() throws {
        let context = ModelContext(try makeRewardContainer())
        let pieceId = UUID()
        let card = RewardPavingCard(pieceId: pieceId, book: "导入", number: 1, hotspotMeasures: [2, 3])
        context.insert(card)
        try context.save()
        // stretch / far / nil（暂无法分析）都不动卡状态
        RewardPavingStore.closeIfGraded(pieceId: pieceId, latestGrade: .stretch, in: context)
        XCTAssertNil(card.closedAt)
        RewardPavingStore.closeIfGraded(pieceId: pieceId, latestGrade: .far, in: context)
        XCTAssertNil(card.closedAt)
        RewardPavingStore.closeIfGraded(pieceId: pieceId, latestGrade: nil, in: context)
        XCTAssertNil(card.closedAt)
        // 升到 play → 关闭（决策八）
        RewardPavingStore.closeIfGraded(pieceId: pieceId, latestGrade: .play, in: context)
        XCTAssertNotNil(card.closedAt)
    }

    // MARK: - G5 Stage B 展示决策：RewardPavingDisplay（ADR-0006 决策二/八）

    /// 正午基准（2025-06-15 12:00 +0800 = epoch 1749960000）：±86400 仍是当地正午，不跨午夜
    private let g5Noon = Date(timeIntervalSince1970: 1_749_960_000)

    private func makePavingCard(pieceId: UUID = UUID(), prescribedAt: Date,
                                completedAt: Date? = nil, closedAt: Date? = nil) -> RewardPavingCard {
        RewardPavingCard(pieceId: pieceId, book: "导入", number: 1,
                         hotspotMeasures: [2, 3], prescribedAt: prescribedAt,
                         completedAt: completedAt, closedAt: closedAt)
    }

    @MainActor
    func testTodayCardFiltersByCompletionClosureAndDay() {
        // 当天未关闭未完成 → 返回
        let active = makePavingCard(prescribedAt: g5Noon)
        XCTAssertEqual(RewardPavingDisplay.todayCard([active], now: g5Noon)?.entityId, active.entityId)
        // 当天已完成（completedAt）→ nil，当天不重复催（决策八）
        let completed = makePavingCard(prescribedAt: g5Noon, completedAt: g5Noon.addingTimeInterval(3_600))
        XCTAssertNil(RewardPavingDisplay.todayCard([completed], now: g5Noon))
        // 当天已关闭（closedAt）→ nil（升档关闭后消失）
        let closed = makePavingCard(prescribedAt: g5Noon, closedAt: g5Noon.addingTimeInterval(3_600))
        XCTAssertNil(RewardPavingDisplay.todayCard([closed], now: g5Noon))
        // prescribedAt 是昨天 → nil（跨天不残留）
        let yesterday = makePavingCard(prescribedAt: g5Noon.addingTimeInterval(-86_400))
        XCTAssertNil(RewardPavingDisplay.todayCard([yesterday], now: g5Noon))
        // 空卡列表 → nil
        XCTAssertNil(RewardPavingDisplay.todayCard([], now: g5Noon))
    }

    @MainActor
    func testTodayCardWithMultipleSameDayCardsReturnsDeterministically() {
        let first = makePavingCard(prescribedAt: g5Noon)
        let second = makePavingCard(prescribedAt: g5Noon.addingTimeInterval(3_600))
        let third = makePavingCard(prescribedAt: g5Noon.addingTimeInterval(7_200))
        let picked = RewardPavingDisplay.todayCard([first, second, third], now: g5Noon)
        XCTAssertNotNil(picked, "多张当天卡 → 返回其中一张不崩")
        // 确定性：同输入两次调用结果一致（todayCard 无随机）
        XCTAssertEqual(RewardPavingDisplay.todayCard([first, second, third], now: g5Noon)?.entityId,
                       picked?.entityId)
        // 实现口径：first 命中（prescribedAt 最晚的当天卡不参与筛选排序）
        XCTAssertEqual(picked?.entityId, first.entityId)
    }

    @MainActor
    func testGradeLabelCoversThreeGrades() {
        XCTAssertEqual(RewardPavingDisplay.gradeLabel(.play), "现在能弹")
        XCTAssertEqual(RewardPavingDisplay.gradeLabel(.stretch), "偏难")
        XCTAssertEqual(RewardPavingDisplay.gradeLabel(.far), "远超当前")
    }

    @MainActor
    func testGradeLabelNilIsHonestUnavailable() {
        XCTAssertEqual(RewardPavingDisplay.gradeLabel(nil), "暂无法分析",
                       "无评估/无法相对定级 → 诚实展示，不编档位（决策一/四）")
    }

    // MARK: G8 连续达标周（weeklyGoalStreak；ADR-0007）

    /// GMT+8、周一起始的固定日历（跨时区/无 DST，确定性）
    private var g8Calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    /// 固定 today = 某周六 12:00（Asia/Shanghai）；上一个完整周 = weekOffset -1
    private var g8Today: Date {
        let c = g8Calendar
        let weekStart = c.dateInterval(of: .weekOfYear,
                                       for: Date(timeIntervalSince1970: 1_760_000_000))!.start
        return c.date(byAdding: .hour, value: 5 * 24 + 12, to: weekStart)!
    }

    /// 相对固定 today 所在周起点的第 weekOffset 周、第 dayIndex（周一=0）天 hour 点
    private func g8Date(weekOffset: Int, dayIndex: Int, hour: Int = 10) -> Date {
        let c = g8Calendar
        let weekStart = c.dateInterval(of: .weekOfYear, for: g8Today)!.start
        let day = c.date(byAdding: .day, value: weekOffset * 7 + dayIndex, to: weekStart)!
        return c.date(byAdding: .hour, value: hour, to: day)!
    }

    /// 指定周/日的 midi take（分钟数）
    private func g8Take(weekOffset: Int, dayIndex: Int, minutes: Int, hasMidi: Bool = true) -> Take {
        Take(startedAt: g8Date(weekOffset: weekOffset, dayIndex: dayIndex),
             durationSec: minutes * 60, hasMidi: hasMidi)
    }

    /// 某完整周内 weeklyGoal 个不同有效日（每天一个 minutes 分钟的 midi take，周一/二/三）
    private func g8QualifyingWeek(_ weekOffset: Int, goal: Int = 3, minutes: Int = 20) -> [Take] {
        (0..<goal).map { g8Take(weekOffset: weekOffset, dayIndex: $0, minutes: minutes) }
    }

    private func g8Streak(_ takes: [Take], goal: Int = 3) -> TodayPlanService.WeeklyGoalStreak {
        TodayPlanService.weeklyGoalStreak(takes: takes, weeklyGoal: goal, today: g8Today,
                                          calendar: g8Calendar)
    }

    func testWeeklyGoalStreakNoTakesOrNoCompletedWeekReturnsZero() {
        XCTAssertEqual(g8Streak([]).currentConsecutiveWeeks, 0)
        XCTAssertEqual(g8Streak([]).longestWeeks, 0)
        // 只有本周（未结束完整周）的 take → 不计入，(0,0)
        let onlyThisWeek = g8QualifyingWeek(0)
        XCTAssertEqual(g8Streak(onlyThisWeek).currentConsecutiveWeeks, 0)
        XCTAssertEqual(g8Streak(onlyThisWeek).longestWeeks, 0)
    }

    func testWeeklyGoalStreakSingleQualifyingWeek() {
        // 仅上一个完整周达标（3 个不同有效日，各 20 分钟 midi take）
        let result = g8Streak(g8QualifyingWeek(-1))
        XCTAssertEqual(result.currentConsecutiveWeeks, 1)
        XCTAssertEqual(result.longestWeeks, 1)
    }

    func testWeeklyGoalStreakThreeConsecutiveWeeks() {
        let takes = g8QualifyingWeek(-3) + g8QualifyingWeek(-2) + g8QualifyingWeek(-1)
        let result = g8Streak(takes)
        XCTAssertEqual(result.currentConsecutiveWeeks, 3)
        XCTAssertEqual(result.longestWeeks, 3)
    }

    func testWeeklyGoalStreakGapResetsCurrentButKeepsLongest() {
        // 缺口前连续 3 个达标周（体现 longest=3 保留）→ 一个完全无 take 的缺口周 → 再达标 1 周
        // （brief 原文「达标 2 周→缺口→再达标 1 周」在该布局下 longest 只能是 2；
        //   (current 1, longest 3) 只有缺口前连续 3 周才能成立，与 ADR「longest 保留 3」一致）
        let takes = g8QualifyingWeek(-5) + g8QualifyingWeek(-4) + g8QualifyingWeek(-3)
            + g8QualifyingWeek(-1)
        let result = g8Streak(takes)
        XCTAssertEqual(result.currentConsecutiveWeeks, 1, "缺口周归零，只保留缺口后 1 周")
        XCTAssertEqual(result.longestWeeks, 3, "归零不抹除历史最长")
    }

    func testWeeklyGoalStreakLastCompletedWeekFailedGivesCurrentZero() {
        // 上一个完整周未达标（只有无 midi / 不足 10 分钟的 take），再往前连续达标 3 周
        let takes = g8QualifyingWeek(-4) + g8QualifyingWeek(-3) + g8QualifyingWeek(-2) + [
            g8Take(weekOffset: -1, dayIndex: 0, minutes: 60, hasMidi: false),
            g8Take(weekOffset: -1, dayIndex: 1, minutes: 9),
        ]
        let result = g8Streak(takes)
        XCTAssertEqual(result.currentConsecutiveWeeks, 0, "最后完整周未达标 → 连续数归零")
        XCTAssertEqual(result.longestWeeks, 3)
    }

    func testWeeklyGoalStreakCurrentWeekNotCounted() {
        // 本周已达标（3 个有效日）但无更早 take → 本周不计入，(0,0)
        let takes = g8QualifyingWeek(0)
        let result = g8Streak(takes)
        XCTAssertEqual(result.currentConsecutiveWeeks, 0)
        XCTAssertEqual(result.longestWeeks, 0)
    }

    func testWeeklyGoalStreakExactBoundariesCount() {
        // 每天累计恰好 600 秒（=10 分钟）算有效日；有效日恰好等于 weeklyGoal 算达标
        let takes = (0..<3).map { g8Take(weekOffset: -1, dayIndex: $0, minutes: 10) }
        let result = g8Streak(takes)
        XCTAssertEqual(result.currentConsecutiveWeeks, 1, "600 秒/天 × 3 天 = 恰好达标")
        XCTAssertEqual(result.longestWeeks, 1)
    }

    func testWeeklyGoalStreakAggregatesByDayNotByTake() {
        // 同一天多个 take 各 <600 秒、累计 ≥600 → 当天有效（按天聚合而非按 take）
        let takes = (0..<3).flatMap { day in
            [g8Take(weekOffset: -1, dayIndex: day, minutes: 5),
             g8Take(weekOffset: -1, dayIndex: day, minutes: 5)]
        }
        let result = g8Streak(takes)
        XCTAssertEqual(result.currentConsecutiveWeeks, 1, "3 天各 5+5 分钟聚合达标；按 take 算则全无效")
        XCTAssertEqual(result.longestWeeks, 1)
    }

    func testWeeklyGoalStreakIgnoresNoMidiAndShortTakes() {
        // hasMidi=false 的 60 分钟长 take 不计入；hasMidi 但 <600 秒不点亮该天
        let qualifyingBefore = g8QualifyingWeek(-2)
        let invalidLast = [
            g8Take(weekOffset: -1, dayIndex: 0, minutes: 60, hasMidi: false),
            g8Take(weekOffset: -1, dayIndex: 2, minutes: 9),
        ]
        let result = g8Streak(qualifyingBefore + invalidLast)
        XCTAssertEqual(result.currentConsecutiveWeeks, 0, "无效 take 不延续连续")
        XCTAssertEqual(result.longestWeeks, 1, "有效只来自 -2 周")
    }

    // MARK: G6 听音辨音程 — 解锁 / 出题 / 判定 / 留痕 / 趋势（ADR-0008 Stage A）

    /// 测试用确定性随机源（简单 LCG，Numerical Recipes 常数）；同种子 → 同序列
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func makeEarContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: EarTrainingRound.self, configurations: config)
    }

    // 解锁：边界严格按 ≤30 / 31...60 / >60

    func testIntervalUnlockZeroAndBoundary30AreEntryTier() {
        XCTAssertEqual(IntervalUnlock.allowedSemitones(currentBeyer: 0), [2, 3, 4, 7, 12], "无进度（0）归入门档")
        XCTAssertEqual(IntervalUnlock.allowedSemitones(currentBeyer: 30), [2, 3, 4, 7, 12], "30 归入门")
    }

    func testIntervalUnlockBoundary31And60AreAdvancedTier() {
        let advanced = Set([2, 3, 4, 7, 12]).union([1, 5, 9, 10])
        XCTAssertEqual(IntervalUnlock.allowedSemitones(currentBeyer: 31), advanced, "31 进阶")
        XCTAssertEqual(IntervalUnlock.allowedSemitones(currentBeyer: 60), advanced, "60 仍进阶")
    }

    func testIntervalUnlockBoundary61AndBeyondAreFullTier() {
        XCTAssertEqual(IntervalUnlock.allowedSemitones(currentBeyer: 61), Set(1...12), "61 全开")
        XCTAssertEqual(IntervalUnlock.allowedSemitones(currentBeyer: 100), Set(1...12))
    }

    func testIntervalUnlockTiersUnionCoversAllTwelveAndEntryCountFive() {
        let entry = IntervalUnlock.allowedSemitones(currentBeyer: 30)
        let advanced = IntervalUnlock.allowedSemitones(currentBeyer: 60)
        let full = IntervalUnlock.allowedSemitones(currentBeyer: 61)
        XCTAssertEqual(entry.count, 5, "入门档 5 个（最早档 ≥4，出题前置条件恒满足）")
        XCTAssertEqual(entry.union(advanced).union(full), Set(1...12), "三档并集恰为 1...12")
        XCTAssertTrue(advanced.isSuperset(of: entry), "进阶包含入门")
        XCTAssertTrue(full.isSuperset(of: advanced), "后期包含进阶")
    }

    // displayName：中文按字面比较，不假设拼音序

    func testIntervalIDDisplayNamesPinned() {
        XCTAssertEqual(IntervalID(rawValue: 1)?.displayName, "小二度")
        XCTAssertEqual(IntervalID(rawValue: 4)?.displayName, "大三度")
        XCTAssertEqual(IntervalID(rawValue: 6)?.displayName, "三全音", "增四/减五统一单标签三全音（ADR-0008 §7）")
        XCTAssertEqual(IntervalID(rawValue: 7)?.displayName, "纯五度")
        XCTAssertEqual(IntervalID(rawValue: 12)?.displayName, "纯八度")
    }

    func testIntervalIDDisplayNameNonEmptyForAllCases() {
        var names: Set<String> = []
        for interval in IntervalID.allCases {
            XCTAssertFalse(interval.displayName.isEmpty, "rawValue \(interval.rawValue) 名称不得为空")
            names.insert(interval.displayName)
        }
        XCTAssertEqual(names.count, IntervalID.allCases.count, "12 个半音数标签互异（半音数 6 单标签）")
    }

    // 出题：不变量逐题钉

    func testIntervalQuizInvariantsAcrossSeedsAndTiers() {
        let tiers: [Set<Int>] = [
            [2, 3, 4, 7, 12],
            [1, 2, 3, 4, 5, 7, 9, 10, 12],
            Set(1...12),
        ]
        for allowed in tiers {
            for seed in [1, 42, 2026] {
                var gen = SeededGenerator(seed: UInt64(seed))
                for _ in 0..<30 {
                    let q = IntervalQuiz.makeQuestion(allowed: allowed, using: &gen)
                    XCTAssertTrue(IntervalQuiz.rootRange.contains(q.rootMIDINote), "root ∈ [55,67]，实得 \(q.rootMIDINote)")
                    XCTAssertTrue(allowed.contains(q.answerSemitones), "answer ∈ allowed")
                    XCTAssertEqual(q.topMIDINote, q.rootMIDINote + q.answerSemitones)
                    XCTAssertLessThanOrEqual(q.topMIDINote, 79, "冠音 ≤ 79（root ≤67 + 12）")
                    XCTAssertEqual(q.options.count, 4)
                    XCTAssertEqual(q.options.filter { $0 == q.answerSemitones }.count, 1, "正确项恰出现一次")
                    let distractors = q.options.filter { $0 != q.answerSemitones }
                    XCTAssertEqual(distractors.count, 3, "3 个干扰项")
                    XCTAssertEqual(Set(distractors).count, 3, "干扰项互异（半音数互异即标签互异）")
                    for d in distractors {
                        XCTAssertTrue(allowed.contains(d), "干扰项 ∈ allowed")
                    }
                    XCTAssertEqual(Set(q.options).count, 4, "4 选项整体互异")
                }
            }
        }
    }

    func testIntervalQuizEntryTierOptionsAllFromUnlockedFive() {
        let entry: Set<Int> = [2, 3, 4, 7, 12]
        var gen = SeededGenerator(seed: 7)
        for _ in 0..<50 {
            let q = IntervalQuiz.makeQuestion(allowed: entry, using: &gen)
            for option in q.options {
                XCTAssertTrue(entry.contains(option), "入门档 4 选项必须全部来自这 5 个，实得 \(option)")
            }
        }
    }

    func testIntervalQuizDeterministicSameSeed() {
        let allowed: Set<Int> = [2, 3, 4, 7, 12]
        var genA = SeededGenerator(seed: 99)
        var genB = SeededGenerator(seed: 99)
        let seqA = (0..<10).map { _ in IntervalQuiz.makeQuestion(allowed: allowed, using: &genA) }
        let seqB = (0..<10).map { _ in IntervalQuiz.makeQuestion(allowed: allowed, using: &genB) }
        XCTAssertEqual(seqA, seqB, "同种子两次各出 10 题，序列完全相等")
    }

    func testIntervalQuizRootRangePinned() {
        XCTAssertEqual(IntervalQuiz.rootRange, 55...67, "根音窗口 G3~G4，保证冠音 ≤79")
    }

    // 判定

    func testIntervalJudgingCorrectOnExactAnswer() {
        let q = IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12])
        XCTAssertTrue(IntervalJudging.isCorrect(selected: 7, question: q))
    }

    func testIntervalJudgingWrongIncludesAdjacentSemitone() {
        let q = IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12])
        for wrong in [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12] where wrong != 7 {
            XCTAssertFalse(IntervalJudging.isCorrect(selected: wrong, question: q),
                           "选相邻半音 \(wrong) 也必须判错")
        }
    }

    // 留痕：store 写库

    @MainActor
    func testEarTrainingStoreSaveHitRateAndDefaultKind() throws {
        let context = ModelContext(try makeEarContainer())
        let round = EarTrainingStore.save(correct: 7, total: 10, in: context)
        XCTAssertEqual(round.kind, "interval", "默认题型 interval")
        XCTAssertEqual(round.correctCount, 7)
        XCTAssertEqual(round.totalCount, 10)
        XCTAssertEqual(round.hitRate ?? -1, 0.7, accuracy: 0.0001, "hitRate = correct/total 真实比值（带容差）")

        let all = try context.fetch(FetchDescriptor<EarTrainingRound>())
        XCTAssertEqual(all.count, 1)
    }

    @MainActor
    func testEarTrainingStoreSaveZeroTotalHonestNil() throws {
        let context = ModelContext(try makeEarContainer())
        let round = EarTrainingStore.save(correct: 0, total: 0, in: context)
        XCTAssertNil(round.hitRate, "total==0 → hitRate 必须为 nil，禁止编造")
    }

    func testEarTrainingRoundSwiftDataRoundTrip() throws {
        let context = ModelContext(try makeEarContainer())
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let round = EarTrainingRound(kind: "interval", correctCount: 8, totalCount: 10,
                                     hitRate: 0.8, createdAt: createdAt)
        context.insert(round)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<EarTrainingRound>())
        XCTAssertEqual(fetched.count, 1)
        let r = try XCTUnwrap(fetched.first)
        XCTAssertEqual(r.kind, "interval")
        XCTAssertEqual(r.correctCount, 8)
        XCTAssertEqual(r.totalCount, 10)
        XCTAssertEqual(r.hitRate ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(r.createdAt, createdAt)
    }

    // 趋势：口径照抄 SightReadTrend（最近 N、升序、<3 样本 mean=nil），按 kind 过滤

    func testEarTrainingTrendAscendingMeanAndRecent20() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var rounds: [EarTrainingRound] = []
        // 25 条 interval 轮次（hitRate = i/100，时序递增），最近 20 条 = i=5...24
        for i in 0..<25 {
            rounds.append(EarTrainingRound(correctCount: i, totalCount: 10,
                                           hitRate: Double(i) / 100.0,
                                           createdAt: base.addingTimeInterval(Double(i))))
        }
        let summary = EarTrainingTrend.summarize(rounds: rounds)
        XCTAssertEqual(summary.totalCount, 20, "只取最近 20 轮")
        XCTAssertEqual(summary.hitRates.count, 20)
        XCTAssertEqual(summary.hitRates.first ?? -1, 0.05, accuracy: 0.0001, "时间升序（窗口内最早 i=5 在左）")
        XCTAssertEqual(summary.hitRates.last ?? -1, 0.24, accuracy: 0.0001, "最新 i=24 在右")
        XCTAssertEqual(summary.mean ?? -1, (0.05 + 0.24) / 2, accuracy: 0.0001,
                       "20 个等差样本 0.05...0.24 → 均值 = 首尾平均")

        // 有效样本 < 3 → 均值 nil（诚实留白）
        let sparse = EarTrainingTrend.summarize(rounds: Array(rounds.prefix(2)))
        XCTAssertNil(sparse.mean)
        XCTAssertEqual(sparse.totalCount, 2)
        XCTAssertEqual(sparse.hitRates.count, 2)
    }

    func testEarTrainingTrendFiltersByKind() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var rounds: [EarTrainingRound] = []
        for i in 0..<3 {
            rounds.append(EarTrainingRound(correctCount: i + 1, totalCount: 10,
                                           hitRate: Double(i + 1) / 10.0,
                                           createdAt: base.addingTimeInterval(Double(i))))
        }
        // 混入 1 条非 interval 题型（二期预留），不得参与统计
        rounds.append(EarTrainingRound(kind: "rhythm", correctCount: 10, totalCount: 10,
                                       hitRate: 1.0, createdAt: base.addingTimeInterval(100)))
        let summary = EarTrainingTrend.summarize(rounds: rounds)
        XCTAssertEqual(summary.totalCount, 3, "非 interval 题型不计数")
        XCTAssertEqual(summary.hitRates, [0.1, 0.2, 0.3], "只统计 interval，时间升序")
        XCTAssertEqual(summary.mean ?? -1, 0.2, accuracy: 0.0001)
    }

    func testEarTrainingTrendExplicitKindParameterFilters() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var rounds: [EarTrainingRound] = []
        for i in 0..<3 {
            rounds.append(EarTrainingRound(kind: "rhythm", correctCount: 5, totalCount: 10,
                                           hitRate: 0.5,
                                           createdAt: base.addingTimeInterval(Double(i))))
        }
        rounds.append(EarTrainingRound(kind: "interval", correctCount: 1, totalCount: 10,
                                       hitRate: 0.1, createdAt: base.addingTimeInterval(100)))
        let summary = EarTrainingTrend.summarize(rounds: rounds, kind: "rhythm")
        XCTAssertEqual(summary.totalCount, 3, "kind 参数过滤生效")
        XCTAssertEqual(summary.hitRates, [0.5, 0.5, 0.5])
        XCTAssertEqual(summary.mean ?? -1, 0.5, accuracy: 0.0001)
    }

    // MARK: - G6 Stage B：练耳会话状态机（IntervalQuizSession；不测真实发声——音频属设备/真机项）

    /// 固定题目 q 重复填满一轮 10 题（session init 预生成整轮）
    @MainActor
    private func makeSession(questions: [IntervalQuestion], context: ModelContext) -> IntervalQuizSession {
        var queue = questions
        let fallback = questions.first ?? IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12])
        return IntervalQuizSession(allowed: Set(1...12), context: context) {
            queue.isEmpty ? fallback : queue.removeFirst()
        }
    }

    @MainActor
    func testSessionAllCorrectFinishesAndSavesOneRound() throws {
        let context = ModelContext(try makeEarContainer())
        let questions = (0..<10).map { _ in
            IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12])
        }
        let session = makeSession(questions: questions, context: context)

        for i in 0..<10 {
            XCTAssertFalse(session.finished, "第 \(i + 1) 题答完前不得 finished")
            session.answer(7)
            session.next()
        }
        XCTAssertTrue(session.finished, "第 10 次 next 后本轮结束")
        XCTAssertEqual(session.finalHitRate ?? -1, 1.0, accuracy: 0.0001)

        let rounds = try context.fetch(FetchDescriptor<EarTrainingRound>())
        XCTAssertEqual(rounds.count, 1, "一轮恰写一条 round")
        let round = try XCTUnwrap(rounds.first)
        XCTAssertEqual(round.kind, "interval")
        XCTAssertEqual(round.correctCount, 10)
        XCTAssertEqual(round.totalCount, 10)
    }

    @MainActor
    func testSessionSevenCorrectRecordsHitRate0point7() throws {
        let context = ModelContext(try makeEarContainer())
        // 前 7 题答对、后 3 题答错（答案 7，选 2 判错）
        let questions = (0..<10).map { _ in
            IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12])
        }
        let session = makeSession(questions: questions, context: context)
        for i in 0..<10 {
            session.answer(i < 7 ? 7 : 2)
            session.next()
        }
        XCTAssertTrue(session.finished)
        XCTAssertEqual(session.finalHitRate ?? -1, 0.7, accuracy: 0.0001, "命中 7/10 = 0.7（带容差）")

        let rounds = try context.fetch(FetchDescriptor<EarTrainingRound>())
        XCTAssertEqual(rounds.count, 1)
        XCTAssertEqual(try XCTUnwrap(rounds.first).correctCount, 7)
    }

    @MainActor
    func testSessionAnswerIdempotentFirstAnswerWins() throws {
        let context = ModelContext(try makeEarContainer())
        // 单题：answer 7（对）再 answer 2（错）——只按首次计，selected 不被第二次覆盖
        let session = makeSession(
            questions: Array(repeating: IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12]), count: 10),
            context: context)
        session.answer(7)
        session.answer(2)
        XCTAssertEqual(session.selected, 7, "首次作答保留，第二次不覆盖")
        // 走完剩余各题：循环内先答当前题再 next（首次 answer 打在已答的 q1 上是 no-op）
        for _ in 1..<10 {
            session.answer(7)
            session.next()
        }
        // 上循环结束时停在 q10：补答并 next 收尾
        session.answer(7)
        session.next()
        XCTAssertTrue(session.finished)
        XCTAssertEqual(session.finalHitRate ?? -1, 1.0, accuracy: 0.0001, "重复作答不额外扣分")
    }

    @MainActor
    func testSessionNextAfterFinishedDoesNotWriteSecondRound() throws {
        let context = ModelContext(try makeEarContainer())
        let session = makeSession(
            questions: Array(repeating: IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12]), count: 10),
            context: context)
        for _ in 0..<10 {
            session.answer(7)
            session.next()
        }
        XCTAssertTrue(session.finished)
        session.next()
        session.next()
        let rounds = try context.fetch(FetchDescriptor<EarTrainingRound>())
        XCTAssertEqual(rounds.count, 1, "finished 后再调 next 不得产生第二条 round（收尾防重入）")
    }

    @MainActor
    func testSessionNextBeforeLastQuestionAdvancesAndResetsSelection() throws {
        let context = ModelContext(try makeEarContainer())
        // 两题不同答案，验证推进后 selected 复位 nil、displayIndex 跟随
        let first = IntervalQuestion(rootMIDINote: 60, answerSemitones: 7, options: [7, 2, 3, 12])
        let second = IntervalQuestion(rootMIDINote: 62, answerSemitones: 3, options: [3, 7, 2, 12])
        let session = makeSession(questions: [first] + Array(repeating: second, count: 9), context: context)

        XCTAssertEqual(session.displayIndex, 1)
        XCTAssertNil(session.selected, "初始未作答")
        session.answer(7)
        XCTAssertEqual(session.selected, 7)
        session.next() // 未到第 10 题：正常推进
        XCTAssertFalse(session.finished)
        XCTAssertEqual(session.currentQuestion, second, "推进到第 2 题")
        XCTAssertNil(session.selected, "推进后 selected 复位 nil")
        XCTAssertEqual(session.displayIndex, 2)
        // 新题按新答案作答
        session.answer(3)
        XCTAssertEqual(session.selected, 3)
    }

    // MARK: G7 简谱标签纯函数（固定调，ADR-0009 Stage A）—— 数字/升降/八度点

    // 自然音（accidental=nil）：按 pitch class 直取数字，.none。
    func testNumberedNaturalWhiteKeysDefaultNoAccidental() {
        let expected: [(Int, Int)] = [(60, 1), (62, 2), (64, 3), (65, 4), (67, 5), (69, 6), (71, 7)]
        for (midi, digit) in expected {
            let l = NumberedNotation.label(midiPitch: midi)
            XCTAssertEqual(l, NumberedLabel(digit: digit, accidental: .none, octaveDotsUp: 0, octaveDotsDown: 0),
                           "midi \(midi) → 数字 \(digit) 无记号、基准八度无点")
        }
    }

    // 黑键 + 显式 ♯：数字 = pc−1 自然音。
    func testNumberedBlackKeysWithExplicitSharp() {
        XCTAssertEqual(NumberedNotation.label(midiPitch: 61, accidental: .sharp),
                       NumberedLabel(digit: 1, accidental: .sharp, octaveDotsUp: 0, octaveDotsDown: 0), "C♯ → ♯1")
        XCTAssertEqual(NumberedNotation.label(midiPitch: 66, accidental: .sharp),
                       NumberedLabel(digit: 4, accidental: .sharp, octaveDotsUp: 0, octaveDotsDown: 0), "F♯ → ♯4")
        XCTAssertEqual(NumberedNotation.label(midiPitch: 68, accidental: .sharp),
                       NumberedLabel(digit: 5, accidental: .sharp, octaveDotsUp: 0, octaveDotsDown: 0), "G♯ → ♯5")
    }

    // 黑键 + 显式 ♭：数字 = pc+1 自然音。
    func testNumberedBlackKeysWithExplicitFlat() {
        XCTAssertEqual(NumberedNotation.label(midiPitch: 63, accidental: .flat),
                       NumberedLabel(digit: 3, accidental: .flat, octaveDotsUp: 0, octaveDotsDown: 0), "E♭ → ♭3")
        XCTAssertEqual(NumberedNotation.label(midiPitch: 70, accidental: .flat),
                       NumberedLabel(digit: 7, accidental: .flat, octaveDotsUp: 0, octaveDotsDown: 0), "B♭ → ♭7")
    }

    // 倍升/倍降：基准 pc−2 / pc+2（mod 12）。
    func testNumberedDoubleSharpAndDoubleFlat() {
        // D𝄪 = E（pitch 64 = pc4，基准 pc2 → 数字 2）
        XCTAssertEqual(NumberedNotation.label(midiPitch: 64, accidental: .doubleSharp),
                       NumberedLabel(digit: 2, accidental: .doubleSharp, octaveDotsUp: 0, octaveDotsDown: 0))
        // E𝄫 = D（pitch 62 = pc2，基准 pc4 → 数字 3）
        XCTAssertEqual(NumberedNotation.label(midiPitch: 62, accidental: .doubleFlat),
                       NumberedLabel(digit: 3, accidental: .doubleFlat, octaveDotsUp: 0, octaveDotsDown: 0))
    }

    // 显式还原：落在自然 pc 上按 pc 取数字、.natural。
    func testNumberedExplicitNaturalOnNaturalPC() {
        XCTAssertEqual(NumberedNotation.label(midiPitch: 60, accidental: .natural),
                       NumberedLabel(digit: 1, accidental: .natural, octaveDotsUp: 0, octaveDotsDown: 0), "中央 C 带 ♮ → 1♮")
    }

    // 黑键缺省兜底（accidental=nil）：确定性等音默认（pc 1/3/6/8 → ♯，pc 10 → ♭）。
    func testNumberedBlackKeysNilAccidentalDeterministicDefault() {
        let expected: [(Int, Int, NumberedAccidental)] = [
            (61, 1, .sharp), (63, 2, .sharp), (66, 4, .sharp), (68, 5, .sharp), (70, 7, .flat),
        ]
        for (midi, digit, acc) in expected {
            let l = NumberedNotation.label(midiPitch: midi)
            XCTAssertEqual(l, NumberedLabel(digit: digit, accidental: acc, octaveDotsUp: 0, octaveDotsDown: 0),
                           "midi \(midi) 缺省 → \(acc) \(digit)")
        }
    }

    // 黑键缺省兜底确定性：同输入连调 3 次结果完全相等（无摇摆）。
    func testNumberedBlackKeysNilAccidentalStableAcrossRepeatedCalls() {
        for midi in [61, 63, 66, 68, 70] {
            let first = NumberedNotation.label(midiPitch: midi)
            XCTAssertEqual(NumberedNotation.label(midiPitch: midi), first)
            XCTAssertEqual(NumberedNotation.label(midiPitch: midi), first, "midi \(midi) 三次调用结果一致")
        }
    }

    // 八度点：中央 C 八度（C4–B4）0/0，向上/向下各差一个八度 +1 点。
    func testNumberedOctaveDotsAroundReferenceOctave() {
        // C5/C6：数字仍 1，上方点 1/2
        XCTAssertEqual(NumberedNotation.label(midiPitch: 72).octaveDotsUp, 1, "C5 → 上 1 点")
        XCTAssertEqual(NumberedNotation.label(midiPitch: 72).octaveDotsDown, 0)
        XCTAssertEqual(NumberedNotation.label(midiPitch: 84).octaveDotsUp, 2, "C6 → 上 2 点")
        XCTAssertEqual(NumberedNotation.label(midiPitch: 84).digit, 1)
        // C3/C2：下方点 1/2
        XCTAssertEqual(NumberedNotation.label(midiPitch: 48).octaveDotsDown, 1, "C3 → 下 1 点")
        XCTAssertEqual(NumberedNotation.label(midiPitch: 48).digit, 1)
        XCTAssertEqual(NumberedNotation.label(midiPitch: 36).octaveDotsDown, 2, "C2 → 下 2 点")
        // 边界：B4（71）仍在基准八度 0/0，C5（72）起才有上方点
        XCTAssertEqual(NumberedNotation.label(midiPitch: 71), NumberedLabel(digit: 7, accidental: .none, octaveDotsUp: 0, octaveDotsDown: 0))
        XCTAssertEqual(NumberedNotation.label(midiPitch: 72), NumberedLabel(digit: 1, accidental: .none, octaveDotsUp: 1, octaveDotsDown: 0))
        // 中央 C 恰在基准 0/0
        XCTAssertEqual(NumberedNotation.label(midiPitch: 60), NumberedLabel(digit: 1, accidental: .none, octaveDotsUp: 0, octaveDotsDown: 0))
    }

    // MIDI 边界 0 / 127 不崩：octave 点有限非负、数字在 1...7。
    func testNumberedExtremeMIDIPitchDoesNotCrash() {
        for midi in [0, 127] {
            let l = NumberedNotation.label(midiPitch: midi)
            XCTAssertTrue((1...7).contains(l.digit), "midi \(midi) 数字 \(l.digit) 越界")
            XCTAssertGreaterThanOrEqual(l.octaveDotsUp, 0, "midi \(midi) 上方点为有限非负")
            XCTAssertGreaterThanOrEqual(l.octaveDotsDown, 0, "midi \(midi) 下方点为有限非负")
        }
    }

    // MARK: G7 简谱几何 overlay（ADR-0009 Stage B）—— 文本部件 / 符头取框（纯函数）

    // 自然音标签：core 只有数字、无变音符号，八度点空。
    func testNumberedGlyphNaturalCoreNoDots() {
        let g = NumberedGlyphText.from(NumberedLabel(digit: 1, accidental: .none, octaveDotsUp: 0, octaveDotsDown: 0))
        XCTAssertEqual(g.core, "1")
        XCTAssertEqual(g.dotsUp, [])
        XCTAssertEqual(g.dotsDown, [])
    }

    // 变音符号映射钉死：♯/♭/𝄪/𝄫/♮ → core = 记号 + 数字。
    func testNumberedGlyphAccidentalSymbolsPinned() {
        XCTAssertEqual(NumberedGlyphText.from(NumberedLabel(digit: 1, accidental: .sharp, octaveDotsUp: 0, octaveDotsDown: 0)).core, "♯1")
        XCTAssertEqual(NumberedGlyphText.from(NumberedLabel(digit: 7, accidental: .flat, octaveDotsUp: 0, octaveDotsDown: 0)).core, "♭7")
        XCTAssertEqual(NumberedGlyphText.from(NumberedLabel(digit: 2, accidental: .doubleSharp, octaveDotsUp: 0, octaveDotsDown: 0)).core, "𝄪2")
        XCTAssertEqual(NumberedGlyphText.from(NumberedLabel(digit: 3, accidental: .doubleFlat, octaveDotsUp: 0, octaveDotsDown: 0)).core, "𝄫3")
        XCTAssertEqual(NumberedGlyphText.from(NumberedLabel(digit: 1, accidental: .natural, octaveDotsUp: 0, octaveDotsDown: 0)).core, "♮1")
    }

    // 八度点数组：up=2 → ["·","·"] 且 down 空；down=1 → down 一条且 up 空。
    func testNumberedGlyphOctaveDotsArrays() {
        let up = NumberedGlyphText.from(NumberedLabel(digit: 1, accidental: .none, octaveDotsUp: 2, octaveDotsDown: 0))
        XCTAssertEqual(up.dotsUp, ["·", "·"])
        XCTAssertEqual(up.dotsDown, [])
        let down = NumberedGlyphText.from(NumberedLabel(digit: 1, accidental: .none, octaveDotsUp: 0, octaveDotsDown: 1))
        XCTAssertEqual(down.dotsUp, [])
        XCTAssertEqual(down.dotsDown, ["·"])
    }

    // up 与 down 不会同时非空（NumberedNotation 的八度算法保证）：
    // 全音域逐半音扫一遍，任一标签至多一侧有点。
    func testNumberedGlyphUpAndDownNeverBothNonEmpty() {
        for midi in 0...127 {
            let g = NumberedGlyphText.from(NumberedNotation.label(midiPitch: midi))
            XCTAssertTrue(g.dotsUp.isEmpty || g.dotsDown.isEmpty,
                          "midi \(midi) 上下八度点同时非空（up \(g.dotsUp.count) / down \(g.dotsDown.count)）")
        }
    }

    // 真实音高端到端：C6（84）→ core "1" + 上 2 点；B♭3（58，谱面 ♭）→ core "♭7" + 下 1 点。
    func testNumberedGlyphFromRealPitches() {
        let c6 = NumberedGlyphText.from(NumberedNotation.label(midiPitch: 84))
        XCTAssertEqual(c6.core, "1")
        XCTAssertEqual(c6.dotsUp, ["·", "·"])
        XCTAssertEqual(c6.dotsDown, [])
        let bFlat3 = NumberedGlyphText.from(NumberedNotation.label(midiPitch: 58, accidental: .flat))
        XCTAssertEqual(bFlat3.core, "♭7")
        XCTAssertEqual(bFlat3.dotsUp, [])
        XCTAssertEqual(bFlat3.dotsDown, ["·"])
    }

    // noteFrame 几何：以给定中心为 rect 中点，宽高 = sp*1.1 且为正。
    func testNoteFrameCentersOnGivenCenter() {
        let r = NumberedAnnotationBuilder.noteFrame(centerX: 100, centerY: 50, sp: 10)
        XCTAssertEqual(r.midX, 100, accuracy: 0.01)
        XCTAssertEqual(r.midY, 50, accuracy: 0.01)
        XCTAssertEqual(r.width, 11, accuracy: 0.01, "宽 = sp*1.1 = 11")
        XCTAssertEqual(r.height, 11, accuracy: 0.01, "高 = sp*1.1 = 11")
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertGreaterThan(r.height, 0)
    }

    // noteFrame 随 sp 同比缩放：sp 翻倍 → 宽高翻倍（中心不动）。
    func testNoteFrameScalesWithSp() {
        let small = NumberedAnnotationBuilder.noteFrame(centerX: 100, centerY: 50, sp: 10)
        let big = NumberedAnnotationBuilder.noteFrame(centerX: 100, centerY: 50, sp: 20)
        XCTAssertEqual(big.width, small.width * 2, accuracy: 0.01)
        XCTAssertEqual(big.height, small.height * 2, accuracy: 0.01)
        XCTAssertEqual(big.midX, small.midX, accuracy: 0.01)
        XCTAssertEqual(big.midY, small.midY, accuracy: 0.01)
    }

    // MARK: M9 导出 DTO — includeWithNeko 全链路 + 旧包向后兼容
    // collectMetadata/restore 共用的最小内存库（两函数触到的全部 @Model，缺表会静默空 fetch）

    @MainActor
    private func makeExportContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AppSettings.self, Take.self, GateEvent.self, Piece.self, ScoreFile.self,
            ScoreErrorMark.self, DailyPlan.self, PracticeTask.self, PlacementResult.self,
            VelocityCalibration.self, CoursePathState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    func testCollectMetadataCarriesIncludeWithNeko() throws {
        let context = ModelContext(try makeExportContainer())
        context.insert(ScoreErrorMark(scoreName: "拜厄 12", measure: 5, type: "note",
                                      note: "升4", occurrenceCount: 3, includeWithNeko: true))
        context.insert(ScoreErrorMark(scoreName: "拜厄 12", measure: 9, type: "rhythm",
                                      note: "切分", occurrenceCount: 1, includeWithNeko: false))

        let metadata = ExportService.collectMetadata(context: context)

        let withNeko = try XCTUnwrap(metadata.errorMarks.first { $0.measure == 5 })
        XCTAssertTrue(withNeko.includeWithNeko, "true 的标记必须原样进包")
        let withoutNeko = try XCTUnwrap(metadata.errorMarks.first { $0.measure == 9 })
        XCTAssertFalse(withoutNeko.includeWithNeko, "false 的标记不冒充 true")
    }

    @MainActor
    func testLegacyErrorMarkDTOJSONWithoutNekoKeyDecodesFalse() throws {
        // 旧导出包的 errorMarks 条目没有 includeWithNeko 键（其它键齐全）→ 解码不失败、补 false
        let legacy = """
        [{"scoreName":"哈农 1","measure":3,"type":"note","note":"降7","occurrenceCount":2}]
        """
        let decoded = try JSONDecoder.iso.decode([ExportService.ErrorMarkDTO].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertFalse(decoded[0].includeWithNeko, "缺键 → 默认 false")

        // 新包带键：true 正常解出（decodeIfPresent 不吞显式值）
        let current = """
        [{"scoreName":"哈农 1","measure":3,"type":"note","note":"降7","occurrenceCount":2,"includeWithNeko":true}]
        """
        let withKey = try JSONDecoder.iso.decode([ExportService.ErrorMarkDTO].self, from: Data(current.utf8))
        XCTAssertTrue(withKey[0].includeWithNeko)
    }

    @MainActor
    func testRestoreRoundTripKeepsIncludeWithNeko() throws {
        let sourceContext = ModelContext(try makeExportContainer())
        sourceContext.insert(ScoreErrorMark(scoreName: "拜厄 8", measure: 12, type: "fingering",
                                            note: "3 指改 4", occurrenceCount: 2, includeWithNeko: true))

        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("m9-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let zipURL = try ExportService.buildExport(baseDir: baseDir, includeVideos: false, context: sourceContext)

        let restoreContext = ModelContext(try makeExportContainer())
        _ = try ExportService.restore(from: zipURL, into: baseDir, in: restoreContext)

        let restored = try restoreContext.fetch(FetchDescriptor<ScoreErrorMark>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.scoreName, "拜厄 8")
        XCTAssertEqual(restored.first?.includeWithNeko, true, "恢复后 includeWithNeko 保持 true")
    }

    // MARK: P13 S12 循环设置卡 1 右注（真实曲名 / 空串诚实回退）

    func testS12RightCaptionWithPieceTitle() {
        let caption = S12LoopSettingsSheet.rightCaption(pieceTitle: "小星星", totalMeasures: 16)
        XCTAssertTrue(caption.contains("曲目：小星星"), "有真实曲名时带「曲目：」")
        XCTAssertTrue(caption.contains("共 16 小节"), "同时保留总小节数")
    }

    func testS12RightCaptionEmptyTitleShowsMeasuresOnly() {
        let caption = S12LoopSettingsSheet.rightCaption(pieceTitle: "", totalMeasures: 16)
        XCTAssertEqual(caption, "共 16 小节", "空曲名只显小节数，不补「练习」之类占位")
        XCTAssertFalse(caption.contains("曲目："))
    }

    // MARK: P1 连续循环遍数面板（LoopConfig.targetLoopCount / completedLoopCount / 顶栏与 badge 文案）

    func testLoopConfigTargetLoopCountDefaultsToUnlimited() {
        XCTAssertEqual(LoopConfig().targetLoopCount, 0, "默认 0 = 不限遍数，维持现状")
        XCTAssertEqual(
            LoopConfig(startMeasure: 2, endMeasure: 5, mode: .adaptiveUp, gapSec: 4, countIn: false, targetLoopCount: 3).targetLoopCount,
            3,
            "显式传入的遍数原样保留（其余字段不受影响）"
        )
    }

    /// 一遍 = 走完 region 全部期望音（65 是终点小节最后一音 → 立即 wrap 回小节 0）
    @MainActor
    private func playOneLoopPass(_ session: PracticeSession) {
        for pitch in [UInt8(60), 64, 67, 72, 65] {
            session.handle(MIDIEvent(kind: .noteOn(note: pitch, velocity: 90), channel: 0, timeNanos: 1))
        }
    }

    @MainActor
    func testCompletedLoopCountIncrementsOnEachWrap() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        XCTAssertEqual(session.completedLoopCount, 0, "未开弹前为 0")

        playOneLoopPass(session)
        XCTAssertEqual(session.completedLoopCount, 1, "第一次 wrap 回起点 → 1 遍")
        XCTAssertEqual(session.followState.measureIndex, 0, "遍数自增不改光标状态")

        playOneLoopPass(session)
        playOneLoopPass(session)
        XCTAssertEqual(session.completedLoopCount, 3, "三次 wrap → 3 遍")
    }

    @MainActor
    func testHeaderSubtitleOmitsLoopProgressWithoutTarget() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)

        let text = PracticeRoomView.headerSubtitleText(
            scoreLoaded: true,
            startMeasure: session.loopConfig.startMeasure,
            endMeasure: session.loopConfig.endMeasure,
            completedLoopCount: session.completedLoopCount,
            targetLoopCount: session.loopConfig.targetLoopCount,
            bpm: session.tempoState.bpm
        )
        XCTAssertFalse(text.contains("遍"), "不限遍数 → 文案不出现「遍」字")
        XCTAssertEqual(text, "1–3 小节 · ♩=72", "区间 + BPM 原文案逐字不变")

        // 谱未加载好：只给 BPM，不编造小节号（原逻辑）
        let noScore = PracticeRoomView.headerSubtitleText(
            scoreLoaded: false, startMeasure: 1, endMeasure: 3,
            completedLoopCount: 0, targetLoopCount: 0, bpm: 72
        )
        XCTAssertEqual(noScore, "♩=72")
    }

    @MainActor
    func testHeaderSubtitleShowsProgressWhenTargetSet() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        // 与 S12 applyAndStart 同一写入口径：整份 LoopConfig 回写（含 targetLoopCount）
        session.loopConfig = LoopConfig(
            startMeasure: 1, endMeasure: 3, mode: .loop, gapSec: 3, countIn: true, targetLoopCount: 3
        )

        for _ in 0..<3 { playOneLoopPass(session) }
        XCTAssertEqual(session.completedLoopCount, 3, "弹满 3 遍")
        XCTAssertEqual(session.phase, .finished, "弹满即自动 finish；计数不清零，进度仍可显示")

        let text = PracticeRoomView.headerSubtitleText(
            scoreLoaded: true,
            startMeasure: session.loopConfig.startMeasure,
            endMeasure: session.loopConfig.endMeasure,
            completedLoopCount: session.completedLoopCount,
            targetLoopCount: session.loopConfig.targetLoopCount,
            bpm: session.tempoState.bpm
        )
        XCTAssertTrue(text.contains("3/3 遍"), "target=3 且弹满 3 遍 → 追加「3/3 遍」")
        XCTAssertTrue(text.hasPrefix("1–3 小节 · "), "区间仍在最前，进度追加在末尾")
    }

    func testLoopProgressTextOnlyWithTarget() {
        XCTAssertNil(PracticeRoomView.loopProgressText(completedLoopCount: 0, targetLoopCount: 0),
                     "不限 → nil，循环格 badge 不显示（不造假进度）")
        XCTAssertEqual(PracticeRoomView.loopProgressText(completedLoopCount: 2, targetLoopCount: 5), "2/5")
        XCTAssertEqual(PracticeRoomView.loopProgressText(completedLoopCount: 3, targetLoopCount: 3), "3/3")
    }

    func testTargetLoopPickSelectionSequence() {
        // chip 选择序列：不限 → 0，选 3 → 3，选 5 → 5
        XCTAssertEqual(TargetLoopPick.none.loopCount, 0, "「不限」= 0（不限遍数）")
        XCTAssertEqual(TargetLoopPick.three.loopCount, 3)
        XCTAssertEqual(TargetLoopPick.five.loopCount, 5)

        // chip 文案（brief §3：不限 / 3 遍 / 5 遍）
        XCTAssertEqual(TargetLoopPick.none.title, "不限", "空态档位叫「不限」，不写「无目标」")
        XCTAssertEqual(TargetLoopPick.three.title, "3 遍")
        XCTAssertEqual(TargetLoopPick.five.title, "5 遍")

        // 打开 sheet 的回显：既有值反查选中项
        XCTAssertEqual(TargetLoopPick.pick(for: 0), .none)
        XCTAssertEqual(TargetLoopPick.pick(for: 3), .three)
        XCTAssertEqual(TargetLoopPick.pick(for: 5), .five)
        XCTAssertEqual(TargetLoopPick.pick(for: 7), .none, "三档之外的存量值按「不限」呈现，不冒充档位")
    }

    @MainActor
    func testAutoFinishWhenTargetLoopCountReached() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        session.loopConfig = LoopConfig(
            startMeasure: 1, endMeasure: 3, mode: .loop, gapSec: 3, countIn: true, targetLoopCount: 3
        )

        playOneLoopPass(session)
        XCTAssertEqual(session.phase, .performing, "第 1 遍：还差 2 遍，不收尾")
        playOneLoopPass(session)
        XCTAssertEqual(session.phase, .performing, "第 2 遍：还差 1 遍，不收尾")

        playOneLoopPass(session)
        XCTAssertEqual(session.completedLoopCount, 3, "第三遍 wrap 后计数到 3")
        XCTAssertEqual(session.phase, .finished, "弹满目标遍数 → 自动 finish()，phase 停在 finished")

        // 收尾后不再计遍（handle 被 phase 挡掉）
        playOneLoopPass(session)
        XCTAssertEqual(session.completedLoopCount, 3, "finished 后 MIDI 事件不再推进遍数")
    }

    @MainActor
    func testNoAutoFinishWithoutTargetLoopCount() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        XCTAssertEqual(session.loopConfig.targetLoopCount, 0, "默认 0 = 不限遍数")

        for _ in 0..<4 { playOneLoopPass(session) }
        XCTAssertEqual(session.completedLoopCount, 4, "四遍都计数")
        XCTAssertEqual(session.phase, .performing, "target=0 → 循环照旧一直转，绝不自动收尾")
    }

    @MainActor
    func testStartResetsCompletedLoopCountFromPreviousSession() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        session.loopConfig.targetLoopCount = 5

        playOneLoopPass(session)
        playOneLoopPass(session)
        XCTAssertEqual(session.completedLoopCount, 2)

        _ = session.finish()
        XCTAssertEqual(session.completedLoopCount, 2, "finish() 不清零：收尾后仍显示「2/5」")

        // 同一会话对象再开一轮：上一会话的 2 遍不带进来
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        XCTAssertEqual(session.completedLoopCount, 0, "start() 清零上一会话计数（每会话独立）")
    }

    @MainActor
    func testFinishIsIdempotent() {
        let session = PracticeSession()
        session.configure(scoreName: "样例", expectedPerMeasure: region, startBPM: 72)
        session.start(metronome: MetronomeService(), countIn: false, metronomeOn: false)
        session.loopConfig.targetLoopCount = 5
        playOneLoopPass(session)

        // 固定 now：finish() 默认取 Date()，两次调用若跨了整秒边界 durationSec 会抖
        let now = Date()
        let first = session.finish(now: now)
        let second = session.finish(now: now)
        XCTAssertEqual(first, second, "重复 finish() 返回同一 summary（幂等，不重复落库）")
        XCTAssertEqual(session.phase, .finished, "重复 finish() 不把 phase 带走")
    }

    func testS12TargetPickWritesBackLoopConfig() {
        // applyAndStart 的写回口径：整份 LoopConfig 一次回写，targetLoopCount 随选中档位带走
        let three = S12LoopSettingsSheet.loopConfig(
            start: 2, end: 6, mode: .adaptiveUp, gapSec: 4, countIn: false, target: .three
        )
        XCTAssertEqual(three.targetLoopCount, 3, "选中「3 遍」→ 写回 3")
        XCTAssertEqual(three.startMeasure, 2, "目标遍数与区间/模式/间隔同批写回，不丢字段")
        XCTAssertEqual(three.endMeasure, 6)
        XCTAssertEqual(three.mode, .adaptiveUp)
        XCTAssertEqual(three.gapSec, 4)
        XCTAssertFalse(three.countIn)

        let five = S12LoopSettingsSheet.loopConfig(
            start: 1, end: 8, mode: .loop, gapSec: 3, countIn: true, target: .five
        )
        XCTAssertEqual(five.targetLoopCount, 5, "选中「5 遍」→ 写回 5")

        // 首次打开默认选中「不限」（=0，维持现状）
        let none = S12LoopSettingsSheet.loopConfig(
            start: 1, end: 8, mode: .loop, gapSec: 3, countIn: true, target: .none
        )
        XCTAssertEqual(none.targetLoopCount, 0, "默认「不限」→ 0")
        XCTAssertEqual(
            TargetLoopPick.pick(for: LoopConfig().targetLoopCount), .none,
            "空态回显：默认 LoopConfig 的 targetLoopCount 落在「不限」档"
        )
    }
}
