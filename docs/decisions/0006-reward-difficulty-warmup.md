# ADR-0006: 奖励曲难点段落自动混入热身（G5）

## 状态
已确认（2026-10-10，用户 8 项口径全部拍板）

## 背景
PRD M3 Q4=A（docs/PRD.md L144）：奖励曲自由选；app 分析导入曲技术点并标
"现在能弹 / 偏难 / 远超当前"，偏难曲的难点段落自动混进热身铺路，但不阻止弹。
竞品断点 D5 记录该能力仅有任务类型字段、无分析/混入逻辑（docs/competitive-gap.md）。
本 ADR 兑现该承诺：对真实可解析导入曲做静态难度评估与定级，把"偏难"曲最难的
2-4 小节自动排成热身之后的可选铺路卡，非门禁、不阻止用户直接弹任何曲目。

## 前提与数据来源
- 导入曲建档：CourseEngine.registerImportedScore（Services/CourseEngine.swift L184）。
  仅 `imported.canFollow == true`（musicxml/mxl/mscz/mid，可解析出音）才建 Piece
  （book="导入"、sourceScoreId 挂 ScoreFile）；PDF 等 canFollow=false 只建 ScoreFile、无 Piece。
- 静态分析输入复用既有链路：ScoreLoader.loadScore → Score；
  ScoreExpectedPitches.extract 取每小节期望音（与练习室/判分同源，不新增解析）。
- 当前课程进度：CoursePathState 的 currentBeyer / currentHanon（current* 由 Piece 状态派生）。
  对当前在练的拜厄/哈农条目用同一套静态难度口径算"当前水平基准分"。

## 决策一：难度相对当前课程进度定级（非绝对标尺）
三档相对"当前在练条目"的难度基准：
- 计算导入曲整体静态难度分 D，以及当前课程条目基准分 B（拜厄/哈农当前条目中取较高者，
  代表用户当下能处理的上限）。
- 现在能弹：D ≤ B × kPlay（明显在能力内）。
- 偏难：B × kPlay < D ≤ B × kFar（略高于当下，铺路可承接）。
- 远超当前：D > B × kFar（差距过大，铺了也跟不上）。
- 具体 kPlay / kFar 与难度分量权重在 Stage A 集中常量、公开可查（非黑箱），并写单测固定。

整体静态难度分量（从可解析谱提取，算不出的维度不编）：
黑键/升降号比例、音符密度（单位小节音数）、相邻音程跳度、和弦厚度（同时键数）、
速度记号（若有 referenceTempo）。PDF/不可解析谱走决策四。

## 决策二：热身卡之后追加独立"奖励曲铺路"卡（非强制）
- 不并进哈农热身本体，而是在今日热身卡之后追加一张独立卡，视觉复用 G3 矫正卡的卡外壳
  （ADR-0005 的 correctionCard 语言），标识"奖励曲铺路"。
- 卡片展示：导入曲标题、定级"偏难"、难点小节（1-based）、练习法（进房锁定难点段循环）。
- 点按进 PracticeRoomView，进入即锁定难点小节区间（复用 G3 Stage B 的
  initialHotspots 进房机制）。非门禁、不阻止弹、不影响过关/课程状态/streak。

## 决策三：每天最多 1 首导入曲的 1 个难点段（2-4 小节）
- 当日至多排 1 张铺路卡（选"最该先铺"的那一条），避免热身臃肿。
- 选择口径（Stage A 纯函数）：在所有"偏难"档导入曲中，选超出基准比例最高、
  且最久未铺路（当天未完成/从未铺）者； tie-break 用确定性规则（标题/entityId），禁止随机。

## 决策四：PDF 等无法解析出音的导入曲——诚实标"暂无法分析"
- canFollow=false / ScoreLoader 解析失败的导入曲：不出三档、不进热身。
  在曲库该曲位置诚实展示"暂无法分析（仅可查看的谱面）"，禁止凭曲名/文件信息编造难度（红线 1）。
- OMR（PDF 自动转谱）是 PRD 红线，本能力不做。

## 决策五：难点段按小节静态难度定位（连续 2-4 小节）
- 对每小节算静态难度：黑键比例、音符密度、相邻/旋律音程跳度、和弦厚度（与决策一同口径、小节级）。
- 在全曲小节难度序列上取窗口大小 2-4 小节中累计/峰值难度最高的连续窗口作为难点段；
  窗口在合法小节内钳制，单小节也不越界。取确定性结果（同分取更靠前），不随机。

## 决策六：完成口径 = 练完一遍（不看达标）
- 进房对难点小节循环、练完一遍即标记铺路卡完成（同 ADR-0005 决策四口径），
  不设命中率/速度门槛，避免铺路卡变成又一道门禁。

## 决策七：只有"偏难"档铺路；"远超当前"只标档
- 仅"偏难"档生成铺路卡。"远超当前"只在曲库展示档位，不进热身——
  差距太大铺了也跟不上；随用户水平提升（基准 B 上升）重新评估时会自动降为"偏难"再铺路。

## 决策八：铺路卡消失规则
- 当天完成（completedAt 落值）后当日不重复催促。
- 该曲重新分析后升到"现在能弹"档：不再铺路，既有未结铺路记录关闭。
- 导入曲/谱被删除：不展示其卡。重新评估触发点=进入今日页/导入完成后（Stage B 接线）。

## 持久化（新增 @Model，写入既有 Models.swift，不新增文件）
- RewardDifficultyAssessment：pieceId、scoreFileId、grade（play/stretch/far 三档 rawValue）、
  difficultyScore、baselineScore、reasons（可空，技术点说明）、engineVersion、assessedAt。
  同一 piece 保留最新评估（upsert，幂等）。
- RewardPavingCard：pieceId、book/number（导入曲标识）、hotspotMeasures（0-based 2-4 小节）、
  prescribedAt、completedAt(可空)、closedAt(可空，升档/删除时关闭)。
  当日"是否该出卡"由最新定级=偏难 + 无当天未完成卡派生；卡只负责小节快照与当天去重。
- Schema 在 PianoSempaiApp 注册（同既有模型加法）。

## 边界 / 红线
- 只对 canFollow 且能真实解析出音的导入曲评估；PDF/失败/算不出一律诚实降级，禁止编难度（红线 1）。
- 铺路卡非门禁：不改 Piece.status（只由 CourseEngine 写）、不写 Take/TakeAnalysis、
  不触发过关/推进/streak、不阻止用户弹任何曲目。
- 不做 OMR；不跨曲推荐其它教材条目。
- 选择/定级/窗口均为确定性结果，禁止随机；阈值与权重集中公开、带单测。

## 分阶段
- Stage A（纯核心、可单测）：谱面→整体静态难度分、小节级难度序列、相对基准的三档判定、
  每日 1 条铺路选择纯函数、2-4 小节难点窗口纯函数、RewardDifficultyAssessment /
  RewardPavingCard 存储与 upsert/完成/关闭。逻辑并入既有 Services 文件（新 MARK），
  测试追加 PracticeCoreTests.swift。
- Stage B（视图）：曲库导入曲三档/暂无法分析标识、今日"奖励曲铺路"卡（热身之后）、
  进房锁难点段（复用 G3 initialHotspots）、完成回写、评估/铺路派生接线。
A 独立验证绿后才派 B。

## Grill 日期
2026-10-10
