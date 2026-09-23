# S09 曲目详情（修订版 · 以 Stitch code.html 为真值）

- 真值文件：`56e0e80e9c8a4432b7dd8970fa0fe2a9/code.html`
- 逻辑画布：**390 × 844 pt**（DESKTOP 大画布导出，body 固定 390×844，按 390 逻辑宽施工）
- 字体：Noto Serif SC（serif，标题）/ Noto Sans SC（sans，正文）
- Status: Final

## 1. 用途

单曲目作战页：曲目元信息、技术目标与过关硬标准、小节段/热点、最近 Take 列表、吸底双 CTA。无 tab bar。

## 2. 全局布局（VStack，三段式）

```
Header（状态栏 12pt 顶距 + 导航 44）
Main（scroll，px16，卡片间距 12）
Footer（吸底，pb28，双按钮 + home indicator）
```

- body：`w390 h844`，flex-col justify-between，overflow-hidden。
- Main：flex-1，纵向滚动（隐藏滚动条），`px16 pt4 pb16`，子视图间距 **12**。

## 3. 逐层规范

### 3.1 状态栏

- 容器：`pt12 px28`，高约 44（含安全区）。
- 左：`9:41`，15pt，semibold，tracking-tight，色 textPrimary。
- 右：信号/wifi 图标 16pt + 电池（22×11，1pt 边框 textPrimary/80，圆角 3，内块圆角 1.5；右侧 1.5×4 电池耳）。

### 3.2 导航栏（h44，px16）

- 左：返回按钮 **40×40**，热区外扩 −8ml；chevron_left 24pt。
- 中：「曲目详情」serif **17pt semibold**，tracking-wide。
- 右：更多按钮 40×40，more_horiz 22pt。
- 按压态：opacity 0.6。

### 3.3 卡片通用样式（四张卡一致）

- 背景 `card #262220`；1pt 边框 `cardBorder #332D29`；圆角 **16pt**（rounded-2xl）；内边距 **16**；shadow-sm。

### 3.4 Hero 卡（曲目信息）

- 顶部行：标题 serif **23pt bold** tracking-tight「拜厄 第45条」；右侧状态 pill：`px8 py2`，圆角全圆，11pt medium，**bg 琥珀 #D4A24E，文字 #1C1917**，tracking-wider，文案「练习中」，带 shadow-sm。
- 副标题：13pt normal muted，「训练教材 · 拜厄钢琴基本教程」，mb14。
- Meta 区：顶部分隔线 1pt `cardBorder/70`，pt12；flex-wrap，行间距 8；12pt。
  - 行内项间距：图标/点与文字 6，项右 margin 16。
  - 项1：1.5×1.5 琥珀圆点 ＋「当前进度」muted ＋「17–24 小节」primary medium。
  - 项2：metronome 14pt muted ＋「参考速度」＋「♩=76」primary medium。
  - 项3（整行换行，pt4）：flag 图标 13pt ＋ 文案 11.5pt，色 amber/90：「疑似谱面错误 1 处」。

### 3.5 技术目标卡

- 标题行（mb10）：左 14pt semibold「技术目标」；右 11pt muted mono「OP.101」。
- Chips（flex-wrap，间距 8，mb12）：`px10 py4`，圆角 **8**，bg `#1C1917`，1pt 边框 `amberBorder = rgba(212,162,78,0.45)`，文字 12pt medium 琥珀。三个：音阶跑动 / 右手转指 / 均匀力度。
- 过关标准脚注块：11pt muted，leading-relaxed；bg `#1C1917/50`（即 #1C1917 以 50% 覆盖卡片），圆角 **12**，p10，1pt 边框 `cardBorder/40`。
  - 文案（锁定）：「过关标准：连续 2 遍错音率 ≤2%、节奏偏差均值 ≤50ms、达到 ♩=72（课程数据，不可由 AI 修改）」

### 3.6 段落与循环卡

- 标题行（mb12）：左 14pt semibold「段落与循环」；右 11pt muted「重点攻坚小节」。
- 小节格：**grid 8 列等宽，间距 6，mb12**；每格高 **36**，圆角 8，13pt，flex 居中。
  - 17–20（已练段）：1pt 琥珀边框，琥珀字，bg `amberMuted/20`（amberMuted 为 rgba(212,162,78,.18)，再取 20% ≈ 3.6% 琥珀覆盖），medium。
  - 21（热点/当前）：**bg 实琥珀 #D4A24E，字 #1C1917 bold**；阴影 `0 0 12px rgba(212,162,78,0.35)`；右上角 1.5×1.5 深色小圆点（绝对定位 top4 right4）。
  - 22–24（未练）：1pt 边框 `cardBorder/70`，字 `textMuted/60`，bg `#1C1917/30`，normal。
