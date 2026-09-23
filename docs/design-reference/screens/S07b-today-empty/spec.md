# S07b 今日 · 定级前空状态（真值修订版）

- 真值来源：Stitch `code.html`（max-w-[420px] 画布，body 深色满屏；以 390 逻辑宽为施工基准，最大允许 420）
- Status: Revised

## 用途一句话

首次进入（未定级）的今日页：线稿插画 + 解释 20 分钟三段定级，两个去向（开始定级 / 先逛曲库），底部含定级内容提示卡。

## 总体结构

- body：`#1C1917`，默认文字 `#F5F2ED`，flex-col justify-between，`min-h-screen`，`pb-24`（避让底部固定栏）。
- 内容画布：`max-w-[420px] mx-auto`，`px-5` 20pt，`pt-3`、`pb-6`，flex-col flex-1。
- 底部为 fixed 浮层容器（max-w-420）：内含 FAB + tab bar。

## 1. 模拟状态栏

- 行容器：text-xs，**muted 色** `#9C948B`，`tracking-wider` medium，pt-1、pb-3。
- 左「9:41」；右 Material Symbols：`signal_cellular_4_bar` 15pt、`wifi` 15pt、`battery_full` 18pt，均 muted。

## 2. Header（mt-2 mb-5）

- 左列：问候「晚上好」12pt medium muted，`tracking-wide`，mb-1；日期标题「9月18日 周五」**Noto Serif SC 26pt bold**，`tracking-tight leading-tight`。
- 右上连接胶囊（**绿色版**，与 S07 琥珀版不同）：
  - `bg-[#1E2721]`，边框 `#2B3E30`，文字 `#4ADE80`，`px-2.5 py-1`，full 圆角，11pt medium，`tracking-wide`，shadow-sm。
  - 状态点 6pt `#4ADE80`，`animate-pulse`。
  - 文案：「特伦斯 V70 已连接」（设备名在前）。

## 3. 中央空态内容（flex-1，items-center，text-center）

### 3.1 线稿插画

- 容器：**160 × 112pt**（w-40 h-28），相对定位，mb-5。
- 氛围底：absolute inset-0，`bg-[#D4A24E]/5`，full 圆角，`blur-2xl`。
- SVG（viewBox 160×110）元素：
  - 三条声波弧线：琥珀 `#D4A24E`，stroke-width 1.2，透明度由外到内 0.25（虚线 dash 3,3）/ 0.4 / 0.6。
  - 节拍器点：圆心 (80,38) r=3，`#D4A24E` @70%；虚线摆线至 (80,65)，@50%，dash 2,2。
  - 琴键床：rect (24,68) 112×34，圆角 4，填充 `#262220`，描边 `#332D29` 1.2；7 条白键分隔线 x=38/52/66/80/94/108/122。
  - 黑键 4 个：8×20，圆角 1.5，填充 `#1C1917`，描边 `#332D29` 0.8（x=33/47/103/117）。
  - 中央高亮键：10×21（x=75），圆角 1.5，`#D4A24E` @20% 填充 + 1.2 琥珀描边；键上点 r=1.5 实心琥珀。
  - 底线：(28,102)→(132,102)，琥珀 @70%，1.5 宽，round 端。

### 3.2 文案

- 标题「还没有你的练习计划」：serif **20pt bold**，`tracking-tight`，mb-2.5。
- 正文：13pt，`#9C948B`，`leading-relaxed`，`max-w-[320px]`，mb-6：
  「花 20 分钟做一次三段定级，Neko 会按你的真实水平排拜厄、哈农和 599。定级随时可以退出，进度会保留。」

### 3.3 三格统计占位（grid-cols-3 gap-2.5，mb-6）

- 每格：`bg-[#262220]`，边框 `#332D29/80`，`rounded-xl` 12pt，`py-2.5 px-2`，居中纵列。
- 标签：11pt muted，mb-0.5——「本周 streak」「本周时长」「距 599」。
- 值：「—」14pt **mono（系统等宽）** medium，muted。

### 3.4 操作按钮组（space-y-2.5）

- 主按钮：全宽，`py-3.5 px-4`，**`rounded-xl` 12pt**（非 16），`bg-[#D4A24E]`，hover `#C2913D`，active scale .99，时长 150ms。
  - 文字「开始 20 分钟定级」15pt semibold，`#161311`（近黑深棕，注意非 `#1C1917`），`tracking-wide`；右侧 `arrow_forward` 18pt。
  - 阴影 `shadow-lg shadow-[#D4A24E]/10`。
- 幽灵按钮：全宽，`py-2.5 px-4`，12pt 圆角，透明底，1pt 边框 `#332D29`，13pt medium muted；hover 边框 `#D4A24E/40` + 底 `#262220` + 文字转主色。
  - 文案「我已经有基础，先自己逛逛曲库」。

### 3.5 底部提示卡（mt-4）

- `bg-[#262220]/60`，边框 `#332D29/60`，12pt 圆角，`px-3.5 py-2.5`，flex 居中 gap-2。
- `info` 图标 16pt 琥珀；文案 11pt muted 左对齐：
  「定级内容：自评 1 分钟 + 视奏 2 段 + 力度校准 2 分钟。」

## 4. 底部浮层（fixed bottom-0，z-50）

