# S16 侧拍回看（修订 spec · 以 code.html 为真值）

- Screen ID: `1287377a7f334ecba2c5f09a008659a5`
- 真值文件：Stitch code.html（DESKTOP 元数据，390 逻辑宽竖版，单屏内容）
- 画布基准：容器 `max-w-[390px]`，px16，1px = 1pt
- Status: Final（本文件取代旧 spec）

## 用途一句话

录后本地回看：紧凑播放器叠加 21 点骨架与时间点标注；3 条带置信度的手型观察（中/高/低）；免责卡常驻；可去问 Neko 或重新校准。本页不产生任何过关/分数写入。

## 颜色

tailwind.config（命名简短，映射到全局语义）：

| Token | 值 | 语义 |
|---|---|---|
| `bg` | `#1C1917` | 页面底色、进度槽、切换 chip 底 |
| `card` | `#262220` | 卡片底色 |
| `border` | `#332D29` | 1pt 卡边框 |
| `amber` | `#D4A24E` | 主琥珀：骨架、当前时间码、主按钮 |
| `green` | `#7FA97C` | 通过/稳定：中指骨架、0:21 标记 |
| `red` | `#C97064` | 警示：拇指问题、标注 |
| `light` | `#F5F2ED` | 主文字 |
| `muted` | `#9C948B` | 次级文字 |

内联/SVG hex（config 之外）：

| Hex | 位置 |
|---|---|
| `#141210` | 播放器画面底 |
| `#1b1816` | 透视琴床填充 |
| `#2a2522` | 白键分割线（1.2pt） |
| `#0d0c0a` | 透视黑键 |
| `#C4BDB5` | 低置信行正文色 |
| `rgba(212,162,78,0.07)` | 手部柔影填充（带 6pt blur） |
| amber 各透明度 | 骨架连线 0.6–0.9；时间码点发光 |
| `rgba(127,169,124,0.4)` / `rgba(212,162,78,0.4)` | 观察列表圆点发光 |
| `rgba(229,72,77,*)` | 无（本屏 red 用 #C97064，非录制红 #E5484D） |

字体：

- serif：`"Noto Serif SC"`（页面标题、卡标题、按钮主文案除外）
- sans：`"Plus Jakarta Sans"`
- mono：未自定义，使用 Tailwind 默认等宽栈（时间码 0:14/0:32）
- 图标：Material Symbols Outlined（FILL0 wght400 opsz24）

## 页面结构

```
容器（390，px16 pt12 pb24，flex col justify-between）
├ 上区（flex col gap12）
│   ├ 状态栏
│   ├ 顶栏（返回 / 标题 / 分享 + 更多）
│   ├ ① 视频卡（画面 142pt + scrubber + 三 chips）
│   ├ ② 观察卡（3 行）
│   └ ③ 免责卡
└ 底部双按钮（问 Neko / 重新校准）
```

### 1. 状态栏

px4 pt4，12px medium muted：左「9:41」；右图标 signal_cellular_alt 13、wifi 13、battery_full 14，间距 6pt。

### 2. 顶栏 header（py4）

- 左：返回钮 32×32pt，`arrow_back_ios_new` 24px `#F5F2ED`；hover 转 amber；active opacity .7
- 中：「侧拍回看」serif 18px semibold tracking-wide
- 右：两枚 32×32pt 图标钮 `ios_share` / `more_horiz`，均 20px `#9C948B`，hover 转主色
- 注意：真值标题**不带曲名/时长后缀**（旧示意稿有，作废）

### 3. 卡① 视频播放器

- 容器 bg #262220、1pt 边 #332D29、圆角 **16pt**、p 10pt，flex col gap8，overflow-hidden

#### 3a. 播放画面

