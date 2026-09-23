# S19 练琴笔记 · 修订 spec

> 真值来源：Stitch code.html（MOBILE 稿，main `max-w-[390px] min-h-screen`，以 **390×844 逻辑点**为准）。
> 注意：本屏 Tailwind 配置**重写了圆角阶梯**：`rounded`=2pt、`rounded-lg`=4pt、`rounded-xl`=8pt、`rounded-full`=12pt（非真"全圆角"）；spacing token：space-xs=4、space-sm=8、space-md=16、margin-sm=20。

## 1. 用途与页面定位

课后随手记 + Neko 周报 + 待处理问题的时间线；笔记可关联 take。从他页 push，**无 tab bar**；右下 FAB 新建。

## 2. 颜色系统（实际使用色）

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#161311` | background / surface / surface-dim | **main 底（注意非 #1C1917）**；FAB 图标语义色 |
| `#221f1d` | surface-container | 笔记卡底、未选筛选 chip 底 |
| `#4f4537` | outline-variant | 卡片/未选 chip/关联钮边框（20–40% 透明） |
| `#d4a24e` | primary-container | 选中筛选 chip 底；「课后」强调；FAB 底；辉光 |
| `#563900` | on-primary-container | 选中 chip 文字、FAB 铅笔图标（深棕字） |
| `#f3be67` | primary / primary-fixed-dim | 「课后」badge 字、待处理圆点 |
| `#9c8f7e` | outline | 日期、未选 chip 文字、元信息图标 |
| `#d3c4b2` | on-surface-variant | 导航图标、正文文字（90% 透明）、关联钮文字 |
| `#e9e1dd` | on-surface | 标题/状态栏文字 |
| `#2d2927` | surface-container-high | 关联 take 按钮底 |
| `#383432` | surface-container-highest / surface-variant | 「Neko 周报」badge 底 |
| `#eac085` | secondary-fixed-dim / secondary | 「Neko 周报」badge 字 |
| `#93000a` | error-container | 「问题」badge 底（20% 透明） |
| `#ffb4ab` | error | 「问题」badge 字、边框（30%） |

字体：标题 `Noto Serif SC`（headline-sm = **20/28**）；正文/label `Noto Sans SC`：body-md 14/22、body-sm 12/18、label-md **12/16 ls+0.06 medium**、label-sm **11/14 ls+0.08 medium**。图标 Material Symbols。

## 3. 整体布局层级

```
main (390pt, bg #161311, flex-col)
├─ 内容滚动区 flex-1 pb=112（为 FAB/底部留空）
│  ├─ 状态栏
│  ├─ 导航行（返回 | 练琴笔记 | 搜索）
│  ├─ 筛选 chips 横滑行
│  └─ 笔记卡列表（3 张，间距 16）
├─ FAB（fixed，右下）
└─ home indicator
```

### 3.1 状态栏
- `pt=12 px=24`；9:41 12pt semibold on-surface；右信号 15 / wifi 15 / battery_full 18pt，on-surface 色。

### 3.2 导航行
- `px=20 pt=16 pb=12`；三个元素等分布局。
- 返回/搜索钮：**36×36 正圆**，图标 22pt，色 on-surface-variant；hover 变 primary，按压缩放 0.95。
- 居中标题：serif **20pt（headline-sm）** tracking-wide「练琴笔记」。

### 3.3 筛选 chips 行
- `px=20 py=8`，横滑（隐藏滚动条），chip 间距 **4pt**。
- 统一：`px=14 py=6`，rounded-full（按配置 = **12pt 圆角**），label-md（12pt medium）。
- **选中（全部）**：bg `#d4a24e` + 文字 `#563900`（深棕字，非白字）；辉光 `0 0 12pt rgba(212,162,78,0.2)`；按压缩放 opacity 0.9。
- 未选：bg `#221f1d` + 边框 outline-variant 30%，文字 `#9c8f7e`；hover 字 on-surface、边变实。
- 真值顺序：**全部 / 我的记录 / Neko 周报 / 问题**（单选）。

### 3.4 笔记卡（通用结构）
- bg `#221f1d`，圆角 **8pt**（rounded-xl），边框 outline-variant **20%**，`p=16`；列内间距 **8pt**；hover 边框变 primary-container 40%。
- 结构：
  1. **头部行两端**：左日期 12pt body-sm、`#9c8f7e`、tracking-wider；右类型 badge `px=8 py=2`、圆角 **2pt**、label-sm（11pt）。
  2. 标题：serif **20pt medium** on-surface，`pt=2`。
  3. 正文：14pt / 行高 22（relaxed），on-surface-variant **90%**。
  4. 底部行（`pt=4`）：按类型不同。