- 外层 pointer-events-none 全宽 flex-col items-center；内层 max-w-420 相对 pointer-events-auto。

### 4.1 FAB「问 Neko」（本屏为带文字胶囊，与 S07/S06 不同）

- 位置：`absolute right-4 -top-12`（tab bar 顶缘上方 48pt，距右 16）。
- 形态：胶囊按钮，flex `gap-1.5`，`px-3 py-1.5`；`bg-[#262220]/95` + `backdrop-blur-md`，边框 `#D4A24E/40`，`shadow-xl shadow-black/40`；hover 边框转实色琥珀，active .95。
- 内容：**实心猫脸图标 16pt（fill 琥珀，含猫脸笑脸图案）** + 文字「问 Neko」12pt medium 琥珀，tracking-wide。

### 4.2 Tab Bar

- `bg-[#161311]/95`（注意：比 app bg 更深的色值，仅本屏），顶边 `#332D29/80`，`px-2 pt-2.5 pb-6`，`backdrop-blur-lg`，flex justify-around。
- 每 tab flex-1 flex-col items-center：图标 22pt Material Symbols；文字 **10pt**，mt-1，`tracking-wider`；下方统一有 4pt 圆点占位。
- 激活（今日）：`calendar_today` filled + 文字 **semibold 琥珀** + 4pt 琥珀实点。
- 未激活：`auto_stories`（曲库）/ `piano` / `inventory_2`（档案，注意非 leaderboard）/ `person`；muted medium + 透明圆点；hover 主文字。
- Home Indicator：absolute `bottom-1.5`，128 × 4pt，`bg-white/20`。

## 颜色 Token 总表

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark | 页面底、插画黑键 |
| `#262220` | cardDark | 统计卡/提示卡（/60）、FAB（/95）、琴键床 |
| `#332D29` | borderDark | 全部边框（/80、/60）、琴键描边 |
| `#D4A24E` | amberAccent | 插画线稿/高亮键、主按钮、FAB、info 图标 |
| `#C2913D` | amberHover | 主按钮 hover |
| `#F5F2ED` | textMain | 日期标题等主文字 |
| `#9C948B` | textMuted | 问候/正文/状态栏/未激活 tab |
| `#1E2721` | connection-green-bg | 绿色连接胶囊底 |
| `#2B3E30` | connection-green-border | 绿色胶囊边框 |
| `#4ADE80` | success-green | 连接点与胶囊文字 |
| `#161311` | surface-blackest | tab bar（/95） |
| `#FFFFFF` @20% | home-indicator | Home 指示条 |
| `#000000` @40% | fab-shadow | FAB 阴影 |

主按钮文字色 `#161311` 为内联值（非 config token），与 tab bar 底色同值。

## 字体

- serif：Noto Serif SC——日期 26 bold、空态标题 20 bold。
- sans：**Plus Jakarta Sans**（本批首次出现，回退 system-ui）——11–15pt。
- mono：系统默认等宽（统计值「—」14pt）。
- Material Symbols：`FILL 0 / wght 350`；filled 变体 wght 400。

## 交互热区

- 主按钮：全宽高约 50pt；幽灵按钮全宽约 40pt。
- 三统计卡：仅展示，无热区。
- FAB 胶囊：约 ≥44pt 高（py-1.5 + 12pt 文字行）。
- Tab：每格 flex-1（390 宽下约 78pt）。

## 与旧 spec 的主要差异（修正点）

1. **连接胶囊真值为绿色**：底 `#1E2721`、边 `#2B3E30`、文字/点 `#4ADE80`，文案「特伦斯 V70 已连接」；旧 spec 只锁文案未给色值，且 ASCII 图沿用 S07 位置。
2. **插画尺寸与构成补全**：真值 160×112pt 完整 SVG（声波三弧 + 节拍器 + 7 白键/4 黑键/中央琥珀高亮键 + 底线），旧 spec 仅「约 96pt 线稿、柔光圆环 8%」，尺寸错误且描述不全。
3. **统计占位卡**：旧 spec「值 — 为 muted serif 28」→ 真值为 **mono 14pt**、标签 11pt、12pt 圆角卡。
4. **按钮圆角**：真值 12pt（`rounded-xl`），旧 spec 无；主按钮文字色 `#161311`、hover `#C2913D`；按钮组在提示卡**上方**（旧 ASCII 图提示卡在按钮上方，顺序相反）。
5. **FAB 形态**：本屏 FAB 是**带「问 Neko」文字+实心猫脸的胶囊**（琥珀边 /40），非纯圆图标钮；旧 spec 仅写「tab + FAB」。
6. **tab bar 底色**：真值 `#161311/95` + blur-lg（比常规更深），档案 tab 图标为 `inventory_2`、激活 tab 带 4pt 小圆点；旧 spec 无。
7. 状态栏在本稿为 muted 小样式（非白底主色 sticky 栏）。
8. 画布上限真值 420（旧 spec 无此信息）。

## 旧 spec 有、html 无（待产品确认，勿删）

- 未连接 MIDI 时主按钮仍可点（自评不需琴；视奏步再引导连接）。
- 定级中途退出后主按钮变「继续定级（还剩 X 分钟）」。
- 逛曲库为只读浏览，未解锁教材详情页练习 CTA 引导先定级。
