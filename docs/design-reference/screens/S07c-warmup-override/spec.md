# S07c 热身强开确认（Bottom Sheet·真值修订版）

- 真值来源：Stitch `code.html`（390 × 844 画布；桌面衬底 `#100E0D`）
- Status: Revised

## 用途一句话

热身未完成想直接进主菜时的底部弹层硬拦截：告知后果、必选强开原因（默认预选中一项）、明示留痕且不影响解锁，再执行强开或回去补热身。

## 总体层级

```
z-0  背景今日页（opacity-40 + blur 2pt，不可点）
z-10 scrim（bg-black/60 + backdrop-blur 4pt，底部对齐容器）
z-20 顶部状态栏（浮层上的 9:41）
     Bottom Sheet（满宽，顶部 28pt 圆角，贴底）
```

## 1. 背景层（今日页虚化，z-0，pointer-events-none）

- `absolute inset-0 opacity-40 blur-[2px]`，`px-5 pt-3 pb-8` flex-col。
- 内含简化今日页（仅供施工参考背景构成，尺寸以 S07 为准）：状态栏；「今日」serif 2xl + 连接胶囊（`#262220`/`#332D29`，琥珀点）；周打卡卡（`rounded-xl` 12pt p-3.5，7 个 32pt 圆，本背景里一/二为 `bg-amber/20 border-amber/40`）；「今日任务」小标题；三张任务卡：
  - **热身卡（门禁目标）**：p-4，12pt 圆角；左侧进度环 40pt——底环 stroke `#332D29` 宽 3，进度环 stroke `#D4A24E` 宽 3，`dasharray 97.4 / dashoffset 61`（约 37.5% ≈ 3/8 分钟），round 端；中心「3/8」10pt 琥珀 mono。「热身」标签 `bg-amber/15`；标题 serif 14 medium「热身 · 哈农1（8分钟）」；副文「高抬指慢练 · 仍需 5 分钟」；右侧红色「未完成」11pt medium `#C97064`。
  - 主菜卡：opacity-60，「主菜」标签为 `bg-card-border` muted。
  - 奖励曲卡：opacity-40。

## 2. Scrim 与浮层状态栏

- 遮罩：`relative z-10 w-full h-full flex flex-col justify-end bg-black/60 backdrop-blur-[4px]`。
- 浮层顶部状态栏（absolute top，z-20）：`px-7 pt-3.5`，12pt semibold，`text-tx-primary/80`；右侧系统图标 15–17pt。

## 3. Bottom Sheet 卡片

- 容器：满宽，`bg-[#262220]`（card），顶部 1pt 边框 `#332D29`，**`rounded-t-[28px]`（仅顶部圆角 28pt）**，`px-6` 24pt、`pt-5` 20pt、`pb-7` 28pt，flex-col。
- 阴影：**`0 -12pt 40pt rgba(0,0,0,0.65)`**（向上投影）。
- 入场动画：fade-in + slide-in-from-bottom（位移约 24pt），duration 300ms。

### 3.1 拖拽手柄

- 36 × 4pt（w-9 h-1），full 圆角，`bg-[#332D29]`，居中，mb-4。

### 3.2 标题区

- flex `gap-2`，items-center，mb-2：
  - 图标圆：**24pt 圆**，`bg-[#C97064]/15`（red/15），`lock` 图标 16pt，色 **`#C97064`（红色）**。
  - 标题「热身还没完成」：serif **19pt semibold**，`tracking-tight`，`#F5F2ED`。

### 3.3 正文

- 13pt regular，`leading-relaxed`，`#9C948B`，mb-4：
  「今天的热身还差 5 分钟。热身是为了保护手，规则上不能直接进入主菜。你仍然可以手动强开，但这会被记录在月报里。」

### 3.4 原因选择

- 标签行 flex 两端，mb-2.5：左「强开原因（必选）」12pt medium muted `tracking-wide`；右「记录于个人档案」10pt `#D4A24E/80`。
- 列表 `space-y-2`（8pt），mb-4；4 行均为整行可点（cursor-pointer）：
  - **选中态（第1行）**：`px-3.5` 14pt、**`py-3` 12pt**，`bg-[#1C1917]/80`，边框 **`#D4A24E/40`**，`rounded-xl` 12pt；文案 13pt **medium 主文字色**。
  - 未选态（其余3行）：px-3.5、**`py-2.5` 10pt**，`bg-[#1C1917]/40`，边框 `#332D29/70`，hover 边框转实色；文案 13pt muted。
  - Radio：16 × 16pt 圆；未选 1pt 边框 `#332D29`；选中 **2pt 琥珀边框 + 中央 8pt 琥珀实心圆**。
  - 四项文案：①「时间不够，只弹主菜」（默认选中）②「手状态不错，今天跳过」③「热身曲太无聊」④「其他（写一句）」。
  - 第4行选中后的文本输入框在本稿中未展开（html 注释明确「not selected, show no extra input」）。

### 3.5 留痕提示框

