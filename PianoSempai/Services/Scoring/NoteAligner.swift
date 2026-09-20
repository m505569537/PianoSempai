import Foundation

// 离线对齐引擎（SPEC §5）：弹性节奏图 + DP note matching + 置信度。
// 纯函数、不触库、不发网络（红线 6）。对标 parangonar（投影口径见 NoteAlignerTests）：
// parangonar 只产 match/deletion/insertion；Swift 保留 wrongPitch 产品语义，
// 投影 deletion = missing + wrongPitch、insertion = extra + wrongPitch。

enum NoteAligner {

    struct TempoPoint: Equatable, Sendable {
        let beat: Double
        let sec: Double
    }

    // MARK: - 公开入口

    /// - Parameters:
    ///   - references: 评分区间内的参考音（可含 grace；grace 不进 DP 与分母，§6）
    ///   - played: 演奏音（onset 升序，MidiTakeParser 产出）
    ///   - segments: 非中断段的 played 下标范围（MidiTakeParser.segments；空 = 单段全量）
    ///   - tolerance: 节奏容差（§9）
    ///   - startBPM: 起速（节拍器/take.tempoAvg；无锚点时的兜底斜率）
    static func align(
        references: [ReferenceNote],
        played: [PlayedNote],
        segments: [Range<Int>] = [],
        tolerance: ScoringTolerance,
        startBPM: Double
    ) -> AlignmentResult {
        let nonGrace = references.filter { !$0.isGrace }
        let graces = references.filter { $0.isGrace }
        let windowSec = tolerance.timingWindowMs / 1000
        let expectedSecPerBeat = 60.0 / max(30.0, startBPM)
        let resolvedSegments: [Range<Int>] = segments.isEmpty
            ? (played.isEmpty ? [] : [0..<played.count])
            : segments

        // C) 顺序逐段处理（断点续弹，PRD L64）：每段锚点只允许配 refCursor 之后的参考音
        //    （段内自由时间偏移、斜率带宽保护）→ 去趋势进全局保序节奏图 → 段预测函数；
        //    段内若发现「onset 超出范围末拍预测 + 首参考音 pitch 复现」= 新一遍重启
        //    → 本遍到此为止（本批只评首遍，后续遍数如实计数，§5）。
        var aligned: [AlignedNote] = []
        var matchedRefIDs = Set<Int>()
        var detrended: [TempoPoint] = []
        var anchors: [TempoPoint] = []
        var refCursor = 0
        var playCursor = 0
        var passesPlayed = played.isEmpty ? 0 : 1
        var restartCount = 0
        var coversFullScope = false
        var scoredToEnd = false
        let scopeEndBeat = nonGrace.map(\.onsetBeat).max() ?? 0
        let firstPitch = nonGrace.first?.pitch
        var restartedHere = false

        segmentLoop: for seg in resolvedSegments {
            let globalSlice: [(global: Int, note: PlayedNote)] =
                seg.enumerated().compactMap { local, gi in gi >= playCursor ? (gi, played[gi]) : nil }
            guard !globalSlice.isEmpty else { continue }
            // 评分已完结（前段重启）时不再锚定——剩余 played 属于后续遍数
            if refCursor >= nonGrace.count { scoredToEnd = true; continue }

            // 段内锚点（refCursor 之后），去趋势 → 段预测函数
            let (points, offset) = segmentAnchors(
                references: Array(nonGrace[refCursor...]), segPlayed: globalSlice.map(\.note),
                expectedSecPerBeat: expectedSecPerBeat
            )
            detrended.append(contentsOf: points)
            anchors.append(contentsOf: points)
            let base = tempoInterpolator(knots: isotonic(detrended), fallbackSecPerBeat: expectedSecPerBeat)
            let segTempo = { (beat: Double) -> Double in base(beat) + offset }

            // 重启检测：本段内第一个「onset 明确超出范围末拍预测（> 末拍预测 + 容差带）
            // && pitch == 首参考音」的音。容差带内的尾音不算重启
            // （1.05×慢弹时末音 onset == 末拍预测，不误判；真正的循环重启明显超出）
            var effective = globalSlice
            var restartLocal: Int?
            if let firstPitch {
                for (local, entry) in globalSlice.enumerated() {
                    if entry.note.onsetSec > segTempo(scopeEndBeat) + windowSec && entry.note.pitch == firstPitch {
                        restartLocal = local
                        break
                    }
                }
            }
            if let rl = restartLocal {
                restartedHere = true
                restartCount += 1
                // local == 0 → 整段都是重启后的遍数：该段不评分
                effective = rl == 0 ? [] : Array(globalSlice[..<rl])
            }

            // 和弦同刻预配对（≥2 音组，pitch 最近优先，不强制顺序）
            let pre = chordPreMatchSegment(
                nonGrace: nonGrace, from: refCursor, segPlayed: effective.map(\.note),
                segTempo: segTempo, windowSec: windowSec
            )
            aligned.append(contentsOf: pre.aligned)
            matchedRefIDs.formUnion(pre.matchedRefIDs)

            let effectiveSecs = effective.map(\.note.onsetSec)
            let segMin = effectiveSecs.first ?? 0
            let segMax = effectiveSecs.last ?? 0

            // 段前缺口：预测 onset 早于段起点-2×容差带 → missing（单调节奏图下追不上）
            while refCursor < nonGrace.count {
                let ref = nonGrace[refCursor]
                if pre.matchedRefIDs.contains(ref.id) {
                    refCursor += 1 // 已配走，直接消耗
                    continue
                }
                if segTempo(ref.onsetBeat) < segMin - 2.0 * windowSec {
                    aligned.append(missingNote(ref))
                    refCursor += 1
                    continue
                }
                break
            }
            // 段窗口：预测 onset ≤ 段末 + 2×容差带（已配走的直接消耗）
            var windowEnd = refCursor
            var windowRefs: [ReferenceNote] = []
            while windowEnd < nonGrace.count {
                let ref = nonGrace[windowEnd]
                if pre.matchedRefIDs.contains(ref.id) {
                    windowEnd += 1
                    continue
                }
                if segTempo(ref.onsetBeat) > segMax + 2.0 * windowSec { break }
                windowRefs.append(ref)
                windowEnd += 1
            }
            guard !windowRefs.isEmpty else {
                if restartedHere { break segmentLoop }
                continue
            }

            let segRemaining = effective.filter { !pre.usedPlayedLocalIndices.contains($0.global - seg.lowerBound) }
                .map(\.note)
            guard !segRemaining.isEmpty else {
                refCursor = windowEnd
                if restartedHere { break segmentLoop }
                continue
            }

            let outcome = alignSegment(
                refs: windowRefs, played: segRemaining, tolerance: tolerance, tempoFn: segTempo
            )
            aligned.append(contentsOf: outcome.aligned)
            matchedRefIDs.formUnion(outcome.matchedRefIDs)
            refCursor = windowEnd // 窗口内参考音已全部定性（DP 内含 missing）
            playCursor = seg.upperBound

            if restartedHere { break segmentLoop } // 本遍结束；剩余 played 属后续遍数
        }
        if !restartedHere && refCursor >= nonGrace.count { scoredToEnd = true }

        // 全局节奏图（全部去趋势锚点）
        let knots = isotonic(detrended)
        let globalBase = tempoInterpolator(knots: knots, fallbackSecPerBeat: expectedSecPerBeat)

        // 段后剩余参考音 = missing（跨段缺口不计：留在最后一段窗口外的按 missing 收尾，§5）
        for idx in refCursor..<nonGrace.count {
            aligned.append(missingNote(nonGrace[idx]))
        }

        // 遍数：1 + 段循环中检测到的重启数（restartCount）
        passesPlayed += restartCount
        _ = scoredToEnd

        // D) 倚音宽限：extra 中与未用 grace 同 pitch 者 → correct（grace 不进分母也不计 extra，§6）
        aligned = matchGraces(aligned: aligned, graces: graces)

        // E) 计数与覆盖
        let matched = aligned.filter { $0.cls == .correct || $0.cls == .wrongPitch }
        let matchedRefCount = matched.count
        let wrongCount = aligned.filter { $0.cls == .wrongPitch }.count
        let missingCount = aligned.filter { $0.cls == .missing }.count
        let extraCount = aligned.filter { $0.cls == .extra }.count

        let scopeMeasures = Set(nonGrace.map(\.measureIndex))
        let coveredMeasures = Set(matched.compactMap(\.refMeasureIndex))
        coversFullScope = !scopeMeasures.isEmpty && scopeMeasures.isSubset(of: coveredMeasures)

        // F) 置信度（公式显式：0.4×锚点覆盖 + 0.4×匹配率 + 0.2×(1-残差/2容差带)，§5 禁黑箱）
        let anchorScore = min(1.0, Double(anchors.count) / 5.0)
        let matchScore = Double(matchedRefCount) / Double(max(1, nonGrace.count))
        let anchorResidual = meanAnchorResidualSec(anchors: anchors, tempoFn: globalBase)
        let residualScore = 1.0 - min(1.0, anchorResidual / max(0.001, 2.0 * windowSec))
        let confidence = 0.4 * anchorScore + 0.4 * matchScore + 0.2 * residualScore

        var reasons: [String] = []
        if anchors.count < 3 {
            reasons.append("对齐锚点不足 3 个，节奏图不可靠")
        }
        let matchRate = Double(matchedRefCount) / Double(max(1, nonGrace.count))
        if matchRate < 0.5 {
            reasons.append("匹配率低于 50%，多数音符没对上")
        }
        if !coversFullScope {
            reasons.append("未覆盖评分区间内全部小节")
        }

        let summary = tempoSummary(knots: knots, anchors: anchors, fallbackSecPerBeat: expectedSecPerBeat)

        return AlignmentResult(
            aligned: sortedAligned(aligned),
            matchedRefCount: matchedRefCount,
            missingCount: missingCount,
            extraCount: extraCount,
            wrongCount: wrongCount,
            tempoMap: summary,
            confidence: confidence,
            lowConfidenceReasons: reasons,
            passesPlayed: passesPlayed,
            coversFullScope: coversFullScope
        )
    }

