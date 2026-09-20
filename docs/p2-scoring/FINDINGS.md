# P2 Scoring · M1 只读核查报告（FINDINGS）

- 日期：2026-09-20 · 执行：Claude Code（只读核查，未写任何生产代码）
- 基线：main @ `12ef690`（工作区干净）· Xcode 26.6 · swift-sheet-music pin `2a3a6f7`
- 方法：对 SPEC §10/§12 的每个锚点逐一 grep/读码/抽样验证（含 SwiftData 模型、
  swift-sheet-music 包源码、样例谱 XML 实数、PRD 行号）。结论分三档：
  ✅ 吻合 / ⚠ 行号漂移（内容吻合）/ ❌ 偏离（实现时必须按本文件修正口径）。

## 1. §10 集成点锚点

| SPEC 锚点 | 实测 | 结论 |
|---|---|---|
| `PracticeSession.finish()` @ PracticeSession.swift L132 | L132 `func finish() -> TakeSummary` | ✅ 行号精确 |
| `PracticeSession.persist(...)` @ L239 | L239 `static func persist(_ summary:taskType:isFreePlay:startedAt:interruptions:title:in:) -> Take` | ✅ 行号与签名吻合（纯落库，未含分析触发——符合 §10 要求在视图层触发） |
| `PracticeRoomView.load()` @ L395–419 | L395 起，body 与 spec 描述一致：有 scoreFile 用之，否则 **Bundle 兜底 SpikeSample32**（待修的冒充点，实测确认存在） | ✅ |
| TakeAnalysisService `pendingDimensionNames` @ L47–49 | L47–49，内容 `["六维雷达","小节热力","节奏偏差","弱总分"]` | ✅ 精确 |
| TakeReportView 引用 @ L186 | L186 `ForEach(analysis.pendingDimensionNames...)`（「完整判分」卡） | ✅ 精确 |
| 「连续 2 次」文案 SettingsView L262 / PieceDetailView L163 | L262 / L163 逐字吻合 | ✅ 精确 |
| PianoSempaiApp Schema 数组 @ L12–24 | 实际 L12–25（12 个模型，无 TakeAnalysis） | ⚠ 漂移 1 行，内容吻合 |
| `Take.midiFileURL` → `Documents/midi/yyyy/MM/take-*.jsonl`，字段 t/k/n/v/suspicious | `RawMIDIEventRecord` L9–17 五字段逐字吻合；TakeStore.readEvents 存在 | ✅ |
| Take 现无 pieceId/scoreFileId/analysisId/isPassEligible | 确认全部缺失（M4 按加字段实施） | ✅（与 §8 预期一致） |
| TakeSummary 无 pieceId/scoreFileId 透传字段 | 确认缺失——M2/M5 需在 TakeSummary/persist 链路补（spec §10 前提，非矛盾） | ⚠ 实现前提 |
| commit `12ef690`（模拟器默认模拟输入行为） | 存在于 main 历史 | ✅ |
| 零网络基线（grep URLSession） | `PianoSempai/` 下 0 处 | ✅（M5 结束时按同口径复查） |
| SandboxPaths（jsonl 解析入口） | Features/Library/PDFLibraryView.swift 内（全局可见） | ✅ |

## 2. §12 文件清单核查

| 项 | 实测 | 结论 |
|---|---|---|
| 新增 Services/Scoring/ 七文件 | 目录不存在（应然） | ✅ 全部待建，无残留同名 |
| 新增 Tests/PianoSempaiTests/Scoring/ | 目录不存在（应然） | ✅ |
| 修改目标全部存在 | Models.swift / PianoSempaiApp.swift / CourseEngine.swift / PracticeRoomView.swift / PracticeSession.swift / TakeReportView.swift / TakeAnalysisService / PieceDetailView.swift / LibraryView.swift / ExportService.swift(+测试) | ✅ |
| 复用 SpikeSample32.musicxml | PianoSempai/Resources/SampleScores/ 在库 | ✅ |
| 现有 @Model 名与 §8 新表 `TakeAnalysis` | 无同名类；现有 `P1TakeAnalysis`(struct) 与 `TakeAnalysisService`(enum) 为 P1 简化分析器 | ⚠ 见偏离 D-3 |

## 3. swift-sheet-music API 锚点（§1 参考时序来源）

