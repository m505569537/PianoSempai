import Foundation
import SwiftData
import SheetMusicCore
import SheetMusicLoader

// 分析编排（SPEC §10）：纯计算（analyzeTake）与 SwiftData IO（run）分离。
// 纯函数不依赖 ModelContext/磁盘，可注入单测；run 负责 IO + 幂等 upsert + 过关落库。
// 红线：判分只读分析，只有 CourseEngine 写 Piece.status；失败不吞、不抛假分（§14）。

enum ScoringOrchestrator {

    /// 引擎版本（幂等 upsert 键之一；SPEC §8）
    static let engineVersion = "P2-scoring-1.0"

    // MARK: - 输入 / 输出

    struct Input {
        /// 已按评分区间提取好的参考音；空 = 无参考谱
        var references: [ReferenceNote]
        var played: [PlayedNote]
        /// 各非中断段的 played 下标范围（MidiTakeParser.segments；断点续弹按段锚定，§5）。
        /// 空 = 单段全量（纯单测可直接喂 references/played）
        var segments: [Range<Int>] = []
        /// 各非中断段起始秒（连续性维跨段跳过用）
        var segmentStartSecs: [Double]
        var calibration: VelocityCalibration?
        var referenceTempo: Int
        var standards: ScoringStandards
        var startBPM: Int
        var isFreePlay: Bool
    }

    /// 一次分析的完整产出（含落库所需 JSON 串与过关判定）。
    /// errorMessage 非 nil = error outcome（解析/编码失败，不吞错、不假分）。
    struct AnalysisOutcome: Equatable {
        let engineVersion: String
        let errorMessage: String?
        let canEvaluate: Bool
        let passesHardMetrics: Bool
        /// = canEvaluate（回写 take.isPassEligible；低置信/无谱 → false 不计数不清零）
        var eligibleForPass: Bool { canEvaluate }
        let confidence: Double
        let lowConfidenceReasons: [String]
        // 六维（可空；自由弹奏/无谱全 nil）
        let pitchScore: Int?
        let rhythmScore: Int?
        let tempoScore: Int?
        let dynamicsScore: Int?
        let continuityScore: Int?
        let handsScore: Int?
        let weakTotal: Int?
        let wrongCount: Int
        let missingCount: Int
        let extraCount: Int
        let wrongPitchCount: Int
        /// 评分区间内非 grace 参考音数（错音率分母；S09/S13 重算指标用）
        let referenceNoteCount: Int
        let rhythmMedianMs: Double
        let rhythmMeanMs: Double
        let tempoTargetHit: Bool
        /// 实测平均速度（BPM；0 = 速度维算不出）
        let avgBPM: Double
        let hotspotMeasures: [Int]
        let alignmentJSON: String
        let measureHeatJSON: String
        /// 过关三硬指标明细（S13/S09 展示 + 「差多少」）
        let passMetrics: [CourseEngine.MetricResult]
        let passReasons: [String]

        static func error(_ message: String) -> AnalysisOutcome {
            AnalysisOutcome(
                engineVersion: ScoringOrchestrator.engineVersion, errorMessage: message,
                canEvaluate: false, passesHardMetrics: false,
                confidence: 0, lowConfidenceReasons: [],
                pitchScore: nil, rhythmScore: nil, tempoScore: nil,
                dynamicsScore: nil, continuityScore: nil, handsScore: nil,
                weakTotal: nil,
                wrongCount: 0, missingCount: 0, extraCount: 0, wrongPitchCount: 0,
                referenceNoteCount: 0,
                rhythmMedianMs: 0, rhythmMeanMs: 0, tempoTargetHit: false, avgBPM: 0,
                hotspotMeasures: [], alignmentJSON: "[]", measureHeatJSON: "{}",
                passMetrics: [], passReasons: [message]
            )
        }
    }

    // MARK: - 纯函数（不依赖 ModelContext / 磁盘）