    // MARK: - 和弦同刻预配对

    struct ChordPreMatchResult: Sendable {
        var aligned: [AlignedNote]
        var matchedRefIDs: Set<Int>
        var usedPlayedIndices: Set<Int>
    }

    /// 同 onsetBeat 参考组（≥2 音）与邻近 played 的 pitch 最近配对（§5「不强制顺序」）。
    /// 组内逐一消耗候选；配走的 played 不再进段 DP。非组参考音完全不动。
    static func chordPreMatchResult(
        nonGrace: [ReferenceNote],
        played: [PlayedNote],
        firstPassRange: Range<Int>,
        tempoFn: (Double) -> Double,
        windowSec: Double
    ) -> ChordPreMatchResult {
        // 分组（onsetBeat 视为同刻：差 < 1e-6）
        var groups: [(beat: Double, refs: [ReferenceNote])] = []
        for ref in nonGrace.sorted(by: { $0.onsetBeat < $1.onsetBeat }) {
            if let last = groups.last, abs(last.beat - ref.onsetBeat) < 1e-6 {
                groups[groups.count - 1].refs.append(ref)
            } else {
                groups.append((ref.onsetBeat, [ref]))
            }
        }

        var aligned: [AlignedNote] = []
        var matchedRefIDs = Set<Int>()
        var usedPlayedIndices = Set<Int>()

        for group in groups where group.refs.count >= 2 {
            let predicted = tempoFn(group.beat)
            var candidates: [Int] = []
            for i in firstPassRange where !usedPlayedIndices.contains(i) {
                if abs(played[i].onsetSec - predicted) <= windowSec {
                    candidates.append(i)
                }
            }
            // 双侧 pitch 最近优先：组内按 pitch 升序、候选按 pitch 升序，顺序配对
            let sortedRefs = group.refs.sorted { $0.pitch < $1.pitch }
            let sortedCandidates = candidates.sorted { played[$0].pitch < played[$1].pitch }
            var ri = 0, ci = 0
            while ri < sortedRefs.count && ci < sortedCandidates.count {
                let ref = sortedRefs[ri]
                let pi = sortedCandidates[ci]
                let p = played[pi]
                aligned.append(AlignedNote(
                    refMeasureIndex: ref.measureIndex,
                    refBeatInMeasure: ref.beatInMeasure,
                    refPitch: ref.pitch,
                    playedPitch: p.pitch,
                    deltaMs: (p.onsetSec - predicted) * 1000,
                    cls: p.pitch == ref.pitch ? .correct : .wrongPitch,
                    hand: ref.hand
                ))
                matchedRefIDs.insert(ref.id)
                usedPlayedIndices.insert(pi)
                ri += 1; ci += 1
            }
        }
        return ChordPreMatchResult(aligned: aligned, matchedRefIDs: matchedRefIDs, usedPlayedIndices: usedPlayedIndices)
    }

