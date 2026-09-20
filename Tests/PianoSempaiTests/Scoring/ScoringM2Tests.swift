import XCTest
import SheetMusicCore
import SheetMusicLoader
@testable import PianoSempai

/// P2 M2：参考谱提取器（§3）+ 演奏解析器（§4）。
/// 覆盖：示例谱 256 总音 / 128+128、rest 推进游标（空 chord 口径，D-1）、
/// 区间裁剪与 rebased、踏板按住抬手延收音、同 pitch 重复、中断分段、velocity=0。
final class ScoringM2Tests: XCTestCase {

    // MARK: - §3 参考谱提取：示例谱

    private func loadSampleScore() throws -> Score {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml"),
            "内置示例谱缺失"
        )
        return try ScoreLoader.loadScore(contentsOf: url)
    }

    func testSampleScore256NotesSplitRightLeft128() throws {
        let score = try loadSampleScore()
        let output = ScoreReferenceNotes.extract(score: score)
        XCTAssertTrue(output.isTwoStaff)
        XCTAssertEqual(output.notes.count, 256, "示例谱总音数 256")
        XCTAssertEqual(output.notes.filter { $0.hand == .right }.count, 128, "右手 staff 128 音")
        XCTAssertEqual(output.notes.filter { $0.hand == .left }.count, 128, "左手 staff 128 音")
    }

    func testSampleMeasureBoundariesOnsetBeatsAreMultiplesOfFour() throws {
        let score = try loadSampleScore()
        let output = ScoreReferenceNotes.extract(score: score)
        // 4/4 全四分音符：每小节首拍 onsetBeat = 4 的倍数
        for note in output.notes where note.beatInMeasure == 0 {
            XCTAssertEqual(
                note.onsetBeat.truncatingRemainder(dividingBy: 4), 0,
                accuracy: 0.0001,
                "小节 \(note.measureIndex) 首拍 onsetBeat 应为 4 的倍数，实际 \(note.onsetBeat)"
            )
        }
        // 全四分音符：时值 1 拍
        for note in output.notes where !note.isGrace {
            XCTAssertEqual(note.durationBeats, 1, accuracy: 0.0001)
        }
    }

    func testMeasureRangeClippingRebased() throws {
        let score = try loadSampleScore()
        // 只取第 1–4 小节（0-based 闭区间）
        let output = ScoreReferenceNotes.extract(score: score, measureRange: 0...3)
        XCTAssertEqual(output.notes.count, 32, "4 小节 × 8 音")
        // rebased：区间起点归零，全部 onsetBeat < 16
        let maxOnset = output.notes.map(\.onsetBeat).max() ?? -1
        XCTAssertLessThan(maxOnset, 16)
        XCTAssertGreaterThanOrEqual(output.notes.map(\.onsetBeat).min() ?? -1, 0)
        // measureIndex 保持绝对 0-based
        XCTAssertEqual(Set(output.notes.map(\.measureIndex)), Set([0, 1, 2, 3]))
    }

    // MARK: - §3 rest 推进（空 chord 口径，D-1）：构造含休止的小谱

    /// 2 小节 4/4：m1 = C4 D4 + 二分休止；m2 = E4 F4 G4 A4。
    /// rest 必须推进游标，否则 m2 的 onset 会错成 2/3/4/5。
    private func restScore() throws -> Score {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>G</sign><line>2</line></clef></attributes>
              <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><rest/><duration>2</duration><type>half</type></note>
            </measure>
            <measure number="2">
              <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rest-fixture-\(UUID().uuidString).musicxml")
        try Data(xml.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try ScoreLoader.loadScore(contentsOf: url)
    }

    func testRestAdvancesCursor() throws {
        let score = try restScore()
        let output = ScoreReferenceNotes.extract(score: score)
        XCTAssertTrue(output.isTwoStaff == false, "单谱表")
        XCTAssertEqual(output.notes.count, 6, "2+4 音（休止不产音但推进游标）")
        // m1: C4@0, D4@1；二分休止推进 2 拍 → m2 从 @4 开始
        let byPitch = Dictionary(uniqueKeysWithValues: output.notes.map { ($0.pitch, $0.onsetBeat) })
        XCTAssertEqual(byPitch[60] ?? -1, 0, accuracy: 0.0001, "C4 onset 0")
        XCTAssertEqual(byPitch[62] ?? -1, 1, accuracy: 0.0001, "D4 onset 1")
        XCTAssertEqual(byPitch[64] ?? -1, 4, accuracy: 0.0001, "E4 onset 4（rest 推进了 2 拍）")
        XCTAssertEqual(byPitch[65] ?? -1, 5, accuracy: 0.0001, "F4 onset 5")
        XCTAssertEqual(byPitch[67] ?? -1, 6, accuracy: 0.0001, "G4 onset 6")
        XCTAssertEqual(byPitch[69] ?? -1, 7, accuracy: 0.0001, "A4 onset 7")
        // 单 staff → hand 全 unknown
        XCTAssertTrue(output.notes.allSatisfy { $0.hand == .unknown })
    }

    func testRangeClipOnRestScore() throws {
        let score = try restScore()
        // 只取第 2 小节（0-based 1...1）：4 音，rebased 0..3
        let output = ScoreReferenceNotes.extract(score: score, measureRange: 1...1)
        XCTAssertEqual(output.notes.count, 4)
        XCTAssertEqual(output.notes.map(\.onsetBeat), [0, 1, 2, 3], "区间起点归零")
        XCTAssertEqual(Set(output.notes.map(\.measureIndex)), Set([1]))
    }

    // MARK: - §4 演奏解析

    private func event(_ kind: String, _ note: UInt8 = 64, _ value: UInt8 = 0, at sec: Double, suspicious: Bool = false) -> RawMIDIEventRecord {
        RawMIDIEventRecord(
            t: UInt64(sec * 1_000_000_000) + 5_000_000_000, // 偏移锚点，验证 min(t) 归零
            k: kind, c: 0, n: note, v: value, suspicious: suspicious
        )
    }

    func testTimeNormalizationMinIsZero() {
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 3.0),
            event("off", 60, 0, at: 4.0),
        ])
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].onsetSec, 0, accuracy: 0.0001, "首事件归零")
        XCTAssertEqual(result.notes[0].endSec, 1.0, accuracy: 0.0001)
    }

    func testPedalHoldExtendsEndToPedalRelease() {
        // on60@0 → off60@1（此时踏板踩着）→ 抬踏板@2 → endSec = 2（PRD L187）
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0),
            event("cc64", 64, 127, at: 0.5),
            event("off", 60, 0, at: 1.0),
            event("cc64", 64, 0, at: 2.0),
        ])
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].endSec, 2.0, accuracy: 0.0001, "踏板按住抬手延到抬踏板")
        XCTAssertEqual(result.notes[0].onsetSec, 0, accuracy: 0.0001, "onset 不受踏板影响")
        XCTAssertEqual(result.pedalEventCount, 2)
    }

    func testSamePitchRepeatUnderPedalNotMerged() {
        // on60@0 → 踏板@0.5 → off60@1 → on60@1.5 → off60@1.8 → 抬踏板@2
        // 两个音都延到抬踏板收音（spec：同 pitch 重复是新音，不合并）
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0),
            event("cc64", 64, 127, at: 0.5),
            event("off", 60, 0, at: 1.0),
            event("on", 60, 90, at: 1.5),
            event("off", 60, 0, at: 1.8),
            event("cc64", 64, 0, at: 2.0),
        ])
        XCTAssertEqual(result.notes.count, 2)
        XCTAssertEqual(result.notes.map(\.onsetSec), [0, 1.5])
        XCTAssertEqual(result.notes.map(\.endSec), [2.0, 2.0])
    }

    func testNoteOffWithoutPedalEndsImmediately() {
        let result = MidiTakeParser.parse(events: [
            event("on", 64, 90, at: 0),
            event("cc64", 64, 127, at: 0.2),
            event("off", 64, 0, at: 1.0),
            event("cc64", 64, 0, at: 3.0),
        ])
        _ = result
        // 换一组：踏板从未踩下
        let plain = MidiTakeParser.parse(events: [
            event("on", 64, 90, at: 0),
            event("off", 64, 0, at: 1.0),
        ])
        XCTAssertEqual(plain.notes[0].endSec, 1.0, accuracy: 0.0001, "无踏板 → off 即收音")
    }

    func testVelocityZeroNoteOnTreatedAsOff() {
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0),
            event("on", 60, 0, at: 1.0), // velocity=0 noteOn = noteOff（双保险）
        ])
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertEqual(result.notes[0].endSec, 1.0, accuracy: 0.0001)
    }

    func testInterruptionSplitsSegments() {
        // 断连起点 @2s：0–2s 的音在段 0，2s 之后的音在段 1（tempo 估计不跨间隙，§5）
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0),
            event("off", 60, 0, at: 0.5),
            event("on", 62, 100, at: 1.0),
            event("off", 62, 0, at: 1.5),
            event("on", 64, 100, at: 3.0),
            event("off", 64, 0, at: 3.5),
            event("on", 65, 100, at: 4.0),
            event("off", 65, 0, at: 4.5),
        ], interruptionRanges: [2])
        XCTAssertEqual(result.notes.count, 4)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0], 0..<2)
        XCTAssertEqual(result.segments[1], 2..<4)
        XCTAssertEqual(result.segmentIndexOfNote, [0, 0, 1, 1])
    }

    func testSuspiciousCounted() {
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0, suspicious: true),
            event("off", 60, 0, at: 0.5),
            event("cc64", 64, 127, at: 0.6, suspicious: true),
        ])
        XCTAssertEqual(result.suspiciousCount, 2)
    }

    func testEmptyEventsSafe() {
        let result = MidiTakeParser.parse(events: [], interruptionRanges: [1])
        XCTAssertEqual(result.notes.count, 0)
        XCTAssertEqual(result.segments.count, 0)
    }

    // MARK: - gate 返修：EOS flush 乱序（M2-GATE-REWORK.md 精确复现）

    func testEOSFlushOrderingPedalHeldToStreamEnd() {
        // 踏板踩下后从不抬起：早 onset 音被踏板挂起（pedalExtended），
        // 晚 onset 音到结束仍按住（active）。EOS flush 不得乱序。
        // 流在 @3 结束（末事件在 @2，结束时刻由调用方传入）
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0),
            event("cc64", 64, 127, at: 0.5),
            event("off", 60, 0, at: 1.0),   // 踏板踩着 → 60 进 pedalExtended，onset=0
            event("on", 62, 100, at: 2.0),  // 仍按住 → active，onset=2
            // 流 @3 结束，踏板未抬起
        ], streamEndSec: 3.0)
        XCTAssertEqual(result.notes.count, 2)
        XCTAssertEqual(result.notes.map(\.onsetSec), [0, 2], "notes 必须按 onset 升序")
        XCTAssertEqual(result.notes.map(\.pitch), [60, 62], "排序后 [60@0, 62@2]")
        for end in result.notes.map(\.endSec) {
            XCTAssertEqual(end, 3.0, accuracy: 0.0001, "两者都在流末收音")
        }
        XCTAssertEqual(result.segments, [0..<2], "单段")
    }

    func testEOSFlushOrderingWithInterruptionSplit() {
        // 交错 flush + 断连：排序后段边界仍正确（段号随 onset 单调，范围连续）
        let result = MidiTakeParser.parse(events: [
            event("on", 60, 100, at: 0),
            event("cc64", 64, 127, at: 0.5),
            event("off", 60, 0, at: 1.0),   // 60@0 进 pedalExtended（段 0）
            event("on", 62, 100, at: 1.5),  // 62@1.5 仍按住（段 0）
            // 断连 @2
            event("on", 64, 100, at: 3.0),  // 64@3（段 1）
            event("cc64", 64, 0, at: 3.5),  // 抬踏板 → 60 收音 @3.5（段 1！onset 已过断连切分？onset=0 → 段 0）
            event("off", 64, 0, at: 4.0),
            event("on", 65, 100, at: 4.5),
            // 流 @5 结束：62@1.5、65@4.5 在 EOS 按住 flush
        ], interruptionRanges: [2])
        XCTAssertEqual(result.notes.count, 4)
        // 排序后：60@0(段0) → 62@1.5(段0) → 64@3(段1) → 65@4.5(段1)
        XCTAssertEqual(result.notes.map(\.pitch), [60, 62, 64, 65], "按 onset 升序（60 的收音在 3.5 但 onset 仍最早）")
        XCTAssertEqual(result.notes.map(\.onsetSec), [0, 1.5, 3.0, 4.5])
        XCTAssertEqual(result.segmentIndexOfNote, [0, 0, 1, 1], "段号由 onset 落点决定，与收音时刻无关")
        XCTAssertEqual(result.segments, [0..<2, 2..<4], "排序后段边界连续")
    }
}