- 满宽 h **142pt**，底 `#141210`，圆角 12pt，relative，overflow-hidden
- SVG viewBox `350×142`（满宽 350pt）：
  - 透视琴床：path `M0 88 L350 78 L350 142 L0 142 Z` 填 `#1b1816`
  - 7 条白键分割线：x38→32 等，1.2pt `#2a2522`（近大远小透视）
  - 6 个透视黑键多边形：填 `#0d0c0a`
  - 手部柔影：闭合 path，填 amber **7%**，`filter:blur(6px)`
  - 骨架连线（21 点式简化呈现）：
    - 掌弓 5 段（110,104 → 136,92 → 162,76 → 190,68 → 216,72 → 236,84）：amber 1.2pt opacity .75
    - 拇指（1指）：3 段 **`#C97064` 1.4pt**，首段虚线 `2 1.5`（异常）
    - 食指：amber 1.2pt .8
    - 中指：**`#7FA97C` 1.3pt .9**（稳定，绿色）
    - 无名指：amber 1.1pt .7
    - 小指：amber 1.1pt .6
  - 关节点 21 枚：普通 amber r1.8–2.8；拇指点 red r2–2.2；中指点 green r2.2–2.4
  - 拇指尖 (172,108) 三重标注：实心圆 r7 填 red 25%、描边 1.8pt；外环 r13 red 虚线 `2 2` 1pt；中心点 r2.4 red
- 画面内覆盖元素：
  - 左下红色标签胶囊：底 `#1C1917` 90%、1pt 边 red 60%，`backdrop-blur(sm)`，px8 py2，11px red：6pt 红点（animate-pulse）+「1指触键偏平」
  - 播放钮：画面正中 **36×36pt** 圆，底 black 40%、1pt 边 white 20%，`backdrop-blur(xs)`（~2pt）；`play_arrow` 18px `#F5F2ED`（图标右移 2pt 居中）；active scale .95
  - 右上分辨率角标：底 black 50%，9px muted，px6 py2，圆角 4pt，tracking-wider：「1080P · 60fps」

#### 3b. Scrubber

- 时间码行（gap8）：左「0:14」11px mono medium **amber**；右「0:32」11px mono muted
- 进度条：flex-1 h4pt，底 `#1C1917` 全圆角，overflow-hidden，relative：
  - 已播放：宽 **43.75%**（14/32），amber 全圆角
  - 当前标记：left 43.75%，4pt 宽红线 `#C97064`（translate-x −1/2）
  - 0:21 标记：left **65.6%**（21/32），4pt 宽绿线 `#7FA97C`
- 整条为拖拽热区（html 未给手柄，按系统手势）

#### 3c. 切换 chips 行（pt2，flex between）

- 左组 gap6，每枚胶囊 px8 py2，11px：
  - 「骨架 ON」：底 amber 15%、1pt 边 amber 50%，字 amber medium，前 6pt 琥珀点
  - 「标注 ON」：底 red 15%、1pt 边 red 50%，字 red medium，前 6pt 红点
  - 「原片」：底 `#1C1917`、1pt 边 #332D29，字 muted；按下转主色（关骨架+关标注）
- 右：「拜厄 45 · 第 21 小节」10px muted

### 4. 卡② 这一段的观察（3）

- 容器 bg #262220、1pt 边、圆角 16pt、p 12pt，flex col gap10
- 卡头 pb8，底边 1pt #332D29 70%，flex between：
  - 标题 serif 13px semibold tracking-wide「这一段的观察（3）」
  - 右「已对齐音频时间戳」10px muted
- 三行（行间 1pt 分隔线 #332D29 60%），每行 py8，flex between gap8：
  1. 中点：8×8pt 琥珀圆（mt6，发光 .4）；正文 12px/1.15 `#F5F2ED`：mono amber「0:14」+「手腕位置偏低，可能影响黑键移动」；右 badge 10px medium，底 amber 10%、1pt 边 amber 30%、字 amber：「置信度 中」
  2. 高：绿点（发光 green .4）；mono green「0:21」+「转指时 3 指支撑稳定」；badge green 10%/边 30%：「置信度 高」
  3. 低：灰点 muted（无发光）；正文色 **`#C4BDB5`**：mono muted「0:26」+「手掌遮挡，无法判断」；badge 底 `#1C1917`、1pt 边 #332D29、字 muted：「置信度 低 · 不评价」
- 每行整行为热区：点击 seek 到对应时间码、标注闪烁（html 未绑事件，按交互规范）

### 5. 卡③ 免责卡

