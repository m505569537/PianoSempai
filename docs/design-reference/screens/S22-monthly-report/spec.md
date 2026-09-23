# S22 月度报告（修订版 · 以 code.html 为真值）

- Screen ID：`c8dbc7cdf98046efbb1169c091324f5b`
- 画布元数据：2560×2730 DESKTOP 长画布；实际内容为 390 逻辑宽手机竖版（`max-w-[390px]`），按 390 逻辑宽取值
- 真值文件：`/tmp/stitch-truth/screens/c8dbc7cdf98046efbb1169c091324f5b/code.html`
- Status：Revised

## 1. 用途

月度静态复盘：四项统计、教材路线推进（含锁定行）、热身/强开记录、节奏稳定度 4 周趋势、手型建议、Neko 本月观察（带引用数）；底部导出 PDF / 把观察写进笔记。

## 2. 颜色令牌（tailwind.config + 全部内联 hex）

| Hex / 值 | 语义名 | 使用位置 |
|---|---|---|
| `#1C1917` | bg 主背景 | 页面底 / sticky 头尾（/95）/ 进度条轨道 / 红警行底 / 趋势图容器底 |
| `#262220` | card 卡片底 | 统计卡、各 section 卡、月份 pill、PDF 按钮底 |
| `#332D29` | border 发丝边 | 卡片边、头尾边线（/60、/70）、分隔线、轨道边、趋势网格 |
| `#D4A24E` | amber 主强调 | 月份 pill 字/边（/40）、47 次数字、进度填充、徽章、趋势线/区、Neko 卡边（/30）、写笔记按钮 |
| `#F3C576` | amber-light | config 令牌；导出 PDF 图标 hover 色（常态为 `#D4A24E`） |
| `#C97064` | red 警示 | 强开行描边（/30）、三角图标、标签文字 |
| `#7FA97C` | green 正向 | 热身徽章（底 /15、边 /30）、+19、数据点/成功语义 |
| `#F5F2ED` | text 主文字 | 标题、数字、按钮文字（home indicator /20） |
| `#9C948B` | muted 次文字 | 标签、单位、脚注、锁行、图表刻度文字 |
| `#201C1A` | Neko 卡渐变底端 | Neko 卡 `to-[#201C1A]`（比 card 更深） |
| `#e0b05e` | 写笔记按钮 hover | hover 字面色 |
| 渐变 amber 0.25→0 | amberGlow | 趋势图面积填充 |

字体真值注意：html 的 body CSS 用 `-apple-system / BlinkMacSystemFont / Segoe UI / Roboto` 覆盖了 tailwind 的 sans，故未显式标 `font-serif/font-mono` 的文字实际走**系统 Sans**；标题 Noto Serif SC，数字 JetBrains Mono。SwiftUI 落地按项目默认 Sans 即可，观感一致。

## 3. 整体结构

- 外壳：宽 390，min-h 844，纵向，`justify-between`，底部 `pb-8`（32）。
- Header（sticky，z-30）：底 surface/95 + backdrop-blur，`px-4` pt-3 pb-2，下边线 1px `#332D29`/60。
  - 主行高 40（h-10）：返回 36×36 圆形（-ml-1，chevron 20 stroke 2）；标题居中 serif 17pt semibold tracking-wide「2026 年 9 月 · 月度报告」；右导出 PDF 图标 36×36，amber，图标 20 stroke 1.8。
  - 月份切换行：居中，`gap-6`（24），pt-3 pb-2，13pt。两侧按钮 muted（hover primary）：左 chevron 14 +「8月」；右「10月」+ chevron 14。中间 pill：`px-3.5 py-0.5`（14×2），圆角 99，card 底、14pt medium amber、1px amber/40、shadow-sm，逐字「9月」。
- main：`px-4` py-4，区块间 `space-y-4`（16）。
- Footer（sticky bottom）：surface/95 + backdrop-blur，`px-4` pt-3 pb-3，上边线 `#332D29`/70，`space-y-2.5`（10）。home indicator 128×4 圆角条 primary/20，mt 4。

## 4. 逐区块规范

### 4.1 四统计卡（2×2）

- Grid 2 列，`gap-2.5`（10）。
- 单卡：card 底，1px border，圆角 12（rounded-xl），`p-3`（12），纵向 `justify-between`。
- 标签 12pt muted；数字行 mt 6，baseline 对齐：数字 23pt mono semibold tracking-tight primary，单位 12pt muted。
- 内容：有效练习 `14 天`；总时长 `8 h 32 m`（h 右 mr 4）；完成 take **`47 次`（数字 amber）**；平均每周 `3.2 次`。

### 4.2 教材路线推进

- 卡：card 底 / border / 圆角 12 / `p-3.5`（14）。
- 卡头 mb 12：serif 14pt semibold，前置 6×6 amber 圆点；右 11pt muted「月度跨度」。
- 行容器 `space-y-3.5`（14）：
  - 每行标签 13pt mb 6：左 primary medium，右 mono 12pt amber 百分比。
  - 轨道：高 8（h-2），surface 底，圆角 99，1px border/50，裁剪。
  - 拜厄 43→48：填充 62%，渐变 amber/80→amber；哈农 1→4：填充 40%，实色 amber/80。
  - 车尔尼 599（锁定行）：标签整组 muted，锁图标 14 +「车尔尼 599」；右 12pt muted「预计 11 月中解锁」；轨道边 /40，填充 `#332D29` 宽 15%。
- 脚注：mt 14，pt 10，顶边 border/70，11pt muted，前置 14px info 图标 amber/70，逐字「解锁只由硬数据规则判定」。

### 4.3 热身与门禁记录

