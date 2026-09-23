# S21 对比两次 Take（修订版 · 以 code.html 为真值）

- Screen ID：`771fe17b29204a688c2301026195582a`
- 画布元数据：2560×2902 DESKTOP 长画布；实际内容为 390 逻辑宽手机竖版（`max-w-[390px]`），所有尺寸按 390 逻辑宽取值
- 真值文件：`/tmp/stitch-truth/screens/771fe17b29204a688c2301026195582a/code.html`
- Status：Revised

## 1. 用途

同曲目同小节段两次 take 的进步对比：样本选择、六维叠加雷达、速度双线、错音热力双条、关键 delta；只展示不产生过关判定。CTA 针对 21 小节发起专项循环。

## 2. 颜色令牌（tailwind.config + 全部内联 hex）

| Hex / 值 | 语义名 | 使用位置 |
|---|---|---|
| `#1C1917` | surface 主背景 | body / main 底；选择行底（/80）；热力条容器底；delta 行底；点圈描边（stroke） |
| `#262220` | card 卡片底 | 全部 5 张 section 卡 |
| `#332D29` | card-border 发丝边 | 卡片描边；导航下边（/60）；雷达网格/轴线；速度图网格线；热力条容器边；delta 卡行边；home indicator |
| `#453E3A` | 雷达最外层六边形描边 | 雷达 100% 六边形（比 card-border 亮一档） |
| `#D4A24E` | amber.main（Take A / 基准） | A 行描边（/40）、radio、badge 底（/20）、分数、雷达多边形边 2.2、速度线 2.4、热点格、delta 新值、CTA 底、参考虚线（/75） |
| `rgba(212,162,78,0.15)` | amber.subtle | config 令牌（html 内实际以渐变 0.45→0.15 实现） |
| `#E5B96E` | amber.bright（A 高亮文字） | A 分数 78 分；热点摘要文字；delta 新值文字 |
| `#8FA3B8` | bluegrey.main（Take B） | B 行描边（/40）、radio、badge 底（/20）、雷达多边形边 2、速度线 2、热点格（/40、/55） |
| `rgba(143,163,184,0.15)` | bluegrey.subtle | config 令牌（实际渐变 0.35→0.08） |
| `#ADC0D4` | bluegrey.bright | B 分数 65 分；B 热点摘要文字 |
| `#F5F2ED` | text.primary | 标题、行主要文字、雷达轴标签 |
| `#9C948B` | text.muted | 速度 ♩= 值、轴标签（速度图 m.x）、非强调文字 |
| `#6E665E` | text.dim | 副标题、卡眉、提示、速度图 Y 轴刻度 |
| `#2A2522` | 热力图「无错音」格底 | 双条全部 clean 格 |
| `#34D399`（Tailwind emerald-400） | delta 进步箭头 | 三行末尾 ↑ |
| 渐变 `#D4A24E` 0.45→0.15 | gradAmber | 雷达 A 多边形填充 |
| 渐变 `#8FA3B8` 0.35→0.08 | gradBlueGrey | 雷达 B 多边形填充 |

## 3. 整体结构与间距

- `main`：宽 390，min-h 844，纵向 VStack，底留白 `pb-10`（40pt）。
- 状态栏：`pt-3`（12）`px-6`（24）；左 9:41 为 mono 13pt semibold primary；右侧图标 14×14（w-3.5），电池框 20×10、圆角 3、内芯 14×6 圆角 1.5；右组 `gap-1.5`（6），opacity 0.9，11pt。
- 导航栏：`px-4`（16）`pt-3`（12）`pb-3`（12），底边线 1px `#332D29` 60%。
  - 左返回、右分享各为 36×36 圆形按钮（chevron 20×20，stroke 2 / 分享 stroke 1.8）。
  - 中列居中：标题 serif 17pt semibold，tracking wide；副标 11pt dim，mt 2。
- 可滚动内容：`px-4`（16）、`pt-3.5`（14）、卡间 `space-y-3.5`（14）。
- 底部 home indicator：`pt-3`（12）`pb-2`（8），128×4 圆角条 `#332D29`。

## 4. 逐卡规范

