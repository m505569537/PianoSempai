import XCTest
import SheetMusicCore
@testable import PianoSempai

/// P2 M3：NoteAligner（SPEC §5）+ parangonar 对拍夹具验收（§5 对拍口径）。
/// 投影：match=correct；deletion=missing+wrongPitch；insertion=extra+wrongPitch。
/// 6 组夹具投影计数必须与 expected.json 完全一致；timing 不做逐毫秒断言。
final class NoteAlignerTests: XCTestCase {

    // MARK: - 夹具加载（folder reference：Fixtures/<case>/*.json）

    private struct FixtureRef: Decodable {
        let id: Int
        let pitch: Int
        let onsetBeat: Double
        let durationBeats: Double
        let measureIndex: Int
        let beatInMeasure: Double
        let hand: String
        let isGrace: Bool
    }

    private struct FixturePerf: Decodable {
        let pitch: Int
        let onsetSec: Double
        let endSec: Double
        let velocity: Int
        let isSuspicious: Bool
    }

    private struct FixtureExpected: Decodable {
        struct Counts: Decodable { let match: Int; let deletion: Int; let insertion: Int }
        let counts: Counts
    }

    private func fixtureURL(caseDir: String, file: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: file, withExtension: "json",
                subdirectory: "Fixtures/\(caseDir)"
            ),
            "夹具缺失：Fixtures/\(caseDir)/\(file).json（folder reference 层级应保留）"
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func loadCase(_ caseDir: String) throws -> (
        refs: [ReferenceNote], played: [PlayedNote],
        expectedMatch: Int, expectedDeletion: Int, expectedInsertion: Int
    ) {
        let refs = try decode([FixtureRef].self, url: fixtureURL(caseDir: caseDir, file: "reference"))
            .map { r in
                ReferenceNote(
                    id: r.id, pitch: UInt8(max(0, min(127, r.pitch))),
                    onsetBeat: r.onsetBeat, durationBeats: r.durationBeats,
                    measureIndex: r.measureIndex, beatInMeasure: r.beatInMeasure,
                    hand: Hand(rawValue: r.hand) ?? .unknown, isGrace: r.isGrace
                )
            }
        let played = try decode([FixturePerf].self, url: fixtureURL(caseDir: caseDir, file: "performance"))
            .map { p in
                PlayedNote(
                    pitch: UInt8(max(0, min(127, p.pitch))), onsetSec: p.onsetSec,
                    endSec: p.endSec, velocity: UInt8(max(0, min(127, p.velocity))),
                    isSuspicious: p.isSuspicious
                )
            }
        let expected = try decode(FixtureExpected.self, url: fixtureURL(caseDir: caseDir, file: "expected"))
        return (refs, played, expected.counts.match, expected.counts.deletion, expected.counts.insertion)
    }

    /// 投影计数（§5 口径）：match=correct；deletion=missing+wrongPitch；insertion=extra+wrongPitch
    private func projected(_ result: AlignmentResult) -> (match: Int, deletion: Int, insertion: Int) {
        (
            result.aligned.filter { $0.cls == .correct }.count,
            result.missingCount + result.wrongCount,
            result.extraCount + result.wrongCount
        )
    }

    private func assertFixture(_ caseDir: String, startBPM: Double = 60) throws {
        let (refs, played, m, d, i) = try loadCase(caseDir)
        let result = NoteAligner.align(
            references: refs, played: played,
            tolerance: .beginner, startBPM: startBPM
        )
        let projection = projected(result)
        XCTAssertEqual(projection.match, m, "\(caseDir)：match 投影不一致")
        XCTAssertEqual(projection.deletion, d, "\(caseDir)：deletion 投影不一致（missing+wrongPitch）")
        XCTAssertEqual(projection.insertion, i, "\(caseDir)：insertion 投影不一致（extra+wrongPitch）")
    }

    func testFixture01Perfect() throws { try assertFixture("01_perfect") }
    func testFixture02WrongPitch() throws { try assertFixture("02_wrong_pitch") }
    func testFixture03Missing() throws { try assertFixture("03_missing") }
    func testFixture04Extra() throws { try assertFixture("04_extra") }
    func testFixture05TempoFlex() throws { try assertFixture("05_tempo_flex") }
    func testFixture06Pedaled() throws { try assertFixture("06_pedaled") }

    // MARK: - 中断段（跨间隙禁匹配）

