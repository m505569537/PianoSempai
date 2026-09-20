# P2 M5a 任务书：后端集成（编排器 + 透传 + 谱可用性三态）

> 只做后端与可测纯逻辑，**不做 SwiftUI 视图渲染**（S13/S09/S08 界面留 M5b）。
> SPEC 权威：docs/p2-scoring/SPEC.md §10（集成点）、§8（持久化）、§11 标注的数据流、§14 红线。
> 开工先重新 grep 校验行号（锚点可能漂移）。完成后停等 Hermes，**不开始 M5b**。

## 已就绪可直接复用（M2–M4 已落地，勿重写）
- `ScoreReferenceNotes.extract(score:measureFrom:to:) -> [ReferenceNote]`（含 hand/onsetBeat/duration/measure/beat/grace）
- `MidiTakeParser.parse(events: [RawMIDIEventRecord], interruptionStartSecs: [Double] = [], streamEndSec: Double? = nil) -> MidiTakeParser.Result`（字段 notes / segmentIndexOfNote / segments:[Range<Int>] / pedalEventCount / suspiciousCount；notes 已 onset 升序、踏板已修正）。**开工 grep 确认真实签名与 Result 字段名**。
- `NoteAligner.align(references:played:tolerance:startBPM:) -> AlignmentResult`
- `TakeScorer.score(result:played:references:calibration:referenceTempo:standards:segmentStartSecs:) -> Scored`
- `ScoringStandards.beginner/intermediate/advanced`（tolerance + 错音率/节奏中位/速度比阈值）
- `CourseEngine.evaluatePass(...) / passGap(...) / consecutivePassStreak(...) / applyPassIfConsecutive(piece:takesOldestFirst:in:)`
- `TakeAnalysis` @Model（字段见 Models.swift 约 L297+），`Take` 已有 `pieceId: UUID? / scoreFileId: UUID? / analysisId: UUID? / isPassEligible: Bool`（带默认值）。
- 谱：`ScoreLoader.loadScore(contentsOf url: URL) throws -> Score`；原始事件：`TakeStore.readEvents(from url: URL) throws -> [RawMIDIEventRecord]`（字段 t/k/c/n/v/suspicious，见 TakeStore.swift）；路径解析 `SandboxPaths.resolve(_:)`。

## A. ScoringOrchestrator（新文件 Services/Scoring/ScoringOrchestrator.swift）

目标：一次 take 分析的可测编排。**把纯计算与 SwiftData IO 分开**，便于单测注入。

1. 定义纯函数 `analyzeTake(input:) -> AnalysisOutcome`（不依赖 ModelContext）：
   - 输入 struct：`references: [ReferenceNote]`（已按 measure 区间提取好；空=无参考谱）、
     `played: [PlayedNote]`、`segmentStartSecs: [Double]`、`calibration: VelocityCalibration?`、
     `referenceTempo: Int`、`standards: ScoringStandards`、`startBPM: Int`、`isFreePlay: Bool`。
   - 无 references 或 isFreePlay：返回 `canEvaluate=false` 的统计级 outcome（不出对错分），**不抛假分**。
   - 否则：NoteAligner → TakeScorer，产出六维（nil 透传）、counts、confidence、
     canEvaluate（= confidence≥0.6 且 coversFullScope 且非自由/无谱；0.6 用命名常量）、
     passesHardMetrics（调 CourseEngine.evaluatePass 纯判定，注入所需计数/中位/速度布尔）。
   - alignmentJSON：用 JSONEncoder 编码 aligned（AlignedNote 已 Codable）；measureHeatJSON 编码 [Int:Double]。
   - 解析/对齐异常 do-catch：返回 error outcome，不吞（带 error 标记供 UI 显示"本次分析失败/数据不足"）。
