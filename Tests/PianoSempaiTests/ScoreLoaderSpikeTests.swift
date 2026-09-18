import XCTest
import SheetMusicCore
import SheetMusicLoader
@testable import PianoSempai

/// Spike A 单测：确认 ScoreLoader 在本工程内可解析 MusicXML 与 .mscz（zip 含 .mscx）。
final class ScoreLoaderSpikeTests: XCTestCase {

    private func locate(_ name: String, _ ext: String) throws -> URL {
        // 测试宿主是 app，Bundle.main 即 app bundle；测试自有资源走 Bundle(for:)
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext),
            "resource \(name).\(ext) not found"
        )
    }

    func testMusicXMLSampleLoads32Measures() throws {
        let score = try ScoreLoader.loadScore(contentsOf: locate("SpikeSample32", "musicxml"))
        let measures = score.parts.first?.staves.first?.measures.count ?? 0
        XCTAssertEqual(measures, 32)

        var noteCount = 0
        for staff in score.parts.first?.staves ?? [] {
            for measure in staff.measures {
                for voice in measure.voices {
                    for element in voice.elements {
                        if case let .chord(chord) = element {
                            noteCount += chord.notes.count
                        }
                    }
                }
            }
        }
        XCTAssertEqual(noteCount, 256) // 32 小节 × 8 个四分音符
    }

    func testMsczZipLoads() throws {
        let url = try locate("Fixture", "mscz")
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(ScoreLoader.sniff(bytes), .mscz, "mscz 应被 sniff 识别为 zip 容器")
        let score = try ScoreLoader.loadScore(contentsOf: url)
        let measures = score.parts.first?.staves.first?.measures.count ?? 0
        XCTAssertGreaterThan(measures, 0, "mscz 解析后应至少有 1 个小节")
    }

    func testNotatedSecondsMapping() throws {
        let score = try ScoreLoader.loadScore(contentsOf: try locate("SpikeSample32", "musicxml"))
        let c0 = score.cursor(atSeconds: 0)
        let c1 = score.cursor(atSeconds: 10)
        XCTAssertEqual(c0.measureIndex, 0)
        XCTAssertGreaterThanOrEqual(c1.measureIndex, c0.measureIndex, "时间越晚光标小节不应回退")
        XCTAssertEqual(score.seconds(at: c0), 0, accuracy: 0.001)
    }
}