    /// 报告排序：有参考位的按（小节, 拍, 音高），extra（无参考位）排末尾
    static func sortedAligned(_ aligned: [AlignedNote]) -> [AlignedNote] {        aligned.sorted { lhs, rhs in
            switch (lhs.refMeasureIndex, rhs.refMeasureIndex) {
            case (let l?, let r?) where l != r: return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                switch (lhs.refBeatInMeasure, rhs.refBeatInMeasure) {
                case (let l?, let r?) where l != r: return l < r
                default: return (lhs.playedPitch ?? 0) < (rhs.playedPitch ?? 0)
                }
            }
        }
    }

    // MARK: - 段内锚点（自由偏移）

    /// 段内锚点：两指针同 pitch 贪心，相邻锚点斜率带宽保护（相对期望斜率 0.2×–5×），
    /// 段内允许自由时间偏移（tempo 估计不跨间隙，§5）。
    /// 返回：去趋势锚点（sec - offset）与段偏移（首尾锚点拟合直线的截距）。
    static func segmentAnchors(
        references: [ReferenceNote],
        segPlayed: [PlayedNote],
        expectedSecPerBeat: Double
    ) -> (points: [TempoPoint], offset: Double) {
        var anchors: [TempoPoint] = []
        var j = 0
        var lastBeat: Double?
        var lastSec: Double?
        let minSlope = 0.2 * expectedSecPerBeat
        let maxSlope = 5.0 * expectedSecPerBeat

        for ref in references {
            var k = j
            while k < segPlayed.count {
                let candidate = segPlayed[k]
                if candidate.pitch == ref.pitch, candidate.onsetSec >= (lastSec ?? -Double.infinity) {
                    var ok = true
                    if let lb = lastBeat, let ls = lastSec {
                        let slope = (candidate.onsetSec - ls) / max(0.25, ref.onsetBeat - lb)
                        if slope < minSlope || slope > maxSlope { ok = false }
                    }
                    if ok {
                        anchors.append(TempoPoint(beat: ref.onsetBeat, sec: candidate.onsetSec))
                        lastBeat = ref.onsetBeat
                        lastSec = candidate.onsetSec
                        j = k + 1
                        break
                    }
                }
                k += 1
            }
        }

        guard let first = anchors.first else { return ([], 0) }
        guard let last = anchors.last, last.beat > first.beat else {
            // 单锚点：偏移 = sec - 期望斜率 × beat
            let offset = first.sec - expectedSecPerBeat * first.beat
            return (anchors.map { TempoPoint(beat: $0.beat, sec: $0.sec - offset) }, offset)
        }
        let slope = (last.sec - first.sec) / (last.beat - first.beat)
        let offset = first.sec - slope * first.beat
        return (anchors.map { TempoPoint(beat: $0.beat, sec: $0.sec - offset) }, offset)
    }

