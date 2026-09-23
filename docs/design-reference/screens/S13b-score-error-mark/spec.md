# S13b 标记疑似谱面错误（修订 spec · 以 code.html 为真值）

- Screen ID: `2d65df0c23514829a4a233e07385229b`
- 真值文件：Stitch code.html
- 画布基准：body `width:390px; height:844px; overflow:hidden`；1px = 1pt
- 用户投诉页；本文件取代旧 spec，所有数字以 html 为准
- Status: Final

## 用途一句话

底部抽屉式反馈：用户把「连续多遍弹成同一个音」的位置标记为疑似谱错，选类型、写备注，提交给 Neko；明确不扣分。

## 三层遮罩结构（z 轴）

```
body（#1C1917，390×844，flex col justify-between）
├ z-0  背景假 S13 页（#141211，opacity .35，blur .6pt）
├ z-10 scrim：bg-black/60 + backdrop-blur(2pt)
└ z-20 底部抽屉 sheet（#262220，顶圆角 28pt）
```

## 颜色

tailwind.config 定义：

| Token | 值 | 用途 |
|---|---|---|
| `bg` | `#1C1917` | body / 输入框与勾选框底 |
| `sheet` | `#262220` | 抽屉底 |
| `borderCol` | `#332D29` | 抽屉顶边、各 1pt 边框 |
| `amberMain` | `#D4A24E` | 主琥珀：标题副标、选中 chip、提交钮 |
| `amberMuted` | `#A37B34` | config 定义，本画布正文未直接使用 |
| `redAlert` | `#C97064` | 警示红：谱条图例点、虚线圈、疑点 callout |
| `textMain` | `#F5F2ED` | 抽屉主文字 |
| `textMuted` | `#9C948B` | 次级文字 |

内联颜色（含背景假层与谱条/SVG）：

| Hex | 位置 |
|---|---|
| `#141211` | 背景假层底 |
| `#282320` | 假层标题分隔线 |
| `#E5DFD7` | 假层曲名文字 |
| `#201D1A` | 假层卡片底；说明文字框底 |
| `#2D2825` | 假层卡片边框 |
| `#E08A7C` | 假层「错音与漏音」红字 |
| `#2A2522` | 假层中性热力格 |
| `#3A2C26` | 假层中级热力格 |
| `#482822` | 假层 m21 格 |
| `#342D28` | 假层底部假按钮 |
| `#463F3A` | 抽屉抓手条、home 指示条 |
| `#F9F7F1` | 纸质谱条底色 |
| `#E8E3D5` | 纸面点阵（径向 1pt 圆点，16×16pt 平铺） |
| `#E0DACB` | 纸谱条 1pt 外边框 |
| `#E6E0D2` | 纸内表头分隔线 |
| `#423C36` | 纸表头「m. 21」粗体 |
| `#786E65` | 纸表头次要字 |
| `#8C8276` | 纸表头图例字 |
| `#4B443D` | 谱号 𝄞𝄢、谱面文字深色 |
| `#7A7067` | 五线谱线（0.8pt，opacity .85） |
| `#4A433D` | 小节纵线（1.2pt） |
| `#2C2723` | 普通音符（椭圆 rx3.8 ry2.8，旋转 −20°；符干 1.1pt） |
| `#B34032` | 疑点红色音符（rx4 ry3；符干 1.3pt） |
| `#1F1C1A` | 未选中 chip 底 |
| `#69625A` | 输入框 placeholder |
| `#2C2724` | 取消钮 hover 底 |
| `#1A1715` | 提交钮文字色 |
| `#FFFFFF` | 疑点 callout 文字 |
| `#e0ad57` | 提交钮 hover 色 |
| `rgba(0,0,0,0.65)` | 抽屉投影 `0 -10px 40px` |

字体：

- 标题：`"Noto Serif SC"`（抽屉标题、纸谱条）
- 正文：`"Plus Jakarta Sans"`
- 图标：Material Symbols Outlined

## z-0 背景假页（仅氛围，pointer-events-none）

- 容器 absolute inset-0：底 `#141211`，整体 opacity **35%**，`blur(0.6px)`，p 20pt，flex col justify-between
- 内容：假状态栏（9:41 + 三图标 14px）；假报告头（「主课练习·OP.101」「♩=72·2分14秒」、serif 20px「拜厄 第45条·17–24小节」、「78」serif 30px +「/100·较上一遍提升 +6 分」）；两张假卡（错音 8 格热力、偏差曲线占位 h80）；底部假按钮 h44 opacity 50%
- 施工做法：真实实现即 S13 页快照降透，不必逐元素复刻假层

