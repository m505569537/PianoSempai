# S13 Take 报告（修订 spec · 以 code.html 为真值）

- Screen ID: `e7ca79a0929b42a590cfad9b41bdc02f`
- 真值文件：Stitch code.html（元数据 DESKTOP，实为 390 逻辑宽手机竖版长滚动）
- 画布基准：body `width:390px; min-height:844px`；换算 1px = 1pt（rounded-[Npx]→N pt，spacing N→N×4 pt）
- Status: Final（本文件取代旧 spec）

## 用途一句话

单次 take 弹后立即呈现的报告：弱总分 + 六维雷达同卡并排、错漏音热力+清单、节奏偏差曲线、速度/连续性、力度、置信度脚注；底部固定双按钮。无 tab、无分享。

## 全局 Token（tailwind.config `app.*`）

| Token | 值 | 语义/用途 |
|---|---|---|
| `app.bg` | `#1C1917` | 页面底色、底部栏底色 |
| `app.card` | `#262220` | 所有卡片底色；关闭键 hover 底 |
| `app.cardborder` | `#332D29` | 卡片 1pt 边框（常带透明度 /40 /50 /60） |
| `app.amber` | `#D4A24E` | 主琥珀：分值/描边/图标/折线/雷达 |
| `app.ambermuted` | `rgba(212,162,78,0.15)` | 「主课练习」标签底 |
| `app.amberlight` | `rgba(212,162,78,0.35)` | 热力图中等级（m20/m22） |
| `app.amberdeep` | `#C86D2B` | 深橙：计数 badge、spike 点、图例 |
| `app.text` | `#F5F2ED` | 主文字 |
| `app.muted` | `#9C948B` | 次级文字 |
| `app.subtle` | `#6A635B` | 弱文字（9–11px 注记） |

内联/SVG 中出现、config 之外的颜色：

| Hex | 使用位置 |
|---|---|
| `#3F3732` | 雷达最外层环描边 |
| `#E07A5F` | 危险红橙：错音行圆点、m21 格字/边框/标号、计数 badge 文字 |
| `#1F1B19` | 热力图网格容器底色 |
| `#2C2724` | 中性小节格底色（17/18/19/23/24） |
| `#3A332F` | 中性小节格边框 |
| `#A04523` | m21 最热格底色 |
| `#FFF1EB` | m21 格内「3」字色 |
| `#1B1816` | 节奏偏差图容器底色 |
| `#4A423C` | 偏差图 0 轴实线 |
| `#DEB265` | 主按钮 hover 色 |
| `rgba(212,162,78,0.22)` | 雷达数据多边形填充（即 amber 22%） |
| `rgba(200,109,43,0.4)` | m21 格发光 `0 0 8px` |
| `rgba(212,162,78,0.25)` | 主按钮投影 `0 4px 16px` |
| `rgba(255,255,255,0.05)` | 错音行 hover 底（white/5） |

字体：

- 中文标题/大数字：`"Noto Serif SC"`（font-serif）
- 正文：`"Plus Jakarta Sans"`（font-sans）
- `font-mono`：本画布**未配置**自定义 mono，使用 Tailwind 系统默认等宽栈（iOS 上为 ui-monospace）；用于 ♩=72、时长、小节号、偏差刻度
- Material Symbols Outlined：`FILL 0 / wght 400 / GRAD 0 / opsz 20`，`.fill` 变体 FILL 1（仅电池、replay 用）

## 页面结构（自上而下）

```
body flex-col justify-between（bg #1C1917）
└ 滚动区 div.flex-1.pb-36（底部留 144pt 给固定栏）
  ├ 状态栏
  ├ 导航栏 header（48pt，底部 1pt 分隔线 40%）
  └ main（左右 16pt，顶 16pt，卡片间距 14pt）
      ├ ① 总览卡（分值 + 雷达并排）
      ├ ② 错音与漏音卡（热力图 + 2 行清单 + 只练热点钮）
      ├ ③ 节奏卡（偏差折线）
      ├ ④ 速度与连续性卡（两列统计）
      ├ ⑤ 力度卡（单条信息）
      └ 置信度脚注
└ footer 固定底栏（渐变 + 描边 + 双按钮 + home 指示条）
```

