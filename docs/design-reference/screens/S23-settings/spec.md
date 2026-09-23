# S23 我的 Tab（修订版 · 以 code.html 为真值）

- Screen ID：`8dd7c9ffad7044aab816036bbc8a081a`
- 画布元数据：2560×2878 DESKTOP；实际内容 390 逻辑宽手机竖版（body `w-[390px]`），按 390 逻辑宽取值
- 真值文件：`/tmp/stitch-truth/screens/8dd7c9ffad7044aab816036bbc8a081a/code.html`
- Status：Revised

## 1. 用途

设置主页：个人状态卡 + 五组 inset-grouped 列表（设备 / 课程与提醒 / AI 助教 Neko / 数据 / 关于）；底部 5 tab，「我的」激活。

## 2. 颜色令牌

| Hex / 值 | 语义名 | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark 主背景 | body、状态栏（/95）、tab 栏（/90） |
| `#262220` | cardDark 卡片底 | 个人卡、全部组卡 |
| `#332D29` | borderDark 发丝边 | 卡边、行间分隔（/60）、tab 栏上边（/80） |
| `#D4A24E` | amberAccent | 头像底、脉冲点、行图标盒（底 /10 边 /20）、Plus 标、激活 tab |
| `#F5F2ED` | textMain | 标题、行标题、状态文字 |
| `#9C948B` | textMuted | 组标题（/80）、右值、非强调图标 |
| `#6A635B` | textDim（config 令牌） | config 定义；html 中 chevron 实际以 muted/70 呈现 |
| `#10B981` | emerald-500 连接点 | 电钢琴行、API Key 行状态点，带辉光 `0 0 6px rgba(16,185,129,0.5)` |
| `rgba(255,255,255,0.03)` | 行按压底 | active:bg-white/[0.03] |
| `rgba(255,255,255,0.05)` / `rgba(255,255,255,0.1)` | 普通行图标盒底/边 | 非琥珀语义行 |

图标字体：Material Symbols Outlined，`FILL 0 / wght 400 / GRAD 0 / opsz 20`；激活 tab 图标用 fill-1（FILL 1）。

## 3. 整体结构

- body：390 宽，min-h 844，纵向，`pb-24`（96，为固定 tab 栏留位），overflow-x hidden。
- 状态栏（sticky top，z-30）：surface/95 + backdrop-blur，`pt-3 px-7 pb-2`；9:41 14pt semibold；右信号 4 格条 SVG、WiFi 14×12、电池 20×10（圆角 3、含右侧 1.5pt 电池凸点）。
- main：`px-4` pt-2，组与组之间 `space-y-6`（24）。
- Tab 栏（fixed bottom，z-40）：宽 390 居中，surface/90 + backdrop-blur-xl，上边 1px border/80，`px-3 pt-2 pb-5`（20）；5 列 grid；home indicator 128×4 primary/20，mt 10。

## 4. 页面级标题

- `pt-2 px-1`，「我的」30pt（text-3xl）bold serif tracking-tight。

## 5. 个人状态卡

- card 底 / border / 圆角 16（rounded-2xl）/ `p-4`（16）/ shadow-sm；整卡可点，按压缩放 0.99。
- 横向：左组 gap 14；右 chevron。
  - 头像：48×48 圆，amber 底，serif 18pt bold surface「猫」，shadow-inner。
  - 主行 16pt medium primary tracking-tight「自学钢琴 · 第 6 周」，后跟 6×6 amber animate-pulse 点。
  - 副行 12pt muted mt 2 truncate「路线：拜厄 → 599/849 · 哈农并行」。
  - chevron 20pt，muted/70。

## 6. 组卡通用规范（5 组）

- 组标题：12pt medium muted/80，`px-2`，uppercase tracking-wide；标题与卡间距 6。
- 组卡：card 底 / border / 圆角 16 / overflow-hidden；行间 1px 分隔 borderDark/60；shadow-sm。
- 行：`p-3.5`（14）左右，行高约 48；按压底 white/3%；整行 cursor-pointer。
- 行左：图标盒 28×28 圆角 8 + 14pt 行标题 medium primary，gap 12。
  - 琥珀语义行（电钢琴、API Key）：盒底 amber/10、边 amber/20、图标 amber。
  - 普通行：盒底 white/5、边 white/10、图标 muted。