    /// 段内和弦同刻预配对：同 onsetBeat 参考组（≥2 音）与邻近 played 的 pitch 最近配对
    /// （§5「不强制顺序」）。组内逐一消耗候选；配走的 played 不再进段 DP。
    static func chordPreMatchSegment(
        nonGrace: [ReferenceNote],
        from refCursor: Int,
        segPlayed: [PlayedNote],
        segTempo: @escaping (Double) -> Double,
        windowSec: Double
    ) -> (aligned: [AlignedNote], matchedRefIDs: Set<Int>, usedPlayedLocalIndices: Set<Int>) {
        // 分组（onsetBeat 差 < 1e-6 视为同刻），只取光标之后的参考音
        var groups: [(beat: Double, refs: [ReferenceNote])] = []
        for ref in nonGrace[refCursor...] {
            if let last = groups.last, abs(last.beat - ref.onsetBeat) < 1e-6 {
                groups[groups.count - 1].refs.append(ref)
            } else {
                groups.append((ref.onsetBeat, [ref]))
            }
        }

        var aligned: [AlignedNote] = []
        var matchedRefIDs = Set<Int>()
        var usedLocal = Set<Int>()

        for group in groups where group.refs.count >= 2 {
            let predicted = segTempo(group.beat)
            var candidates: [Int] = []
            for (local, p) in segPlayed.enumerated() where !usedLocal.contains(local) {
                if abs(p.onsetSec - predicted) <= windowSec {
                    candidates.append(local)
                }
            }
            // 双侧 pitch 最近优先：组内按 pitch 升序、候选按 pitch 升序，顺序配对
            let sortedRefs = group.refs.sorted { $0.pitch < $1.pitch }
            let sortedCandidates = candidates.sorted { segPlayed[$0].pitch < segPlayed[$1].pitch }
            var ri = 0, ci = 0
            while ri < sortedRefs.count && ci < sortedCandidates.count {
                let ref = sortedRefs[ri]
                let p = segPlayed[sortedCandidates[ci]]
                aligned.append(AlignedNote(
                    refMeasureIndex: ref.measureIndex,
                    refBeatInMeasure: ref.beatInMeasure,
                    refPitch: ref.pitch,
                    playedPitch: p.pitch,
                    deltaMs: (p.onsetSec - predicted) * 1000,
                    cls: p.pitch == ref.pitch ? .correct : .wrongPitch,
                    hand: ref.hand
                ))
                matchedRefIDs.insert(ref.id)
                usedLocal.insert(sortedCandidates[ci])
                ri += 1; ci += 1
            }
        }
        return (aligned, matchedRefIDs, usedLocal)
    }