### 1. 状态栏

- 容器：`pt-3 px-7`（上 12pt、左右 28pt），flex between，12px semibold tracking-tight
- 左：「9:41」`#F5F2ED`
- 右：图标间距 6pt；`signal_cellular_alt` 16px、`wifi` 16px（均 `#9C948B`）；`battery_full` 18px fill 版 `#F5F2ED`

### 2. 导航栏（h 48pt）

- `px-5 mt-1`，底边框 1pt `#332D29` 40%
- 左：关闭按钮 32×32pt，`-ml-1.5`，圆形；图标 `close` 22px `#9C948B`；hover 文字转 `#F5F2ED`、底 `#262220`；按压缩放 0.95。**不是返回箭头、无分享按钮**
- 中：绝对居中标题「Take 报告」serif 18px semibold tracking-wide
- 右：「第 3 遍 · 刚刚」12px regular `#9C948B`

### 3. 卡① 总览（bg #262220 / 1pt 边框 #332D29 / 圆角 16pt / p 16pt / shadow-sm / overflow-hidden）

装饰光：128×128pt 圆，`-top-10 -right-10`，bg amber 5%，`blur-2xl`（40pt 模糊），不拦截事件。

**上行：曲目 meta（flex items-start justify-between）**

- 左：
  - 标签行 gap 6pt、mb 4pt：「主课练习」11px medium tracking-wider 大写，px 6pt / py 2pt，圆角 4pt，底 `rgba(212,162,78,.15)`，字 `#D4A24E`，1pt 边框 amber 20%；后接「OP.101」12px muted
  - 标题：「拜厄 第45条」serif 16px bold tracking-tight；后缀「· 17–24 小节」14px regular muted
- 右（右对齐）：
  - 速度行：12px mono muted；`speed` 图标 14px amber；「♩=72」
  - 「时长 2分14秒」11px mono `#6A635B`，mt 2pt

**分隔线**：1pt 满宽，`#332D29` 60%，上下 margin 14pt

**下行：分值 + 雷达（flex between，gap 8pt）**

- 左列 `flex-1 pr-2`：
  - 「综合参考」11px muted medium，mb 4pt
  - 分值行 baseline gap 4pt：「78」serif **48px** bold tracking-tighter `#D4A24E`；「/ 100」12px medium muted
  - 说明 11px muted mt 8pt：「进步参考分」+「（不作过关依据）」`#6A635B`
  - 提升 badge：mt 10pt，10px amber，底 amber 10%、1pt 边框 amber 20%，px 8pt py 4pt，圆角 6pt；`trending_up` 12px；「较上一遍提升 +6 分」
- 右列雷达 **145×145pt**，SVG viewBox `160×160`：
  - 三环六边形（中心 80,80，半径 23/35/46）：内环虚线 `dash 2 2`、中环实线均 `#332D29` 1pt；外环 `#3F3732` 1pt
  - 六轴：中心向外 `#332D29` 1pt
  - 数据多边形：填充 amber 22%，描边 `#D4A24E` 1.8pt，linejoin round；六个顶点圆点 r 2.2 `#D4A24E`
  - 维度标签 8.5px `#9C948B`（Plus Jakarta）：**音准（上）/节奏（右上）/连续性（右下）/速度（下）/读谱（左下）/双手协同（左上）**
  - 示例数据：音准 85、节奏 65、连续性 70、速度 80、读谱 90、双手协同 60

### 4. 卡② 错音与漏音（容器同卡①）

- 卡头（整行可点、禁选中文本）gap：
  - 左：竖条 6×14pt 圆角满 `#D4A24E`；标题「错音与漏音」serif 15px bold tracking-wide；gap 8pt
  - 右：「4 处」12px semibold mono，px 8pt py 2pt 全圆角，底 `#C86D2B` 15%、1pt 边框 30%、字 `#E07A5F`；`expand_less` 18px muted；gap 6pt