### 卡 1 · 对比样本设置

- 容器：card 底，1px `#332D29`，圆角 16（rounded-2xl），`p-3.5`（14），shadow-sm。
- 卡眉行 `mb-2.5`（10）：左 11pt semibold dim，uppercase，tracking-wider，逐字「对比样本设置」；右 11pt medium amber「基准: Take A」。
- 行容器 `space-y-2`（8）。A/B 两行同款：
  - `p-2.5`（10），圆角 12（rounded-xl），底 surface 80%；A 行 1px 边 amber 40%，B 行边 bluegrey 40%。
  - radio：14×14 圆形，2px 边（A amber / B bluegrey），内点 6×6 实心同色。
  - 左组 gap 10：badge `px-1.5 py-0.5`（6×2），圆角 4，10pt semibold，底 amber/20（B 为 bluegrey/20）字同色；时间 13pt medium primary。
  - 右组 gap 8：♩= 值 12pt mono muted；分数 14pt mono bold，A `#E5B96E` 78 分、B `#ADC0D4` 65 分。
- 脚注：`mt-2.5`（10），11pt dim 居中，前置 12×12 info 图标（opacity 0.6），逐字「只对比同一首曲目同一小节段」。

### 卡 2 · 六维对比（雷达）

- 容器圆角 16，`p-4`（16），shadow-sm。
- 卡头 `mb-2`（8）：标题 serif 15pt semibold；右侧 11pt 说明 dim；图例 gap 12：10×10 圆点 + 文字（A primary medium「A 今天」、B muted「B 周一」）。
- 画布：`aspect-[1/0.82]`，SVG viewBox 300×240，最大宽 290，居中。
- 网格：中心 (150,115)；六边形 4 层，半径 25/50/75/95：
  - 25%：dash 2-2、opacity 0.6；50%：dash 3-2；75%：dash 3-3；均 1px `#332D29`。
  - 100%：1.2px `#453E3A` 实线。6 条轴线 1px `#332D29`。
- 数据多边形：
  - B（bluegrey）：填充渐变 0.35→0.08，描边 `#8FA3B8` 2px，round join；顶点 r 2.5。
  - A（amber）：填充渐变 0.45→0.15，描边 `#D4A24E` 2.2px，round join；顶点 r 3。
- 数据真值（注释给出）：A 音准84/节奏78/连贯82/力度72/踏板76/读谱85；B 68/58/65/50/70/72。
- 轴标签：serif 11pt semibold primary，六向逐字「音准 / 节奏 / 连贯 / 力度控制 / 踏板 / 读谱」。

### 卡 3 · 速度曲线

- 容器圆角 16，`p-4`，shadow-sm。
- 卡头 `mb-1.5`（6）：serif 15pt 标题 + 11pt dim 说明；右侧 10pt dim 图例：14pt 宽 amber 80% 虚线 +「♩=76 参考」。
- SVG：宽 100%、高 120，viewBox 320×120。
  - 水平网格：y=15(78)/52(68)/85(60) 为 0.8px dash 2-2；y=102(56) 实线；Y 刻度 9pt mono `#6E665E`，右对齐 x=24。
  - 参考线 y=23（76 BPM）：1.2px amber，dash 3-3，opacity 0.75。
  - X 轴小节：x = 46/84/122/160/198/236/274/312 对应 m.17–24；9pt mono `#9C948B`，y=116；m.21 为 9.5pt bold amber。
  - B 线 `#8FA3B8` 2px 平滑贝塞尔；A 线 `#D4A24E` 2.4px。
  - A 点 r 2.5；21 小节点放大 r 3.5 并带 1.5px surface 描边；B 仅 21 小节点 r 3（描边 1px）。
  - 数值标签：21 小节 A「68」8.5pt mono semibold amber（y=44）；B「56」8.5pt bluegrey（y=111）。

### 卡 4 · 错音热点对比

