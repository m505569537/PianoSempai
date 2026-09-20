# P2 判分引擎 SPEC（离线对齐 + 六维 + 过关门禁）

- 版本：P2-scoring-1.0（2026-09-20）
- 权威来源：`docs/PRD.md` M5（L184–209 对齐/六维/热点/诚实边界/门禁联动）、M3 过关（L134–136 连续 2 次）、M4（L151–159 循环/速度）。
- 本文件是 P2 编码的唯一权威。与 PRD 冲突时以 PRD 为准并在本文件标注；CC 发现本文件自相矛盾必须停下报告，禁止自行选边。
- 角色隔离铁律（PRD L360）：**判分（本引擎，只读分析）/ 拍板（CourseEngine 唯一写课程状态）/ 出主意（AI）三者强制隔离**。判分模块禁止写任何课程状态、禁止网络、禁止调用 AI。

## 0. 范围（用户已拍板方案 A）

做：
1. 离线 DP note matching 对齐（对标 parangonar，Swift 重写，纯函数可测）。
2. 六维判分 + 小节热力 + 节奏偏差 + 弱总分，逐 take 落库，全量报告分区折叠、可永久回看。
3. 踏板进判分（CC64 按住时琴键抬起不算音结束）。
4. 对齐置信度；低置信显式「没对上，判分仅供参考」，且不进门禁。
5. CourseEngine 过关判定：连续 2 次高置信达标 take → 过关；阈值写课程数据、公开可查；只对**有真实参考谱**的条目生效。
6. 对任何用户导入的 MusicXML/mscz/MID 可跟弹谱立即能判分。
7. 修复「无谱拜厄条目静默用 SpikeSample32 冒充可跟弹」的瑕疵；把样例谱作为**显式可见、诚实标注的示例曲**接入，端到端可演示。

不做（挂后续，本批禁止偷做也禁止造假占位分）：
- 内置拜厄/哈农/599 的真实参考谱内容（来源由用户另定；无谱条目只能诚实标「暂无参考谱」）。
- 在线实时错音打断（PRD 红线，永不做）。在线跟弹光标继续用 P1 ScoreFollowEngine，本批不替换。
- S20 档案趋势图/周报、S12「只练错误热点」自动选段、S21 双 take 对比、S05 定级换用对齐算法（全部列为 P2.2，本批不动 UI 入口的禁用/占位，但底层数据要为其铺好）。
- 多遍 loop 折叠评分（见 §7 取首遍口径）。
- 自由弹奏判分（无参考谱，只出统计，维持 S14）。
- 视频/手型（P3）、火山方舟（P3）。

## 1. 已决策事项（CC 不必再问，依据均已 grep/读码实证）

- 过关次数 = **连续 2 次**（PRD L135 与现有 UI 文案 SettingsView L262 / PieceDetailView L163 均为 2）。历史进度笔记里出现过「3 次」是笔误，作废。
- 参考时序来源：`swift-sheet-music`（已 pin）。用 `Chord.duration.resolved(in: measureDuration).ticks(division: score.division)`、`Score.resolveTickInMeasure` / `score.division`、`VoiceElement` 的 `.chord/.rest` 累加 onset；不要自造拍号除法。
- 左右手：钢琴为单 Part 双 Staff（样例谱实证 staff1=128 音 / staff2=128 音）。staffIndex 0=右手、1=左手；单 staff 谱 hand=unknown，第 6 维「双手协同」与分手小分出 nil 并明示，不编分。
- 原始演奏数据已落盘：`Take.midiFileURL` 指向 `Documents/midi/yyyy/MM/take-*.midi.jsonl`（JSONL：`t` 纳秒 mach uptime、`k` on/off/cc64、`n` 音高或 64、`v` velocity/CC 值、`suspicious`）。离线分析以此为唯一演奏真值，不依赖在线 followState 的聚合数。
- 现有 `ScoreExpectedPitches.extract` 只取首个 staff 的音高（丢时序/时值/左手），**保留给在线引擎不动**；新建富提取器给离线引擎。
- 新 SwiftData 模型只做加字段/加表的轻量迁移；必须在 `PianoSempaiApp.swift` L12–24 的 Schema 数组注册。
- 模拟器（无真琴）继续默认模拟输入（已是 commit 12ef690 行为）；本批判分开发与验收用模拟源 + 示例曲，不需要真机。
- 不引第三方 ZIP/音频/数学库；DP、统计、JSON 全部 Foundation 实现。parangonar 仅作离线对拍参考脚本，不进 App target。