## z-10 Scrim

- absolute 满屏：`bg-black/60`（黑 60%）+ `backdrop-filter: blur(2px)`（**2pt 背景模糊**）
- opacity 过渡 300ms

## z-20 底部抽屉 Sheet

- 容器：满宽 390；底 `#262220`；**仅顶部两角圆角 28pt**（`rounded-t-[28px]`）；顶边 1pt `#332D29`
- 内边距：px 20pt、pt 12pt、pb 28pt
- 投影（`.sheet-shadow`）：`0 -10px 40px rgba(0,0,0,.65)` + 顶部 1pt 内高光线 `0 -1px 0 #332D29`

### a. 抓手（grab handle）

- 居中，pb 10pt；条 **40×4pt** 全圆角，`#463F3A`

### b. 标题区（mb 12pt）

- 首行 flex between items-center：
  - 标题「标记疑似谱面错误」serif **20px** semibold tracking-tight
  - 右上 chip「反馈给 Neko」12px medium amber 80%，px 8pt py 2pt 全圆角，底 amber 10%、1pt 边框 amber 20%
- 次行 12px `#9C948B` mt 4pt：「拜厄 45 · 第 21 小节 · 今天 20:31 的 take」
- **无 ✕ 关闭按钮**（旧示意稿有，真值没有）

### c. 纸质谱条（mb 14pt）

- 容器圆角 12pt，底 `#F9F7F1` + 点阵纹理（`#E8E3D5` 1pt 圆点 / 16pt 网格），1pt 边框 `#E0DACB`，p 10pt，`shadow-inner`，overflow-hidden
- 纸条表头：flex between，mb 4pt pb 4pt，底边 1pt `#E6E0D2`；10px serif：
  - 左粗体 `#423C36`：「m. 21 (第 21 小节)」
  - 右 `#8C8276`：6×6pt 红点 `#C97064` +「异常音符位置」
- 谱面区高 **88pt**，SVG viewBox `330×84`（满宽 330pt = 抽屉内宽，1:1）：
  - 谱号：𝄞（y24）/ 𝄢（y66），11px bold `#4B443D`
  - 高音五线 y12/17/22/27/32，低音五线 y52/57/62/67/72：`#7A7067` 0.8pt opacity .85
  - 小节线 x26、x320：`#4A433D` 1.2pt
  - 普通和弦（x68 第1拍、x258 第3拍）：符头 `#2C2723`（rx3.8 ry2.8，−20°）+ 符干 1.1pt
  - 疑点组（x158 第2拍）：
    - 虚线圈 r28：填充 `#C97064` 12%，描边 `#C97064` 1.5pt，`dasharray 3.5 2.5`
    - 四个红色符头（高音 y17/27、低音 y57/67）：`#B34032` rx4 ry3；符干 1.3pt
    - callout：rect x180 y34 48×15pt 圆角 3pt，底 `#C97064` 90%；文字 8.5px 600 白「疑点和弦」

### d. 说明框（mb 14pt）

- 底 `#201D1B`，1pt 边框 borderCol 70%，圆角 8pt，p 10pt
- 文案 12px/常规行高，色 `#D6D0C7`，逐字：
  「这个地方你连续 3 遍都弹成了同一个音。可能是你弹错，也可能是谱子本身印错了。标记后不会扣分，Neko 会把它和原始 MIDI 一起留着。」
- 注意：真值文案**只有「不会扣分」，没有「不影响过关」字样**（旧说法勿沿用）

### e. 问题类型 chips（mb 14pt，单选）

- 字段标签 11px 大写 tracking-wider `#9C948B` medium，mb 6pt：「问题类型（可选）」
- chip 行 gap 8pt；每枚 px 12pt py 6pt 全圆角 12px：
  - 选中态「音符/和弦不对」：底 amber **20%**，字 `#D4A24E` medium，**1pt 实心琥珀边框**，内含 6×6pt 琥珀圆点，shadow-sm
  - 未选中「节奏不对」「指法标记可疑」：底 `#1F1C1A`，字 `#9C948B` regular，1pt 边框 `#332D29`；hover 字转 `#F5F2ED`

