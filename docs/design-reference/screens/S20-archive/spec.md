# S20 档案（Tab）· 修订 spec

> 真值来源：Stitch code.html（DESKTOP 渲染稿，body 固定 `w-[390px]`，以 **390 逻辑宽 / 最小高 844pt** 为准；body `pb=92` 给固定 tab bar 让位）。

## 1. 用途与页面定位

长期成长档案：周切换、三统计、Neko 本周观察、6 周能力趋势折线、take 时间线（可筛全部/课程/奖励曲/自由弹奏）。
**有底部 tab bar**（档案=选中琥珀态），右下「问 Neko」胶囊 FAB 悬浮于 tab bar 之上。

## 2. 颜色系统（tailwind.config `brand.*` + 内联）

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | brand.bg | 页面底、吸顶头/ tab bar 底（95%+blur）、日历钮以外的深色底 |
| `#262220` | brand.card | 统计条、全部卡片、时间线行、未选筛选 chip、日历钮底 |
| `#332D29` | brand.border | 发丝边框、分隔线、统计条 divide-x、网格虚线、进度环底槽 |
| `#D4A24E` | brand.amber | 日历钮图标、周圆点、总时长数字、趋势线/环、选中 chip、FAB、tab 激活 |
| `rgba(212,162,78,0.15)` | brand.amber-muted | 「温和复盘」「最新 71」等浅琥珀底 |
| `#F5F2ED` | brand.text | 大标题、统计数字（天/take）、卡片标题、时间线曲名 |
| `#9C948B` | brand.muted | 状态栏、Archives、标签、时间戳、chevron、未选 chip/tab |
| `#6B645D` | brand.subtle | 配置中定义，markup 未见直接使用（备用） |
| `#F7F5EE` | `.score-paper`（CSS 定义但本屏未使用） | 预留浅色"乐谱纸"底色，本屏不渲染 |

透明度变体（真值出现）：琥珀 10/15/20/30/40/50/60%；文字 70/90%；边框 60/70%。
字体：`Noto Serif SC`（400/600/700）用于各级标题；`Plus Jakarta Sans`（含 italic）正文；数字多处用 `font-mono` + `tabular-nums`。

## 3. 整体布局层级

```
body (390pt, pb=92)
├─ header（sticky z=40：状态栏 + 标题行[档案 Archives | 日历钮]）
├─ main（px=16 pt=12 space-y=16）
│  ├─ 周选择 + 三统计条
│  ├─ 本周观察卡
│  ├─ 能力趋势卡（折线 + 手型占位行）
│  └─ Take 时间线（标题 + 筛选 chips + 4 行）
├─ 「问 Neko」胶囊 FAB（fixed bottom=74 right=16）
└─ tab bar（fixed bottom，5 项，档案激活）
```

### 3.1 吸顶 header
- `pt=8 px=20 pb=12`，bg bg **95% + backdrop-blur-md**，底边 border **60%**，z=40。
- 状态栏行：12pt semibold muted；左 9:41；右图标 14pt（信号/wifi 为 text 色 SVG）；电池 **20×10**，边框 muted，圆角 **3pt**，内填充琥珀宽 **14pt**（旧/其他屏为 muted，本屏琥珀）。
- 标题行（`mt=4`）：
  - 左 baseline 簇：大标题「档案」**24pt（text-2xl）serif bold** tracking-wide；副标「Archives」**11pt uppercase** muted，tracking-wider。
  - 右日历钮：**36×36**，圆角 **8pt**，bg card + border，琥珀日历图标 20pt（stroke 1.8）；按压缩放 0.95。

### 3.2 周选择行
- 两端 chevron 圆钮：**28×28 正圆**，图标 16pt（stroke 2），muted；hover text，active 底 card。
- 中央：6×6 琥珀圆点 + **14pt semibold** text「本周 (9/15–9/21)」，`space-x=6`。
- 形态为**图标翻页器**，非旧 spec 的"描边胶囊下拉"。

