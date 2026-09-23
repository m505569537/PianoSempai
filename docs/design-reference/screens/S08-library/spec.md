# S08 曲库 Tab（真值修订版）

- 真值来源：Stitch `code.html`（390 × 844 满屏画布；注意：旧 spec 屏 ID `da5df787…` 标注 v1 `66c56ef8…` 作废，但本次下发的真值 html 目录名正是 `66c56ef873fa4a8ba3cb30ad9e431977`——以本次 code.html 内容为真值）
- Status: Revised

## 用途一句话

三段曲库浏览：训练教材（默认选中）/ 奖励曲库 / 全部导入；横向筛选 chips（教材 + 状态）+ 曲目行（已拿下/练习中/未开始/未解锁四态）+ 底部虚线导入卡。

## 总体结构

- `main`：390 × 844，`bg-[#1C1917]`，flex-col relative，`overflow-hidden shadow-2xl`。
- 顺序：状态栏 → header（标题 + 导入/搜索圆钮）→ 三段分段控件 → 横向筛选 chips → 可滚动曲目列表（pb-24）→ 固定 tab bar（h-82）→ Home Indicator。

## 1. 状态栏（z-30）

- `pt-3` 12pt、`px-7` 28pt、pb-1；12pt semibold，`tracking-tight`，`#F5F2ED`。
- 左「9:41」`tabular`；右：蜂窝 16×12（rect rx 0.7）、Wi-Fi 14×12、电池 20×10（边框 1pt，圆角 2，内芯 14pt，凸点 2×4）。

## 2. Header（px-5 pt-2 pb-3，z-20）

- 左标题行 flex baseline：「曲库」serif **`text-2xl` = 24pt bold**，`tracking-tight`；副标「Library」sans 12pt regular muted。
- 右按钮组 `gap-2.5` = 10pt，两枚 **36 × 36pt 圆钮**（`w-9 h-9 rounded-full`）：
  - `bg-[#262220]/80`，1pt 边框 `#332D29`，hover 边框 `#D4A24E/60`，active scale .95。
  - 导入钮（+ 图标，琥珀 `#D4A24E`，aria-label「导入乐谱」）；搜索钮（放大镜，主文字色，aria-label「搜索曲目」，图标本身 muted hover 主色）。
  - 线性 SVG 16pt，stroke-width 2。

## 3. 三段分段控件（px-5 pb-3）

- 容器：`p-1` 4pt，`bg-[#262220]`，`rounded-xl` **12pt**，1pt 边框 `#332D29`，`grid grid-cols-3 gap-1`，`shadow-inner`（内阴影）。
- 按钮：`py-1.5` 6pt，`rounded-lg` 8pt，12pt。
  - 选中「训练教材」：`bg-[#D4A24E]`，文字 `#1C1917` **semibold**，`shadow-sm`。
  - 未选「奖励曲库 / 全部导入」：medium，`#9C948B`，hover 主文字。

## 4. 筛选 Chips（pb-3，z-20）

- 滚动行：`flex gap-2 overflow-x-auto`，`px-5 py-0.5`，隐藏滚动条。
- chip：`whitespace-nowrap px-3 py-1`，full 圆角，12pt。
  - 选中「全部」：**semibold**，`bg-[#D4A24E]/20`，文字 `#D4A24E`，边框 `#D4A24E/50`。
  - 未选 6 枚（拜厄 / 哈农 / 车尔尼599 / 练习中 / 已拿下 / 未开始）：`bg-[#262220]`，边框 `#332D29`，muted；hover 主文字。
  - 教材 chips 与状态 chips 同一行混排（非旧 spec 的两组分行/下拉形态）。

## 5. 曲目列表（flex-1 overflow-y-auto）

- `px-5 pb-24`，`space-y-2.5` = 10pt。
- 行通用：`rounded-2xl` **16pt**，`p-3.5` 14pt，flex 两端 `gap-3`；active scale .99。
- 行内左组：`gap-3.5` 14pt；序号 `w-5` 20pt 居中，**mono 12pt**（`font-mono tabular`）；曲名 serif 14pt（`text-sm`）；副行 sans 12pt（`text-xs`）mt-0.5，`•` 分隔点色 `#332D29`。

### 行1：已拿下（01）