- `bg-[#D4A24E]/10`，1pt 边框 **`rgba(212,162,78,0.28)`**（hairline-amber），12pt 圆角，p-3，mb-5，flex items-start gap-2.5。
- `info` 图标 18pt 琥珀，mt-0.5。
- 文案 11.5pt，`leading-relaxed`，**`#D4A24E/95`**：
  「强开记录：本周第 1 次 · 将出现在周日 Neko 周报，不会影响任何解锁判定。」

### 3.6 按钮组（flex-col gap-2.5）

- **主按钮在上**：全宽，`py-3.5` 14pt，12pt 圆角，`bg-[#D4A24E]`，文字 `#1C1917` medium 14pt，`tracking-wide`；`shadow-lg shadow-[#D4A24E]/10`；active scale .99。文案「我确认强开，开始主菜」。
- 次按钮在下：全宽，`py-3` 12pt，12pt 圆角，透明底，1pt 边框 `#332D29`，文字 13.5pt medium muted，hover 文字主色、边框 muted/40。文案「去补完热身（5 分钟）」。
- Home Indicator：128 × 4pt，`bg-[#9C948B]/25`，full 圆角，居中，mt-5。

## 颜色 Token 总表

| Hex / rgba | 语义 token | 使用位置 |
|---|---|---|
| `#100E0D` | page-backdrop | 桌面衬底（App 不实现） |
| `#1C1917` | app | 弹层内选项行底（/80、/40） |
| `#262220` | card | Bottom Sheet 底、背景卡 |
| `#332D29` | card-border | Sheet 顶边/手柄/未选边框（/70）/进度底环 |
| `#D4A24E` | amber | 标题图标外的强调、radio、进度环、主按钮、提示框（各透明度） |
| `#C97064` | red | 锁图标（/15 底）、未完成文字 |
| `rgba(212,162,78,0.28)` | hairline-amber | 留痕框边框 |
| `#F5F2ED` | tx-primary | 标题/主文字（/80） |
| `#9C948B` | tx-muted | 正文/未选文案/次按钮/Home 指示（/25） |
| `rgba(0,0,0,0.6)` | scrim | 遮罩底 |
| `rgba(0,0,0,0.65)` | sheet-shadow | Sheet 上投影 |

## 字体

- serif：Noto Serif SC——sheet 标题 19 semibold；背景卡片标题 14–24。
- sans：**Plus Jakarta Sans**（回退 system-ui）——10–14pt。
- 数字「3/8」：mono 10pt 琥珀。
- Material Symbols：全局 **`FILL 1 / wght 400`**（本屏图标全部填充风格）。

## 交互热区

- 4 个原因行：全宽，选中态高约 44pt（py-3）、未选约 36pt（py-2.5）。
- 主按钮全宽约 50pt 高；次按钮约 44pt。
- Sheet 手柄仅视觉（36×4）。

## 与旧 spec 的主要差异（修正点）

1. **弹层形态错误**：旧 spec「中央卡片、宽 350、圆角 12、内边距 20」→ 真值为**贴底 bottom sheet：满宽、仅顶部 28pt 圆角、px-6(24)/pt-5(20)/pb-7(28)、36×4 手柄、向上阴影 0 -12 40 rgba(0,0,0,.65)、300ms 上滑入场**。
2. **锁图标颜色错误**：旧 spec 明确「锁图标琥珀，不是红色恐吓」→ 真值图标为**红色 `#C97064`**（/15 红底圆）；背景热身卡的「未完成」也是同一红色。
3. **遮罩参数补全**：scrim 真值 `bg-black/60 + backdrop-blur 4pt`；背景层 `opacity-40 + blur 2pt`（旧 spec 写 rgba(12,10,9,.55)，无对应实现）。
4. **原因行默认预选**：html 中第 1 项默认选中（主按钮始终可点）；旧 spec「未选原因时确认钮 disabled 灰」在真值中不存在——交互规则待产品确认。
5. **原因行视觉层级补全**：选中行 py-3、bg-app/80、琥珀/40 边、主文字；未选行 py-2.5、bg-app/40、边/70、muted；radio 16pt（2pt 边 + 8pt 芯）。
6. **留痕框边框**：真值为琥珀发丝边 `rgba(212,162,78,0.28)`（config 独立 token），无左缘竖条；旧 spec「琥珀 8% 底 + 琥珀左缘」不准确。
7. **按钮顺序**：真值主按钮（我确认强开）在上、次按钮（去补完热身）在下；旧 spec 描述补完热身视觉优先/默认焦点，并在 ASCII 图中放在上方。
8. 背景内容远比旧 spec 详细：含进度环 40pt（3/8、dasharray 97.4/61）、主菜卡 60%/奖励卡 40% 透明度等，已补全。

## 旧 spec 有、html 无（待产品确认，勿删）

- 点选「其他（写一句）」后展开单行输入框（真值未展开该状态）。
- 未选原因时确认按钮 disabled（真值为默认预选，两种交互需产品裁定）。
- 弹层不可点外部关闭；✕ 取消回今日不留记录（html 无 ✕）。
- 确认后写入 gate-override 事件并进练习室，热身卡标「今日已强开」。
- 本周 ≥3 次时文案变为「本周第 3 次，周报会提醒你留意热身习惯」。
- 语气温柔、无 guilt 词的红线语气要求。
