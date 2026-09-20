# M4 gate 返修 2（定版）：速度维反推缺陷 → AlignedNote 直带真实演奏 onset

全套编译通过，唯一红：TakeScorerTests.swift:212 `testTempoRatioBoundariesByLevel`
（90 BPM / 参考 100，intermediate 比例 0.9 应命中）。

## 根因（Hermes 已读码定位，不必再在 A/B 间猜）

- NoteAligner 构造节奏图时，每个 segment 的锚点做了**去趋势**：
  `segmentAnchors` 返回 `sec - offset`（NoteAligner.swift 约 L337-342），offset 按段拟合截距。
  最终 `AlignmentResult.tempoKnots = isotonic(detrended)` 存的是**去趋势坐标**。
- TakeScorer.tempoFnOf 只拿得到这些去趋势 knots，**拿不到 per-segment offset**，
  于是 `tempoFnOf(beat) + deltaMs/1000` 在「首匹配不在 beat0」或「多段」时系统性不等于真实 onset；
  单段首音 beat=0 时 offset 恰为 0 才碰巧接近。这是结构性缺陷，不是 90.0 浮点踩线。
- **禁止**用 `+1e-6` epsilon 掩盖——那会放过真实的反推偏差。

## 唯一修法（强制）：速度/连续性维直接消费真实演奏 onset

1. ScoringModels.swift `AlignedNote` 增加 `let playedOnsetSec: Double?`
   （extra 也有真实值；missing = nil；correct/wrongPitch 有值）。放字段末尾，保持 Codable。
2. NoteAligner 所有构造 AlignedNote 的点（grep `AlignedNote(`，含 correct/wrongPitch/extra；
   missing 传 nil）写入配对到的演奏音真实 onsetSec。
3. TakeScorer：
   - `tempoDimension`：瞬时 BPM 与 avgBPM 直接用相邻 matched 音的 `playedOnsetSec` 差，
     不再调 tempoFnOf 反推；`hit = avgBPM >= referenceTempo * targetTempoRatio`
     （90 BPM / ratio 0.9 必须精确命中；用真实 onset 后由构造保证，不再需要 epsilon）。
     deltaMs 仍用于节奏维（容差带），不删。
   - `continuityDimension`：相邻 matched 的 playedGap 直接用 playedOnsetSec 差；
     predictedGap 仍可用节奏图（判断"超出预测间隔×2"），但跨中断段跳过逻辑保留。
   - 可删除仅为反推服务的 tempoFnOf（若 tempo/continuity 都不再需要；predictedGap 若保留可改用
     reference onsetBeat × 该段平均 secPerBeat，简单可测，避免再依赖去趋势 knots）。
4. tempoKnots / TempoMapSummary 保留（§5 仍要节奏图摘要 min/max BPM、anchorCount）。

## 测试要求（不得弱化）
- 现有 `testTempoRatioBoundariesByLevel` 转绿：90 BPM 命中 intermediate(0.9)、不命中 advanced(1.0)。
- 新增两侧用例：92 BPM 命中 intermediate；88 BPM 不命中 intermediate。
- 新增一个「首匹配不在 beat0」用例（例如参考从 beat2 起弹、或跳过开头若干音再弹），
  断言 avgBPM 与真实 BPM 偏差 < 0.5（锁死去趋势 offset 缺陷不复发）。
- 6 组 parangonar 夹具投影、M3 身份拍号断言、B1 分级容差、B3 漏音计罚、B4 passedRulesVersion 全保持绿。
- 全套 0 failures；一个 M4 commit；停等 Hermes；**不开始 M5**。

## 备注
- alignmentJSON 编码会自动带新字段（AlignedNote 已 Codable）；若有显式 CodingKeys/解码夹具需同步。
- 这是判分引擎取数口径修正，属 SPEC §5/§6 实现内修正，不改变六维定义与过关阈值；
  修完 Hermes 会把「playedOnsetSec 为速度/连续性真值源」回写进 SPEC。