## 2. 核心领域模型（新增，纯值类型 + 持久层分开）

```swift
enum Hand: String, Codable { case right, left, unknown }

/// 参考音符（从谱面提取，全局按小节/拍定位）
struct ReferenceNote: Equatable, Identifiable {
    let id: Int                 // 提取顺序稳定 id
    let pitch: UInt8            // MIDI 0...127
    let onsetBeat: Double       // 相对评分区间起点的拍数（累计，含跨小节）
    let durationBeats: Double
    let measureIndex: Int       // 0-based；展示 +1
    let beatInMeasure: Double   // 小节内拍（用于错音定位「第几小节第几拍」）
    let hand: Hand
    let isGrace: Bool           // 倚音/装饰音：true 时不进判分分母（见 §6）
}

/// 演奏音符（从 MIDI jsonl 解析，踏板修正后）
struct PlayedNote: Equatable {
    let pitch: UInt8
    let onsetSec: Double        // 相对 take 演奏锚点（首个 count-in 之后 / performing 起点）
    let endSec: Double          // 踏板修正后的实际收音（见 §4）
    let velocity: UInt8
    let isSuspicious: Bool
}

enum NoteMatchClass: String, Codable { case correct, wrongPitch, missing, extra }

struct AlignedNote: Codable, Equatable {
    let refMeasureIndex: Int?
    let refBeatInMeasure: Double?
    let refPitch: UInt8?
    let playedPitch: UInt8?
    let deltaMs: Double?        // 实测 onset 相对节奏图预测 onset，正=拖拍/负=抢拍
    let cls: NoteMatchClass
    let hand: Hand
}
```

`AlignmentResult`：`aligned: [AlignedNote]`、`matchedRefCount/missingCount/extraCount/wrongCount`、`tempoMap` 摘要、`confidence`、`lowConfidenceReasons: [String]`、`passesPlayed: Int`、`coversFullScope: Bool`。

## 3. 参考谱提取器 `ScoreReferenceNotes`（新文件 Services/Scoring/ScoreReferenceNotes.swift）

- 输入：`Score`（SheetMusicCore）+ 评分区间 `measureRange: Range<Int>`（0-based，闭区间；缺省全曲）+ 是否双谱表自动判定。
- 遍历 `part.staves.enumerated` → `staff.measures[range]` → `voice.elements` 时间序：
  - `.chord`：用 `chord.duration.resolved(in:).ticks(division:)` 取时值；该元素 onset 由游标（小节内 tick，含本 voice 前面的 chord+rest 累加）+ 跨小节累计 tick 得到，`/ Double(score.division)` 换拍；chord.notes 每个音生成一条 ReferenceNote（和弦同时刻多音，共享 onsetBeat）。
  - `.rest`：游标推进 rest 的 resolved ticks（**必须**推进，否则后续 onset 全错）。
  - 多 voice：同 staff 多 voice 的 onset 各自计算后合并、按 onsetBeat 稳定排序。
  - `graceNotesBefore/After`：标记 isGrace=true，不占正拍游标。
  - 连音线/tie：以 chord 为单位，时值已含；不重复生成被 tie 走的音头（若模型对 tie 末端也给 noteOn，按同 pitch+相邻 onset 去重，保留首个）。
- hand 映射见 §1；区间起点拍归零（rebased）。
- 输出按 `(onsetBeat, hand, pitch)` 稳定排序。
- 纯函数、不触库、不依赖网络；用示例谱与构造 Score 双套单测（断言：总音数 256、RHLH 各 128、4/4 下小节边界 onsetBeat 为 4 的倍数、rest 推进、区间裁剪正确）。

## 4. 演奏解析器 `MidiTakeParser`（新文件 Services/Scoring/MidiTakeParser.swift）