- 底 `bg-cardDark`，1pt 边框 `#332D29`。
- 序号 01 semibold 琥珀；曲名「拜厄 第45条」semibold（注释说本应第44条但 html 文本为第45条——以 html 文本为准，差异待产品确认）。
- 副行「已拿下 • ♩=88」，速度记号 mono `#D4A24E/90` medium。
- 右状态 pill：`px-2.5 py-1`，full 圆角，**底 `rgba(56,161,105,0.16)`**，文字 `#38A169`，边框 `#38A169/30`，11pt medium；对勾 SVG 12pt stroke 2.5 + 文案「已拿下」。

### 行2：练习中（02，当前焦点）

- 底 cardDark；边框 `#D4A24E/40`；阴影 **`0 0 14pt rgba(212,162,78,0.06)`**（柔和琥珀外发光）；`relative overflow-hidden`。
- **左侧 4pt 琥珀竖条**（absolute w-1，顶到底）；内容 pl-1。
- 序号 02 **bold** 琥珀；曲名行含 **6pt 琥珀脉动点**（animate-pulse）；「拜厄 第45条」semibold。
- 副行「练习中 • 17–24小节 • ♩=72」（速度 mono 琥珀/90）。
- 右 pill：底 `rgba(212,162,78,0.16)`，琥珀文字，边 `#D4A24E/40`，11pt medium；内含**旋转圆环 SVG**（circle r=10、dasharray 24/offset 12，animate-spin 周期 4s）+「练习中」。

### 行3：未开始（03，带锁）

- `bg-cardDark/60`，边框 `#332D29/60`，整行 **opacity-75**。
- 序号 03 regular `#686058`（textSubtle）；曲名「拜厄 第46条」medium `#F5F2ED/90`，旁 12pt 锁图标 textSubtle。
- 副行「未开始 • 前置：第45条」textSubtle。
- 右 pill：底 `rgba(156,148,139,0.12)`，muted 文字，1pt 实色 `#332D29` 边框，11pt regular「未开始」。

### 行4：练习中（04，哈农）

- 常规卡面 + 实色边框；序号 04 semibold 琥珀；曲名「哈农 第1条」semibold。
- 副行「练习中 • 高抬指慢练」muted。
- 右琥珀 pill（底 statusActiveBg，边 `#D4A24E/30`，无旋转图标）。

### 行5：未开始（05）

- `bg-cardDark/70` + 边 `/70`；序号 05 regular textSubtle；曲名「哈农 第2条」medium `/85`；副行仅「未开始」textSubtle；右 muted pill。

### 行6：未解锁（06，车尔尼 599）

- `bg-cardDark/50` + 边 `/50`，整行 **opacity-70**；带锁图标。
- 曲名「车尔尼 599 第1条」medium `/80`；副行「路线解锁：约 8 周后」textSubtle。
- 右 muted pill 文案「**未解锁**」。

## 6. 底部虚线导入卡

- 包裹 `pt-2`；按钮全宽，`py-4 px-4`，`rounded-2xl` 16pt；**1pt 虚线边 `#D4A24E/50`**，底 `bg-[#D4A24E]/[0.04]`，hover `/08`；flex 居中 gap-2，active scale .99。
- 左圆形 + 托：20pt 圆 `bg-[#D4A24E]/20`，内含 14pt 加号线性 SVG（stroke 2.5）琥珀，hover scale 1.1。
- 文案 12pt medium 琥珀 `tracking-tight`：「导入乐谱（MusicXML / .mxl / .mscz / MIDI）」。

## 7. 固定 Tab Bar（absolute bottom，h-[82pt]，z-30）

- `bg-[#1C1917]/95` + **`backdrop-blur-xl`**，顶边 1pt `#332D29`；`px-2 pt-2.5 pb-6`，flex justify-around。
- 每 tab flex-1 flex-col items-center：图标 20pt 线性 SVG；文字 **10pt** mt-1。
- 激活（曲库）：stroke-width **2** 的书形图标 + 右上角 **6pt 琥珀小点**（absolute -top-0.5 -right-1）+ 文字 semibold 琥珀。
- 未激活：今日（日历 1.8）/ 练习室（键盘 1.8）/ 档案（柱状图 1.8）/ 我的（头像 1.8），muted medium，hover 主色。
- Home Indicator：absolute bottom-1，128 × 4pt `bg-white/20`。

## 颜色 Token 总表