    // MARK: - 锚点（全量两指针版本已由 segmentAnchors 取代；保留供单测）

    // MARK: - 旧全量锚点（保留：isotonic 单测用）

    /// 两指针贪心：ref 按序找第一个同 pitch、不早于上一锚点、且相邻隐含斜率落在
    /// 期望斜率 [0.2×, 5×] 带内的 played（防跨遍/远距误锚：如 ref@beat2 配到 10 秒外的同音）。
    /// 带宽 0.2/5 是显式工程参数（覆盖 ±80% 渐快渐慢），非统计魔法数。
    static func coarseAnchors(
        references: [ReferenceNote],
        played: [PlayedNote],
        expectedSecPerBeat: Double
    ) -> [TempoPoint] {
        var anchors: [TempoPoint] = []
        var j = 0
        var lastBeat: Double?
        var lastSec: Double?
        let minSlope = 0.2 * expectedSecPerBeat
        let maxSlope = 5.0 * expectedSecPerBeat

        for ref in references {
            var k = j
            while k < played.count {
                let candidate = played[k]
                if candidate.pitch == ref.pitch, candidate.onsetSec >= (lastSec ?? -Double.infinity) {
                    var ok = true
                    if let lb = lastBeat, let ls = lastSec {
                        let slope = (candidate.onsetSec - ls) / max(0.25, ref.onsetBeat - lb)
                        if slope < minSlope || slope > maxSlope { ok = false }
                    }
                    if ok {
                        anchors.append(TempoPoint(beat: ref.onsetBeat, sec: candidate.onsetSec))
                        lastBeat = ref.onsetBeat
                        lastSec = candidate.onsetSec
                        j = k + 1
                        break
                    }
                }
                k += 1
            }
        }
        return anchors
    }