- 热力图（mt 16pt、pt 4pt）：
  - 说明行 10px mono `#6A635B` mb 6pt，两端对齐：左「小节分布 (17 - 24)」；右图例 8×8pt 小方块 `#C86D2B` +「重点集中于 21 小节」
  - 网格容器：`grid-cols-8 gap-1.5`（列间距 6pt），底 `#1F1B19`，p 6pt，圆角 12pt，1pt 边框 #332D29 60%。单格约 **34×28pt**，格与标号间距 4pt
  - 中性格（17/18/19/23/24）：底 `#2C2724`、1pt 边框 `#3A332F`、圆角 6pt；「✓」9px `#6A635B`；小节号 10px mono muted
  - m20：底 amber 35%、边框 amber 40%；「1」10px bold amber；标号 amber semibold（挂 title「漏1音」）
  - m21：底 `#A04523`、1pt 边框 `#E07A5F`；「3」10px bold `#FFF1EB`；发光 `0 0 8px rgba(200,109,43,.4)`；标号 `#E07A5F` bold
  - m22：同 m20，格内字符「!」
- 明细（mt 14pt，顶 1pt 分隔线 #332D29 50%，pt 12pt，行距 8pt）：每行 12px、py 4pt px 4pt、圆角、hover 底 white/5
  - 行1：圆点 6×6pt `#E07A5F`；「21 小节 · 第 2 拍」medium `#F5F2ED`；右对齐 11px muted「左手应弹 E，实际弹 D」
  - 行2：圆点 amber；「20 小节」；右侧「漏 1 音」
- 动作（mt 12pt pt 8pt，右对齐）：「只练错误热点」12px semibold amber，底 amber 10%、1pt 边框 amber 20%，px 8pt py 4pt，圆角 8pt；`my_location` 14px；按压缩放 0.95

### 5. 卡③ 节奏（容器同卡①）

- 卡头同上，无计数 badge，右侧仅 `expand_less`
- 图（mt 14pt）：
  - 标题行 10px mono mb 8pt：左「拍子偏差 (ms)」muted；右「容限区间 ±50ms」`#6A635B`
  - 图容器：满宽 h **112pt**，底 `#1B1816`，圆角 12pt，1pt 边框 #332D29 60%，p 8pt，flex col justify-between，overflow-hidden
  - SVG viewBox `320×80`，`preserveAspectRatio="none"`：
    - ±50ms 安全色带 rect（y24 h32）填充纵向渐变 amber 10%→3%→10%
    - 三条参考线：y24/y56 `#332D29` 0.8pt 虚线 `2 2`；中轴 y40 `#4A423C` 1pt
    - 折线 path：描边 `#D4A24E` 1.8pt round；Q/T 平滑曲线
    - 数据点：普通 r2 amber；m20/m22 r2.5；m21 尖峰点（180,10）r4，填充 `#C86D2B`、1pt 白描边
    - 数据（ms）：m17 +15、m18 −25、m19 +10、m20 +45、m21 +120、m22 +30、m23 −15、m24 +5
  - 尖峰气泡：absolute 顶 6pt、左 142pt；底 `#C86D2B`，白字 9px bold，px 6pt py 2pt 圆角；「+120ms」+「抢拍倾向」regular 90%
  - X 刻度：满宽 px 8pt，9px mono `#6A635B`：m17 / 18 / 19 / 20 / **21（amber bold）** / 22 / 23 / 24
- 教学提示（mt 10pt，gap 6pt）：`lightbulb` 15px amber；文案 12px muted「十六分音符段落偏快，建议先 **60 BPM** 稳固节拍感。」（加粗处 `#F5F2ED` medium）

### 6. 卡④ 速度与连续性

- 卡头同上，标题「速度与连续性」
- 两列等宽（grid-cols-2 gap 12pt，mt 14pt），子卡：底 `#1C1917` 70%、1pt 边框 #332D29 50%、圆角 12pt、p 12pt
  - 左：「实际均速」11px muted；数值「♩=69」18px bold mono `#F5F2ED` +「/ 目标 72」10px sans `#6A635B`；下行 10px amber：`arrow_downward` 12px +「略低于原速 4%」
  - 右：「停顿次数」11px muted；「3」18px bold mono +「次」12px regular；下行 10px `#E07A5F` truncate「21 小节 ×2，20 小节 ×1」