- 读 `[RawMIDIEventRecord]`（TakeStore.readEvents），把 mach uptime 纳秒换算成相对秒：以第一条 performing 期 noteOn/cc64 之前的锚点（由 take 起点）为 0；调用方负责扣除 count-in（PracticeSession 落盘只在 `.performing` 且 connected 时写事件，故解析到的首事件即演奏起点，直接 min(t) 归零）。
- 断连区间 `take.interruptionRanges`（秒起点列表）：中断空白内的事件不存在（在线端已暂停写），且**中断空白不计漏音、不计节奏/连续性**（PRD L64）。解析器输出时把每个事件标 `withinInterruption`，对齐前剔除中断间隙并把前后切成不连续段（tempo 估计不跨间隙）。
- 踏板修正（PRD L187）：维护 damper 状态（CC64 value>=64 为踩下）。noteOff 时若踏板正踩着，该音 endSec 延后到「该 noteOff 之后第一次踏板抬起」时刻；期间同 pitch 再次 noteOn 视为新音（不合并）。onSet 一律用 noteOn（对齐基于 onset，踏板只影响 endSec 与「踩着踏板抬手≠漏音」）。
- velocity=0 的 noteOn 按 noteOff 处理（上游已转，双保险）。
- 输出 `[PlayedNote]`（onset 升序），并附 pedalEventCount、suspicious 计数供核对。
- 单测：踏板按住抬手→endSec 延到抬踏板；连音/同 pitch 重复；中断切片；velocity=0。

## 5. 离线对齐引擎 `NoteAligner`（新文件 Services/Scoring/NoteAligner.swift）

对标 parangonar 的 anchor-based DP note matching（简化但同构），纯函数。

输入：`[ReferenceNote]`（区间内）、`[PlayedNote]`、`Tolerance`（节奏容差，见 §9）、起速 BPM（节拍器/take.tempoAvg）。
输出：`AlignmentResult`。

步骤：
1. **全局 tempo 估计（弹性节奏图，不允许单音硬套等比）**：
   - 先用 pitch 多重集粗匹配求若干高置信锚点（同 pitch、单调不回退、可跳过）。
   - 对锚点做单调回归（保序回归 isotonic / 分段线性），把「拍 → 实测秒」拟成单调非降 tempoMap，允许渐快渐慢；至少需要 3 个锚点，否则判低置信。
   - 由 tempoMap 把每个参考 onsetBeat 映射为 predicted onset 秒。
2. **DP 匹配**：在 ref 序列 i 与 played 序列 j 上做序列对齐，三种转移：
   - match(i,j)：代价 = pitch 不符代价（同 0 / 差半音给有限罚分 wrongPitch）+ onset 时间差经容差归一化的代价；只在 |Δms| ≤ 容差窗外的对给高罚分。
   - skip-ref（missing）：固定罚分。
   - insert-played（extra）：固定罚分。
   - 单调性约束：i、j 都只增；允许和弦同时刻（同 onsetBeat 的多个 ref 可与同一秒附近的多个 played 任意配对，按 pitch 最近优先，不强制顺序）。
   - 中断间隙两侧禁止跨间隙匹配（§4 切段，各段独立对齐后拼接，missing 不计跨段）。
3. **回溯分类**：match 且 pitch 相等=correct；match 但 pitch 不等=wrongPitch（仍记 deltaMs，用于节奏统计）；未匹配 ref=missing；未匹配 played=extra。
4. deltaMs = played.onsetSec − predicted(onsetBeat)。

容差窗外与置信：
- 单次匹配若 |Δms| 超窗，仍允许匹配但标为 timing 超差（计入节奏维度），不静默丢弃。
- `confidence ∈ 0...1`：由锚点覆盖率、matched/(ref 非 grace 数)、tempoMap 拟合残差综合（实现给出明确公式并写注释，禁止黑箱魔法数无注释）。
- 低置信判定（任一）：锚点 <3；matched 率 <0.5；区间覆盖不足（coversFullScope=false，见下）。lowConfidenceReasons 逐条中文写明。

