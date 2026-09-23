# S14 自由弹奏（修订 spec · 以 code.html 为真值）

- Screen ID: `aa01a2dd37b3408a9c4f840957b7150e`
- 真值文件：Stitch code.html
- 画布基准：390 逻辑宽（容器 `max-w-[390px]`），1px = 1pt；无 tab
- Status: Final（本文件取代旧 spec）

## 用途一句话

不跟谱、不打分的即兴沙盒：实时钢琴卷帘可视化 + 仅 MIDI 录制计时；弹后一句话备忘，结束保存或丢弃。全页无评分、无摄像头。

## 颜色 Token

tailwind.config：

| Token | 值 | 用途 |
|---|---|---|
| `surface` (DEFAULT) | `#1C1917` | 页面底色 |
| `surface.dim` | `#151311` | 更深面（备用） |
| `surface.bright` | `#262220` | 更亮面 |
| `card.bg` | `#262220` | 全部卡片底 |
| `card.border` | `#332D29` | 全部 1pt 卡边框 |
| `amber.glow` | `#D4A24E` | 主琥珀 |
| `amber.muted` | `rgba(212,162,78,0.25)` | 琥珀半透明 |
| `amber.faint` | `rgba(212,162,78,0.08)` | 琥珀弱底 |
| `text.main` | `#F5F2ED` | 主文字 |
| `text.muted` | `#9C948B` | 次级文字 |
| `text.faint` | `#655F58` | 弱文字（谱面刻度、占位） |

内联 hex（config 之外）：

| Hex | 位置 |
|---|---|
| `#181513` | 卷帘画布底（90% 不透明） |
| `#E5484D` | 录制红点（呼吸动画） |
| `#F5E1B5` | 新触音符块中段亮色 |
| `rgba(51,45,41,0.45)` | 卷帘横向网格线（24pt 间距，1pt） |
| `rgba(229,72,77,0.7)` | 录制红点发光 `0 0 6px` |
| 多档 amber 透明度 | 音符块 10–90% 渐变（见下） |

字体（本屏与其他屏不同，注意切换）：

- serif：`"Noto Serif SC"`（页面标题、卡片标题、结束并保存）
- mono：**`"JetBrains Mono"`**（时长、音符数、时间码、刻度），`.font-tabular` 开 tnum
- sans：**`"Inter"`**（正文/输入框）
- 图标：Material Symbols Outlined

## 页面结构

```
body（#1C1917，flex col justify-between）
├ 状态栏（pt12 px28）
└ 容器（max-w390 居中，px20 pt12 pb32，flex col justify-between）
  ├ header：返回 / 标题 / 历史录音
  ├ main（flex-1，纵向居中，区块间距 16pt）
  │   ├ ① 卷帘卡（画布 184pt + 底部安抚文案）
  │   ├ ② 计量条（时长 | 音符 | 录制状态）
  │   └ ③ 备忘卡（标题 + 单行输入）
  └ footer：节拍器 / 结束并保存（大胶囊）/ 丢弃 + home 条
```

### 1. 状态栏

- `pt-3 px-7`，13px mono tracking-tight：左「9:41」semibold `#F5F2ED`
- 右（12px）：6×6pt 琥珀点 +「MIDI 已就绪」11px `#9C948B`；`wifi` 15px、`battery_full` 17px muted，gap 8pt

### 2. 导航 header（py 8pt）

- 左：返回钮 **40×40pt**，`-ml-2`，圆形；`arrow_back_ios_new` 24px `#9C948B`；hover 转主色；active scale .95
- 中：「自由弹奏」serif 20px medium tracking-wide
- 右：胶囊钮 px 12pt py 6pt，底 `#262220`、1pt 边框 #332D29，12px muted；`history` 16px；hover 字/边转琥珀（边框 amber 40%）；文字「历史录音」

### 3. 卡① 卷帘可视化

- 容器：bg `#262220`、1pt 边框 #332D29、圆角 **16pt**、p 16pt、shadow-2xl、overflow-hidden、flex col justify-between
- 画布：满宽 h **184pt**，圆角 12pt，底 `#181513` 90%，1pt 边框 #332D29 60%，`.piano-roll-grid`（横向 1pt 线 `rgba(51,45,41,.45)`，24pt 行高），p 12pt
- 左侧音高辅助列（absolute left8，9px mono `#655F58`，5 个标签纵向分布）：**C5 / G4 / C4 / F3 / C3**
- 音符块（absolute，右侧定位，全圆角横向渐变琥珀条，符头朝右即播放方向）：
  1. h5 × w58pt，top22，right45%，渐变 amber 20%→60%→90%，发光 `0 0 8px .3`
  2. h6 × w75pt，top64，right65%，15%→50%→80%
  3. h5 × w90pt，top98，right30%，25%→70%→100%，发光 .4
  4. h6 × w50pt，top86，right12%，**60%→`#F5E1B5`→100%**，发光 .6（最近触发，最亮）
  5. h5 × w110pt，top146，right22%，10%→40%→70%
- 播放头：absolute right12，1pt 竖线，纵向渐变透明→amber 40%→透明
- 画布底部信息行（z20，顶 1pt 边 #332D29 40%，pt8pt，10px，flex between）：
  - 左 mono：6×6pt 琥珀点 +「力度 74 · C4 挂留」`#9C948B`
  - 右 mono `#655F58`：「44.1kHz MIDI IN」