    func testInterruptionSegmentsNoCrossGapMatching() {
        // 12 个参考音 beat 0..11（3 小节，BPM60 = 1s/拍）；
        // 断连缺口吞掉整个第 2 小节（beat 4–7）→ coversFullScope=false
        var refs: [ReferenceNote] = []
        for beat in 0..<12 {
            refs.append(ReferenceNote(
                id: beat, pitch: UInt8(60 + beat % 5), onsetBeat: Double(beat),
                durationBeats: 1, measureIndex: beat / 4, beatInMeasure: Double(beat % 4),
                hand: .right, isGrace: false
            ))
        }
        var played: [PlayedNote] = []
        // 段 0：beat 0,1（秒 0,1）
        for (beat, sec) in [(0, 0.0), (1, 1.0)] {
            played.append(PlayedNote(pitch: UInt8(60 + beat % 5), onsetSec: sec, endSec: sec + 0.5, velocity: 90, isSuspicious: false))
        }
        // 段 1：beat 8..11（秒 8..11）；beat 4..7 = 整小节缺失
        for (beat, sec) in [(8, 8.0), (9, 9.0), (10, 10.0), (11, 11.0)] {
            played.append(PlayedNote(pitch: UInt8(60 + beat % 5), onsetSec: sec, endSec: sec + 0.5, velocity: 90, isSuspicious: false))
        }
        let result = NoteAligner.align(
            references: refs, played: played,
            segments: [0..<2, 2..<6],
            tolerance: .beginner, startBPM: 60
        )
        // 断点续弹语义（PRD「重连断点继续」）：续弹段带 +5s 段偏移，从断点后第一个
        // 音高吻合的参考音（beat 3）继续——beat 3..6 在秒 8..11 弹对；
        // beat 2（续弹起点前漏）与 beat 7..11（take 结束未弹）= missing ×6；
        // 两种时序解读（续弹 beat 3 起 / 直接跳 beat 8 起）pitch 完全相同，
        // 对齐器按段偏移选择续弹口径（PRD L64 断点继续）。
        XCTAssertEqual(result.aligned.filter { $0.cls == .correct }.count, 6)
        XCTAssertEqual(result.missingCount, 6)
        XCTAssertEqual(result.extraCount, 0, "跨间隙缺口不产 extra（段独立对齐）")
        XCTAssertEqual(result.coversFullScope, false, "第二小节后有未弹参考音 → 覆盖不完整")
        // 身份级断言（gate）：不仅核对计数，还核对「配对到的是哪些参考拍号」，
        // 彻底区分续弹 vs 跳到 beat8 两种解读。ref beat index = measure*4 + beatInMeasure。
        func refBeat(_ a: AlignedNote) -> Int {
            (a.refMeasureIndex ?? -1) * 4 + Int(a.refBeatInMeasure ?? -1)
        }
        let correctBeats = Set(result.aligned.filter { $0.cls == .correct }.map(refBeat))
        let missingBeats = Set(result.aligned.filter { $0.cls == .missing }.map(refBeat))
        XCTAssertEqual(correctBeats, [0, 1, 3, 4, 5, 6], "段1 必须续弹到 beat3-6，而非跳到 beat8-11")
        XCTAssertEqual(missingBeats, [2, 7, 8, 9, 10, 11], "beat2 续弹漏 + beat7-11 未弹")
        // 中断空白不判漏（PRD L64）：静默期本身不产生 missing/extra
        // （beat 4..7 的缺失来自「续弹跳过」，不是空白期惩罚——空白期无事件无扣分）
    }

    // MARK: - 和弦（同 onsetBeat 多参考音）

    func testChordNotesPairWithoutForcingOrder() {
        let refs = [
            ReferenceNote(id: 0, pitch: 60, onsetBeat: 0, durationBeats: 1, measureIndex: 0, beatInMeasure: 0, hand: .right, isGrace: false),
            ReferenceNote(id: 1, pitch: 64, onsetBeat: 0, durationBeats: 1, measureIndex: 0, beatInMeasure: 0, hand: .right, isGrace: false),
            ReferenceNote(id: 2, pitch: 67, onsetBeat: 1, durationBeats: 1, measureIndex: 0, beatInMeasure: 1, hand: .right, isGrace: false),
        ]
        // 演奏顺序与参考序相反（同刻和弦内不强制顺序，按 pitch 最近配对）
        let played = [
            PlayedNote(pitch: 64, onsetSec: 0.02, endSec: 0.9, velocity: 90, isSuspicious: false),
            PlayedNote(pitch: 60, onsetSec: 0.04, endSec: 0.9, velocity: 90, isSuspicious: false),
            PlayedNote(pitch: 67, onsetSec: 1.0, endSec: 1.9, velocity: 90, isSuspicious: false),
        ]
        let result = NoteAligner.align(
            references: refs, played: played, tolerance: .beginner, startBPM: 60
        )
        XCTAssertEqual(result.aligned.filter { $0.cls == .correct }.count, 3)
        XCTAssertEqual(result.extraCount, 0)
        XCTAssertEqual(result.missingCount, 0)
    }

    // MARK: - 低置信（锚点 <3；匹配率 <0.5）

    func testLowConfidenceFewerThanThreeAnchors() {
        let refs = [
            ReferenceNote(id: 0, pitch: 60, onsetBeat: 0, durationBeats: 1, measureIndex: 0, beatInMeasure: 0, hand: .right, isGrace: false),
            ReferenceNote(id: 1, pitch: 62, onsetBeat: 1, durationBeats: 1, measureIndex: 0, beatInMeasure: 1, hand: .right, isGrace: false),
        ]
        let played = [
            PlayedNote(pitch: 60, onsetSec: 0, endSec: 0.9, velocity: 90, isSuspicious: false),
            PlayedNote(pitch: 62, onsetSec: 1, endSec: 1.9, velocity: 90, isSuspicious: false),
        ]
        let result = NoteAligner.align(references: refs, played: played, tolerance: .beginner, startBPM: 60)
        XCTAssertEqual(result.confidence, 0, accuracy: 1.0, "置信度仍在 0...1")
        XCTAssertTrue(result.lowConfidenceReasons.contains("对齐锚点不足 3 个，节奏图不可靠"))
        XCTAssertLessThan(result.confidence, 1.0)
    }

