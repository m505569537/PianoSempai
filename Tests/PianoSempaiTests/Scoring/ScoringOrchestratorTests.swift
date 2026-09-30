import SwiftData
import XCTest
import SheetMusicCore
import SheetMusicLoader
@testable import PianoSempai

/// P2 M5a：分析编排（纯 analyzeTake + IO 幂等 upsert + 过关落库）+ 谱可用性三态 + 示例曲目录。
final class ScoringOrchestratorTests: XCTestCase {

    // MARK: 夹具

    private func makeRefs(count: Int = 8) -> [ReferenceNote] {
        (0..<count).map { beat in
            ReferenceNote(id: beat, pitch: UInt8(60 + beat), onsetBeat: Double(beat),
                          durationBeats: 1, measureIndex: beat / 4, beatInMeasure: Double(beat % 4),
                          hand: .right, isGrace: false)
        }
    }

    private func perfectPlayed(count: Int = 8) -> [PlayedNote] {
        (0..<count).map { beat in
            PlayedNote(pitch: UInt8(60 + beat), onsetSec: Double(beat),
                       endSec: Double(beat) + 0.8, velocity: 80, isSuspicious: false)
        }
    }

    private func makeInput(
        refs: [ReferenceNote]? = nil,
        played: [PlayedNote]? = nil,
        isFreePlay: Bool = false
    ) -> ScoringOrchestrator.Input {
        ScoringOrchestrator.Input(
            references: refs ?? makeRefs(),
            played: played ?? perfectPlayed(),
            segmentStartSecs: [],
            calibration: nil,
            referenceTempo: 60,
            standards: .beginner,
            startBPM: 60,
            isFreePlay: isFreePlay
        )
    }