- 安抚文案（pt12，居中 12px `#9C948B`）：「随便弹，不打分 · 音符只记录在本机」（间隔点 `#655F58`）

### 4. 卡② 计量条

- 容器：bg #262220、1pt 边 #332D29、圆角 **12pt**、px16 py12，flex between，12px
- 左组：「本次时长」muted +「**12:34**」JetBrains Mono semibold 14px tnum `#F5F2ED`
- 分隔竖线：h12 × 1pt `#332D29`
- 中组：「音符」muted +「**486**」mono semibold 14px tnum amber
- 分隔竖线同上
- 右组 11px：红点 **8×8pt** `#E5484D`（脉冲动画：2s 缓动，opacity 1→.4、scale 1→.85；发光 `0 0 6px rgba(229,72,77,.7)`）+「录制中（仅 MIDI）」

### 5. 卡③ 这次弹了什么

- 容器：bg #262220、1pt 边、圆角 16pt、p 16pt，内部行距 10pt
- 卡头 flex between：左标题 serif 15px semibold tracking-wide「这次弹了什么」；右「随想随记」11px muted
- 说明 11px/relaxed muted：「系统不会猜曲名。你可以随手记一句」
- 输入框（mt4）：满宽，底 `#1C1917`，1pt 边 #332D29，圆角 12pt，px14 py10，12px `#F5F2ED`；placeholder `#655F58`；聚焦边框 amber 70%；**单行**（右侧内嵌 `edit_note` 图标 16px `#655F58`，right12 top10）
- placeholder 逐字：「例如：瞎弹了一段菊次郎的夏天」

### 6. 底部操作区 footer

- pt12，flex col items-center gap16
- 三操作同行（gap 12pt）：
  - 「节拍器」`flex-1`：py12 px12，圆角 12pt，透明底、1pt 边 #332D29（hover amber 50%），12px medium；`timer` 18px amber
  - 「结束并保存」`flex-[1.4]`（约占 41%）：**全圆角胶囊**，py12 px16，底 amber 10%，**2pt 琥珀描边**，字 `#D4A24E`，hover 反转为底 amber/字 `#1C1917`；发光 `0 0 16px rgba(212,162,78,.18)`；`stop_circle` 19px；文字 serif semibold 13px tracking-wide
  - 「丢弃」`flex-1`：py12 px12，圆角 12pt，透明底（hover 底 #262220），12px medium muted → hover 主色
- home 指示条：128×4pt 全圆角 `#332D29`，mt4

## 全部状态与交互热区

| 元素 | 热区 | 状态 |
|---|---|---|
| 返回 | 40×40pt | hover / scale .95 |
| 历史录音 | 胶囊 ≥44pt 高 | 默认 / hover 琥珀边字 |
| 录制红点 | — | 2s 呼吸（opacity+scale）；非按钮 |
| 备注输入 | 满宽 ~40pt | 默认 / 聚焦琥珀边 |
| 节拍器 | flex-1（约 96×48pt） | hover 边框变色 / scale .98 |
| 结束并保存 | flex-1.4 胶囊 ≥48pt | 默认描边 / hover 实心反转 / scale .97 |
| 丢弃 | flex-1（约 64×48pt） | hover 底字 / scale .98；点击走删除确认（焦点默认取消） |

进入即捕获 MIDI；保存后写入自由 take（无评分/无课程关联），空标题用「自由弹奏 · 时间」；历史录音入口跳档案自由弹奏筛选。以上流程行为沿用旧 spec（html 无异议）。

## 相对旧 spec 的主要修订

1. 字体：真值 sans 为 **Inter**、mono 为 **JetBrains Mono**（旧 spec 未指定）；全部数值 mono tnum。
2. 状态栏右侧真值为「**● MIDI 已就绪** + wifi/电池」（旧 spec 无）。
3. 导航右上真值为「**history 图标 + 历史录音**」胶囊按钮（旧 spec 仅文字 ⇪）。
4. 卷帘：真值画布高 **184pt**、底 `#181513`、24pt 横向网格；5 条**从右向左流动的琥珀渐变音符块**（5–6pt 高、50–110pt 宽），左侧 5 个音高标签 C5/G4/C4/F3/C3；底部含「力度 74·C4 挂留 / 44.1kHz MIDI IN」信息行。旧 spec「8pt 圆角块」描述过粗。
5. 安抚文案真值「随便弹，不打分 · 音符只记录在本机」，位于卷帘卡内而非独立区。
6. 计量条为**单卡三段式**（12:34 白字 / 486 琥珀字 / 红点录制中），竖分隔线 1pt；红点 8pt、2s 呼吸（旧 spec 说 1s，改 2s）。
7. 备忘输入真值为**单行**（圆角 12pt、内嵌 edit_note 图标），旧 spec「多行 3 行高」作废；标题为「这次弹了什么」，副标「随想随记」。
8. 底部布局真值为**同一行三件**：节拍器（flex1，圆角12描边）/ 结束并保存（flex1.4，**2pt 描边大胶囊**）/ 丢弃（flex1，幽灵文字钮）。旧 spec「主按钮全宽在下、丢弃在左上」作废。
9. 补全全部色值、透明度与发光参数（旧 spec 无任何数值）。

## 红线落点

- 全页无评分、无错音提示、无门禁；无摄像头入口（仅 MIDI）。
- 「不打分 / 仅本机 / 仅 MIDI」三处文案逐字保留。