区间与多遍：
- 本批取**第一遍完整覆盖**评分（PRD §7）：played 序列按参考区间时长/tempoMap 切出首个完整走过区间的一遍；若无法可靠切遍（循环多次且无法区分），`passesPlayed` 如实计数并默认取首段，且在结果里声明「按首遍评分」。后续多遍聚合挂 P2.2。
- coversFullScope：首遍是否覆盖区间内全部小节（缺失整段小节=false）。

parangonar 对拍验收（PRD L185「输出一致才验收」）：
- Hermes 在仓外脚本目录用 Python parangonar 3.2.0 构造 ≥6 组 MIDI 对（完美/错音/漏音/多弹/抢拖拍/踏板延音），导出「参考+演奏」note 序列；Swift 侧加一个 `SCSMTestHarness`（仅 test target，可被 `xcodebuild test` 调用）读同一批 JSON 跑 NoteAligner。
- 对拍口径：**correct/missing/extra/wrongPitch 的分类计数一致**（节奏 deltaMs 允许数值误差，不要求逐毫秒相同，因 tempoMap 实现可不同）。分类计数不一致的用例必须修到达标或在 spec 记录口径差异并经 Hermes 确认。

## 6. 六维评分 `TakeScorer`（新文件 Services/Scoring/TakeScorer.swift）

输入 AlignmentResult + PlayedNote（velocity）+ ReferenceNote + `VelocityCalibration?`。全部 0...100，**算不出的维度返回 nil，UI 显式「后续/数据不足」，禁止编分**。弱总分仅由非 nil 维度等权（或在 §9 指定权重）得到并始终标注「弱总分，仅进步曲线用，不作过关依据」。

1. 音高 pitchScore：依据 correct /（非 grace 参考音数），wrongPitch/missing/extra 各自计数并定位到小节·拍。grace 参考音不进分母（装饰音容错），但 extra 的装饰乱弹仍计 extra。
2. 节奏 rhythmScore：correct+wrongPitch 匹配对的 |deltaMs| 在容差带内的比例 + 抢/拖倾向（mean deltaMs 正负）。输出：分数、中位/均值偏差、抢拍或拖拍标签、逐音偏差分布（供 S13 折叠明细，本批先给数据结构与简表，不做高级图）。
3. 速度稳定性 tempoScore：tempoMap 瞬时速度的变异度（CV）与渐快渐慢；对照 take 目标/referenceTempo 给「是否达标速度」布尔（门禁用）。无 ≥8 个可计时匹配返回 nil。
4. 力度 dynamicsScore：velocity 均匀度（同节拍层级内 CV）、左右手力度差、旋律/伴奏层级差。**有 VelocityCalibration 才做个人曲线归一**；无校准则只给原始相对统计且标注「未校准，仅相对值」；样本 <8 返回 nil。
5. 连续性 continuityScore：非中断导致的停顿次数（相邻 matched onset 间隔超过「该拍预测间隔 × 2 且 >1.5s」）与卡顿热点小节；中断间隙不算停顿（§4）。
6. 双手协同 handsScore：仅双 staff 谱；RHLH 各自 correct 率的均衡度与同步和弦到位率。单 staff/unknown → nil。

每维产出：`score: Int?`、`summary: 中文一句`、`details`（结构化，供折叠区）、`hotspotMeasures: [Int]`（该维贡献的热点小节）。
小节热力：`measureHeat: [Int: HeatValue]`，聚合该小节 wrong/missing/extra/停顿，给 0...1 热度 + 主要问题类型；供 S13 与未来 S12「只练热点」。
自由弹奏（isFreePlay / 无参考谱）：**不出以上任何对错分**，只返回统计（时长/velocity 分布/音域），复用现有 S14 口径。

## 7. 过关门禁（CourseEngine 扩展，唯一写手）