- 底 `#262220` **70%**（半透明卡片），1pt 边 **amber 40%**，圆角 12pt，p10，flex gap8
- `info` 16px amber
- 文案 11px `#D8D2C9`/relaxed，逐字：
  「手型观察仅供参考，永远不会影响过关；单摄有死角，看不清的我会直接说。」

### 6. 底部双按钮（pt12，flex col gap8）

- 主按钮（上）：满宽 py12，圆角 12pt，底 `#D4A24E`（hover `#deb162`），字 `#161311` semibold 14px；`chat` 18px；「带着这些去问 Neko」；shadow-md；active scale .98
- 次按钮（下）：满宽 py10，圆角 12pt，1pt 边 #332D29，底 #262220 40%，13px medium muted；`tune` 16px；「重新校准机位」；hover 字主色/边 muted 50%

## 全部状态汇总

- 播放钮：暂停态显示 play_arrow（真值状态）；播放中应切 pause（待实现补）
- chips 三态：骨架 ON / 标注 ON 可独立开关；「原片」=两者关。真值为骨架+标注双开
- scrubber：已播琥珀、当前红标、0:21 绿标；两个事件标记
- 观察行三态：中（琥珀）/高（绿）/低（灰，文字 `#C4BDB5`，结句「无法判断」+ badge「不评价」）
- 分享：仅系统分享本地视频，不触发上传
- 问 Neko：去提问流并预填本视频与观察上下文（上传确认另走，待产品确认具体页）

## 相对旧 spec 的主要修订

1. 顶栏：真值有**分享 + more_horiz 两枚图标钮**（旧 spec 仅 ⇪）；标题纯「侧拍回看」无后缀；返回箭头（非旧 S13 式 ✕）。
2. 播放画面真值高 **142pt**（卡总高约 220pt，旧说「约 34% 屏高」近似但给精确值）；底 `#141210`、圆角 12pt。
3. 骨架上色规则细化：掌弓/食指/无名/小指标准 amber（透明度分档 .6–.9），**拇指红色 1.4pt（首段虚线）、中指绿色 1.3pt**；21 个关节点半径按指分色；手部柔影 amber 7% + 6pt blur。旧 spec 仅「琥珀」。
4. 拇指标注真值为**三重圆**（r7 红 25% 实底 + r13 红虚环 + 中心点），左下药丸「1指触键偏平」带红脉冲点。
5. Scrubber 精确化：高 4pt、槽 `#1C1917`、已播 43.75% amber；**红（当前）+ 绿（0:21，65.6%）两枚事件标记**；时间码 0:14 为 amber、0:32 muted。
6. 切换 chips 真值样式：**ON=对应色 15% 底+50% 描边+前置同色点**，「原片」=深色暗态；旧 spec「ON=琥珀填充深字」描述不准确（标注 ON 为红色系）。
7. 观察卡标题「这一段的观察（3）」serif 13px + 右上「已对齐音频时间戳」；三行文案真值为「手腕位置偏低…」「转指时 3 指支撑稳定」「手掌遮挡，无法判断」（旧 spec 文案与时间码对应关系全换，0:14 对应中置信手腕条而非拇指条）。
8. 置信 badge 三态精确：中 amber、高 green、低=深色底灰字「**置信度 低 · 不评价**」（旧 spec「虚线描边」改实边深底）；低置信行正文色 `#C4BDB5`（非整行 opacity 0.7）。
9. 免责卡真值为 **card 70% 半透明 + amber 40% 描边**，文案色 `#D8D2C9`；旧 spec「同 S15」两屏其实不同（S15 为实底 #221E1B + amber 20% 边）。
10. 底部按钮：真值为**纵向堆叠**（主在上 py12、次在下 py10），旧 spec 左右并排作废；主按钮文字色 `#161311`、chat 图标；次按钮含 tune 图标。
11. 补分辨率角标「1080P·60fps」、播放钮 36pt 黑 40% 模糊底等全部数值。

## 红线落点

- 免责逐字声明在屏；低置信显式「无法判断 · 不评价」。
- 本页不产生过关/分数写入；手型观察永不进门禁。
- 分享仅本地视频，不上传。
