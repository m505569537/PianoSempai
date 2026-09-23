# S12 段落循环设置（修订版 · 以 Stitch code.html 为真值）

- 真值文件：`e326117680544db8897517772be93a57/code.html`
- 逻辑画布：**390 × 844 pt**（MOBILE 780×1768 @2x 导出；main 容器固定 390×844）
- 字体：Noto Serif SC（serif）/ Noto Sans SC（sans）
- Status: Final

## 1. 用途

从练习室拉起的循环设置。真值为**整屏 sheet 画布**（390×844，无可见 scrim、无 home indicator）；呈现为全屏页面还是占屏 ~78% 的底部抽屉，**待产品确认**——两种形态下内部规范一致。

## 2. 圆角 token（本稿 config 重映射，勿用 Tailwind 默认值）

| 类名 | 实际值 |
|---|---|
| rounded（DEFAULT） | **2pt** |
| rounded-lg | **4pt** |
| rounded-md | **6pt**（沿用默认） |
| rounded-xl | **8pt** |
| rounded-full | 12pt（在小元素上等同全圆角） |

## 3. 全局布局（VStack）

```
Header（pt12 pb8 px16：抓手 + 标题行）
Scroll（flex-1，px16 py4，卡间距 16，pb24）
  卡1 选择小节
  卡2 循环方式
  卡3 每遍之间
Footer（p16，双按钮，毛玻璃吸底）
```

- 背景：surface **`#161311`**（本稿唯一使用 #161311 为页面底的屏；与练习室 #1C1917 不同）。
- 顶部环境光：绝对 −top96，水平居中，320×192，bg `primary/5 = #F3BE67/5`，圆角全圆，blur-3xl。

## 4. Header

- 抓手：**40×4**，rounded-full，bg `outline-variant/60 = #4F4537/60`，mb12，居中。
- 标题行：左 repeat 图标 **20pt primary `#F3BE67`** ＋ headline-sm「段落循环」（serif **20pt**，行高 28，wght 500，tracking-tight），间距 4；右关闭钮 **32×32 rounded-full**：close 20pt，字 on-surface-variant `#D3C4B2`（hover 变 on-surface、bg surface-container `#221F1D`，按压缩放 .95）。

## 5. 卡1 选择小节

- 卡片：bg `surface-container #221F1D`，rounded-xl **8pt**，1pt 边框 `outline-variant/30 = #4F4537/30`，p16，shadow-sm，overflow-hidden；顶边 1pt 内高光（透明→white/5→透明渐变）。
- 标题行：「选择小节」16pt Noto Sans **medium**（行高 24，tracking .01em）；右 11pt label（行高 14，tracking .08em）on-surface-variant：「曲目：拜厄 第45条（共 32 小节）」。

### 5.1 起/终点步进器（grid-cols-2，gap8，mb16）

每格：bg `surface-container-low #1E1B19`，1pt 边框 outline-variant/30，rounded-lg **4pt**，p8，纵向 gap6。

- 标签：11pt on-surface-variant（「起点小节」/「终点小节」）。
- 横向三段：−钮、数值、＋钮。
  - 按钮：**28×28**，rounded **2pt**，bg `surface-container-high #2D2927`（hover surface-bright `#3C3836`），1pt 边框 outline-variant/20；remove/add 16pt on-surface；按压缩放 .95。
  - 数值：serif **20pt medium**（「17」/「24」）＋「小节」11pt on-surface-variant，基线对齐。

### 5.2 32 小节微型时间线（mb8）

- 标注行：11pt on-surface-variant/70，mb6，两端 ＋ 居中：左「第 1 小节」；中 `primary-container #D4A24E` medium「17 - 24 选中 (8小节)」；右「第 32 小节」。
- 条带：**grid 32 列，列间距 2**，高 **32**，bg `surface-container-lowest #100E0C`，p4，rounded-md **6pt**，1pt 边框 outline-variant/25；列底对齐，`repeat(32, minmax(0,1fr))`。
  - 1–16、25–32：`surface-container-highest/60 = #383432/60`，圆角 1pt；高度为示意波形（8~18pt 不等）。
  - 17–24：**primary-container #D4A24E 实填充**，高 20~26pt。
  - **21 错误点**：条内为普通琥珀柱，柱上方绝对定位 −top12 的 **6×6 圆点：bg error #FFB4AB，ring 2pt error-container #93000A，animate-pulse**。
