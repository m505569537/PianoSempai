# ADR-0005: 错误类型 → 矫正练习处方引擎（G3）

## 状态
已确认（2026-10-09，用户 8 项口径全部拍板）

## 背景
竞品调研（docs/competitive-gap.md，断点 D3）：所有学琴 app 在用户弹错后只报「错在哪」，
不告诉「该怎么练才能改掉」。G2 已接通「只练错误热点」，但那是手动循环；本引擎要把错误
分类成可操作的练习法，并在用户反复不过时自动把矫正练习排进今日，形成「诊断 → 处方 →
复查」闭环，且不取代硬指标过关（红线 4）。

## 输入：复用现有信号，不新增采集
来自最近一次/多次 `TakeAnalysis`（经 Take.pieceId 串到同一首）：
- 逐音 `AlignedNote.cls`：correct / wrongPitch / missing / extra；带 refMeasureIndex(0-based)、
  deltaMs(正拖/负抢)、hand。
- 六维分 pitch/rhythm/tempo/dynamics/continuity/hands（nil=算不出）、rhythmMedianMs、avgBPM、
  hotspotMeasures、measureHeatJSON。
- 可评/过关口径：canEvaluate、passesHardMetrics、confidence。

## 决策一：错误类型全量 8 类（一次建全）
引擎从分析信号归并出 8 种错误类型：
1. wrongPitch 错音（wrongPitch 逐音 / pitchScore 低）
2. missing 漏音（missing 逐音）
3. extra 多弹（extra 逐音）
4. rhythm 节奏偏差（|deltaMs| 超容差 / rhythmScore 低 / rhythmMedianMs 超标）
5. tempo 速度不足（tempoTargetHit=false / avgBPM 低于目标比 / tempoScore 低）
6. dynamics 力度（dynamicsScore 低）
7. continuity 连续性中断（continuityScore 低 / 停顿多）
8. hands 双手配合（handsScore 低）
某类信号为 nil（算不出）时该类不判定、不编错；一份分析可同时命中多类。

## 决策二：手工编「错误类型 → 练习法」表，针对 hotspot，不跨曲
BuiltinCatalog.json 条目只有 book/number/referenceTempo，无技术点元数据，故练习法表手工
编写、集中一处（纯数据，非黑箱）。每类给出可执行练习法：慢练速度比、是否分手、是否开
节拍器、达成目标。示例口径（具体数值 Stage 编码时随表定稿）：
- 错音：定位看谱 + 极慢速（参考速 0.5）单手单小节，先唱后弹；目标=该段音高正确。
- 漏音：分手把隐藏的内声部/和弦音逐个出声；目标=齐奏音一个不丢。
- 多弹：数拍克制，只弹谱面音；目标=无额外触键。
- 节奏偏差：节拍器 0.6 速，先拍手/单音跟拍再上键；目标=|deltaMs| 落容差带。
- 速度不足：从能稳的速度起步、节拍器每遍 +4 BPM 阶梯提速；目标=达到目标速且不断。
- 力度：分句做力度对比、强调弱指下键；目标=力度层次可辨。
- 连续性：分段接缝（四小节一组接缝）、减少停；目标=一遍不停顿走完。
- 双手配合：先分手各自成型再合，合时降速；目标=双手对齐。
练习法针对该曲 `hotspotMeasures` 小节；hotspot 为空时给整曲级练习法（慢练全曲/分手），
不指定小节。**不跨曲推荐其它教材条目**（不做「节奏差→去练哈农 X 条」的跨曲目映射）。

## 决策三：连续 2 次可评不过即触发
同一 Piece 最近的 TakeAnalysis 中，连续 2 次满足 canEvaluate=true 且 passesHardMetrics=false
即触发处方。低置信(confidence<0.6)或不可评(canEvaluate=false)的分析**不计入**这 2 次，
也不打断连续计数口径（只有可评的不过才计），避免低质量信号误触发。
"连续"按该曲分析时间倒序判定；中间出现一次通过即清零。

## 决策四：自动加矫正卡，不锁过关
触发后，今日页在主菜**之前**自动出现一张矫正卡（与复习卡/视奏卡并列的可选卡形态，复用
任务卡外壳）。矫正卡展示命中的错误类型 + 对应练习法 + hotspot 小节；点进 PracticeRoomView
对 hotspot 小节循环练习（房间需支持进入即锁定 hotspot 区间）。
- 强制性=非门禁：矫正卡**不锁过关**，曲目能否通过仍只看硬指标（红线 4），不做"必须先完成
  处方才能再考"的强制 gate。
- 完成口径：进房对 hotspot 小节练完一遍即标记完成（不看达标率，避免矫正卡变成又一道门禁）。
- 消失/清零：该曲通过硬指标后矫正卡立即消失、失败计数清零；当天已完成的矫正卡不重复催促
  （但次日若仍连续不过可再出现）。

## 持久化
新增一个 @Model `CorrectionPrescription`（写入既有 Models.swift，**不新增文件**），字段至少：
pieceId、book、number、命中错误类型 [String]、练习法快照、hotspotMeasures(可空=整曲级)、
prescribedAt、completedAt(可空)、resolvedAt(可空)。卡的"是否该出现"优先从该曲最近分析
派生（连续2次可评不过），处方记录负责练习法快照与当天完成/去重；该曲通过即 resolvedAt
落值、不再渲染。Schema 在 PianoSempaiApp 注册（同既有模型加法）。

## 边界 / 红线
- 不新增 MIDI/音频采集；只消费既有 TakeAnalysis/Take。
- 算不出的维度(nil)不判定该类错误，禁止编错（红线 1 诚实）。
- 低置信/不可评不触发、不计入连续不过。
- 矫正卡不改变 Piece.status（只由 CourseEngine 写）、不写 Take/TakeAnalysis、不触发
  过关/推进/streak；过关唯一依据仍是硬指标（红线 4）。
- 不跨曲推荐其它教材条目；练习法表手工集中、公开可查非黑箱。
- 无参考谱/自由弹奏的统计级 take 无错误类型 → 不生成处方。

## 分阶段
- Stage A（纯核心、可单测）：8 类错误归并纯函数（从 AlignedNote/六维信号 → 错误类型集合）、
  连续不过判定纯函数、练习法表查询、hotspot 为空 → 整曲级兜底、CorrectionPrescription
  存储/完成/resolve。零新增文件，逻辑并入既有 Services 文件（建议 Scoring 或
  SightReadSession 同处或新 MARK；测试追加 PracticeCoreTests.swift）。
- Stage B（视图）：今日矫正卡 + 进房锁定 hotspot + 完成标记，房间支持初始循环区间。
A 独立验证绿后才派 B。

## Grill 日期
2026-10-09