- 卡：card / border / 圆角 12 / `p-3.5`，内部 `space-y-2.5`。
- 头行：左 13pt medium primary；右徽章：mono 12pt，`px-2 py-0.5`，圆角 6，底 green/15、字 green、边 green/30，逐字「热身完成率 11/14 次 79%」。
- 警示行：surface 底，圆角 8（rounded-lg），`p-2.5`（10），1px 边 red/30；左 16×16 红三角（mt 2）；文案 12pt leading-snug：red medium「强开主菜 3 次：」+ primary 90%「时间不够×2，热身曲太无聊×1」。
- 免责行：11pt muted，逐字「记录只用于你自己观察，不影响解锁。」

### 4.4 节奏稳定度月度趋势

- 卡：card / border / 圆角 12 / `p-3.5`。
- 头 mb 8：左 13pt medium「节奏稳定度 月度趋势」；右徽章 mono 12pt amber，底 amber/10、边 amber/25，px-2 py-0.5 圆角 4：「52 → 71 」+ 11pt green semibold「+19」。
- 图容器：surface 底，圆角 8，`p-2.5`（10），1px border/60。
  - SVG 高 112（h-28），viewBox 320×85，`preserveAspectRatio="none"`（拉伸铺满）。
  - 三条横网格 y=15/45/75：0.8px border，dash 3-3。
  - 面积：顶点 (30,70)(115,55)(205,34)(290,14)，闭合到底，填 amberGlow（0.25→0）。
  - 折线 2.5px amber，round cap/join。
  - W1–W3 点：r 3.5，surface 填充、2px amber 描边；W4 点 r 4.5，amber 填充、1.5px primary 描边。
  - 数值标签 9pt mono muted（W1 在点下 y=83，W2/W3 在点上 y=48/27）；W4「71」10pt mono semibold amber，y=8。
  - X 轴标签行：flex 均布，`px-3`，pt 4，顶边 border/50，11pt mono muted，逐字「第 1 周 (W1) / W2 / W3 / 第 4 周 (W4)」。

### 4.5 手型趋势（弱提示卡）

- 卡：card/70 底，border，圆角 12，`p-3`（12），横向 gap 10。
- 图标盒 28×28 圆角 8：surface 底 + border，muted 摄像机图标 16。
- 文案 12pt muted leading-relaxed，逐字「手型趋势：本月侧拍 6 条 · 1指触键偏平出现 4 次（仅建议，不进门禁）。」

### 4.6 Neko 的本月观察

- 卡：纵向渐变 `#262220 → #201C1A`，1px 边 amber/30，圆角 12，`p-4`（16），shadow-lg，overflow-hidden。
- 氛围光：绝对定位右上 -32/-32，96×96 圆，amber/5，blur-xl（≈40px 模糊）。
- 头行 mb 10 gap 8：24×24 圆，底 amber/20、边 amber/40，猫脸 glyph 14 amber；serif 15pt semibold「Neko 的本月观察」；右侧 ml-auto 标签 10pt mono amber，底 amber/10、边 /30，px 6 py 2 圆角 4「温和复盘」。
- 正文 13pt primary/90 leading-relaxed mb 14，逐字：
  > 这个月最大的进步是 21 小节转指的节奏偏差从 +120ms 收到 +64ms。下月建议：热身保持每周 3 次哈农 1，主菜速度不要超过 ♩=76；奖励曲可以开始摸《Summer》前 16 小节。
- 证据 chip 行：flex-wrap gap 8，pt 8 顶边 border/70。每 chip：mono 11pt amber，surface 底，`px-2.5 py-1`（10×4），圆角 6，1px border，前置 12px 图标：「引用 47 个 take」（光盘图标）/「引用 6 条侧拍」（摄像机图标）。

## 5. 底部按钮

- 同行 gap 12：
  - 左「导出 PDF」：flex-1，高 44，圆角 12，1px border，card 底（hover border/50），14pt medium primary，图标 16 muted。
  - 右「把观察写进笔记」：flex-[1.4]（宽比 1 : 1.4），高 44，圆角 12，amber 底（hover `#e0b05e`），14pt semibold surface，编辑笔图标 16，shadow-md（amber/10）。
- 按压态：scale 0.98。

## 6. 全部状态与交互热区

- 返回：36×36，active card 底。
- 导出 PDF 图标 / 底部导出 PDF：html 未给禁用态；旧 spec 称 8 月无数据与未来 10 月 pill 置灰 → **待产品确认**（html 中两侧月份仅 muted 普通态，仍可点 hover primary）。
- 证据 chip 可点：分别跳当月 take 列表 / 侧拍列表。
- 写进笔记：写入笔记流（S19）；月报内容静态，PDF 走系统渲染，失败给行内错误（旧 spec 约束，html 无错误态）。

## 7. 相对旧 spec 的主要修订

1. 补全全部数值：390 逻辑宽、卡圆角 12、区块间距 16、统计卡 `p-3`、大数字 23pt mono。
2. 进度条轨道真值为 surface 底 + border/50（旧 spec 写 `#3D3531`，错），高 8（旧 spec 写 6，错）；首行填充为 amber/80→amber 渐变。
3. 月份切换为「文字按钮 + 中间 pill」结构，gap 24；pill 卡底 + amber 字与边（旧 spec 仅述「三段 pill」）。
4. 趋势图补全坐标、点样式（前 3 空心、W4 实心带 primary 描边）、面积渐变 0.25→0、`preserveAspectRatio none` 与 112pt 高。
5. Neko 卡为渐变底 + amber/30 边 + shadow-lg + 右上氛围光（blur-xl）；标签文案「温和复盘」。
6. 底部双按钮宽比 1 : 1.4，高 44，圆角 12；home indicator 在 footer 内。
7. 手型卡底为 card/70（半透明），图标盒 28 圆角 8。
