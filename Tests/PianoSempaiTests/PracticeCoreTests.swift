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
}
