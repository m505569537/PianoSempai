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
}