### f. 备注输入（mb 14pt）

- 标签「备注（可选）」样式同上
- 单行 input：满宽，底 `#1C1917`，1pt 边框 `#332D29`，圆角 12pt，px 14pt py 10pt，12px `#F5F2ED`；placeholder 色 `#69625A`
- placeholder 逐字：「例如：教材上是 do-mi-sol，但听起来像错的」
- 聚焦：边框转 amber 80%

### g. 勾选行（mb 20pt）

- 整行热区，flex gap 10pt，group：
  - 方框 **16×16pt**，圆角 4pt，1pt 边框 `#332D29`，底 `#1C1917`；hover 边框 amber 60%；图中为**未选中空态**
  - 文案 12px `#9C948B`，hover 转主色：「同时在下次问 Neko 时带上这个标记」

### h. 操作按钮行（pt 4pt，gap 10pt）

- 「取消」`flex-1`（占 1 份）：py 12pt px 16pt，圆角 12pt，透明底、1pt 边框 `#332D29`，12px medium `#9C948B`；hover 字主色 + 底 `#2C2724`；active scale .98
- 「提交标记」`flex-[2]`（占 **2 份，取消:提交 = 1:2**）：py 12pt px 16pt，圆角 12pt，底 `#D4A24E`（hover `#e0ad57`），字 `#1A1715` 12px bold，`shadow-md`（amber 15%）；前置 `check` 图标 16px；active scale .98

### i. Home 指示条

pt 16pt 居中；128×4pt 全圆角 `#463F3A`

## 全部状态与交互热区

| 元素 | 热区 | 状态 |
|---|---|---|
| scrim | 满屏 | 点击是否取消：**待产品确认**（html 未绑事件） |
| 抽屉 | — | 出现/消失 300ms 过渡；下滑手势关闭 html 未给出，待产品确认 |
| 类型 chips | 3 枚（约 56–88×32pt） | 单选：选中实心琥珀边 + 圆点；未选深底细边 |
| 备注 input | 满宽 ≥44pt 高 | 默认 / 聚焦（琥珀边） |
| 勾选框 | 整行（16pt 框 + 文案） | 选中态（应有琥珀勾号）html 未给，按全局勾选规范补 |
| 取消 / 提交 | 1:2 宽 | hover / active scale .98；提交成功态 html 未给 |

## 提交后行为（html 之外，待产品确认）

- 旧 spec 所述「S13 错音行变为『疑似谱错·已标记』标签、错音率分子扣除」属规则引擎行为，html 未呈现 → 视觉标签保留，规则待产品确认。
- 旧 spec 所述「同一小节重复提交合并计数」html 未呈现 → 待产品确认。

## 相对旧 spec 的主要修订

1. Scrim：补真值 **bg-black/60 + backdrop-blur 2pt + 300ms**（旧 spec 无参数）。
2. Sheet 容器：真值 **顶圆角 28pt、底 `#262220`、顶边 #332D29、投影 `0 -10px 40px rgba(0,0,0,.65)` + 1pt 内高光**，抓手 40×4pt `#463F3A`（旧 spec 仅「同 S12」）。
3. 谱条：点阵纸 `#F9F7F1/#E8E3D5`、边框 `#E0DACB`；**SVG 谱面区高 88pt**（旧说 96）；疑点为红虚线圈 r28（1.5pt，dash 3.5/2.5）+ **红色符头 #B34032 +「疑点和弦」callout**。
4. 标题区：真值为标题 +「反馈给 Neko」琥珀 chip + 三行定位文案；**无 ✕**。
5. 说明文案逐字替换；旧版「听谱习惯 / 不影响过关」作废，真值只有「不会扣分」。
6. chips：补选中态实色 1pt 边框 + 圆点、未选底色 `#1F1C1A`。
7. 勾选框语义全改：真值为「**同时在下次问 Neko 时带上这个标记**」（旧 spec「错音单列」作废），未选中空态 16pt。
8. 按钮比例明确 **取消:提交 = 1:2**；提交钮文字色 `#1A1715`、check 图标；备注为单行输入框（圆角 12pt，py 10pt）。

## 红线落点

- 显式「标记后不会扣分」；疑似谱错与弹奏失败分开。
- 提交后是否影响过关的文案在本抽屉真值中未出现 → 如需「不影响过关」承诺，**待产品确认后补文案**，不得自行加字。
