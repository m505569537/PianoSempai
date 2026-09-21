# PianoSempai · 数据与状态契约（系统层）

- 本文档是页面导航级 doc：数据模型、文件布局、状态机、写入权限。不含任何视觉细节。
- 产品规则真值在 `PRD.md`（M1–M9）；本文档把 Grill 决策落成实现契约。
- 技术栈：SwiftUI + SwiftData（iOS 17+）+ CoreMIDI/SwiftMIDI；零服务端；AI 为多服务商多模型有序故障转移链（单链、全多模态，每商 Key 独立 Keychain）。

## 1. 写入权矩阵（红线 3 的代码形态）

| 模块 | 能写什么 | 不能写什么 |
|---|---|---|
| M1 MIDI 采集 | 原始 MIDI 事件文件、设备会话状态 | 课程状态、评分 |
| M5 判分引擎（离线） | Take 分析结果（六维/热力/错音/置信度） | 课程状态、解锁 |
| **M3 课程引擎（唯一写手）** | 曲目状态、过关记录、路线推进、今日计划、强开记录消费 | 不改原始 MIDI；不被 AI 调用 |
| M6 手型（端上） | 视频文件、骨架标注、手型观察（confidence） | 课程状态、过关、评分维度门禁 |
| M7 AI 助教（多服务商链） | 笔记草稿/对话消息（本地） | 任何课程/判分/设置状态；只返回"建议" |
| M9 鞭策统计 | streak/周月聚合（从 take 派生，可重建） | 不施压文案之外的状态 |

硬规则：任何 AI 响应里不解析"指令动作"去改模型；AI 输出只渲染在对话/笔记。

## 2. SwiftData 模型（v1，字段可实现时增补但语义锁定）

- **Piece（曲目）**：id(ULID)、title、book（拜厄/哈农/599/奖励曲/导入）、number、totalMeasures、status（locked/notStarted/practicing/passed）、referenceTempo、sourceScoreId、insertedFromPlacementId?、suspectedErrorCount。
- **ScoreFile（谱面文件）**：id、kind（musicxml/mxl/mscz/mid/pdf）、fileURL（沙盒相对路径）、title、pageCount?、canFollow（pdf=false）、parseStatus、importedAt。
- **CoursePathState（路线状态，单例）**：currentBeyer、currentHanon、current599?、projected599Week、weekNumber、placementResultId?。
- **PlacementSelfReport**：id、yearsExperience、books[]、timesPerWeek、durationPref、genres[]、recentPiece、createdAt。
- **PlacementResult**：id、selfReportId、sixAxis{}、entryBeyer、entryHanon、projected599Weeks、velocityCalibrationId?、createdAt。
- **DailyPlan（今日计划）**：id、date、durationChoice(15/30/45)、warmupTaskId、mainTaskId、rewardTaskId?、warmupCompletedAt?、gateOverrideId?、generatedFromRulesVersion。
- **Task**：id、date?、type（warmup/main/reward/free）、pieceId、measureFrom、measureTo、tempo、loopConfig?、status。
- **Take**：id(ULID)、pieceId?、taskType、startedAt、endedAt、durationSec、tempoAvg、midiFileURL、scoreId?、measuresRange、videoFileURL?、analysisId?、noteSnapshot?、isFreePlay、interruptionRanges[]（断连区间）。
- **VelocityCalibration**：id、createdAt、pp/mp/mf 三档 velocity 映射曲线参数、deviceName。
- **TakeAnalysis（M5 结果）**：id、takeId、sixAxis{}、overallReferenceScore（弱总分，标注非门禁）、wrongNoteRate、rhythmicDeviationMedianMs、tempoAchieved、measureHeat{measure:score}、wrongNotes[]、alignmentConfidence（high/med/low）、pedalIncluded（CC64 bool）、suspectedScoreErrorIds[]、engineVersion。
- **GateEvent（门禁/强开）**：id、date、kind（warmupBlocked/override/passAssessed）、reasonTag?、note?、weekIndex。
- **ScoreErrorMark（疑似谱错）**：id、pieceId、measure、takeId、type、note、createdAt、occurrenceCount。
- **VideoClip（视频）**：id、takeId?/monthlyArchiveMonth?、source（activeReview/zfImport）、fileURL、durationSec、retentionCategory（recent8/permanent）、calibrationId?、createdAt。
- **PostureObservation（M6）**：id、videoClipId、timecodeSec、label、confidence（high/med/low）、skeletonVersion；低置信不生成结论性 label。
- **ChatThread / ChatMessage**：threadId、takeContextId?、role（user/neko）、text、attachments[]（videoClipId 经 S18b 确认后才可出现）、evidenceRefs[]（takeId+measure）、providerModel（本次链路实际命中的服务商·模型，运行时写入非写死）、createdAt。
- **VideoUploadConsent（S18b 留痕）**：id、videoClipId、rangeStart/rangeEnd、questionText、providerModel（本次故障转移链实际命中的服务商·模型 id）、deleteAfterAnalysis（bool）、consentedAt。
- **Note**：id、kind（manual/weeklyReport/issue）、title、body、linkedTakeId?、status（open/resolved）、createdAt。
- **WeeklyMonthlyAgg**：periodKey、kind（week/month）、effectiveDays、totalSeconds、takeCount、warmupRate、overrideCount、metrics{}、generatedReportText?。
- **AppSettings（单例）**：notificationConfig、weeklyGoal、videoRetentionRule（default=8/曲）、providerChain（有序条目：服务商 id/显示名/baseURL/模型 id 列表/启用态/排序；仅存非密配置，各 Key 在 Keychain 不在此）、lastSuccessfulProviderModel?、onboardingCompleted。