### 3.3 三统计条
- grid 3 等列，bg card + border，圆角 **12pt**，`py=12 px=8`，列间 divide-x border；文本居中。
- 每列：标签 **11pt medium** muted（`mb=6`）；数字 **18pt（text-lg）bold mono tabular**：
  - 有效练习「4 天」：数字 text 色。
  - 总时长「**2 h 05 m**」：数字**琥珀色**。
  - 完成 take「12 次」：数字 text 色。
- 单位「天/h/m/次」12pt muted。旧 spec"serif 28pt 全琥珀"错误。

### 3.4 本周观察卡（Neko）
- bg card + border，圆角 **16pt**，`p=14`，shadow-sm。
- 头行（`mb=8`）：
  - 24×24 圆头像：bg 琥珀 **20%** + 边框琥珀 **50%**，猫脸 SVG 14pt 琥珀。
  - 标题「本周观察」**12pt serif semibold** text；badge「温和复盘」**10pt mono** 琥珀字，bg 琥珀 15%，`px=6 py=2`。
  - 右时间「周日 21:00 生成」10pt mono muted。
- 正文：**13pt** text **90%** / relaxed：
  「热身完成率从 60% 到 100%了。拜厄 45 的 21 小节偏差还在 ±120ms，下周继续慢练；奖励曲记得留时间。」

### 3.5 能力趋势卡
- bg card + border，圆角 **16pt**，`p=14 space-y=12`。
- 标题行：「能力趋势」12pt serif semibold +「· 节奏稳定度」11pt medium 琥珀；右 pill「最新 71 (+7)」：11pt mono 琥珀，bg 琥珀 10%，`px=8 py=2` **全圆角**。
- **折线图：高 96pt（h-24）**，SVG viewBox `320×80`，overflow-visible：
  - 网格：y=15/45 为 `#332D29` **虚线 dash 3-3**；y=75 实线。
  - 面积：琥珀渐变 28%→0%（x1 顶→y2 底）。
  - 折线：琥珀、**stroke 2.5**、圆角端点/拐点。
  - 6 周数据点（x=15/75/135/195/255/315，y=62/50/44/34/38/22）：普通点 r=3，bg 填充 + 琥珀边 2；**最新点 r=4.5，琥珀实填 + text 色边 1.5**，标签 10pt bold text「71」在点上方；其余点标签 9pt mono muted。
  - 真值序列：**52, 58, 61, 66, 64, 71**。
- 手型趋势行（`pt=4`，顶边 border 60%，两端）：
  - 左 14pt 摄像机图标 + 12pt muted「手型趋势：录像 3 条后展示」。
  - 右 badge「暂无数据」：10pt muted，bg bg，`px=8 py=2`，border——实底小标签，**非旧 spec 的虚线边占位框**。

### 3.6 Take 时间线
- 区块 `space-y=10 pt=4`；标题行两端：「Take 时间线」**14pt serif bold** text；「最近已录 12 条」11pt muted。
- 筛选 chips 横滑（隐藏滚动条），`space-x=6 pb=4`：
  - 「全部」：bg **琥珀实底**、文字 bg 色、12pt medium。
  - 「课程 / 奖励曲 / 自由弹奏」：bg card + border，muted 12pt；hover text。
- 时间线行（`space-y=8`）：bg card + border，圆角 **12pt**，`p=12`，flex 两端，点击态边框变琥珀 60%；cursor-pointer。
  - 左簇 `space-x=12`：
    1. **进度评分环 40×40**：SVG viewBox 36×36，`-rotate-90`；底槽 `#332D29` stroke 3；弧 = 琥珀（按分值透明度微调，stroke-width 3、round 端、dasharray "分值,100"）；环心 **11pt mono bold 琥珀**分值。
    2. 信息列（`space-y=2`）：曲名 **13pt semibold** text + 类型 badge **10pt**（`px=6 py=0.8`，圆角 2）；元信息行 **11pt mono muted**：时间 · ♩速度（text 70%）· 时长。
  - 右 chevron 16pt muted。

真值 4 行：