- 注释行：11.5pt muted；error_outline 图标 14pt 琥珀；间距 6；文案「上次速度 ♩=72 · 错误热点 21 小节」。

### 3.7 最近 Take 卡

- 标题行（mb8）：左 14pt semibold「最近 Take」；右 11pt muted「共 3 次记录」。
- 列表：发丝分隔 `divide cardBorder/60`。每行 `py10`，左右对齐：
  - 左：时间 13pt medium primary；副行 11.5pt muted，mt2。
  - 右：分值 **15pt semibold 琥珀 mono**；下方 10pt muted「分值」。
- 真值数据（三行，全部同速同时长）：
  | 时间 | 副信息 | 分值 |
  |---|---|---|
  | 今天 20:31 | ♩=72 · 2分14秒 | 78 |
  | 今天 20:15 | ♩=72 · 2分14秒 | 72 |
  | 周一 20:40 | ♩=72 · 2分14秒 | 65 |
- 卡内底部：pt10，居中文字按钮「查看全部 take 与趋势」12pt medium amber/70（hover 全琥珀），chevron_right 14pt。

### 3.8 吸底 Footer

- 容器：px16，pt10，**pb28**；bg `bg/95` ＋ backdrop-blur（默认材质模糊）；顶边 1pt `cardBorder/40`；子视图间距 8。
- 主按钮：全宽 **h48**，bg 琥珀，文字 #1C1917，15pt semibold，圆角 **12**；play_arrow 20pt bold；阴影 `shadow-lg shadow-amber/10`；按压 brightness-95。文案「开始练习」。
- 次按钮：全宽 **h44**，bg card，1pt 边框 cardBorder（hover amber/40），文字 13.5pt medium primary，圆角 12；my_location 16pt 琥珀。文案「只练错误热点（21 小节）」。
- Home indicator：128×4，圆角全圆，`textPrimary/25`，mt8，居中。

## 4. 颜色（hex + 语义 + 位置）

| Hex / 值 | 语义名 | 使用位置 |
|---|---|---|
| `#1C1917` | bg | 页面底；chips/图标容器底；次按钮文字压色 |
| `#262220` | card | 四张卡、次按钮底 |
| `#332D29` | cardBorder | 卡片/次按钮边框、分隔线（配透明度） |
| `#D4A24E` | amber 主强调 | 状态 pill、21 格、分值、主按钮、图标 |
| `rgba(212,162,78,0.18)` | amberMuted | 17–20 小节格底（再 /20 使用） |
| `rgba(212,162,78,0.45)` | amberBorder | 技术目标 chips 边框 |
| `#F5F2ED` | textPrimary | 主文字、状态栏 |
| `#9C948B` | textMuted | 次级文字 |
| `#6A635B` | textSubtle | 仅 config 声明，本屏 DOM 未使用（备而不用） |

## 5. 交互热区与状态

- 返回（40×40）：pop。
- 更多（40×40）：上下文菜单（内容待产品确认）。
- 疑似谱错行：点入错误标记列表/已提交态。
- 小节格：热区即格（36 高 × 约 40 宽）；真值中为 div，点选交互待产品确认。
- Take 行（整行，最小高约 44）：→ S13 Take 报告。
- 「查看全部 take 与趋势」：→ 档案/趋势过滤视图。
- 主按钮：→ S11；次按钮：→ S11 且预选 21 小节。
- 未在真值出现、旧 spec 写过的内容（**待产品确认**）：小节步进器（−/+）与长按连改、选段后副文案显示小节数、达标后「已拿下」绿 chip 与 ✓ 横幅。

## 6. 对旧 spec 的主要修正

1. 旧稿 ASCII 图与正稿结构多处不符：无爱心图标；无独立「过关标准」卡（标准是技术目标卡内脚注块）；无步进器行。
2. 标题字号 23pt（旧稿约 24，可接受但以 23 为准）；导航标题 17pt。
3. Take 三行真值均为 ♩=72 · 2分14秒（旧稿各行速度/时长不同，作废）；右侧无「参考」字样，固定 15pt 琥珀 ＋「分值」标注。
4. 小节格高 36、圆角 8、间距 6（旧稿写格高 40）；21 格带辉光阴影与右上小点。
5. 底部主按钮 h48、次按钮 h44，圆角均 12（旧稿未给数值）；次按钮为实底卡而非琥珀描边。
6. 过关标准三项指标合并为一段锁定文案（含「节奏偏差**均值**」，非旧稿的「中位数」）。