- 新增 `PassEvaluation`（值类型）：`canEvaluate: Bool`（有参考谱 + 非自由弹奏 + confidence≥阈值 + coversFullScope）、`passesAllHardMetrics: Bool`、`metrics: [MetricResult]`（错音率/节奏偏差/速度达标，各自实际值 vs 阈值，公开可查）、`reasons: [String]`。
- 硬指标（阈值来自 §9 课程数据，入门宽/进阶严）：错音率 ≤ 阈值、节奏偏差 ≤ 阈值、达到目标速度（tempoScore 达标布尔）。弱总分**不**参与。
- 过关规则：同一 Piece/教材条目，按时间序最近连续 **2 次** canEvaluate=true 且 passesAllHardMetrics=true 的 take → CourseEngine 把 Piece.status 置 `passed`（唯一写手，留痕 rulesVersion）。任一中间 take canEvaluate 但不达标 → 连续计数清零；低置信/无谱 take **不参与计数也不清零**（不可用数据既不算过也不算砸）。
- 「差多少过关」：CourseEngine 提供纯函数返回各硬指标当前值与阈值差，供 S09/S13 展示（阈值公开，非黑箱）。
- 无参考谱条目：canEvaluate 恒 false，曲库/详情/报告显式「暂无参考谱，不判定过关」，**不得**回退 SpikeSample32。
- 本批不做升降回退/复习池（PRD L136，挂后续），只做「连续 2 次达标→passed」。

## 8. 持久化与数据模型变更（Models.swift + Schema 注册）

- 新表 `TakeAnalysis`（@Model）：`takeId: UUID`、`analyzedAt`、`engineVersion: String`（="P2-scoring-1.0"）、`confidence: Double`、`lowConfidenceReasons: [String]`、六维分数（可空，用可选 Int 或 NSNumber 语义的 `Int?`，SwiftData 用可选标量）、`weakTotal: Int?`、`wrong/missing/extra/wrongPitchCount: Int`、`rhythmMedianMs/rhythmMeanMs: Double`、`tempoTargetHit: Bool`、`hotspotMeasures: [Int]`、`measureHeatJSON: String`（结构化热度）、`canEvaluate/passesHardMetrics: Bool`、`alignmentJSON: String`（逐音 AlignedNote，永久回看 + 未来 S21 对比）。
- Take **加字段**（轻量迁移，给默认值）：`pieceId: UUID?`、`scoreFileId: UUID?`、`analysisId: UUID?`、`isPassEligible: Bool`（默认 false）。用于把 take 关联到具体曲目/谱（现在 take 只有 title 字符串）。
- 一个 take 至多一份分析（同 engineVersion 重算幂等：按 takeId+engineVersion upsert，不产生重复行）。
- 原始 jsonl 仍是唯一演奏真值；TakeAnalysis 是派生缓存，可删除重建（导出/恢复行为见 §10，保持「分析可由原始 MIDI + 谱重算」）。
- 旧 take（无完整逐音、或无参考谱）：分析器返回 canEvaluate=false 的统计级结果或不建分析，UI 诚实标注，不回填假分。
- 注册进 `PianoSempaiApp.swift` Schema 数组；写一个 SwiftData 迁移冒烟测试（旧默认值容器可打开、新字段有默认）。

## 9. 容差与课程数据（公开可查，非黑箱）

- 新建 `ScoringTolerance`（值类型）+ `ScoringStandards`（按水平分级的静态表，集中一处，类似 CourseEngine 规则表）：
  - 入门（beginner）：节奏容差窗 ±120ms；错音率阈值 ≤10%；节奏偏差中位 ≤100ms；目标速度达到参考速度的 80% 即算达标。
  - 进阶（intermediate）：±80ms；错音率 ≤5%；节奏中位 ≤70ms；目标速度 90%。
  - 高级（advanced）：±50ms；错音率 ≤3%；节奏中位 ≤50ms；目标速度 100%。
- 分级来源：本批从 Piece/课程条目难度映射（入门：拜厄/哈农；进阶：599；导入曲默认入门，可在未来调）。映射写死集中、注释说明 P2.1 再细化。
- BLE 延迟口径（PRD L57）：不假装亚毫秒；容差就是为 10–20ms BLE 抖动留的带，节奏分按「是否落在带内」而非精确到毫秒惩罚。
- 所有阈值在 S09 过关标准卡/S13 报告中以真实数值展示（替换现在写死的文案），并显示「差多少」。
- confidence 门禁用阈值固定 0.6（写注释，可调集中点）；<0.6 不进门禁。

## 10. 集成点（grep 实证，锚点可能漂移，CC 开工先重新 grep）