| SPEC 断言 | 实测签名 | 结论 |
|---|---|---|
| `Score.division` | `Score.swift L5 public var division: Int` | ✅ |
| `Score.resolveTickInMeasure` | `Score+TickInMeasure.swift L3 public func resolveTickInMeasure(for itemID: ScoreItemID) -> Int?` | ⚠ 见 D-2 |
| `chord.duration.resolved(in: measureDuration).ticks(division:)` | `NoteDuration+Resolved.swift L8 resolved(in measureDuration: Fraction) -> NoteDuration`；`NoteDuration.swift L26 ticks(division: Int)`（**对 `.measure` 会 trap，必须先 resolved**，包内文档明示） | ✅（trap 前提已在 §1 写明，实现时强制先 resolved；measureDuration 用 `Score+EffectiveMeasureDurations.swift` 的 `effectiveMeasureDurations() -> [Fraction]`） |
| `VoiceElement` 的 `.chord/.rest` 累加 | **不存在 `.rest` case**。包内 `VoiceElement.swift L7–17`：**rest = 空 Chord**（`chord.notes.isEmpty`，`isRest` 计算属性、`VoiceElement.rest(duration:)` 构造器） | ❌ 见偏离 D-1 |
| `graceNotesBefore/After` | `Chord.swift L24/L28 public var`（IdentifiedArray<GraceChord>） | ✅ |
| 样例谱 staff1=128 / staff2=128 | SpikeSample32.musicxml XML 实数：staff1=128、staff2=128、合计 256 | ✅（实测，非引用旧测试） |

## 4. PRD 行号锚点

| 引用 | 实测 | 结论 |
|---|---|---|
| M5 @ L184–209 | L184「**对齐**」起、L187 踏板进判分、L209 弱总分呈现 | ✅ |
| M3 过关 @ L134–136 | L135「连续 2 次 take 达到错音率/节奏偏差/目标速度阈值」 | ✅ |
| M4 @ L151–159 | 循环/速度分段在位 | ✅ |
| 隔离铁律 @ L360 | L360 逐字吻合 | ✅ |
| BLE @ L57 / 断连 @ L64 | 逐字吻合（±50ms 示例；中断空白不判漏弹） | ✅ |

## 5. 偏离与实现口径修正（❌/⚠ 汇总，M2 起按此执行）

- **D-1（❌ API 偏离）rest 表示**：`VoiceElement` 无 `.rest` case，rest = 空 Chord
  （`chord.notes.isEmpty` / `isRest`）。§3 的「`.rest`：游标推进 rest 的 resolved ticks」
  实现为「遇 `isRest` 的 `.chord` 同样推进游标、不产 ReferenceNote」。其余 §3 流程不变。
- **D-2（⚠ 口径说明）resolveTickInMeasure**：该函数按 `ScoreItemID` 取 tick，而 §3 的
  提取器按 voice.elements 顺序做游标累加（不经 ScoreItemID）。实现以 §3 游标累加为准；
  `resolveTickInMeasure` 仅可作抽样校验工具，不做主路径。
- **D-3（⚠ 命名/职责衔接）**：§8 新 @Model `TakeAnalysis` 与现有 `P1TakeAnalysis` /
  `TakeAnalysisService`（P1 简化统计器）共存。M4/M5 按 §12 把 TakeReportView 的占位
  渲染切到新分析时，`P1TakeAnalysis.pendingDimensionNames` 的假占位随之删除；二者
  在 M4 前不得同时向 S13 输出（避免双口径）。
- **D-4（⚠ 漂移）**：PianoSempaiApp Schema 数组实际 L12–25（+1 行）；其余全部行号锚点
  精确命中（finish L132、persist L239、load L395、L47–49、L186、L262、L163）。
- **D-5（⚠ 实现前提）**：TakeSummary 目前无 pieceId/scoreFileId；§10 的「persist 后触发
  分析」需要这两个值沿 PracticeRoomView → TakeSummary → Take 传递，M2 建模时一并加。

## 6. 结论

§10/§12 锚点 **24 处核对：19 ✅ 精确、4 ⚠ 漂移/前提、1 ❌ API 偏离（D-1 rest 表示）**。
无 spec 自相矛盾；唯 D-1 需要实现口径替换（以包内 `isRest`/空 Chord 为准），
其余为行号漂移与实现前提记录。M2 可按本文件开工。
