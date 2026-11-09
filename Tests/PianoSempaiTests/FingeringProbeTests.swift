import XCTest
@testable import PianoSempai
import SheetMusicCore
import SheetMusicLoader
import SheetMusicLayout
import SheetMusicLayoutApple

/// G11 探针（Stage A 前置实证）：验证 .mscz 路径的 fingerings 真能从
/// ScoreLoader 走到 Score 模型（MSCXDecoder+Fingering → Note.fingerings）。
/// 这是 app 层指法叠加层数据源成立的最小证据；临时文件，实证后转正为
/// FingeringsOverlay 的数据源测试。
final class FingeringProbeTests: XCTestCase {
    func testMSCXFixtureFingeringsReachScore() throws {
        let url = Bundle(for: FingeringProbeTests.self)
            .url(forResource: "FingeringFixture", withExtension: "mscz")
        let fixture = try XCTUnwrap(url, "FingeringFixture.mscz missing from test bundle")
        let score = try ScoreLoader.loadScore(contentsOf: fixture)
        var hits: [(pitch: Int, text: String)] = []
        for part in score.parts {
            for staff in part.staves {
                for measure in staff.measures {
                    for voice in measure.voices {
                        for element in voice.elements {
                            guard case let .chord(chord) = element else { continue }
                            for note in chord.notes {
                                for f in note.fingerings { hits.append((note.pitch, f.text)) }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(hits.count, 3, "fixture has 3 fingered notes; got \(hits)")
        XCTAssertEqual(hits.map(\.text), ["1", "2", "3"])
        XCTAssertEqual(hits.map(\.pitch), [60, 61, 62])
    }
}

/// G11 Stage A（ADR-0014）：FingeringAnnotationBuilder 纯函数测试。
/// 布局走练习室真实路径（PracticeScoreScrollView.rebuild 自动档逐字镜像：
/// install → ScoreLineBreaker.apply(自动) → LayoutEngine.layout），
/// 不发明第二条布局路径。红线同 G7：只读叠加，不碰判分链。
    // MARK: 布局 harness（镜像 PracticeScoreScrollView.rebuild）

    /// 练习室 rebuild 自动档路径：先装 CoreText 字体度量（DEBUG 下不装会命中
    /// Stub provider 断言），再 ScoreLineBreaker.apply 清原稿换行，最后
    /// LayoutEngine.layout。options 与 makeOptions(staffSize: 28) 同值
    /// （honor + 无 break 徽章）；宽度 330 同 ScoreLineFitTests 的假设。
    /// 返回 (displayScore, document) 二元组——app 侧 builder 正是用同一份
    /// displayScore + document 调用（noteID 必须同源）。
fileprivate func layOutForPractice(_ score: Score) -> (displayScore: Score, document: LayoutDocument) {
        _ = SheetMusicLayoutApple.install
        let laid = ScoreLineBreaker.apply(to: score, measuresPerLine: 0)
        var options = ScoreViewOptions(staffSize: 28, wrapToViewWidth: true, breakPolicy: .honor)
        options.breakIndicatorVisibility = .none
        let document = LayoutEngine.layout(score: laid, options: options, availableWidth: 330)
        return (laid, document)
    }

fileprivate func loadFixture() throws -> Score {
        let url = Bundle(for: FingeringProbeTests.self)
            .url(forResource: "FingeringFixture", withExtension: "mscz")
        let fixture = try XCTUnwrap(url, "FingeringFixture.mscz missing from test bundle")
        return try ScoreLoader.loadScore(contentsOf: fixture)
    }

    /// 内存单音 Score（照 PracticeCoreTests.makeMiniScore 的构造模式）：一小节
    /// 单 staff 单 voice，调号/拍号/谱号 + 一个四分音符，指法可注入。
    private func makeSingleNoteScore(fingerings: [Fingering]) -> Score {
        let elements: [VoiceElement] = [
            .keySignature(KeySignature(concertKey: 0)),
            .timeSignature(TimeSignature(numerator: 4, denominator: 4)),
            .clef(Clef(concertClefType: "G")),
            .chord(Chord(duration: .quarter, notes: ChordNotes([
                Note(pitch: 60, tpc: 21, fingerings: fingerings)
            ]))),
        ]
        let measure = Measure(voices: [Voice(elements: elements)])
        let staff = Staff(defaultClefType: nil, measures: [measure])
        let part = Part(id: "P1", instrument: Instrument(id: "piano"), staves: IdentifiedArray([staff]))
        return Score(division: 480,
                     parts: IdentifiedArray([part]),
                     systemMeasures: IdentifiedArray([SystemMeasure()]))
    }

    /// document 几何里普通 `.chord` 的音符总数（与 builder 同一 11 槽位遍历）。
fileprivate func chordNoteCount(in document: LayoutDocument) -> Int {
        var count = 0
        for system in document.systems {
            for measure in system.measures {
                for element in measure.elements {
                    guard case let .chord(notes, _, _, _, _, _, _, _, _, _, _) = element else { continue }
                    count += notes.count
                }
            }
        }
        return count
    }

final class FingeringOverlayTests: XCTestCase {

    // MARK: 测试

    /// fixture（3 音全带指法）经真实布局 → 3 条标注，文本按文档序 1/2/3，
    /// frame 宽 == sp*1.1（与 Numbered 同一几何契约）。
    func testBuilderProducesAnnotationsFromLayout() throws {
        let (displayScore, document) = layOutForPractice(try loadFixture())
        let annotations = FingeringAnnotationBuilder.build(score: displayScore, document: document)
        XCTAssertEqual(annotations.count, 3, "3 个带指法音符应各产生 1 条标注")
        XCTAssertEqual(annotations.map(\.text), ["1", "2", "3"], "文档序（system→measure→note）")
        let sp = document.metrics.sp
        for annotation in annotations {
            XCTAssertEqual(annotation.frame.width, sp * 1.1, accuracy: 0.0001,
                           "符头框宽与 NumberedNotation 同构（sp*1.1）")
        }
    }

    /// 无指法音跳过：fixture 全部音符有指法 → 标注数 == 几何音符数（一个不丢）；
    /// 内存谱单音 fingerings 为空 → builder 空集不报错（.musicxml/.mid 导入谱
    /// 的自然形态，ADR-0014 红线：空集而非崩/假数据）。
    func testBuilderSkipsUnfingeredAndGraceNotes() throws {
        let (displayScore, document) = layOutForPractice(try loadFixture())
        let total = chordNoteCount(in: document)
        XCTAssertEqual(total, 3, "fixture 恰 3 个普通 chord 音符（无 grace）")
        let annotations = FingeringAnnotationBuilder.build(score: displayScore, document: document)
        XCTAssertEqual(annotations.count, total, "全指法谱不丢音：标注数 == 几何音符数")

        let (bareScore, bareDocument) = layOutForPractice(makeSingleNoteScore(fingerings: []))
        XCTAssertTrue(
            FingeringAnnotationBuilder.build(score: bareScore, document: bareDocument).isEmpty,
            "无指法音不产生标注（grace 走 score[noteID]==nil 同一跳过链）")
    }

    /// role 过滤：只取 role == .fingering 的首条——纯吉他手/弦号不显示；
    /// .fingering 与弦号并存时首条 .fingering 胜出。
    func testFingeringRoleFilter() throws {
        let (guitarScore, guitarDocument) = layOutForPractice(
            makeSingleNoteScore(fingerings: [Fingering(text: "p", role: .rightHandGuitar)]))
        XCTAssertTrue(
            FingeringAnnotationBuilder.build(score: guitarScore, document: guitarDocument).isEmpty,
            "只有吉他手指法（p/i/m/a）不应标成指法数字")

        let (mixedScore, mixedDocument) = layOutForPractice(
            makeSingleNoteScore(fingerings: [Fingering(text: "1"), Fingering(text: "x", role: .stringNumber)]))
        let mixed = FingeringAnnotationBuilder.build(score: mixedScore, document: mixedDocument)
        XCTAssertEqual(mixed.count, 1, "弦号不产生第二条标注")
        XCTAssertEqual(mixed.first?.text, "1", "首条 .fingering role 胜出")
    }

    /// 符头框几何与 NumberedNotation 逐字同构（两 overlay 叠加时锚点必须一致）。
    func testNoteFrameMatchesNumberedGeometry() {
        XCTAssertEqual(
            FingeringAnnotationBuilder.noteFrame(centerX: 10, centerY: 20, sp: 4),
            NumberedAnnotationBuilder.noteFrame(centerX: 10, centerY: 20, sp: 4))
    }
}

/// G11 Stage B（ADR-0014）：练习室「指法」开关接线测试。@State 无法在单测里
/// 直接驱动，按 brief 口径只锁类型层数据路径：空标注视图 init/body smoke +
/// fixture 布局后 builder 非空，以及双开关独立性契约（同一 (displayScore,
/// document) 上两套标注数据各自成立、互不干扰——简谱标上方/指法标下方零几何
/// 冲突的前提）。开关状态本身由 PracticeScoreScrollView 的 `if showFingerings`
/// 纯派生，无需首启副作用（G6 耳训教训不适用）。
final class FingeringToggleTests: XCTestCase {

    /// 视图 init smoke（编译即门槛，不做 UI 快照）：空标注视图可构造、body 可
    /// 求值；数据路径：fixture 经练习室真实布局 → builder 非空，开关打开即有
    /// 内容可画。
    func testOverlayViewSmokeAndDataPathNonEmpty() throws {
        let view = FingeringsOverlayView(annotations: [], sp: 8)
        _ = view.body
        let (displayScore, document) = layOutForPractice(try loadFixture())
        XCTAssertFalse(
            FingeringAnnotationBuilder.build(score: displayScore, document: document).isEmpty,
            "fixture 带指法 → 开关打开时 overlay 数据非空")
    }

    /// 双开关独立性契约：同一 (displayScore, document)——简谱对每个普通 chord
    /// 音符都产生标注（count == 几何音符数），指法只标带指法的 3 音。两数据集
    /// 独立生成、互不干扰，是「两 chip 可同开、零几何冲突」的数据层前提。
    func testBothOverlaysIndependentFromSameDocument() throws {
        let (displayScore, document) = layOutForPractice(try loadFixture())
        let numbered = NumberedAnnotationBuilder.build(score: displayScore, document: document)
        let fingered = FingeringAnnotationBuilder.build(score: displayScore, document: document)
        XCTAssertEqual(numbered.count, chordNoteCount(in: document),
                       "简谱：每个普通 chord 音符都有标注（与指法开关无关）")
        XCTAssertEqual(fingered.count, 3, "指法：只有带指法的音符有标注（与简谱开关无关）")
    }
}