    func testLowConfidenceMatchRateBelowHalf() {
        var refs: [ReferenceNote] = []
        for beat in 0..<10 {
            refs.append(ReferenceNote(
                id: beat, pitch: UInt8(60 + beat), onsetBeat: Double(beat), durationBeats: 1,
                measureIndex: beat / 4, beatInMeasure: Double(beat % 4), hand: .right, isGrace: false
            ))
        }
        // 只弹对 3 个（60/61/62），其余没弹
        let played = (0..<3).map { beat in
            PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat), endSec: Double(beat) + 0.5, velocity: 90, isSuspicious: false)
        }
        let result = NoteAligner.align(references: refs, played: played, tolerance: .beginner, startBPM: 60)
        let matchRate = Double(result.matchedRefCount) / 10.0
        XCTAssertLessThan(matchRate, 0.5)
        XCTAssertTrue(result.lowConfidenceReasons.contains("匹配率低于 50%，多数音符没对上"))
    }

    // MARK: - 保序节奏图（isotonic）与首遍切分

    func testIsotonicEnforcesMonotonicSeconds() {
        let points = [
            NoteAligner.TempoPoint(beat: 0, sec: 0),
            NoteAligner.TempoPoint(beat: 1, sec: 2.0),  // 违序（应 ≤ 后续）
            NoteAligner.TempoPoint(beat: 2, sec: 1.0),
            NoteAligner.TempoPoint(beat: 3, sec: 3.0),
        ]
        let fitted = NoteAligner.isotonic(points)
        for k in 1..<fitted.count {
            XCTAssertGreaterThanOrEqual(fitted[k].sec, fitted[k - 1].sec - 0.0001, "PAVA 后 sec 必须非降")
        }
    }

    func testMultiPassDetectionTakesFirstPass() {
        // 一遍 8 音（beat0..7 → sec0..7），再从头弹一遍（sec10..17）
        var refs: [ReferenceNote] = []
        var played: [PlayedNote] = []
        for beat in 0..<8 {
            refs.append(ReferenceNote(
                id: beat, pitch: UInt8(60 + beat), onsetBeat: Double(beat), durationBeats: 1,
                measureIndex: beat / 4, beatInMeasure: Double(beat % 4), hand: .right, isGrace: false
            ))
        }
        for beat in 0..<8 { // 第一遍：秒 0..7
            played.append(PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat), endSec: Double(beat) + 0.5, velocity: 90, isSuspicious: false))
        }
        for beat in 0..<8 { // 第二遍：秒 10..17（超出范围末拍后重启）
            played.append(PlayedNote(pitch: UInt8(60 + beat), onsetSec: 10.0 + Double(beat), endSec: 10.5 + Double(beat), velocity: 90, isSuspicious: false))
        }
        let result = NoteAligner.align(references: refs, played: played, tolerance: .beginner, startBPM: 60)
        XCTAssertEqual(result.passesPlayed, 2, "检测到 2 遍")
        // 本批取首遍：第二遍的音不产生 extra
        XCTAssertEqual(result.aligned.filter { $0.cls == .correct }.count, 8)
        XCTAssertEqual(result.extraCount, 0, "第二遍不计 extra（按首遍评分，§5）")
    }

    // MARK: - tempoMap 弹性（渐快不硬套等比）

    func testElasticTempoMapFollowsAccelerando() {
        var refs: [ReferenceNote] = []
        var played: [PlayedNote] = []
        var sec = 0.0
        var secPerBeat = 1.0
        for beat in 0..<16 {
            refs.append(ReferenceNote(
                id: beat, pitch: UInt8(60 + beat % 7), onsetBeat: Double(beat), durationBeats: 1,
                measureIndex: beat / 4, beatInMeasure: Double(beat % 4), hand: .right, isGrace: false
            ))
            played.append(PlayedNote(pitch: UInt8(60 + beat % 7), onsetSec: sec, endSec: sec + 0.4, velocity: 90, isSuspicious: false))
            sec += secPerBeat
            secPerBeat *= 0.92 // 渐快
        }
        let result = NoteAligner.align(references: refs, played: played, tolerance: .beginner, startBPM: 60)
        XCTAssertEqual(result.aligned.filter { $0.cls == .correct }.count, 16, "弹性节奏图应跟住渐快")
        XCTAssertEqual(result.wrongCount, 0)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6, "高置信")
        // tempoMap 摘要反映渐快（末段 BPM > 起速）
        XCTAssertGreaterThan(result.tempoMap.maxBPM, 60.0)
    }
}