    // MARK: - 保序回归（PAVA）与插值

    /// 把 (beat, sec) 锚点拟成 sec 关于 beat 的单调非降折线（允许渐快渐慢）
    static func isotonic(_ points: [TempoPoint]) -> [TempoPoint] {
        guard points.count > 1 else { return points }
        struct Block {
            var beatMean: Double
            var secMean: Double
            var weight: Double
        }
        var blocks: [Block] = points.map { Block(beatMean: $0.beat, secMean: $0.sec, weight: 1) }
        var i = 0
        while i < blocks.count - 1 {
            if blocks[i].secMean > blocks[i + 1].secMean {
                let w = blocks[i].weight + blocks[i + 1].weight
                let merged = Block(
                    beatMean: (blocks[i].beatMean * blocks[i].weight + blocks[i + 1].beatMean * blocks[i + 1].weight) / w,
                    secMean: (blocks[i].secMean * blocks[i].weight + blocks[i + 1].secMean * blocks[i + 1].weight) / w,
                    weight: w
                )
                blocks.replaceSubrange(i...i + 1, with: [merged])
                if i > 0 { i -= 1 }
            } else {
                i += 1
            }
        }
        return blocks.map { TempoPoint(beat: $0.beatMean, sec: $0.secMean) }
    }

    /// 折线插值；两端用最近段斜率外推；无节点用 fallback 斜率过原点域
    static func tempoInterpolator(knots: [TempoPoint], fallbackSecPerBeat: Double) -> (Double) -> Double {
        guard !knots.isEmpty else { return { beat in max(0, beat) * fallbackSecPerBeat } }
        if knots.count == 1 {
            let slope = fallbackSecPerBeat
            let offset = knots[0].sec - knots[0].beat * slope
            return { beat in max(0, beat) * slope + offset }
        }
        return { beat in
            if beat <= knots[0].beat {
                let slope = (knots[1].sec - knots[0].sec) / max(0.0001, knots[1].beat - knots[0].beat)
                return max(0, knots[0].sec + (beat - knots[0].beat) * slope)
            }
            let n = knots.count
            if beat >= knots[n - 1].beat {
                let slope = (knots[n - 1].sec - knots[n - 2].sec) / max(0.0001, knots[n - 1].beat - knots[n - 2].beat)
                return knots[n - 1].sec + (beat - knots[n - 1].beat) * slope
            }
            var k = 0
            while k < n - 1 && knots[k + 1].beat < beat { k += 1 }
            let a = knots[k], b = knots[min(k + 1, n - 1)]
            guard b.beat > a.beat else { return a.sec }
            let t = (beat - a.beat) / (b.beat - a.beat)
            return a.sec + t * (b.sec - a.sec)
        }
    }

    /// 锚点残差（秒均值）：锚点实测 sec 与节奏图预测的差
    static func meanAnchorResidualSec(anchors: [TempoPoint], tempoFn: (Double) -> Double) -> Double {
        guard !anchors.isEmpty else { return 1.0 }
        let residuals = anchors.map { abs($0.sec - tempoFn($0.beat)) }
        return residuals.reduce(0, +) / Double(residuals.count)
    }

    // MARK: - 首遍切分

    /// 循环重启检测：implied beat 随第二遍会整体抬升（时间轴单调），时间逆推测不出回绕；
    /// 改用「onset 超出范围末拍预测 + 与首参考音同 pitch」识别重启点。
    static func firstPassRange(
        played: [PlayedNote],
        tempoFn: (Double) -> Double,
        scopeEndBeat: Double,
        firstPitch: UInt8?
    ) -> Range<Int> {
        guard !played.isEmpty, let firstPitch else { return 0..<played.count }
        let scopeEndSec = tempoFn(scopeEndBeat)
        for (idx, note) in played.enumerated() where idx > 0 {
            if note.onsetSec > scopeEndSec && note.pitch == firstPitch {
                return 0..<idx
            }
        }
        return 0..<played.count
    }

