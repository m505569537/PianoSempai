# S07 今日 Tab（已定级常态·真值修订版）

- 真值来源：Stitch `code.html`，full-bleed 390 逻辑宽布局（max-w-[390px]；桌面居中展示）
- Status: Revised（全部色值/尺寸/层级以 code.html 为准；旧 spec 中 html 无的元素保留并标「待产品确认」）

## 用途一句话

每日练习驾驶舱：周打卡卡、今日时长分段选择、三段任务卡（热身已完成 / 主菜进行中 / 奖励曲可选）、全宽开始练习 CTA、MIDI 连接胶囊。

## 画布与总体结构

- 容器：`w-full max-w-[390px] min-h-screen`，`bg-[#1C1917]`，flex-col relative，`pt-0 pb-28`（底部 112pt 避让固定 tab bar）。
- 选区高亮：`selection:bg-[#D4A24E]/30 selection:text-[#F5F2ED]`。
- 结构顺序：状态栏（sticky）→ main（header / streak 卡 / 时长卡 / 今日任务列表 / CTA）→ FAB（absolute）→ tab bar（fixed）。

## 1. 状态栏（sticky top-0，z-40）

- 材质：`bg-[#1C1917]/90` + `backdrop-blur-md`；`pt-3` 12pt、`pb-2` 8pt、`px-7` 28pt。
- 文字 14pt semibold，`tracking-tight`，`#F5F2ED`。左「9:41」。
- 右侧：蜂窝（16×14）、Wi-Fi（16×14）、电池（24×12，边框 `#F5F2ED/70` 圆角 4，内芯 16pt 圆角 2，凸点 2×6 `/70`）。

## 2. Header 行（main 内，`px-5 pt-3`，`space-y-4` 纵排）

- 行容器 `flex justify-between items-center`，纵向 padding pt-1/pb-1。
- 标题「今日」：Noto Serif SC，**32pt bold(700)**，`tracking-tight leading-none`，`#F5F2ED`。
- MIDI 状态胶囊：
  - `bg-[#262220]`，1pt 边框 `#332D29`，full 圆角，`px-3` 12pt、`py-1.5` 6pt，`shadow-sm`。
  - 状态点 **8 × 8pt**，full 圆角，`bg-[#D4A24E]`，`animate-pulse`。
  - 文案「已连接 · 特伦斯 V70」：12pt regular，`tracking-wide`，`#9C948B`。

## 3. 本周打卡卡 Streak Card

- 容器：`bg-[#262220]`，1pt 边框 `#332D29`，`rounded-2xl` = **16pt**，`p-4` = 16pt，`shadow-sm`。
- 标题行（`mb-4`，items-baseline）：
  - 左「本周 2/3 次」：serif **19pt semibold**，`tracking-tight`，`#F5F2ED`。
  - 右「连续达标 5 周」：13pt，`#9C948B`。
- 周列：`grid grid-cols-7 gap-1`（列间距 4pt），每列 flex-col items-center，圆点与文字间距 `space-y-2` = 8pt；底部 `mb-3`。
- 日单元统一为 **32 × 32pt 圆形**（非小圆点），四态：
  1. **已完成（一、二）**：`bg-[#D4A24E]`，对勾图标（Material Symbols `check`，18pt，色 `#1C1917`），`shadow-sm`。
  2. **今天（三）**：2pt 琥珀描边 `#D4A24E`，`bg-[#D4A24E]/10`，数字「3」13pt semibold 琥珀；下方星期标签「三」12pt **琥珀 medium**（其余为 muted）。
  3. **未来（四/五/六/日）**：1pt 边框 `#332D29`，`bg-[#1C1917]/40`，中央 6 × 6pt 圆点 `#332D29`。
  4. 星期标签统一 12pt `#9C948B`。
- 底部脚注：`pt-2` + 顶边 1pt `#332D29/60`，flex 两端：
  - 左「周目标 3 次 · 本周还剩 1 次」11pt muted。
  - 右「Focus Week」**10pt**，`#D4A24E/80`，`uppercase tracking-wider`。

## 4. 今日时长卡 Duration Card

- 容器同卡面：`bg-[#262220]` + 1pt `#332D29`，16pt 圆角，p-4，shadow-sm；flex 两端居中。
- 左标签「今日时长」14pt medium，`tracking-wide`，`#F5F2ED`。
- 右侧组 `space-x-3` = 12pt：
  - 分段控件容器：`bg-[#1C1917]`，`p-1` 4pt，`rounded-xl` 12pt，1pt 边框 `#332D29`，flex。
  - 选项「15 / 30 / 45」：`px-3.5` 14pt、`py-1` 4pt，13pt；未选 `#9C948B`，hover 变主文字色。
  - 选中态「30」：`bg-[#D4A24E]`，`rounded-lg` 8pt，**bold**，文字 `#1C1917`，shadow-sm。控件实际高度约 29pt（非 44）。
  - 尾注「余 42 分钟」12pt muted，`pl-1`。