**卡 1（9/18 周五 · 课后）**
- badge「课后」：bg primary-container **15%** + 边框 30%，字 `#f3be67`。
- 标题「拜厄 45 · 21 小节转指」。
- 正文真值：「今天 60 速度单手能稳定在 ±40ms 了，但一合手右手 1 指还是会平。下周试 64。」
- 关联 take 钮：`px=10 py=4`，bg `#2d2927` + 边框 outline-variant 30%，圆角 2；`graphic_eq` 14pt primary + 11pt on-surface-variant「关联 take：今天 20:31」+ chevron 13pt（opacity 70%）；hover 字/边变 primary。点击 → S13。

**卡 2（9/16 · Neko 周报）**
- badge「Neko 周报」：bg `#383432` + 边框 outline-variant 40%，字 `#eac085`（暖金，非蓝灰），前置 `auto_awesome` 12pt。
- 标题「第 3 周观察」。
- 正文：「热身完成率 100%；奖励曲时间被挤压，本周至少留两次给 Summer。」
- 底部元信息：`schedule` 13pt +「周日 21:00 自动生成」12pt，均 `#9c8f7e`。

**卡 3（9/14 · 问题）**
- badge「问题」：bg error-container **20%** + 边框 error 30%，字 `#ffb4ab`，前置 `error_outline` 12pt。
- 标题「黑键移动手腕紧」。
- 正文：「暂无结论 · 已标记，等下次侧拍一起问 Neko」（注意：旧 spec 的"下次试试坐高一点"真值中无）。
- 底部两端：左 = 6×6 `#f3be67` 圆点 + 11pt「待处理」（primary 色，tracking-wide）；右 12pt outline「标记于练琴中」。

### 3.5 FAB（新建笔记）
- **56×56**（w-14），rounded-full = **12pt 圆角（Stitch 配置如此，非正圆）**；bg `#d4a24e`，铅笔 24pt 深棕 `#563900`。
- 阴影：`0 8pt 24pt rgba(212,162,78,0.35)`；hover bg `#ffddb2`；按压缩放 0.9。
- 位置真值：fixed **bottom=40pt**；水平定位用 `right-1/2 + translate-x=165pt`，换算后钮中心 x=360（**右缘距屏边约 2pt，系 Stitch 定位工件**）。施工建议：trailing 边距 16pt、底边距 40pt（贴 home indicator 之上）——与全局 FAB 位置语言对齐，差值待产品确认。

### 3.6 home indicator
- footer `pb=8 pt=4`；128×4，on-surface-variant **30%**，全圆角，居中。

## 4. 全部状态

| 状态 | 表现（真值） |
|---|---|
| 默认 | 筛选「全部」选中；3 卡完整展示 |
| chip/press | 选中 chip opacity 0.9；未选 hover 变亮；按压缩放 0.95 |
| 卡片 hover | 边框 → primary-container 40% |
| 关联 take 钮 hover | 字/边 → primary |
| 问题卡"待处理→已处理"划线归档 | HTML 未呈现 → 待产品确认 |
- 新建/编辑大 sheet（标题/正文/类型/关联 take 选择器/删除确认）、周报卡"写进下周计划"、搜索结果页：HTML 均未呈现 → 待产品确认（逻辑沿用旧 spec，需补视觉稿）。

## 5. 交互热区

- 返回/搜索：36×36 圆（热区按 44 兜底）。
- 筛选 chip：高约 30pt（触摸热区按 44 兜底），横滑浏览更多。
- 整卡可点进入详情（hover 边框反馈）；卡内关联 take 钮为独立热区。
- FAB 56×56。
- 周报 badge/自动生成行、问题 badge 为展示元素，非热区。

## 6. 与旧 spec 的主要差异（施工必改）

1. **页面底色**：旧按全局深色；真值 `#161311`（非 #1C1917）。
2. **圆角体系**：卡片真值 **8pt**（非 12）；chips/FAB 的 rounded-full 在本配置下 = **12pt 圆角**，需与设计确认是否要真全圆角。
3. 类型标签位置：真值在**头部行右侧**（旧 spec 说"标题行左"）；周报色真值为暖金 `#eac085` 配 `#383432` 底（旧"蓝灰"错误）。
4. 选中筛选 chip：**琥珀底 + 深棕字 `#563900`**，带琥珀辉光。
5. FAB 底边距真值 **40pt**（旧 20pt）；铅笔图标深棕色；水平定位为 Stitch 工件需按 16pt trailing 施工。
6. 卡 3 正文真值为"暂无结论 · 已标记，等下次侧拍一起问 Neko"，旧 spec 文案不存在。
7. 旧 spec 缺全部色值/字号/间距/辉光参数；以第 2、3 节为准。
8. 编辑页、搜索、划线归档、"写进计划"等态真值中无 → 待产品确认。