### 7. 卡⑤ 力度

- 卡头同上，标题「力度」
- 信息条（mt 12pt）：flex items-center gap 8pt，12px muted，底 `#1C1917` 50%，p 10pt，圆角 12pt，1pt 边框 #332D29 40%；`graphic_eq` 16px amber；「力度均匀度 **72/100** · 右手旋律层突出良好」

### 8. 置信度脚注

pt 8pt pb 12pt 居中；11px muted 80%；`verified_user` 13px amber；逐字文案「对齐置信度高 · 踏板已计入判分」

### 9. 底部固定栏 footer

- `fixed bottom` 宽 390pt；背景纵向渐变 `#1C1917 → #1C1917 95% → 透明`；pt 16pt pb 28pt px 16pt；z40；顶 1pt 边框 #332D29 30%；`backdrop-blur-sm`（~4pt）
- 按钮纵向排列、间距 8pt：
  - 主按钮：满宽 h **48pt**，圆角 12pt，底 `#D4A24E`，字 `#1C1917` bold 15px tracking-wide；投影 `0 4px 16px rgba(212,162,78,.25)`；hover `#DEB265`；`replay` 19px fill；「再练一遍（60 BPM 起步）」
  - 次按钮：满宽 h **40pt**，圆角 12pt，透明底、1pt 边框 #332D29，字 12px medium `#9C948B`，hover 字转主色/底 #262220；「返回今日」
- Home 指示条：128×4pt 圆角满，muted 30%，居中 mt 12pt

## 交互热区与状态

- 关闭钮 32×32pt：hover/active 两态；点击离开报告（去向由路由定，待产品确认）
- 四张分区卡头均为整行热区（cursor-pointer），图标 `expand_less` 表示展开态；折叠态图标应旋转 180°（html 仅给展开态）
- 热力格 8 个：约 34×28pt；中性/中级/重级三态；带 title 提示
- 明细行：整行可点，hover white/5
- 「只练错误热点」「再练一遍」「返回今日」：均 active scale .95/.98
- 低置信态（旧 spec 提及）：html 未呈现 → **待产品确认**

## 相对旧 spec 的主要修订（施工注意）

1. 导航：旧 spec「‹ 返回 + 分享」错误；真值为 **✕ 关闭 + 右侧「第3遍·刚刚」，无分享**。
2. 总分：旧 spec 44pt 且不与 /100 同行；真值 **48pt serif，后跟 12px「/ 100」**，且分值与雷达同卡左右并排（旧 spec 分两卡）。
3. 雷达六维名称全改：真值为 **音准/节奏/连续性/速度/读谱/双手协同**（旧：含力度/踏板）。
4. 热力图：旧 spec 为抽象柱形；真值为 **8 个 34×28pt 编号格**（✓/数字/!），容器底 `#1F1B19`，最热 m21 底 `#A04523` 带橙色发光。
5. 明细文案：真值「**21 小节·第 2 拍 · 左手应弹 E，实际弹 D**」「20 小节 · 漏 1 音」，仅展开 2 行（旧 spec 节拍/音符描述作废），并带「只练错误热点」按钮。
6. 新增两整卡：**速度与连续性（♩=69、停顿 3 次）与力度（72/100）**，旧 spec 无。
7. 底部按钮：旧 spec 三按钮（含「针对21小节循环」「问 Neko」）作废；真值为**纵向双按钮：再练一遍（48pt 主）+ 返回今日（40pt 描边）**。
8. 补全全部色值（旧 spec 无数值）、圆角体系（卡 16 / 内嵌 12 / 小标签 4–6）、spike 白描边点与气泡定位。

## 红线落点（真值保留项）

- 弱总分 + 逐字脚注「（不作过关依据）」；本页不产生过关判定。
- 置信度逐字「对齐置信度高 · 踏板已计入判分」。
- 时长示例「2分14秒」。
- 图表数字均为示例，由判分结果驱动。