- 练习结束：`PracticeSession.finish()`（Services/Practice/PracticeSession.swift L132）产出 TakeSummary；`PracticeSession.persist(...)`（L239）落 Take。**在视图收尾 persist 成功后**触发异步分析（不要塞进 persist 静态函数，保持其纯落库）。分析需要：take 的 midiFileURL（用 SandboxPaths 解析 jsonl）、区间 measureFrom/To、scoreFile 对应的参考 Score、tempoAvg、pieceId/scoreFileId。
- 参考谱加载：`PracticeRoomView.load()`（L395–419）现在「有 scoreFile 用之，否则 Bundle SpikeSample32」。改为：
  - 有真实 scoreFile（导入曲/未来教材谱）→ 加载并可评分，take 关联 pieceId/scoreFileId。
  - 内置教材条目但**无 scoreFile** → 不再静默加载 SpikeSample32 冒充；练习室给「暂无参考谱」态：可自由弹/录制（走无判分口径）或引导使用示例曲。具体 UI 见 §11。
  - 新增一个**显式示例曲**入口（曲库里 book="示例" 或独立卡），标题如「示例：SpikeSample32（演示用）」，明确不是拜厄某条；点它才加载 SpikeSample32，可完整跟弹+判分。这保证模拟器/真机都有一条端到端可演示路径，且不冒充教材。
- 分析编排：新增 `ScoringOrchestrator`（@MainActor 或后台 actor 均可，CC 定，但要可单测：把纯分析部分注入），读 jsonl → MidiTakeParser → ScoreReferenceNotes → NoteAligner → TakeScorer → 落/更新 TakeAnalysis；再调 `CourseEngine.evaluatePass(...)` 纯判定，**只有 CourseEngine 写 Piece.status**。
- 分析失败/解析异常：不吞错；TakeAnalysis 可记 error 状态或不建，UI 显式「本次分析失败/数据不足」，绝不抛假分；不影响 take 已落库与 streak（有效练习只认 MIDI+时长，PRD M9 口径不变）。
- 导出/恢复（ExportService + 其测试）：TakeAnalysis 派生数据纳入导出 JSON；新增断言「分析数据不含任何凭据」延续既有红线；保证删分析后能用 jsonl+谱重算。
- 不破坏 P1 网络零请求：本批不引入任何 URLSession（grep 断言）。

## 11. UI 替换范围（最小必要，视觉沿用夜琴房 token，不加新屏，只改既有屏内容）

- S13 TakeReportView（Features/Practice/TakeReportView.swift）：
  - 有可评分分析：用六维分区折叠替换 `pendingDimensionNames`（现写死「六维雷达/小节热力/节奏偏差/弱总分」L186 + TakeAnalysisService L47-49）。展示：弱总分（带「仅供进步曲线，不作过关依据」脚注）、六维分（nil 维度显式「数据不足/后续提供」）、错音/漏音/多弹计数与小节·拍定位、节奏中位偏差与抢/拖标签、小节热力（简表：按小节列出问题密度，不做复杂图形）、对齐置信度；低置信顶部琥珀条「没对上，判分仅供参考，本次不计入过关」。
  - 过关进度：展示硬指标三项实际值/阈值/差多少 + 「连续达标 N/2」；过关成功轻庆祝（PRD 无撒花轰炸，用克制文案/状态变化）。
  - 无参考谱/自由弹奏/旧 take：保持统计口径，明示「无参考谱，不判定对错/过关」。
- S09 PieceDetailView：过关标准卡（L159–163）阈值从 ScoringStandards 真值渲染；无谱条目显示「暂无参考谱，开放后可判分过关」；示例曲标注演示用途。
- S08 曲库：加入示例曲显式入口；无谱教材条目的「跟弹」动作改为诚实态（不进入一个拿样例谱冒充的练习室）。
- S20 档案：本批**不**做趋势图（仍占位），但其「后续版本提供」文案保留；不动 S12 热点自动选段入口的禁用态（数据已在 measureHeat，按钮可从「禁用」改为本批接「只练热点」吗？——见 §0：列为 P2.2，本批不接，仅确保 measureHeat 已可取）。
- S05 定级：本批不换对齐算法（P2.2），保留现有规则估算文案。
- 所有新增文案只用中文，沿用现有 19 色 token 与字体，不引入第三方图表库；热力/雷达用 SwiftUI 原生极简绘制或条形/色块，不许为画图引库。