    /// 无 references 或 isFreePlay → 统计级 outcome（canEvaluate=false，不出对错分，§0）。
    /// 演奏为空（非自由弹奏）→ error outcome（不抛、不假分，§D）。
    static func analyzeTake(input: Input) -> AnalysisOutcome {
        guard !input.isFreePlay else {
            return statisticsOutcome(reason: "自由弹奏不判分（仅统计，SPEC §0/§6）")
        }
        guard !input.references.isEmpty else {
            return statisticsOutcome(reason: "暂无参考谱，不判定对错/过关")
        }
        guard !input.played.isEmpty else {
            return .error("无演奏数据，本次分析失败/数据不足")
        }

        let result = NoteAligner.align(
            references: input.references, played: input.played,
            segments: input.segments,
            tolerance: input.standards.tolerance, startBPM: Double(input.startBPM)
        )
        let scored = TakeScorer.score(
            result: result, played: input.played, references: input.references,
            calibration: input.calibration, referenceTempo: input.referenceTempo,
            standards: input.standards, segmentStartSecs: input.segmentStartSecs
        )

        let nonGraceCount = input.references.filter { !$0.isGrace }.count
        let passEval = CourseEngine.evaluatePass(
            wrongPitchCount: result.wrongCount,
            missingCount: result.missingCount,
            referenceNonGraceCount: nonGraceCount,
            rhythmMedianMs: scored.rhythmStats?.medianMs ?? 0,
            tempoTargetHit: scored.tempo.tempoTargetHit,
            confidence: result.confidence,
            coversFullScope: result.coversFullScope,
            hasScore: true,
            isFreePlay: input.isFreePlay,
            standards: input.standards
        )

        let canEvaluate = result.confidence >= ScoringStandards.confidenceGateThreshold
            && result.coversFullScope

        do {
            let alignmentData = try JSONEncoder.iso.encode(result.aligned)
            let heatData = try JSONEncoder.iso.encode(scored.measureHeat)
            let alignmentJSON = String(data: alignmentData, encoding: .utf8) ?? "[]"
            let measureHeatJSON = String(data: heatData, encoding: .utf8) ?? "{}"
            return AnalysisOutcome(
                engineVersion: engineVersion,
                errorMessage: nil,
                canEvaluate: canEvaluate,
                passesHardMetrics: passEval.passesAllHardMetrics,
                confidence: result.confidence,
                lowConfidenceReasons: result.lowConfidenceReasons,
                pitchScore: scored.pitch.score,
                rhythmScore: scored.rhythm.score,
                tempoScore: scored.tempo.score,
                dynamicsScore: scored.dynamics.score,
                continuityScore: scored.continuity.score,
                handsScore: scored.hands.score,
                weakTotal: scored.weakTotal,
                wrongCount: result.wrongCount,
                missingCount: result.missingCount,
                extraCount: result.extraCount,
                wrongPitchCount: result.wrongCount,
                referenceNoteCount: nonGraceCount,
                rhythmMedianMs: scored.rhythmStats?.medianMs ?? 0,
                rhythmMeanMs: scored.rhythmStats?.meanMs ?? 0,
                tempoTargetHit: scored.tempo.tempoTargetHit,
                avgBPM: scored.tempo.avgBPM ?? 0,
                hotspotMeasures: scored.hotspotMeasures,
                alignmentJSON: alignmentJSON,
                measureHeatJSON: measureHeatJSON,
                passMetrics: passEval.metrics,
                passReasons: passEval.reasons
            )
        } catch {
            // 编码失败不吞错（§10），错误 outcome 不假分
            return .error("分析结果编码失败：\(error.localizedDescription)")
        }
    }

    /// 统计级 outcome（无谱/自由弹奏）：全六维 nil，不出对错分，weakTotal nil
    static func statisticsOutcome(reason: String) -> AnalysisOutcome {
        AnalysisOutcome(
            engineVersion: engineVersion, errorMessage: nil,
            canEvaluate: false, passesHardMetrics: false,
            confidence: 0, lowConfidenceReasons: [reason],
            pitchScore: nil, rhythmScore: nil, tempoScore: nil,
            dynamicsScore: nil, continuityScore: nil, handsScore: nil,
            weakTotal: nil,
            wrongCount: 0, missingCount: 0, extraCount: 0, wrongPitchCount: 0,
            referenceNoteCount: 0,
            rhythmMedianMs: 0, rhythmMeanMs: 0, tempoTargetHit: false, avgBPM: 0,
            hotspotMeasures: [], alignmentJSON: "[]", measureHeatJSON: "{}",
            passMetrics: [], passReasons: [reason]
        )
    }