- 说明行（mt6，11pt outline `#9C8F7E`）：1.5 error 圆点 ＋「第 21 小节存在常错音符，系统已自动定位」。

### 5.3 快捷 chips（grid-cols-4，gap4，pt4）

- 通用：整钮 py6 px8，rounded-lg **4pt**，12pt（行高 16，tracking .06em，medium）；bg surface-container-low，边框 outline-variant/40，字 on-surface，hover 边框 primary/50。
- ① 错误热点：filled error 图标 12pt #FFB4AB ＋ 文字 on-surface。
- ② **当前段（激活）**：bg `primary-container/15 = #D4A24E/15`，1pt 边框 primary-container，字 primary `#F3BE67` medium，shadow-inner。
- ③ 全曲：字 on-surface-variant，hover 变 on-surface。
- ④ 手动：同③。
- 真值 JS：点任一 chip 即把它切换为激活样式（单选互斥）。

## 6. 卡2 循环方式

- 卡片样式同卡1。标题「循环方式」16pt medium，mb8。
- 单选项（space-y **4**），每行 px12 py10，rounded-lg 4pt，flex 两端：

| 状态 | 容器 | 单选钮 | 文案 14pt | 右注 11pt outline |
|---|---|---|---|---|
| 选中 | bg surface-container-low，1pt 边框 **primary-container/60** | 16pt 圆，1pt 边框 primary `#F3BE67`，内 8pt 实心 primary | medium「逐遍循环（默认）」 | 原速稳定练习 |
| 未选 | bg low/60，边框 outline-variant/30（hover 全 opacity） | 16pt 圆，边框 outline-variant/80，空心 | on-surface-variant「每遍提速 +5 BPM」 | 渐进肌肉记忆 |
| 未选 | 同上 | 同上 | 「崩了自动 −5 BPM 重来」 | 智能降级缓冲 |

- 底部常驻提示（mt8，pt4，顶边 1pt outline-variant/20）：pets 图标 16pt primary；12pt on-surface-variant/80 leading-tight：「连崩 2 遍自动暂停，Neko 会建议降速或分手」。**真值中此行常驻显示**，不随选项折叠。

## 7. 卡3 每遍之间

- 卡片样式同卡1。标题「每遍之间」16pt medium，mb8。
- 两行（divide-y outline-variant/20）：

### 7.1 间隔准备时间

- 左：hourglass_top 16pt outline ＋ 14pt「间隔准备时间」。
- 右步进器：bg surface-container-low，1pt 边框 outline-variant/30，rounded-lg 4pt，p4；−/＋ 钮 28×28 rounded 2pt bg surface-container-high；值 **14pt medium，min-w56，居中**：「3 秒」。

### 7.2 节拍器预备拍 1 小节

- 左：图标真值渲染为 **file_map_stack**（data-icon 写 metronome，DOM 文本是 file_map_stack——实现时统一用 metronome 语义，图标字形待产品确认）16pt outline ＋ 14pt 文案。
- iOS 开关（role=switch，aria-checked=true，ON）：**48×24 圆角全圆**，bg primary-container `#D4A24E`，p2，内容右对齐，shadow-inner；旋钮 **20×20 圆形** bg surface-container-lowest `#100E0C`，shadow-sm，中心 6×6 primary 圆点。OFF 态底色真值未画（按 token 应取 surface-container-highest，待产品确认）。

## 8. Footer（吸底）

- p16，bg `surface-container-low/95 = #1E1B19/95` ＋ **backdrop-blur-md**；顶边 1pt outline-variant/25；flex gap8。
- 取消：**flex-1**，py12，rounded-lg 4pt，1pt 边框 outline-variant/60，14pt medium on-surface，hover bg surface-container。
- 开始循环练习：**flex-[2]（比例 1:2）**，py12，rounded-lg 4pt，**bg primary-container #D4A24E**（hover primary #F3BE67），字 on-primary **`#432C00`**，14pt medium，shadow-md（hover shadow primary/20）；filled play_arrow 18pt。

## 9. 颜色（hex + 语义 + 位置）

### App 实际使用（DOM 内联/类名命中）