| Hex / rgba | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark | 页面底、tab bar（/95）、选中分段文字色 |
| `#262220` | cardDark | 行卡（/50–/80）、分段容器、chips、圆钮 |
| `#332D29` | cardBorder | 全部边框/分隔点/未解锁态 |
| `#D4A24E` | amberAccent | 选中态/序号/速度记号/竖条/脉动点/导入卡（各透明度） |
| `#E5B96B` | amberLight | **config 定义但本屏未使用** |
| `#F5F2ED` | textMain | 曲名/标题/系统图标（各透明度） |
| `#9C948B` | textMuted | 副行/未选/未激活 |
| `#686058` | textSubtle | 未开始/未解锁弱化文字 |
| `#38A169` | statusDone | 已拿下文字/边框（/30） |
| `rgba(56,161,105,0.16)` | statusDoneBg | 已拿下 pill 底 |
| `rgba(212,162,78,0.16)` | statusActiveBg | 练习中 pill 底 |
| `rgba(156,148,139,0.12)` | statusMutedBg | 未开始 pill 底 |
| `#FFFFFF` @20% | home-indicator | Home 指示条 |

## 字体

- serif：Noto Serif SC——页标题 24 bold；曲名 14 semibold/medium。
- sans：**Plus Jakarta Sans**（回退 system-ui）——10–12pt。
- mono：**JetBrains Mono**——序号（12pt）、♩= 速度记号；全部 `tabular-nums`。

## 状态与交互热区

- 行四态视觉：已拿下（绿 pill + 对勾）/ 练习中（琥珀边 + 左竖条 + 发光/旋转，普通练习中行无竖条）/ 未开始（75% 弱化 + 锁 + 前置说明）/ 未解锁（50% 卡底 + 70% 透明 + 约 8 周后）。
- 热区：曲目行全宽（约 60pt 高）；圆钮 36pt；chip 高约 28pt；虚线卡约 52pt；tab 每格 flex-1。

## 与旧 spec 的主要差异（修正点）

1. **分段控件形态错误**：旧 spec「选中段底部 2pt 琥珀指示器」→ 真值为**统一容器（card 底、12pt 圆角、1pt 边、p-1、内阴影），选中段为 8pt 圆角琥珀实心块+深字 semibold**。
2. **筛选 chips 形态错误**：旧 spec「教材 chips + 状态 chips 分组、带▾下拉」→ 真值为**单行横向滚动 7 枚**（全部/拜厄/哈农/车尔尼599/练习中/已拿下/未开始），选中 chip 为琥珀 /20 底 + /50 边；无下拉。
3. **曲目行圆角/高度**：真值 16pt 圆角、p-3.5（行高约 60pt，非 56）；且每行带 **mono 两位序号（01–06）**，旧 spec 无序号。
4. **练习中行视觉补全**：真值有 4pt 左竖条、6pt 标题脉动点、0 0 14pt 琥珀 6% 外发光、pill 内 4s 旋转圆环；旧 spec 仅「琥珀字+脉动小点」。
5. **状态 pill 体系统一**：三色半透明底（绿 rgba(56,161,105,.16) / 琥珀 rgba(212,162,78,.16) / 灰 rgba(156,148,139,.12)）+ 11pt；旧 spec 无具体值。
6. **弱化层级精确化**：未开始行 cardDark/60 + opacity .75；哈农2 cardDark/70；599 cardDark/50 + opacity .70、文案「未解锁」；旧 spec 笼统称 0.5 透明。
7. **虚线导入卡**：真值 16pt 圆角、py-4、1pt 虚线 /50、底 /4%（hover /8%）、带圆托加号图标；旧 spec「圆角 8、1.5 虚线 0.3」错误。
8. Header 两枚 36pt 圆钮（导入琥珀 +、搜索）为真值明确元素；旧 spec ASCII 图把连接胶囊放在曲库页右上（html 无连接胶囊）。
9. 速度记号 ♩=88/72 为 mono 琥珀/90；旧 spec 仅部分提及。

## 旧 spec 有、html 无（待产品确认，勿删）

- 曲库页右上 MIDI 连接胶囊（本 html 无；按全局骨架可能保留）。
- 状态 chip 点开本屏小下拉（全部/未开始/练习中/已拿下）。
- 教材 chip 单选、再点取消；筛选切换列表 120ms 淡入；空筛选结果空态文案。
- 奖励曲库段行来源标「手动导入」无锁态；全部导入段显示文件类型图标与导入时间。
- 行1 注释提示「拜厄 第44条」与渲染文本「第45条」不一致——以 html 渲染文本为准，条目命名待产品确认。
- 行点击 → S09；点导入开 Files，失败 → S08b。
- 无商城/社区、PDF 不进此页的红线。