- 行右：12pt muted 右值（可含状态点）+ chevron 18pt dim，gap 6。

### 6.1 设备（4 行）

1. 电钢琴（piano 图标 17pt，琥珀盒）：右 8×8 emerald-500 辉光点 +「特伦斯 V70 · 已连接」12pt medium muted。
2. MIDI 诊断（cable）：右值「事件正常」。→ S24
3. 力度校准（graphic_eq）：右值 mono「2026-09-18」。
4. 视频保留（videocam）：右值「每曲最近 8 条」。

### 6.2 课程与提醒（3 行）

1. 课程路线总览（alt_route）：仅 chevron。
2. 通知时间（notifications）：右值「工作日 20:30 · 周末 14:00」。
3. 周目标（flag）：右值「3 次 × 30 分钟」。

### 6.3 AI 助教 Neko（3 行）

- 组标题行内嵌右侧标：10pt 常规字重 amber，底 amber/10，px 6 py 0.8 圆角 2「Plus」。
1. 火山方舟 API Key（key，琥珀盒）：8×8 emerald-500 辉光点 +「已设置」。→ S25
2. 默认模型（smart_toy）：右值 mono 12pt「doubao-seed-2.0-pro」。
3. 练琴笔记（auto_stories）：仅 chevron。→ S19

### 6.4 数据（3 行）

1. 导出我的全部数据（download）：仅 chevron。→ S26
2. 从备份恢复（history）：仅 chevron。
3. 存储占用（storage）：右值「1.2 GB（视频 0.9 GB）」。

### 6.5 关于（2 行 + 页脚）

1. 隐私与红线（security）：仅 chevron。
2. 关于 PianoSempai（info）：右值 mono「v0.1.0」。
- 组卡外页脚：`pt-3 pb-2`，11pt dim serif，uppercase tracking-widest，opacity 0.7，逐字「PianoSempai · 静夜琴房」。末组 `pb-4`。

## 7. Tab 栏（5 项）

- 每项 VStack：图标 22pt + 10pt 文字（mt 4，medium，tracking-tight），常态 muted、hover primary。
- 顺序与图标：今日 calendar_today / 曲库 library_music / 练习室 piano / 档案 insights / 我的 person。
- 「我的」：图标 fill-1、amber；文字 semibold amber。

## 8. 全部状态与交互热区

- 整个人卡热区、全部行整行可点（最小高约 48）。
- 连接/Key 状态点：emerald 辉光（正常）。旧 spec 的异常态（红点「未连接 · 去连接」、Key 未设置琥珀脉冲行）html 未呈现 → **待产品确认**（html 仅展示正常态；脉冲动效只出现在个人卡小绿/琥珀点，且该点为 amber）。
- 本页无红色/危险行（与旧 spec 一致）。

## 9. 相对旧 spec 的主要修订

1. 个人卡真值：头像 48 实心 amber 圆 +「猫」字（旧 spec 写 52 琥珀描边 + 猫耳线稿，错）；主文案「自学钢琴 · 第 6 周」+ 副行「路线：拜厄 → 599/849 · 哈农并行」，无「课程路线总览 →」按钮。
2. 通知时间真值「工作日 20:30 · 周末 14:00」（旧 spec「周日 21:00 · 工作日 20:30」，错）。
3. 存储占用真值「1.2 GB（视频 0.9 GB）」（旧 spec「视频 642MB」，错）。
4. 组标题含「Plus」标签；组间间距 24；组卡圆角 16；行内边 14；图标盒统一 28 圆角 8。
5. Tab 图标为 Material Symbols（person FILL 1 激活），旧 spec 未指定图标体系。
6. 页面大标题「我的」30pt bold serif。
7. 入口名「火山方舟 API Key」（与 S25 实际为多服务商链，名称差异待产品确认是否改文案）。
