# 0003: 课程推进状态机 Grill 决议（条目状态为唯一真相）

## 状态
已确认（2026-09-30 用户 OK）

## 背景
P1/P2 编码完成后做跨页代码审查，发现「练 → 过关 → 课程往前走」的主闭环从未接通：
- PRD 只定义了过关 = 连续 2 次达标 take，但没写过关后课程进度如何前移。
- 代码里进度存在两套互相不同步的真相：`CoursePathState.currentBeyer/currentHanon`
  单游标 与每个 `Piece.status`。过关函数 `applyPassIfConsecutive` 只把 Piece.status
  置为 passed，从不推进 current*；全仓没有任何代码推进 current。
- 今日页 / PracticeHub 进房时也不传 piece，导致这些入口的 take 无 pieceId，
  过关判定整段被跳过。
结果：即使反复达标，明天今日页仍停在拜厄第 1 条。本决议补齐该状态机。

## 决策内容（15 项）

### 一、真相模型
- Q1：课程进度的唯一真相 = 每个教材条目（Piece）各自的状态。
  `currentBeyer/currentHanon` 降级为从状态实时派生的值，不再手动维护，
  根除两套真相打架。

### 二、推进时机与当前条目
- Q2：第 2 次达标 take 落库、条目判 passed 的那一刻，下一条立刻解锁
  （不等下次会话）。
- Q3：「当前主菜」= 拜厄轨最小号非 passed/非 waived 条目；哈农热身同理。
- Q4：同一教材轨任一时刻至多 1 条 practicing。

### 三、定级 / 复习 / 回退
- Q5：定级插入点之前的条目记独立终态 waived（已免修），不参与推进，不算 passed。
- Q6：过关条目自动进入间隔复习（复习池），防回生。
- Q7：连续不过关时自动回退上一条目。

### 四、复习与回退细则
- Q8：复习间隔 1 → 3 → 7 → 14 天递增。
- Q9：复习 take 不达标 → 退回 practicing。
- Q10：连续 3 次不过关 take 触发自动回退。
- Q11：哈农为独立轨，同样 2 次过关推进（目录前 20 条）。

### 五、衔接 / 落态 / 封顶 / 手动边界
- Q12：车尔尼 599 在拜厄全 106 条通关前恒 locked，通关后第 1 条解锁。
- Q13：回退原子落态——当前条目 practicing→notStarted，上一条目 passed→practicing。
- Q14：复习间隔到 14 天后每 14 天循环，不毕业。
- Q15：手动强开不能标记过关或解锁条目；推进只认真实 take 数据。

## 状态机（每教材轨独立：拜厄 / 哈农 / 599）

状态集合：
- `locked` 未解锁
- `waived` 已免修（终态，跳过）
- `notStarted` 已解锁未开始
- `practicing` 在练
- `reviewing` 复习中（到期的已过关条目）
- `passed` 已过关（在复习间隔中等待下次到期）

转换（全部由 CourseEngine 消费 take 硬数据触发，唯一写手）：
1. locked → notStarted：前一条变 passed 时立刻解锁
2. notStarted → practicing：产生首个有效 take
3. practicing → passed：连续 2 次达标 take
4. passed → reviewing：到达复习日
5. reviewing → passed：复习 take 达标，间隔进一档
6. reviewing → practicing：复习 take 不达标
7. 连续 3 次不过关：当前条目 → notStarted，上一条目 → practicing（原子）

派生：
- 当前主菜 = 拜厄轨最小号非 passed/非 waived；当前热身 = 哈农轨同理
- 复习调度：passed 条目带 nextReviewAt + intervalStage；今日页每日至多取 1 条
  到期复习（nextReviewAt 最早优先），插在热身与主菜之间
- 复习为单次判定：1 次达标即续期，1 次不达标即退回 practicing

## 边界 / 红线
1. 只有 CourseEngine 能写状态；View / AI 不得改任何课程状态。
2. 过关、推进、回退只认真实 take 硬数据，无手动跳条入口。
3. waived 是免修不是过关，不参与连续计数与复习。
4. 599 解锁严格绑定拜厄全通关，不提前。

## Grill 日期
2026-09-30