    static func countPasses(
        played: [PlayedNote],
        tempoFn: (Double) -> Double,
        scopeEndBeat: Double,
        firstPitch: UInt8?
    ) -> Int {
        guard !played.isEmpty, let firstPitch else { return 0 }
        let scopeEndSec = tempoFn(scopeEndBeat)
        var passes = 1
        for (idx, note) in played.enumerated() where idx > 0 {
            if note.onsetSec > scopeEndSec && note.pitch == firstPitch {
                passes += 1
            }
        }
        return passes
    }

    /// tempoFn 的逆（秒 → 拍）：单调折线二分求逆
    static func impliedBeat(sec: Double, tempoFn: (Double) -> Double) -> Double {
        var lo = -10.0, hi = 2000.0
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            if tempoFn(mid) < sec { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    // MARK: - 单段 DP

    struct SegmentOutcome: Sendable {
        var aligned: [AlignedNote]
        var matchedRefIDs: Set<Int>
        /// 本段最后匹配的参考音在传入 slice 里的全局下标（游标推进用）
        var lastMatchedRefIndexGlobal: Int?
    }

    /// DP 对齐（单段 vs 参考窗口）。转移与罚分（全部显式常量，注释即口径）：
    /// - match(i,j) = pitch 罚 + 时间罚。
    ///   pitch 罚：同 0、异 1.0（有限罚 → 时间近的错音（成本≈1+时间）优先于 漏+多（2+2））
    ///   时间罚 = min(|deltaSec| / 容差秒, 3.0)（超差仍可配，只是贵——「timing 超差计入节奏维度」）
    /// - skip-ref（missing）= 2.0；insert-played（extra）= 2.0
    /// - i、j 单调；同 onsetBeat 的和弦时间罚近似相等，DP 自动按 pitch 最近配对
    static func alignSegment(
        refs: [ReferenceNote],
        played: [PlayedNote],
        tolerance: ScoringTolerance,
        tempoFn: @escaping (Double) -> Double
    ) -> SegmentOutcome {
        guard !played.isEmpty else {
            return SegmentOutcome(aligned: [], matchedRefIDs: [], lastMatchedRefIndexGlobal: nil)
        }
        guard !refs.isEmpty else {
            var aligned: [AlignedNote] = []
            for p in played {
                aligned.append(AlignedNote(
                    refMeasureIndex: nil, refBeatInMeasure: nil, refPitch: nil,
                    playedPitch: p.pitch, deltaMs: nil, cls: .extra, hand: .unknown
                ))
            }
            return SegmentOutcome(aligned: aligned, matchedRefIDs: [], lastMatchedRefIndexGlobal: nil)
        }

        let windowSec = tolerance.timingWindowMs / 1000
        let R = refs.count
        let P = played.count
        let skipPenalty = 2.0
        let insertPenalty = 2.0
        let pitchMismatchPenalty = 1.0
        let maxTimePenalty = 3.0

        var cost = Array(repeating: Array(repeating: Double.infinity, count: P + 1), count: R + 1)
        var from = Array(repeating: Array(repeating: 0, count: P + 1), count: R + 1) // 1=match 2=skipRef 3=insert
        cost[0][0] = 0
        for j in 1...P { cost[0][j] = cost[0][j - 1] + insertPenalty; from[0][j] = 3 }
        for i in 1...R { cost[i][0] = cost[i - 1][0] + skipPenalty; from[i][0] = 2 }

        for i in 1...R {
            let ref = refs[i - 1]
            let predicted = tempoFn(ref.onsetBeat)
            for j in 1...P {
                let p = played[j - 1]
                let delta = abs(p.onsetSec - predicted)
                let timePenalty = min(delta / windowSec, maxTimePenalty)
                let pitchPenalty = p.pitch == ref.pitch ? 0.0 : pitchMismatchPenalty
                let matchCost = cost[i - 1][j - 1] + pitchPenalty + timePenalty
                let skipCost = cost[i - 1][j] + skipPenalty
                let insertCost = cost[i][j - 1] + insertPenalty

                let best = min(matchCost, skipCost, insertCost)
                cost[i][j] = best
                from[i][j] = best == matchCost ? 1 : (best == skipCost ? 2 : 3)
            }
        }

        // 回溯（序反着收集，最后翻转为报告序）
        var aligned: [AlignedNote] = []
        var matchedRefIDs = Set<Int>()
        var lastMatchedGlobal: Int?
        var i = R, j = P
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && from[i][j] == 1 {
                let ref = refs[i - 1]
                let p = played[j - 1]
                let predicted = tempoFn(ref.onsetBeat)
                let deltaMs = (p.onsetSec - predicted) * 1000
                aligned.append(AlignedNote(
                    refMeasureIndex: ref.measureIndex,
                    refBeatInMeasure: ref.beatInMeasure,
                    refPitch: ref.pitch,
                    playedPitch: p.pitch,
                    deltaMs: deltaMs,
                    cls: p.pitch == ref.pitch ? .correct : .wrongPitch,
                    hand: ref.hand
                ))
                matchedRefIDs.insert(ref.id)
                // 回溯自尾向头：首次命中即「本段最晚匹配的参考音」（游标推进用）
                if lastMatchedGlobal == nil {
                    lastMatchedGlobal = i - 1
                }
                i -= 1; j -= 1
            } else if i > 0 && from[i][j] == 2 {
                aligned.append(missingNote(refs[i - 1]))
                i -= 1
            } else if j > 0 {
                let p = played[j - 1]
                aligned.append(AlignedNote(
                    refMeasureIndex: nil, refBeatInMeasure: nil, refPitch: nil,
                    playedPitch: p.pitch, deltaMs: nil, cls: .extra, hand: .unknown
                ))
                j -= 1
            } else {
                break
            }
        }

        return SegmentOutcome(
            aligned: aligned.reversed(),
            matchedRefIDs: matchedRefIDs,
            lastMatchedRefIndexGlobal: lastMatchedGlobal.map { refs.startIndex + $0 }
        )
    }

    private static func missingNote(_ ref: ReferenceNote) -> AlignedNote {
        AlignedNote(
            refMeasureIndex: ref.measureIndex, refBeatInMeasure: ref.beatInMeasure,
            refPitch: ref.pitch, playedPitch: nil, deltaMs: nil, cls: .missing, hand: ref.hand
        )
    }

    // MARK: - 倚音宽限

    /// extra 中与未用 grace 同 pitch 者 → correct（grace 不进分母也不计 extra，§6 装饰音容错）
    static func matchGraces(aligned: [AlignedNote], graces: [ReferenceNote]) -> [AlignedNote] {
        guard !graces.isEmpty else { return aligned }
        var available = graces
        var result: [AlignedNote] = []
        for note in aligned {
            if note.cls == .extra, let playedPitch = note.playedPitch,
               let idx = available.firstIndex(where: { $0.pitch == playedPitch }) {
                let grace = available.remove(at: idx)
                result.append(AlignedNote(
                    refMeasureIndex: grace.measureIndex,
                    refBeatInMeasure: grace.beatInMeasure,
                    refPitch: grace.pitch,
                    playedPitch: playedPitch,
                    deltaMs: nil,
                    cls: .correct,
                    hand: grace.hand
                ))
            } else {
                result.append(note)
            }
        }
        return result
    }

    // MARK: - tempoMap 摘要

    static func tempoSummary(
        knots: [TempoPoint],
        anchors: [TempoPoint],
        fallbackSecPerBeat: Double
    ) -> TempoMapSummary {
        var bpms: [Double] = []
        if knots.count >= 2 {
            for k in 0..<(knots.count - 1) {
                let dBeat = knots[k + 1].beat - knots[k].beat
                let dSec = knots[k + 1].sec - knots[k].sec
                if dSec > 0.001, dBeat > 0.001 {
                    bpms.append(60.0 * dBeat / dSec)
                }
            }
        }
        if bpms.isEmpty {
            bpms.append(60.0 / max(30.0, fallbackSecPerBeat))
        }
        return TempoMapSummary(
            anchorCount: anchors.count,
            minBPM: bpms.min() ?? 0,
            maxBPM: bpms.max() ?? 0
        )
    }
}