Keychain：每服务商独立条目（如 `<providerId>.apiKey`，account 含服务商 id 互不串）；永不进 SwiftData/日志/导出包。

## 3. 沙盒文件布局

```
Documents/
  scores/            MusicXML/mxl/mscz/mid（可跟弹）
  pdfs/              只读 PDF
  midi/yyyy/MM/      原始 MIDI（只追加，建议每 take 一个 .mid + 事件 json）
  video/active/      "录给 AI 看"片段（每曲保最近 8，LRU）
  video/monthly/yyyy-MM/  Zf 导入（永久，手动清理）
  exports/           用户导出的 zip（可被用户删）
  db/                SwiftData store
```
- MIDI 原始事件只追加不可变（M1/Phase7）。
- take 删除：软删 DB + 文件进入系统回收策略；导出包不依赖 App 可解析（开放格式）。

## 4. 关键状态机

**曲目过关（M3）**：practicing →（连续 2 次 take 全部硬阈值达标，规则引擎判定）→ passed；AI/手型/总分均不参与。失败永远停留 practicing，无降级羞辱。
**热身门禁（每日）**：warmup 未完成 → 点主菜 → S07c；选原因并确认 → gateOverride 留痕 → 放行；补完成 → warmupCompletedAt。
**速度自适应（M4，练习循环内）**：两遍达标 +5 BPM（上限参考速度）；崩 −5；连崩 2 遍暂停提示休息；所有变化只影响本练习，不改曲目参考速度。
**定级**：selfReport → sightread2 段 → velocity 校准 → PlacementResult → 生成第 1 周 DailyPlan。
**连接（M1）**：connected / disconnected；断连暂停判分、续录拼接、take 记 interruptionRanges。
**视频生命周期**：不存在日常录制态；只有 activeReview（S15 校准→录制→S16 标注→可选 S18b 上传）与 monthlyImport（S17，永不自动上传/分析）。

## 5. 外部接口（出站：用户配置的多服务商链，OpenAI 兼容）

- 一条有序故障转移链，全部为多模态模型；提问时按序尝试，任一可用即工作，失败静默切换，全链失败才报错；粘住上次成功模型，定时试探高优先级恢复。
- 每个服务商：预设模板（火山方舟默认 `https://ark.cn-beijing.volces.com/api/v3`、百炼、DeepSeek 等）或 OpenAI 兼容自定义 baseURL；服务商下可配多个模型 id；均不写死在 App，在 S25 维护。
- 请求体只含：本地组装的必要上下文（take 指标/小节/偏差/证据），视频问题额外带经 S18b 确认的切片；纯文字/MIDI 问题不带任何附件。
- 响应契约：必须返回 evidenceRefs；无证据时输出"没听清/没看清"类，不得给纠错结论（红线 2 由 prompt + 客户端校验双重保证：缺 evidence 的结论不渲染为"纠错"）。
- 出站域名仅限用户在 S25 配置的服务商域名；崩溃/统计 SDK 也不加（零服务端原则）。
- 诊断记录实际命中的服务商·模型与每跳失败原因（如 401/ModelNotOpen/网络/耗时），供 S25 展示。

## 6. 有效练习与 streak（M9）

- 有效练习 = 有 MIDI 且当日累计 ≥10 分钟。
- streak 按周展示 7 灯（周一起始）；断签不扣任何东西，不产生负向文案。
- 周日 21:00 本地任务生成周报（本地通知一条）；月报每月 1 日生成上月。
