# 0004: 日常视奏训练 Grill 决议（G4）

## 状态
已确认（2026-10-09 用户 OK 两项核心决策；其余按产品性格由 Hermes 定）

## 背景
竞品差距分析（docs/competitive-gap.md）与用户画像共同指向同一短板：用户"五线谱
都会但读谱最易藏拙"，练琴偏"以曲代功"，缺即时读谱能力。代码里视奏能力
`SightReadSession` 已存在，但只在入学定级 S04 用一次，且 `loadExpectedPitches`
硬编码只读示范曲 `SpikeSample32` 一首——没有日常训练、没有内容供给、没有趋势
留痕。本决议把视奏变成可持续的日常轻训练。

## 核心决策（用户拍板）
1. 素材来源：从内置教材（拜厄/哈农）抽"还没练到的超前条"当陌生片段。
   零额外内容成本，难度天然只比当前进度高一点。
2. 判定口径：轻量——命中率 + 用时 + 停顿数。不走 M5 六维对齐，避免每次视奏
   变成一场考试。

## 决策内容

### 一、进度与候选带
- 课程进度唯一真相 = Piece 状态（ADR-0003 Q1），当前游标 `cursor` 从该轨状态
  派生（= 最小号非 passed/非 waived 条），与已有的 derivedCursor 同口径。
- 候选带 = 同一教材轨 `[cursor+1, cursor+6]` 共 6 条 `locked` 条目。
  - 跳过已越过教材上限的号（拜厄 106 / 哈农 20）。
  - 拜厄、哈农两轨合并候选；每次在候选带内随机/轮换选 1 条。
- 接近教材末尾、候选不足 6 条时：有多少用多少；两轨都耗尽（全曲已过）时，
  允许复用历史视奏过的条目，并在结果上诚实标记"复习性视奏"，不伪装成首见。

### 二、片段切分与去重
- 每条取连续 4 小节；条目总小节数 ≤ 4 时取整条。默认从第 1 小节起。
- 去重：持久化视奏记录（见三），同一 `(book, number, measureStart)` 已视奏过
  则不再优先选；候选带内若全部视奏过，按"最久未视奏"优先复用。
- 谱定位复用 `BundledScore.resourceName(book:number:)` / `BundledScore.url(book:number:)`
  （与练习室同一路径，真实解析，不硬编码音符）。

### 三、持久化与趋势（新增模型，不污染过关链路）
新增 `@Model SightReadDrillRecord`：
- `entityId: UUID`
- `book: String`、`pieceNumber: Int`、`measureStart: Int`、`measureCount: Int`
- `expected: Int`、`matched: Int`、`pauses: Int`
- `hitRate: Double?`（expected==0 时为 nil，不编数字）
- `elapsedSeconds: Int`
- `isReview: Bool`（复习性视奏 true）
- `createdAt: Date`

视奏记录**不**写 `Take` / `TakeAnalysis`，**不**触发过关、**不**推进课程、
**不**计入连续达标周（G8 独立）。它是只读谱能力的旁观察样本。

趋势：展示最近约 20 次命中率（含首见/复习区分），给一条命中率走势与均值，
文案由 Neko 温柔解读（如"最近读陌生谱明显不卡了"）。数据不足时诚实留白。

### 四、判定口径（轻量）
- 期望音：片段内**全部声部**的期望音序列（沿用 `SightReadSession` 遍历
  `parts.first` 全部 staves 的口径，而非 `ScoreExpectedPitches.extract` 的单
  staff）。把 `loadExpectedPitches` 泛化为接收 `Score`/URL，不再绑死
  SpikeSample32。
- 命中率：沿用现有音序贪心匹配；`expected==0` → hitRate nil。
- 用时：start→stop 的真实秒数；停顿：相邻音间隔 > 2s 的次数（现有口径）。
- 呈现"谱面片段"：渲染该片段五线谱供眼读（复用现有谱面渲染），不跟灯、
  不 waterfall。

### 五、入口与边界
- 入口：今日页"今日可选"区一张视奏卡（与今日主菜并列，非强制），亦可从
  专门入口查看历史趋势。不做进 App 强推。
- 不设门禁、不要求达标、不连刷压力：一次一段，结束即出轻结果。
- 未连接 MIDI 键盘时：可进入看谱/说明，但不能产生命中率（无输入不编数字）。

## 非目标（明确不做）
- 不做 M5 对齐/多维评分、不做节奏实时判分。
- 不从用户导入的奖励曲抽片段（避免难度失控与剧透）。
- 不专门为视奏额外编排一批小曲（本次零新增内容）。
- 不与过关 / streak / 排行榜挂钩。

## 影响面
- 新增 `SightReadDrillRecord` 模型；泛化期望音加载；新增选片纯逻辑（候选带、
  去重、轮换，可单测）。
- 今日页加可选卡；新增视奏进行/结果/趋势的呈现。
- 测试：选片算法（游标边界、候选带、去重、教材末尾、跨轨）、判定口径、
  记录写入与趋势聚合；SwiftData 夹具一律 `ModelContext(container)`
  （不用 .mainContext，前证 trap）。
