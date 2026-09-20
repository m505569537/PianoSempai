# P2 M4 gate 返修（Hermes 独立验证，未放行）

当前 M4 工作区**编译失败**（xcodebuild：ScoringModels.swift:78 cannot find type 'TempoPoint'；
AlignmentResult does not conform to Equatable；TakeScorer.swift:150 另有参数错误被级联掩盖）。
修完下列 2 个编译问题 + 3 个语义问题，全套必须转绿，再停等 Hermes。用内置 Edit 改，shell 只跑 xcodebuild/git。

## A. 编译问题（必修）

A1. `TempoPoint` 类型作用域
- 现状：TempoPoint 是 NoteAligner 的嵌套类型（NoteAligner.swift:10 `struct TempoPoint`），
  但 ScoringModels.swift:76 给 AlignmentResult 加了 `let tempoKnots: [TempoPoint]`，该文件找不到类型。
- 修法（选干净的一种）：把 `struct TempoPoint`（beat/sec，Equatable/Sendable）**提升为顶层**放进
  ScoringModels.swift；NoteAligner 内删除嵌套定义、直接用顶层 TempoPoint（其静态方法里用到的
  TempoPoint 引用无需限定）。确认 TakeScorer/测试所有引用仍成立。

A2. DimensionResult 缺字段
- TakeScorer.swift:150 构造 `DimensionResult(..., tempoTargetHit: hit)`，但结构体（L10–15）
  只有 score/summary/hotspotMeasures。
- 修法：给 `DimensionResult` 加 `let tempoTargetHit: Bool`，默认语义"非速度维 = false"。
  为避免给其他 5 维逐个补参，给 init 一个默认值 `tempoTargetHit: Bool = false`（或加便捷 init），
  仅 tempoDimension 传真实 hit。

## B. 语义问题（必修，SPEC 红线）

B1. 节奏容差被硬编码成 beginner
- TakeScorer.swift:50 `rhythmDimension(result:tolerance:.beginner)` 写死。
  SPEC §9 要求按入门/进阶/高级用 120/80/50ms。
- 修法：`TakeScorer.score(...)` 增加参数 `standards: ScoringStandards`（不要裸传 tolerance，
  节奏带取 `standards.tolerance`），rhythmDimension 用该 tolerance；调用方/测试显式传分级。
  补一个测试：同一组 delta 数据，beginner 节奏分 > intermediate（容差越严分越低）。

B2. 速度达标比例硬编码 0.8
- TakeScorer.swift:148 `avgBPM >= target * 0.8` 写死。SPEC §9 是 0.8/0.9/1.0。
- 修法：用 `standards.targetTempoRatio`。补 intermediate(0.9)/advanced(1.0) 边界测试各一。

B3. 过关"错音率"分子分母错误（最重要）
- 现状 CourseEngine.evaluatePass L266：`rate = wrongCount / noteCount`（noteCount=演奏音数，含多弹）。
  问题：①漏一半音但没弹错音 → 错音率 0% 可过关（漏音完全不罚，违背门禁意图）；
  ②多弹会改变分母、稀释比率。
- SPEC §6 音高正确分母=非 grace 参考音数；门禁错音率应与之互补。
- 修法：evaluatePass 改为接收 `wrongPitchCount: Int`、`missingCount: Int`、
  `referenceNonGraceCount: Int`，
  `rate = (wrongPitchCount + missingCount) / max(1, referenceNonGraceCount)`。
  extra 不进错音率（多弹另由 extraCount 展示，SPEC 三硬指标不含多弹率）。
- 同步改：`passGap`、MetricResult 文案/阈值（maxWrongNoteRate 语义不变，10%/5%/3%）、
  所有调用与 TakeScorerTests/CourseEngine 相关测试（现有 wrongCount:20,noteCount:100 用例要按新参数改）。
- 补回归测试：参考 100 音、wrongPitch=0 但 missing=50 → rate=50%，beginner 也不过；
  wrong=5 missing=5 → rate=10% 恰好达 beginner 阈值边界。

B4. 过关留痕 rulesVersion（SPEC L162）
- applyPassIfConsecutive 只置 status="passed"，没留规则版本。
- 修法：①Piece 模型加 `var passedRulesVersion: String? = nil`（轻量迁移，加进显式 init，默认 nil）；
  ②CourseEngine 新增 `static let scoringRulesVersion = "P2-scoring-1.0"`（独立于 P1 的
  rulesVersion="P1-rule-1.0"，后者是定级计划生成版本，不要动）；
  ③applyPassIfConsecutive 真正过关时写 `piece.passedRulesVersion = Self.scoringRulesVersion`。
  补测试断言过关后该字段=="P2-scoring-1.0"，未过关保持 nil。

## C. 验收
- 编译干净；全套 `xcodebuild ... test` 转绿（在现有数量上新增 B1/B2/B3/B4 用例，0 failures）。
- 既有 6 组 parangonar 夹具投影与 M3 身份断言保持绿，不得为迁就改动而弱化。
- 一个 M4 commit（信息含 six-dimension scorer / TakeAnalysis / two-consecutive-pass gate / level standards）。
- 完成停在输入框等 Hermes gate；**不要开始 M5**。
- 范围仍限 SPEC §6/§7/§8；TakeAnalysis 的 upsert 编排与实际"何时分析"属 M5，本批不做。