- 容器圆角 16，`p-4`，shadow-sm。卡头 `mb-3`（12）：serif 15pt 标题 + 11pt 小节范围；右 10pt dim「颜色越深代表错误频次越高」。
- 双条 `space-y-3`（12）：
  - 条标签行 11pt `mb-1.5`（6）：8×8 色点 + 名称（A primary medium / B muted）；右侧 mono 摘要：A `#E5B96E`「共 4 处错音 · 集中在 21 小节」；B `#ADC0D4`「共 11 处错音 · 18–19/21 连贯失误」。
  - 条容器：surface 底，1px `#332D29`，圆角 8（rounded-lg），`p-1`（4）；8 列 grid，`gap-1`（4）。
  - 格高 24（h-6），圆角 4，9pt mono 数字居中：
    - clean：`#2A2522` 底 + dim 数字。
    - A 条：m.20 底 amber/30 + 边 amber/40 + `#E5B96E` medium；m.21 实底 amber + surface bold「21★」+ shadow-sm。
    - B 条：m.18/m.20 底 bluegrey/40 + 边 /60 + `#ADC0D4`；m.19 底 /55 + 边 /70 + 白字 medium；m.21 实底 bluegrey + surface bold「21★」。

### 卡 5 · 关键指标进阶

- 容器圆角 16，`p-4`，shadow-sm。
- 卡头 `mb-3`：serif 15pt 标题；右胶囊 `px-2 py-0.5` 圆角 99，10pt medium，底 amber/20、字 amber、边 amber/30，逐字「综合提升 +13分」。
- 行容器 `space-y-2.5`（10）。三行同款：`p-2.5`（10）圆角 12，surface 底，1px `#332D29`；左：6×6 amber 点（gap 8）+ 13pt primary 指标名；右 mono 13pt：旧值 muted → dim，新值 `#E5B96E` semibold，emerald-400 bold ↑（ml 4）。
  - 节奏偏差 21小节：`+120ms → +64ms`
  - 错音率：`8% → 3%`
  - 平均速度：`60 → 72 BPM`
- 脚注：`mt-3`（12）`pt-2.5`（10），顶分隔线 `#332D29` 60%，11pt dim 居中，逐字「对比仅展示，不产生新的过关判定。」

### 底部 CTA

- 容器 `pt-2`（8）`pb-1`（4）。按钮全宽，`py-3.5`（14）`px-4`，圆角 12，实底 amber，文字 14pt semibold surface，tracking wide，shadow-md；右箭头 16×16（stroke 2.2）。逐字「针对 21 小节发起专项循环」。

## 5. 字体

- 标题类：Noto Serif SC（导航 17 semibold / 卡标题 15 semibold / 雷达轴标签 11 semibold）。
- 正文：Plus Jakarta Sans（13 medium / 11 / 10 semibold）。
- 数字：JetBrains Mono，分数 bold，♩= 与图内数字常规；图内刻度 8.5–9pt。

## 6. 状态与交互热区

- 返回 / 分享按钮：36×36 热区；hover 底 `#262220`，按压缩放 0.95。
- 选择行：整行可点（换选 A/B）；选中态=彩色 40% 边 + radio 内点；未选态 html 未呈现 → **待产品确认**（旧 spec 提及不符条目灰显并给原因，html 无此态）。
- CTA：hover 底 `#E5B96E`，按压缩放 0.99；跳转 S12 预填 21 小节专项循环，不产生过关判定。
- 热力格、雷达、曲线为只读展示，无热区。

## 7. 相对旧 spec 的主要修订

1. 旧 spec 无任何精确数值：补全 390 逻辑宽、全部圆角（卡 16 / 行 12 / 格 4）、间距（卡间 14、行内 10）。
2. 雷达填充真值为双渐变（A 0.45→0.15，B 0.35→0.08），描边 A 2.2 / B 2，非旧 spec 笼统的「各 15%、边 1.5」。
3. 速度图参考线为 amber ♩=76（非 muted），21 小节用放大点 + 数值文字，无「竖线与气泡」组件。
4. 热力格为 8 列网格（格高 24、圆角 4、`#2A2522` 空态），非字符色阶条；A/B 摘要文案逐字锁定。
5. delta 箭头色为 emerald-400 `#34D399`；行底 surface + 发丝边。
6. CTA 圆角 12、高约 48、shadow-md。
