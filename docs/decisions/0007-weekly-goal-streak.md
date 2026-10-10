# ADR-0007 — 连续达标周数（轻激励）

- 状态：accepted
- 日期：2026-10-10
- 关联：竞品差距 G8（docs/competitive-gap.md P2-3）；兑现今日页 StreakRow 标题右侧「连续达标 N 周」的诚实留白（TodayView.swift L1054 原注释：无可信字段→不渲染）。

## 背景

P1 五项（G1–G5）清零后，G8 是 P2 唯一 open 的轻激励项。现状：

- `TodayPlanService.weekStreak` 只算本周 7 灯（litDays / minutesPerDay），无跨周连续概念。
- 「有效练习日」口径已锁定：当天有 `Take.hasMidi` 且当日累计 `durationSec/60 ≥ 10` 分钟（M9）。
- 周目标次数 = `AppSettings.weeklyGoal`（默认 3）。
- 曲目级有 `CourseEngine.consecutivePassStreak`，但那是单曲目过关连续，与「周」无关，不复用。

## 决策（用户 4 项口径，2026-10-10 Grill 全拍板）

1. **达标周定义**：一周（周一→周日）内「有效练习日」数量 ≥ `weeklyGoal`，该周记为达标。
2. **只数已结束的完整周**：连续数只统计「严格早于今天所在周」的完整周。本周即使已达标也不计入——避免后半周荒废导致已显示的数字回退。本周连续数因此在整周内稳定不回退。
3. **最轻激励**：仅在今日页 StreakRow 标题行右侧显示真实「连续达标 N 周」，填补现有留白；不加徽章/刻度/动画/奖励/Neko 弹语等任何新机制。
4. **中断与历史**：某一完整周未达标，连续数归零重计；同时计算并保留「历史最长连续达标 N 周」，在档案页周区以小字展示。归零不抹除历史最长。

## 实现口径

新增纯函数（TodayPlanService，与现有 streak 同文件、同口径，周一起始 `firstWeekday=2`）：

```
static func weeklyGoalStreak(
    takes: [Take], weeklyGoal: Int, today: Date,
    calendar: Calendar = .current
) -> (currentConsecutiveWeeks: Int, longestWeeks: Int)
```

- 只遍历**已结束的完整周**：从「最早有效 take 所在周」到「今天所在周的前一周」，逐周连续枚举，中间无 take 的周也作为一个槽位（=未达标，用于正确归零与跨缺口计数）。
- 每周先聚合 7 天的分钟数（复用与 weekStreak 相同的 hasMidi + `durationSec/60` 累计），有效日 = 当天分钟 ≥10；有效日数 ≥ weeklyGoal 则该周达标。
- 从最早到最近完整周扫描：达标则 run+1，否则 run=0；currentConsecutiveWeeks = 最后一个完整周结束时的 run（最后一个完整周未达标则为 0）；longestWeeks = 全程最大 run。
- 纯函数、可注入 Calendar，从 takes 现算，**不新增 @Model、不持久化、不写任何状态**——数字永远真实，无脏状态/漂移。
- 边界：weeklyGoal≤0 时按达标处理无意义，函数要求 weeklyGoal≥1（调用点恒为 AppSettings 默认 3；测试覆盖正常范围）；无 takes / 无已结束完整周 → (0,0)。

展示：

- 今日页 StreakRow：标题行改为左右布局，左「本周 X/weeklyGoal 次」不变，右侧新增真实「连续达标 N 周」（N=0 也如实显示，不写死、不隐藏真实值）。
- 档案页 ArchiveView 周 streak 区：补一行小字「历史最长连续达标 N 周」（纯函数同口径，weeklyGoal 取 AppSettings）。
- 两处数字均由同一纯函数得出，禁止各处各算/写死。

非目标：不做达标周的日历高亮、不做徽章/奖励、不推送庆祝、不改 Piece/Take/课程状态、不影响 G3/G4/G5 任何既有逻辑。

## 验证

- 纯函数单测（PracticeCoreTests 追加）：含构造跨周 takes 的夹具，覆盖——
  0 已结束周/无 take→(0,0)；单个完整达标周→(1,1)；连续 3 周达标→(3,3)；达标 2 周→缺口周未达标→再达标 1 周→(1,3)（current 归零、longest 保留 3）；本周已达标但未结束→不计入（current 不含本周）；有效日恰好等于 weeklyGoal 边界、当日分钟恰好 10 边界；无 hasMidi 的 take 不计。
- 独立全新全量 xcodebuild test，总数在 691 基础上 +新增测试、0 failures。