2. IO 层 `@MainActor func run(for take: Take, scoreFile: ScoreFile?, piece: Piece?, measureFrom/To, referenceTempo, in context:)`：
   - 用 take.midiFileURL 经 SandboxPaths 解析 jsonl，读 [MIDIEvent]（复用 TakeStore 的读法/解码，注意 startNano=首事件）。
   - 经 ScoreLoader 加载 scoreFile 对应谱 → ScoreReferenceNotes.extract（区间取 take.measureFrom/To）。
   - 调纯函数 analyzeTake。
   - **幂等 upsert** TakeAnalysis：按 (takeId, engineVersion="P2-scoring-1.0") 找现有行，有则原地更新、无则新建（迁移测试已锁定此语义）；回填 take.analysisId / take.isPassEligible。
   - 若 piece != nil 且该 take 可评：拉同 piece 历史 takes（时间升序）的 (eligible,passed)，调 `CourseEngine.applyPassIfConsecutive`（**只有它写 Piece.status**）。
   - 分析失败不影响 take 已落库与 streak（有效练习口径 M9 不变）。
3. 纯函数必须可不依赖 App/磁盘单测：构造 references+played 直接断言六维/canEvaluate/JSON 往返。

## B. PracticeSession.persist 透传 pieceId/scoreFileId
- `PracticeSession.persist(...)` 增加可选参数 `pieceId: UUID? = nil, scoreFileId: UUID? = nil`，
  落 Take 时写入（带默认值，不破坏现有调用方与测试）。
- 视图层**本里程碑先不接线调用**（M5b 做），只保证签名与落库正确；可加一个单测：persist 后 take 带 pieceId。

## C. 谱可用性三态（纯逻辑，先不做 UI）
新增一个可测的纯决策（放 ScoringOrchestrator 或 ScoreAvailability.swift）：
`enum ScoreAvailability { case realScore(ScoreFile), samplePiece, unavailable }`
- 有真实 scoreFile（导入曲）→ realScore。
- 显式"示例曲" → samplePiece（加载 Bundle SpikeSample32）。
- 内置教材条目但无 scoreFile → unavailable（**禁止静默回退 SpikeSample32**）。
- 决策函数输入：piece/scoreFile/是否示例曲标记；单测断言三条分支。
- 在 BuiltinCatalog 体系里给"示例曲"一个显式建模（CatalogEntry 增加可选 isSample/示例书 或独立入口数据），
  标题含"示例"，book 不伪装成拜厄/哈农/599；catalogStatus 对示例曲返回 notStarted（不锁）。
  **只加数据与纯逻辑，不改 LibraryView/PracticeRoomView 的界面**（M5b 接线）。
- 现有 PracticeRoomView.load 的"否则加载 SpikeSample32" fallback：本里程碑先把其决策改调 ScoreAvailability
  （unavailable 时不再假装加载到可评分态），但**界面三态呈现留 M5b**；若改动会牵动大段 UI，可仅抽函数+标 TODO(M5b)，保证不编译出"无谱却按样例评分"的路径。

## D. 测试（Tests/PianoSempaiTests/Scoring/ScoringOrchestratorTests.swift 等）
- 完美演奏→六维非 nil（hands 在双 staff 才有）、canEvaluate=true、passesHardMetrics=true。
- 无 references / isFreePlay → canEvaluate=false、无对错分、不建过关。
- 低置信（构造大量错配）→ canEvaluate=false 但**不**清零连续计数（仅断言纯 outcome 层 eligible=false）。
- alignmentJSON/measureHeatJSON 编码再解码一致。
- analyzeTake 喂畸形/空输入返回 error outcome 不抛、不假分。
- 幂等：同 take+version 跑两次只 1 行（可用 in-memory ModelContainer 做 IO 层测试）。
- ScoreAvailability 三分支 + 示例曲 catalogStatus=notStarted。
- 6 组 parangonar 夹具与 M2–M4 全部测试保持绿。

## E. 红线（commit 前自检，延续 SPEC §14）
- 不发任何网络请求（本里程碑结束 grep 断言无 URLSession）；不引第三方库；不动在线 ScoreFollowEngine。
- 算不出=nil+诚实；无谱不冒充；弱总分不进门禁；原始 jsonl 不可变、分析可重建。
- 全套 `xcodebuild test ... iPhone 17 Pro` 必须 **0 failures**；新增测试一并跑过。
- 一个 commit（M5a）；完成后停，汇报改动文件与测试数，等 Hermes gate。