| Hex / 值 | 语义 | 位置 |
|---|---|---|
| `#161311` | surface 页面底 | 本屏底 |
| `#221F1D` | surface-container | 三张卡、close hover 底 |
| `#1E1B19` | surface-container-low | 步进器/单选行底、footer /95 |
| `#100E0C` | surface-container-lowest | 时间线条带底、开关旋钮 |
| `#2D2927` | surface-container-high | −/＋ 钮底 |
| `#3C3836` | surface-bright | −/＋ hover |
| `#383432` | surface-container-highest / surface-variant | 时间线未选柱 /60 |
| `#F3BE67` | primary | 标题图标、单选选中、chips 激活字、环境光 /5 |
| `#D4A24E` | primary-container | 时间线 17–24、选中边框/60、开关 ON、主 CTA |
| `#432C00` | on-primary | 主 CTA 文字 |
| `#E9E1DD` | on-surface | 主文字 |
| `#D3C4B2` | on-surface-variant | 次级文字、close 图标 |
| `#9C8F7E` | outline | 说明/右注文字 |
| `#4F4537` | outline-variant | 各类边框（/20~/60）、抓手 /60 |
| `#FFB4AB` | error | 21 错误点、错误热点图标 |
| `#93000A` | error-container | 错误点 ring |

### Config 声明但 DOM 未直接使用（备而不用，列出防混淆）

`#FFDEAD` primary-fixed、`#7E5703` inverse-primary、`#EAC085` secondary、`#614415` secondary-container、`#C5A764` tertiary-container、`#E2C37D` tertiary、`#FFDDB2` secondary-fixed、`#FFDF9A` tertiary-fixed、`#563900` on-primary-container，以及其余 on-*-fixed / inverse-* token。

## 10. 交互热区 与 状态

- 抓手（40×4）：可拖拽下滑关闭（cursor-grab；手势行为待产品确认）。
- 关闭 32×32：dismiss sheet。
- 起/终点 −/＋：28×28 热区；越界保护 1 ≤ 起 < 终 ≤ 32，越界时按钮应置灰（真值未画禁用态，**待产品确认**）；步进与时间线/chips 双向联动。
- 时间线小柱：32 个热区（每柱约 10pt 宽，可点选跳转/定位——真值未绑定事件，**待产品确认**）。
- 快捷 chips：整钮热区（约 32 高），单选互斥；错误热点应联动为 21 小节（具体边界待产品确认）。
- 循环方式：整行热区（约 40 高）单选。
- 间隔 −/＋：28×28；步长/上下限真值未给，**待产品确认**。
- 开关：48×24 整热区切换。
- 取消/开始：flex 1:2，整钮热区（约 44 高）；开始 → 回 S11 并按设置进入循环。
- 旧稿写但真值无（**待产品确认**）：半透明 scrim、home indicator、「只练21 / 错点前后各2小节」chip 文案（真值为 错误热点/当前段/全曲/手动）、「达标后自动 +5」（真值为「每遍提速 +5 BPM」）、「练完停 3 秒再来」括注。

## 11. 对旧 spec 的主要修正

1. 画布/形态：真值是 390×844 整屏 sheet 且无 scrim、无 home indicator；旧稿写「78% 高 sheet ＋ scrim」。
2. 数字全部补齐：抓手 40×4（旧稿宽 36）；卡圆角 **8pt**（旧稿顶圆角 12）；chips/步进器圆角 4；时间线条带高 32、圆角 6、底 #100E0C。
3. 21 标记真值是柱**上方** error 色脉冲圆点 ＋ ring（#FFB4AB/#93000A），不是小三角。
4. 快捷 chips 四枚文案与旧稿全部不同（错误热点/当前段/全曲/手动），且激活态有明确 amber/15 底 ＋ 琥珀边框 ＋ inner shadow。
5. 循环方式三选的右注、默认选中项明确；「连崩 2 遍」提示**常驻**卡底（旧稿写条件展开）。
6. 「每遍之间」为独立卡：间隔步进器（右对齐、min-w56、值「3 秒」）＋ 48×24 iOS 琥珀开关；开关旋钮白底 ＋ 中央琥珀点。
7. 底部按钮比例 **1:2**（旧稿仅写幽灵/主钮），圆角 4，毛玻璃 footer；主 CTA 字色 #432C00。
8. 页面底色 **#161311** 与 S11/S11b 的 #1C1917 不同；顶部有 blur-3xl 琥珀环境光。