    /// 参考谱 URL 决策（纯，可单测）：真实谱 > 内置公版谱 > 无（nil = 无参考谱 → 统计级）。
    /// 「有没有内置谱」由纯映射判定（与 ScoreAvailability 同源，599/示例 → nil）；
    /// 「谱在哪」交给 bundledResolver（默认 Bundle 查找，测试可注入）。
    /// 真实谱存在但沙盒文件缺失时**不**回退到内置谱：不拿另一份谱冒充评分（§10）。
    /// - Parameter bundledResolver: 内置谱 URL 解析（默认 Bundle 查找；测试可注入，避免依赖宿主资源）
    static func referenceScoreURL(
        scoreFile: ScoreFile?,
        bundledBook: String?,
        bundledNumber: Int,
        bundledResolver: (String, Int) -> URL? = BundledScore.url
    ) -> URL? {
        if let scoreFile {
            return SandboxPaths.resolve(scoreFile.fileURL)
        }
        guard let book = bundledBook,
              BundledScore.resourceName(book: book, number: bundledNumber) != nil else {
            return nil
        }
        return bundledResolver(book, bundledNumber)
    }

    // MARK: - IO 层（@MainActor；幂等 upsert + 过关落库）

    /// 分析并落库一条 take。上游解析/读取失败 → error outcome，不影响 take 已落库与 streak。
    @MainActor
    @discardableResult
    static func run(
        for take: Take,
        scoreFile: ScoreFile?,
        piece: Piece?,
        measureFrom: Int?,
        measureTo: Int?,
        referenceTempo: Int,
        standards: ScoringStandards,
        bundledBook: String? = nil,
        bundledNumber: Int = 0,
        in context: ModelContext
    ) -> AnalysisOutcome {
        // 1) 读取原始事件（jsonl 不可变，唯一演奏真值）
        let events: [RawMIDIEventRecord]
        do {
            guard let url = SandboxPaths.resolve(take.midiFileURL) else {
                return .error("MIDI 文件不存在：\(take.midiFileURL)")
            }
            events = try TakeStore.readEvents(from: url)
        } catch {
            return .error("MIDI 读取失败：\(error.localizedDescription)")
        }

        // 2) 参考谱（真实谱或内置公版谱；两者都没有 → 无参考谱，统计级，不冒充，§10）
        // （演奏解析/段切分由 analyzeAndStore 委托 MidiTakeParser 完成）
        var references: [ReferenceNote] = []
        if let scoreURL = referenceScoreURL(
            scoreFile: scoreFile, bundledBook: bundledBook, bundledNumber: bundledNumber
        ) {
            do {
                let score = try ScoreLoader.loadScore(contentsOf: scoreURL)
                // take.measureFrom/To 为 1-based 展示值；提取器用 0-based 闭区间
                let range: ClosedRange<Int>? = {
                    guard let from = measureFrom ?? take.measureFrom,
                          let to = measureTo ?? take.measureTo else { return nil }
                    return max(0, from - 1)...max(0, to - 1)
                }()
                references = ScoreReferenceNotes.extract(score: score, measureRange: range).notes
            } catch {
                return .error("参考谱解析失败：\(error.localizedDescription)")
            }
        }

        // 3) 校准/分析/幂等 upsert/过关落库（委托 analyzeAndStore）
        return analyzeAndStore(
            take: take,
            piece: piece,
            references: references,
            events: events,
            interruptionRanges: take.interruptionRanges,
            referenceTempo: referenceTempo,
            standards: standards,
            in: context
        )
    }

    // MARK: - 幂等 upsert + 过关落库