    // MARK: 夹具（IO 层）

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Take.self, ScoreFile.self, Piece.self, TakeAnalysis.self, VelocityCalibration.self,
            // CoursePathState：ADR-0003 状态机接线后，过关/回退会重算 current* 派生缓存
            CoursePathState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func locate(_ name: String, _ ext: String) throws -> URL {
        // 测试宿主是 app，Bundle.main 即 app bundle；测试自有资源走 Bundle(for:)
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext),
            "resource \(name).\(ext) not found"
        )
    }

    private func docsURL(_ relativePath: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativePath)
    }

    /// 追加写 jsonl（TakeStore 的真实落盘格式；返回沙盒相对路径）
    @discardableResult
    private func writeJSONL(_ records: [RawMIDIEventRecord], relative: String) throws -> String {
        let url = docsURL(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        for record in records { try TakeStore.append(record, to: url) }
        return relative
    }

    // MARK: D1 完美演奏：六维非 nil（hands 单 hand = nil）、canEvaluate、达标

    func testPerfectPerformanceOutcome() {
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput())
        XCTAssertNil(outcome.errorMessage)
        XCTAssertTrue(outcome.canEvaluate)
        XCTAssertTrue(outcome.passesHardMetrics)
        XCTAssertTrue(outcome.eligibleForPass)
        XCTAssertNotNil(outcome.pitchScore)
        XCTAssertNotNil(outcome.rhythmScore)
        XCTAssertNotNil(outcome.tempoScore)
        XCTAssertNotNil(outcome.dynamicsScore)
        XCTAssertNotNil(outcome.continuityScore)
        // 单 hand 谱 → hands nil（§6）
        XCTAssertNil(outcome.handsScore)
        XCTAssertNotNil(outcome.weakTotal)
        XCTAssertTrue(outcome.lowConfidenceReasons.isEmpty, "完美演奏不应有低置信原因")
        XCTAssertEqual(outcome.passMetrics.count, 3, "三硬指标明细")
    }

    // MARK: D2 无参考谱 / 自由弹奏 → 统计级，不出对错分

    func testNoReferencesGivesStatisticsOutcome() {
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput(refs: []))
        XCTAssertFalse(outcome.canEvaluate)
        XCTAssertFalse(outcome.eligibleForPass, "不可评 take 不参与过关计数")
        XCTAssertNil(outcome.pitchScore, "无参考谱不出对错分（红线 1）")
        XCTAssertNil(outcome.weakTotal)
    }

    func testFreePlayGivesStatisticsOutcome() {
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput(isFreePlay: true))
        XCTAssertFalse(outcome.canEvaluate)
        XCTAssertNil(outcome.pitchScore)
        XCTAssertTrue(outcome.lowConfidenceReasons.contains(where: { $0.contains("自由弹奏") }))
    }

    // MARK: D3 低置信 → canEvaluate=false（eligible=false，不清零是 streak 层语义）

    func testLowConfidenceOutcomeNotEligible() {
        // 16 参考音只弹 3 个 → 匹配率 < 0.5 → 低置信
        let refs = makeRefs(count: 16)
        let played = perfectPlayed(count: 3)
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput(refs: refs, played: played))
        XCTAssertFalse(outcome.canEvaluate, "低置信 take 不可评（不参与计数也不清零）")
        XCTAssertFalse(outcome.eligibleForPass)
        XCTAssertTrue(outcome.lowConfidenceReasons.contains(where: { $0.contains("匹配率") }))
    }

    // MARK: D4 JSON 编码往返

    func testJSONRoundTrip() throws {
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput())
        let decoder = JSONDecoder()
        let aligned = try decoder.decode([AlignedNote].self, from: Data(outcome.alignmentJSON.utf8))
        XCTAssertFalse(aligned.isEmpty, "alignmentJSON 往返可解码")
        let heat = try decoder.decode([Int: Double].self, from: Data(outcome.measureHeatJSON.utf8))
        _ = heat // 空或非空均可；关键是编码/解码不抛
    }

    // MARK: D5 畸形/空输入 → error outcome，不抛、不假分

    func testEmptyPlayedIsErrorOutcome() {
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput(played: []))
        XCTAssertNotNil(outcome.errorMessage, "空演奏 = error outcome（不抛、不假分）")
        XCTAssertFalse(outcome.canEvaluate)
    }

    // MARK: D6 IO 层：幂等 upsert + 过关落库（in-memory ModelContainer）

    @MainActor
    func testRunTwiceIsIdempotentSingleRow() throws {
        let context = ModelContext(try makeContainer())
        let take = Take(durationSec: 8, taskType: "main", hasMidi: true,
                        midiFileURL: "midi/test.jsonl", measureFrom: 1, measureTo: 2)
        context.insert(take)
        try context.save()

        let refs = makeRefs()
        let events: [RawMIDIEventRecord] = (0..<8).flatMap { beat -> [RawMIDIEventRecord] in
            let t = UInt64(beat * 1_000_000_000)
            return [
                RawMIDIEventRecord(t: t, k: "on", c: 0, n: UInt8(60 + beat), v: 90, suspicious: false),
                RawMIDIEventRecord(t: t + 800_000_000, k: "off", c: 0, n: UInt8(60 + beat), v: 0, suspicious: false),
            ]
        }
        let first = ScoringOrchestrator.analyzeAndStore(
            take: take, piece: nil, references: refs, events: events,
            referenceTempo: 60, standards: .beginner, in: context
        )
        XCTAssertTrue(first.canEvaluate)
        try context.save()

        // 第二次（重算）：仍只有 1 行，take.analysisId 指向它
        _ = ScoringOrchestrator.analyzeAndStore(
            take: take, piece: nil, references: refs, events: events,
            referenceTempo: 60, standards: .beginner, in: context
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<TakeAnalysis>())
        XCTAssertEqual(rows.count, 1, "同 take+version 重算必须幂等（不重复建行）")
        XCTAssertEqual(take.analysisId, rows.first?.entityId)
        XCTAssertTrue(take.isPassEligible)
    }

    @MainActor
    func testRunTwoEligiblePassesMarksPiecePassed() throws {
        let context = ModelContext(try makeContainer())
        let piece = Piece(title: "示例：SpikeSample32（演示用）", book: "示例", number: 0,
                          status: "notStarted", referenceTempo: 60)
        context.insert(piece)

        // 两遍相同的完美演奏 take（时间升序）
        for pass in 0..<2 {
            let take = Take(startedAt: Date(timeIntervalSinceNow: Double(pass * 60)),
                             durationSec: 8, taskType: "main", hasMidi: true,
                             pieceId: piece.entityId)
            context.insert(take)
            let events: [RawMIDIEventRecord] = (0..<8).flatMap { beat -> [RawMIDIEventRecord] in
                let t = UInt64((Double(pass) * 60 + Double(beat)) * 1_000_000_000)
                return [
                    RawMIDIEventRecord(t: t, k: "on", c: 0, n: UInt8(60 + beat), v: 90, suspicious: false),
                    RawMIDIEventRecord(t: t + 800_000_000, k: "off", c: 0, n: UInt8(60 + beat), v: 0, suspicious: false),
                ]
            }
            let outcome = ScoringOrchestrator.analyzeAndStore(
                take: take, piece: piece,
                references: makeRefs(), events: events,
                referenceTempo: 60, standards: .beginner, in: context
            )
            XCTAssertTrue(outcome.canEvaluate)
        }
        try context.save()

        XCTAssertEqual(piece.status, "passed", "连续 2 次可评达标 → 课程引擎写 passed")
        XCTAssertEqual(piece.passedRulesVersion, "P2-scoring-1.0", "过关留痕规则版本")
    }

    // MARK: D7 双谱表 → hands 维有分（§6：单 staff 才 nil）

    func testTwoStaffReferencesYieldHandsScore() {
        let refs: [ReferenceNote] = (0..<8).map { beat in
            ReferenceNote(id: beat, pitch: UInt8(60 + beat), onsetBeat: Double(beat),
                          durationBeats: 1, measureIndex: beat / 4, beatInMeasure: Double(beat % 4),
                          hand: beat < 4 ? .right : .left, isGrace: false)
        }
        let outcome = ScoringOrchestrator.analyzeTake(input: makeInput(refs: refs))
        XCTAssertNil(outcome.errorMessage)
        XCTAssertNotNil(outcome.handsScore, "双 staff 谱（两手都有数据）→ hands 维有分")
        XCTAssertEqual(outcome.handsScore, 100, "两手都全对 → 协同满分")
    }

    // MARK: D8 中断断点续弹：段范围进对齐器（MidiTakeParser.segments 不再被丢弃）

    @MainActor
    func testInterruptedTakeAlignsPerSegment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let refs = makeRefs()
        // 前 4 音 0–3s，断连（第 5s 起），后 4 音 8–11s：单段对齐会被 5s 空白拖垮
        let events: [RawMIDIEventRecord] = (0..<8).flatMap { beat -> [RawMIDIEventRecord] in
            let onset = beat < 4 ? Double(beat) : Double(beat + 4)
            let t = UInt64(onset * 1_000_000_000)
            return [
                RawMIDIEventRecord(t: t, k: "on", c: 0, n: UInt8(60 + beat), v: 90, suspicious: false),
                RawMIDIEventRecord(t: t + 700_000_000, k: "off", c: 0, n: UInt8(60 + beat), v: 0, suspicious: false),
            ]
        }
        let take = Take(durationSec: 14, taskType: "main", hasMidi: true,
                        midiFileURL: "midi/interrupted.jsonl", measureFrom: 1, measureTo: 2)
        context.insert(take)

        let outcome = ScoringOrchestrator.analyzeAndStore(
            take: take, piece: nil, references: refs, events: events,
            interruptionRanges: [5], referenceTempo: 60, standards: .beginner, in: context
        )
        XCTAssertTrue(outcome.canEvaluate, "断点续弹按段锚定，仍应可评（段范围已透传对齐器）")
        XCTAssertEqual(outcome.wrongCount, 0)
        XCTAssertEqual(outcome.missingCount, 0, "中断空白不计漏音（段前缺口只在段内判定）")
        XCTAssertEqual(outcome.extraCount, 0)
        XCTAssertEqual(outcome.continuityScore, 100, "跨中断段起点不计停顿（PRD L64）")
    }

    // MARK: D9 IO 层 run：读磁盘 jsonl + 载谱 → 幂等 upsert（无谱不冒充）

    @MainActor
    func testRunReadsJSONLAndScoreFromDiskThenUpserts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // 真实谱落 Documents（SandboxPaths 只解析存在的相对路径）
        let scoreRel = "midi/m5a-run-test.musicxml"
        let scoreURL = docs.appendingPathComponent(scoreRel)
        try FileManager.default.createDirectory(at: scoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: scoreURL)
        try FileManager.default.copyItem(at: try locate("SpikeSample32", "musicxml"), to: scoreURL)
        defer { try? FileManager.default.removeItem(at: scoreURL) }

        // 参考音真值来自同一份谱（避免手写音高与谱面漂移）；♩=60 → 1 拍 = 1 秒
        let score = try ScoreLoader.loadScore(contentsOf: scoreURL)
        let extracted = ScoreReferenceNotes.extract(score: score, measureRange: 0...1)
        let refs = extracted.notes.filter { !$0.isGrace }
        XCTAssertFalse(refs.isEmpty, "前两小节应有参考音")

        let events: [RawMIDIEventRecord] = refs.flatMap { ref -> [RawMIDIEventRecord] in
            let t = UInt64(max(0, ref.onsetBeat) * 1_000_000_000)
            return [
                RawMIDIEventRecord(t: t, k: "on", c: 0, n: ref.pitch, v: 90, suspicious: false),
                RawMIDIEventRecord(t: t + 700_000_000, k: "off", c: 0, n: ref.pitch, v: 0, suspicious: false),
            ]
        }
        let jsonlRel = try writeJSONL(events, relative: "midi/m5a-run-test.jsonl")
        defer { try? FileManager.default.removeItem(at: docs.appendingPathComponent(jsonlRel)) }

        let scoreFile = ScoreFile(kind: "musicxml", fileURL: scoreRel, title: "SpikeSample32", canFollow: true)
        let take = Take(durationSec: 40, taskType: "main", hasMidi: true,
                        midiFileURL: jsonlRel, measureFrom: 1, measureTo: 2, tempoAvg: 60)
        context.insert(take)

        let outcome = ScoringOrchestrator.run(
            for: take, scoreFile: scoreFile, piece: nil,
            measureFrom: nil, measureTo: nil,
            referenceTempo: 60, standards: .beginner, in: context
        )
        XCTAssertNil(outcome.errorMessage)
        XCTAssertTrue(outcome.canEvaluate, "按谱面真值合成的完美演奏应可评")
        XCTAssertNotNil(outcome.pitchScore)
        XCTAssertEqual(outcome.missingCount, 0)

        let rows = try context.fetch(FetchDescriptor<TakeAnalysis>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(take.analysisId, rows.first?.entityId, "回填 analysisId")
        XCTAssertTrue(take.isPassEligible)
        XCTAssertEqual(rows.first?.engineVersion, ScoringOrchestrator.engineVersion)
    }

    @MainActor
    func testRunWithoutScoreFilePersistsStatisticsRowWithoutFakeScores() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let events: [RawMIDIEventRecord] = (0..<8).flatMap { beat -> [RawMIDIEventRecord] in
            let t = UInt64(beat * 1_000_000_000)
            return [
                RawMIDIEventRecord(t: t, k: "on", c: 0, n: UInt8(60 + beat), v: 90, suspicious: false),
                RawMIDIEventRecord(t: t + 700_000_000, k: "off", c: 0, n: UInt8(60 + beat), v: 0, suspicious: false),
            ]
        }
        let rel = try writeJSONL(events, relative: "midi/m5a-noscore-test.jsonl")
        defer { try? FileManager.default.removeItem(at: docsURL(rel)) }

        let take = Take(durationSec: 10, taskType: "main", hasMidi: true, midiFileURL: rel)
        context.insert(take)

        let outcome = ScoringOrchestrator.run(
            for: take, scoreFile: nil, piece: nil,
            measureFrom: nil, measureTo: nil,
            referenceTempo: 60, standards: .beginner, in: context
        )
        XCTAssertNil(outcome.errorMessage)
        XCTAssertFalse(outcome.canEvaluate, "无谱 → 不可评（不冒充可评分）")
        XCTAssertNil(outcome.pitchScore, "无参考谱不出对错分（红线 1）")
        XCTAssertFalse(outcome.eligibleForPass)

        let rows = try context.fetch(FetchDescriptor<TakeAnalysis>())
        XCTAssertEqual(rows.count, 1, "统计级分析也落一行（可删可重建）")
        XCTAssertNil(rows.first?.pitchScore, "持久化层同样禁止编分")
        XCTAssertFalse(take.isPassEligible)
    }

    // MARK: D10 IO 层 run：上游读取失败 → error outcome，不建行、不清零 streak

    @MainActor
    func testRunWithMissingMIDIFileIsErrorOutcomeWithoutRow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let take = Take(durationSec: 8, taskType: "main", hasMidi: true,
                        midiFileURL: "midi/m5a-missing-\(UUID().uuidString).jsonl")
        context.insert(take)

        let outcome = ScoringOrchestrator.run(
            for: take, scoreFile: nil, piece: nil,
            measureFrom: nil, measureTo: nil,
            referenceTempo: 60, standards: .beginner, in: context
        )
        XCTAssertNotNil(outcome.errorMessage, "读取失败不吞错")
        XCTAssertFalse(outcome.canEvaluate)
        XCTAssertFalse(outcome.passesHardMetrics)
        let rows = try context.fetch(FetchDescriptor<TakeAnalysis>())
        XCTAssertTrue(rows.isEmpty, "失败不建分析行（不假分）")
        XCTAssertNil(take.analysisId)
        XCTAssertFalse(take.isPassEligible, "失败不清零、不冒充可评")
    }

    // MARK: B PracticeSession.persist 透传 pieceId/scoreFileId

    @MainActor
    func testPersistCarriesPieceAndScoreFileIds() throws {
        let container = try ModelContainer(
            for: Take.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let pieceId = UUID()
        let scoreFileId = UUID()
        let summary = TakeSummary(durationSec: 10, noteCount: 5, midiFileName: "x.jsonl")
        let take = PracticeSession.persist(
            summary, taskType: "main", isFreePlay: false,
            startedAt: Date(), interruptions: [], title: "",
            pieceId: pieceId, scoreFileId: scoreFileId, in: context
        )
        XCTAssertEqual(take.pieceId, pieceId)
        XCTAssertEqual(take.scoreFileId, scoreFileId)
    }

    // MARK: C 谱可用性三态 + 示例曲目录

    func testScoreAvailabilityThreeBranches() {
        let sf = ScoreFile(kind: "musicxml", fileURL: "scores/a.musicxml", title: "A", canFollow: true)
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: sf, isSampleEntry: false), .realScore(sf))
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: true), .samplePiece)
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: nil, isSampleEntry: false), .unavailable)
        // 真实谱优先于示例标记
        XCTAssertEqual(ScoreAvailability.resolve(scoreFile: sf, isSampleEntry: true), .realScore(sf))
    }

    func testSampleEntryInCatalogIsNotStartedAndLabeled() throws {
        let entries = CatalogLoader.loadBuiltin()
        let sampleEntry = try XCTUnwrap(entries.first { $0.isSample }, "目录需含显式示例曲")
        XCTAssertEqual(sampleEntry.book, "示例", "示例曲 book 不得伪装成教材")
        XCTAssertTrue(sampleEntry.title.contains("示例"))
        let status = CourseEngine.catalogStatus(
            book: sampleEntry.book, number: sampleEntry.number,
            pathState: CoursePathState()
        )
        XCTAssertEqual(status, .notStarted, "示例曲 notStarted（不锁）")
    }
}