## 5. 今日任务列表

- 区块：`pt-2`，flex-col，`space-y-2.5` = 10pt。
- 区块头（`px-0.5`）：左「今日任务」serif **16pt semibold**，`tracking-tight`；右「3 项」12pt muted。

### 5.1 任务1：已完成（热身·哈农）

- 行容器：`bg-[#262220]`，1pt 边框 `#332D29`，16pt 圆角，`p-3.5` 14pt，flex 两端。
- 左组 `space-x-3.5`（14pt）：
  - 状态圆 32pt：`bg-emerald-950/60`（`#022c22` @60%），1pt 边框 `emerald-500/30`（`#10b981` @30%），对勾 18pt `emerald-400`（`#34d399`）。
  - 文案列 `space-y-0.5`：标签行 `space-x-2`——「热身」标签 10pt medium，琥珀文字，1pt 边框 `#D4A24E/40`，`px-1.5 py-0.5`，4pt 圆角；标题「哈农 第1条」15pt medium，`line-through opacity-75`。
  - 副行「8 分钟 · 高抬指慢练」12pt muted。
- 右尾「已完成」12pt muted，light(300)。

### 5.2 任务2：进行中（主菜·拜厄，当前焦点卡）

- 行容器：`bg-[#262220]`，**左侧 2pt 琥珀边 `#D4A24E`**，其余三边 1pt `#332D29`，16pt 圆角，**`p-4`**，`shadow-md`，flex-col `space-y-3` = 12pt。
- 主行 flex 两端：
  - 左组间距 14pt：播放圆 **36pt**（w-9），`bg-[#D4A24E]/15`，边框 `#D4A24E/40`，`play_arrow` 20pt（filled）琥珀，`shadow-sm`。
  - 「主菜」标签：10pt semibold，**`bg-[#D4A24E]` 填充、文字 `#1C1917`**，px-1.5/py-0.5，4pt 圆角。
  - 标题「拜厄 第45条」**16pt semibold**；副行「17–24 小节 · 18 分钟」12pt muted。
  - 右 chevron 20pt muted。
- 内嵌提示条（非旧 spec 所述「右上 chip」）：
  - `bg-[#1C1917]/70`，1pt 边框 `#332D29`，`rounded-xl` 12pt，`px-3 py-2`。
  - `info` 图标 16pt 琥珀；文案 12pt muted：「上次错误集中在 **21 小节**」，其中「21 小节」`#F5F2ED` medium；整行 truncate。

### 5.3 任务3：可选（奖励曲）

- 行容器：卡面 + 1pt `#332D29`，16pt 圆角，p-3.5，flex 两端。
- 图标圆 32pt：`bg-[#1C1917]`，边框 `#332D29`，`music_note` 18pt muted。
- 「奖励曲」标签 10pt regular：muted 文字，1pt 边框 `#332D29`，4pt 圆角。
- 标题「《Summer》久石让」15pt medium；副行「自选 · 有余力再弹」12pt muted。
- 右 chevron 20pt `#9C948B/60`。

## 6. 主 CTA「开始练习」

- 区块 `pt-3`；按钮全宽，`py-3.5` 14pt，16pt 圆角。
- 常态：`bg-[#D4A24E]`，文字 `#1C1917` bold 16pt，`tracking-wide`；`play_circle` 20pt filled；图标文字间距 8pt。
- 按压：`active:bg-[#c29141]`；阴影 `shadow-lg shadow-[#D4A24E]/10`（琥珀色 10% 辉光）。

## 7. FAB「问 Neko」（absolute，z-30）

- 位置：`right-5` 20pt，`bottom-[92px]`（tab bar 顶缘上约 10pt）。
- 形态：**52 × 52pt 纯圆**，`bg-[#262220]/95` + `backdrop-blur-md`，**1pt** 琥珀描边，`shadow-xl`。
- 猫脸线稿 24pt，`stroke-width 1.8`，琥珀；hover 1.05 / active 0.95。

## 8. 底部 Tab Bar（fixed bottom，z-40）

- 宽 `max-w-[390px]` 水平居中；材质 `bg-[#1C1917]/90` + **`backdrop-blur-xl`**，顶边 1pt `#332D29`；`pt-2` 8pt、`pb-6` 24pt、`px-3` 12pt。
- 5 等列，每列 flex-col items-center `space-y-1`：Material Symbols 图标 **23pt**，文字 11pt。
- 激活（今日）：`calendar_today`（filled）+ 文字 medium，琥珀；未选 muted，hover 主文字。
- 图标：曲库 `library_music` / 练习室 `piano` / 档案 `leaderboard` / 我的 `person`。
- Home Indicator：128 × 4pt，`#F5F2ED/30`，full 圆角，`mt-3`。