## 12. 文件清单（CC 实施前重新 grep 校验存在性）

新增 Services/Scoring/：
- ScoreReferenceNotes.swift（§3）
- MidiTakeParser.swift（§4）
- NoteAligner.swift（§5，含 tempoMap/DP/置信）
- TakeScorer.swift（§6，六维+热力）
- ScoringModels.swift（§2 值类型 + Tolerance/Standards §9）
- ScoringOrchestrator.swift（§10 编排，注入式可测）
- （过关判定在现有 CourseEngine.swift 扩展，不新建写手）

修改：
- Models.swift（新增 TakeAnalysis @Model；Take 加 4 字段）
- PianoSempaiApp.swift（Schema 注册 TakeAnalysis）
- CourseEngine.swift（PassEvaluation/evaluatePass/连续 2 次/差多少；rulesVersion 升级注释）
- PracticeRoomView.swift（谱加载三态 + pieceId/scoreFileId 透传 + 示例曲）
- PracticeSession.swift（summary/persist 透传 pieceId/scoreFileId；分析在视图层 persist 后触发）
- TakeReportView.swift + TakeAnalysisService（六维真实渲染，删假占位）
- PieceDetailView.swift / LibraryView.swift（阈值真值、无谱诚实态、示例曲入口）
- ExportService.swift + 测试（分析数据导出、无凭据断言）
- 内置目录/资源：示例曲的呈现（复用 SpikeSample32.musicxml，不新增假教材谱）
测试新增 Tests/PianoSempaiTests/Scoring/：ScoreReferenceNotesTests、MidiTakeParserTests、NoteAlignerTests（含 6 组对拍夹具）、TakeScorerTests（六维含 nil 维度）、PassEvaluationTests（连续 2 次/清零/低置信不计数/无谱不可评）、ScoringMigrationTests、ScoringExportTests。
- test 资源：把对拍用的参考/演奏 JSON 放 Tests/ 资源目录（Hermes 生成 parangonar 夹具，CC 负责接入）。

## 13. 里程碑拆分（CC 执行，每个独立 commit + 跑全套；A 节奏：每个里程碑停等 Hermes 验证）

- M1 只读核查：grep 校验 §10/§12 全部锚点与签名，列出 spec-vs-代码偏离表（含行号修正），**不写代码**，输出到 `docs/p2-scoring/FINDINGS.md`，停等 Hermes。
- M2 模型与提取/解析层：ScoringModels + ScoreReferenceNotes + MidiTakeParser + 单测（示例谱 256/128+128、rest、区间、踏板、中断、vel0）。
- M3 对齐引擎：tempoMap + DP + 置信 + 6 组构造夹具单测全绿；接入 Hermes 提供的 parangonar 对拍 JSON，分类计数一致。
- M4 六维 + 持久化 + 过关：TakeScorer、TakeAnalysis 模型与迁移、CourseEngine 连续 2 次判定与差多少；单测含连续/清零/低置信/无谱/nil 维度。
- M5 集成 + UI：练习室三态谱加载、示例曲入口、分析编排触发、S13 六维真实渲染与置信条、S09/S08 阈值与无谱诚实态、导出；删除所有假占位分；全套测试 + build + 0 网络 grep；停等 Hermes 端到端。

## 14. 全局红线复述（CC 每条 commit 前自检）

1. 不编分：算不出=nil + 诚实文案；无谱不冒充；低置信不进门禁。
2. 课程状态只由 CourseEngine 写；分析器只读；AI/网络不参与 P2。
3. 原始 MIDI jsonl 不可变，是唯一演奏真值；分析可重建。
4. 弱总分不作过关依据；过关只看连续 2 次硬指标。
5. 自由弹奏无对错分；中断空白不判漏/不判停顿。
6. 不引第三方图表/音频/数学库，不发网络请求。
7. 修改最小化：不动 P1 在线 ScoreFollowEngine、不做 §0 挂账项。