| 时间 | 曲名 | 类型 badge | ♩ | 环分 | 时长 |
|---|---|---|---|---|---|
| 今天 20:31 | 拜厄 45 | 主菜（琥珀 15% 底/30% 边） | 72 | **78** | 2分14秒 |
| 今天 20:15 | 拜厄 45 | 热身（`#332D29` 底/muted 字） | 60 | **72** | 8分钟 |
| 周一 20:40 | Summer（久石让） | 奖励曲（琥珀 20% 底/40% 边） | 84 | **85** | 3分02秒 |
| 周一 | 哈农 1 | 热身（`#332D29` 底/muted 字） | 60 | **70** | 9分钟 |

### 3.7 「问 Neko」胶囊 FAB
- fixed **bottom=74pt（贴 tab bar 顶）right=16**，z=40。
- 胶囊：`px=14 py=8` 全圆角，bg 琥珀，文字 bg 色 **12pt semibold** tracking-wide；猫脸图标 16pt；`space-x=6`；阴影 shadow-lg 琥珀 **20%**；按压缩放 0.95。

### 3.8 底部 tab bar
- fixed bottom，宽 390 居中，z=50；bg bg **95% + backdrop-blur-lg**，顶边 border，`px=8 py=8`；5 项等宽（每项 **56pt 宽**，列布局，图标/文字间距 4）。
- 图标 20pt；文字 **10pt**；未选 muted（stroke 1.8），hover text。
- **档案（激活）**：图标/文字全琥珀，图标 stroke **2** bold，文字 10pt bold；图标右上附加 **6×6 琥珀小圆点**。
- 五项及图标：今日（日历）、曲库（书本）、练习室（钢琴键）、档案（档案盒）、我的（人像）。

## 4. 全部状态

| 状态 | 表现（真值） |
|---|---|
| 默认 | 本周、全部筛选；4 行均有评分环 |
| 周切换 | 左右圆钮翻页（切周本地查询） |
| 行按压 | 边框 → 琥珀 60% |
| chip/tab hover | muted → text |
| FAB/按钮按压 | scale 0.95 |
| 空周文案 | HTML 未呈现 → 待产品确认 |
| 多选对比模式（S21）、月报入口（S22）具体位置 | HTML 未呈现（日历钮/卡片是否承载）→ 待产品确认 |
| 行点击目标 S13 / 自由弹奏无报告回放 | 沿用旧 spec 导航定义，真值未画目标页 |

## 5. 交互热区

- 日历钮 36×36；周 chevron 28×28（按 44 热区兜底）。
- 时间线整行热区（含环、信息，右 chevron 为指示非独立钮）。
- 筛选 chips 高约 28；tab 每项 56 宽 × 约 44 高。
- 问 Neko FAB 胶囊整体热区。
- 统计条三列为展示，非热区（真值无点击态）。

## 6. 与旧 spec 的主要差异（施工必改）

1. **统计数字**：旧"serif 28pt 全琥珀"；真值 **18pt mono bold**，仅总时长琥珀，其余 text 色；圆角 12 卡 + divide-x。
2. **周选择形态**：旧"描边胶囊下拉"；真值 chevron 翻页钮 + 圆点内联文本。
3. **时间线结构全改**：旧"2pt 竖线+彩色节点圆点、行高 60、自由行无分显示音符数"；真值为**卡片行 + 40pt 琥珀评分环**，4 行（78/72/85/70）全部有分；类型用 badge（主菜/热身/奖励曲），右 chevron。
4. 时间线真值数据与旧 spec 完全不同（旧：♩68/60/65、Summer 无评分；真值见 3.6 表）。
5. 手型占位：真值为分隔线行 +「暂无数据」实底 badge，非虚线框。
6. **新增**：头部日历钮（36×36/8pt 圆角）、琥珀电池填充、问 Neko 胶囊 FAB（bottom 74）、「最新 71 (+7)」pill、「温和复盘」badge。
7. 折线图高 96pt 与旧 spec 一致（保留）；线宽 2.5、虚线网格、最新点 4.5+白边等细节旧 spec 缺失。
8. 旧 spec 的空周、月报/对比入口归属在真值中无明确承载 → 待产品确认。