## 颜色 Token 总表

tailwind.config 定义：

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | bg | 页面/状态栏/分段控件底；卡内深底 /70、/40 |
| `#262220` | card | 全部卡片、胶囊、FAB（/95） |
| `#332D29` | card-border | 所有 1pt 边框、未来态点、分隔线（/60） |
| `#D4A24E` | amber DEFAULT | 已完成圆、选中态、标签/竖条/图标/FAB 描边、Focus Week（/80） |
| `#382e1c` | amber.subtle | **config 定义但本屏未使用** |
| `#1C1917` | amber.dark | 同 bg（仅 token 别名） |
| `#F5F2ED` | textMain | 主文字（各透明度） |
| `#9C948B` | textMuted | 副文字、未激活 |

内联/工具类额外色值：

| Hex | 语义 | 使用位置 |
|---|---|---|
| `#c29141` | amber-pressed | CTA 按压迫色 |
| `#022c22` @60% | success-bg | 已完成状态圆底（emerald-950/60） |
| `#10b981` @30% | success-border | 状态圆边框（emerald-500/30） |
| `#34d399` | success-text | 对勾色（emerald-400） |

## 字体

- serif：Noto Serif SC——页面标题 32 bold；streak 主数 19 semibold；区块标题 16 semibold；任务卡曲名 15/16 semibold-medium。
- sans：Noto Sans SC——10–14pt 标签与正文。
- 图标：Material Symbols Outlined，常规 `FILL 0 / wght 300`，filled 变体 `FILL 1 / wght 400`。

## 交互热区

- 时长三选项：各约 ≥44pt 宽 × 29pt 高。
- 任务卡：全宽行，最小高度任务1/3 约 60pt、任务2 约 104pt；整行可点（任务2 含 chevron）。
- CTA：全宽约 52pt 高。
- FAB：52pt 圆，距底 92 / 距右 20。
- Tab：每格约 69pt 宽。

## 与旧 spec 的主要差异（修正点）

1. **周打卡形态完全错误**：旧 spec「7 个直径 10pt 圆点均分」→ 真值为 **32pt 大圆 × 7**，内含对勾（已完成）/ 数字（今天，2pt 琥珀环 + /10 底）/ 6pt 小点（未来），列间 gap 4。
2. **streak 卡文案真值**：「本周 2/3 次 + 连续达标 5 周」，脚注「周目标 3 次 · 本周还剩 1 次」+ 英文「Focus Week」；旧 spec 无。
3. **时长控件**：旧 spec「三等分按钮高 44、surface-low 描边」→ 真值为**容器内分段控件（深底 #1C1917、12pt 圆角、p-1），选项 15/30/45 无单位，选中项 8pt 圆角琥珀块**，实际高约 29pt；另有「余 42 分钟」尾注。
4. **任务卡类别竖条规则错误**：旧 spec「热身绿 / 主菜琥珀 / 奖励曲蓝灰，左 3pt 竖条」→ 真值仅**进行中的主菜卡**有 2pt 左竖条；热身已完成用绿色对勾圆；奖励曲用深底音符圆；**无任何蓝色**。
5. **错误热点形态**：旧 spec「右上琥珀描边 chip」→ 真值为卡底**整宽内嵌 info 提示条**（深底 /70、12pt 圆角、info 图标 + 「上次错误集中在 21 小节」）。
6. 标签体系真值：「热身」琥珀描边标签 / 「主菜」琥珀实心深字标签 / 「奖励曲」muted 描边标签，均 10pt、4pt 圆角。
7. 连接胶囊尺寸真值：8pt 状态点、px-3/py-1.5、12pt 文案（旧 spec 无具体值）。
8. 补全：FAB 52pt 1pt 描边（S06 线框为 56pt 2pt 描边，两处不一致，待产品确认统一）；tab bar bg /90 + blur-xl、pb-6；CTA 按压迫色 `#c29141`。

## 旧 spec 有、html 无（待产品确认，勿删）

- 「晚上好 / 9月18日 周五」问候与日期区（S07b 空态有问候，常态 html 只有「今日」大标题）。
- 底部「本周进度」进度条（轨道高 4、2h05m / 3h）——本 html 无此元素。
- 点 streak 圆点出 tooltip 显示当日时长。
- 切换时长后任务卡副标题时间联动重算。
- 下拉刷新同步 take 存储。
- 「热身 8–12 分钟」「♩=72」「Summer 前 16 小节」等旧文案细节（html 副文案为「8 分钟 · 高抬指慢练」等）。