    /// 分析并落库一条 take（解析 + upsert + 过关判定串联，测试可注入 events/refs）。
    @MainActor
    @discardableResult
    static func analyzeAndStore(
        take: Take,
        piece: Piece?,
        references: [ReferenceNote],
        events: [RawMIDIEventRecord],
        interruptionRanges: [Int] = [],
        referenceTempo: Int,
        standards: ScoringStandards,
        in context: ModelContext
    ) -> AnalysisOutcome {
        let parsed = MidiTakeParser.parse(
            events: events,
            interruptionRanges: interruptionRanges,
            streamEndSec: Double(take.durationSec)
        )
        let segmentStartSecs = parsed.segments.compactMap { seg -> Double? in
            parsed.notes.indices.contains(seg.lowerBound) ? parsed.notes[seg.lowerBound].onsetSec : nil
        }
        let calibration = (try? context.fetch(
            FetchDescriptor<VelocityCalibration>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ))?.first

        let outcome = analyzeTake(input: Input(
            references: references,
            played: parsed.notes,
            segments: parsed.segments,
            segmentStartSecs: segmentStartSecs,
            calibration: calibration,
            referenceTempo: referenceTempo,
            standards: standards,
            // 起速：take.tempoAvg（节拍器/实测，NoteAligner 契约）优先，缺失回落参考速度
            startBPM: take.tempoAvg > 0 ? take.tempoAvg : referenceTempo,
            isFreePlay: take.isFreePlay
        ))

        // 幂等 upsert（takeId + engineVersion 键）+ 回填 take
        let takeId = take.entityId
        let engineVersion = ScoringOrchestrator.engineVersion
        let descriptor = FetchDescriptor<TakeAnalysis>(
            predicate: #Predicate { $0.takeId == takeId && $0.engineVersion == engineVersion }
        )
        let row = (try? context.fetch(descriptor).first) ?? TakeAnalysis()
        row.takeId = take.entityId
        row.engineVersion = engineVersion
        row.analyzedAt = Date()
        row.confidence = outcome.confidence
        row.lowConfidenceReasons = outcome.lowConfidenceReasons
        row.pitchScore = outcome.pitchScore
        row.rhythmScore = outcome.rhythmScore
        row.tempoScore = outcome.tempoScore
        row.dynamicsScore = outcome.dynamicsScore
        row.continuityScore = outcome.continuityScore
        row.handsScore = outcome.handsScore
        row.weakTotal = outcome.weakTotal
        row.wrongCount = outcome.wrongCount
        row.missingCount = outcome.missingCount
        row.extraCount = outcome.extraCount
        row.wrongPitchCount = outcome.wrongPitchCount
        row.referenceNoteCount = outcome.referenceNoteCount
        row.rhythmMedianMs = outcome.rhythmMedianMs
        row.rhythmMeanMs = outcome.rhythmMeanMs
        row.tempoTargetHit = outcome.tempoTargetHit
        row.avgBPM = outcome.avgBPM
        row.hotspotMeasures = outcome.hotspotMeasures
        row.measureHeatJSON = outcome.measureHeatJSON
        row.canEvaluate = outcome.canEvaluate
        row.passesHardMetrics = outcome.passesHardMetrics
        row.alignmentJSON = outcome.alignmentJSON
        if row.modelContext == nil {
            context.insert(row)
        }
        take.analysisId = row.entityId
        take.isPassEligible = outcome.eligibleForPass

        // 过关落库（只有 CourseEngine 写 Piece.status；只有可评 take 参与）
        if let piece, outcome.canEvaluate {
            let history = pieceTakeHistory(pieceId: piece.entityId, in: context)
            CourseEngine.applyPassIfConsecutive(piece: piece, takesOldestFirst: history, in: context)
        }
        return outcome
    }

    /// 同 piece 历史 takes（时间升序）的 (eligible, passed)——过关连续计数输入（§7）。
    /// 未分析的 take 不参与（无分析行 = 无判定）。
    static func pieceTakeHistory(pieceId: UUID, in context: ModelContext) -> [(eligible: Bool, passed: Bool)] {
        let takes = ((try? context.fetch(FetchDescriptor<Take>())) ?? [])
            .filter { $0.pieceId == pieceId }
            .sorted { $0.startedAt < $1.startedAt }
        let analyses = (try? context.fetch(FetchDescriptor<TakeAnalysis>())) ?? []
        let analysisByTake = Dictionary(uniqueKeysWithValues: analyses.map { ($0.entityId, $0) })
        return takes.compactMap { take in
            guard let a = take.analysisId.flatMap({ analysisByTake[$0] }) else { return nil }
            return (eligible: a.canEvaluate, passed: a.passesHardMetrics)
        }
    }
}
