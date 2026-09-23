# S17 导入月度录像（尼康 Zf 相册）· 修订 spec

> 真值来源：Stitch code.html（DESKTOP 渲染稿，body 固定 `w-[390px]`，以 **390pt 逻辑宽 / 最小高 844pt** 为准）。
> 所有数值直接换算自 Tailwind 类：间距 N×4=pt；`rounded-[Npx]`→N pt。

## 1. 用途与页面定位

每月一次从系统相册挑选尼康 Zf 拍摄的练琴视频，复制到本机永久归档。**不上传、不判分、不自动分析手型**。
从「档案」push 进入，**无 tab bar**；底部为 sticky 操作区。

## 2. 颜色系统（tailwind.config `app.*` + 内联 hex）

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | app.bg | body 底、底部栏底、存储 badge/1080p tag 底、未选 checkbox 底 |
| `#262220` | app.card | 全部卡片/行底、按钮 active 态 |
| `#332D29` | app.border | 卡片/行/标签边框、分隔圆点 |
| `#D4A24E` | app.amber | 选中 checkbox、选中行边框（40% 透明）、时长文字、左侧强调边、主 CTA 底、Zf badge 圆点 |
| `#C2913D` | app.amberHover | 主 CTA hover |
| `#F5F2ED` | app.text | 标题/主文字；正文内「Zf」强调 |
| `#9C948B` | app.muted | 状态栏、副标题、次要文字、未选标题 |
| `#6A635B` | app.subtle | 未选 checkbox 边框、未选行元信息 |
| `#141210` | app.darker | 视频缩略图底 |
| `#2A2421` | （仅内联，body 外侧描边 40% 透明） | body `border-x`，桌面预览框用，App 内不实现 |
| `#000000` 70% | — | 缩略图右下角时长标签底 |

字体：标题 `Noto Serif SC`（400/600/700）；正文 `Plus Jakarta Sans`（400/500/600/700）。图标 Material Symbols Outlined。

## 3. 整体布局层级

```
body (390pt, flex-col, justify-between)
├─ 内容组
│  ├─ 状态栏  h=44
│  ├─ 导航栏  px=20
│  └─ main    px=16, 子项间距 14, pb=24
│     ├─ 说明卡
│     ├─ 月份汇总卡
│     └─ 候选列表区（标题行 + 4 行 article）
│        └─ 底部琥珀提示卡
└─ footer（sticky：全不选 + 导入 CTA + home indicator）
```

### 3.1 状态栏（h=44）
- `px=24 pt=12`，文字 13pt medium，色 muted；左 `9:41`，右信号/wifi（15pt 图标）+ 电池外框 20×10（描边 muted，圆角 2，内填充 muted 宽 12）。

### 3.2 导航栏
- 内边距 `px=20 pt=8 pb=12`，flex 两端对齐。
- 返回按钮：**36×36 圆形**（`-ml=4` 热区补偿），图标 `arrow_back_ios_new` 24pt，muted；hover text、active 底 card。热区 ≥44（含外扩）。
- 标题：serif **18pt semibold**，tracking-wide，文案「导入月度录像」。
- 右侧来源 badge：`px=10 py=4` 全圆角，bg card、border，文字 **11pt** muted「尼康 Zf」；前置 6×6 琥珀圆点。

### 3.3 main 通用
- `px=16`，各 section 垂直间距 **14pt**（space-y-3.5），`pb=24`。

### 3.4 说明卡（intro）
- bg card + border，圆角 **16pt**，`p=14`，flex `gap=12`，shadow-sm。
- 左图标盒：**28×28**，圆角 **8pt**，bg bg、border，琥珀图标 `photo_camera` 17pt；`mt=2` 顶对齐。
- 文案：**12.5pt / 行高 1.65**，muted；其中「Zf」text 色 + medium。
- 文案真值：「每月一次，从相册挑选 Zf 拍的练琴视频存档。这些视频永久保留在本机，只供你回看，不上传、不判分。」

### 3.5 月份汇总卡
- bg card + border，圆角 **16pt**，`p=16`，内部 `space-y=10`。
- 第一行 baseline 两端：
  - 左：**17pt bold** tracking-tight「2026 年 9 月」。
  - 右：存储 badge，11pt，`px=8 py=2`，圆角 **6pt**，bg bg + border（80%），muted，文案「本机剩余空间 24 GB」。
- 第二行：**12.5pt medium**，琥珀色：「已选 3 段 · 共 12分40秒 · 约 1.8 GB」。

### 3.6 候选列表
- 区块 `space-y=8`。
- 标题行 `px=4` 两端：左 11pt medium、uppercase、tracking-wider「相册候选项 (4)」；右 11pt muted「按录制时间排序」。
- 行容器 article：bg card、圆角 **12pt**、`p=12`、flex 两端 `gap=12`。

**选中行（前 3 行）**：边框 `#D4A24E` 40% 透明。
- 左簇 flex `gap=12`：
  1. checkbox：**20×20，圆角 6pt**，选中态 bg 琥珀 + `check` 16pt（色 bg，bold）。
  2. 缩略图：**64×44（宽 16 × 高 11，非 16:9）**，圆角 8pt，bg darker + border，overflow-hidden；右下角时长标签 9pt mono，bg 黑 70%，text 色，`px=4 py=1`。第 1 行额外含琥珀点阵纹理（6×6，40% 透明）+ 琴键柱装饰（占位装饰，真实实现用视频首帧）。
  3. 元信息列：`space-y=2`；标题 **14pt medium** text（truncate）；元信息行 **11.5pt** muted、`gap=8`：琥珀时长 medium + 圆点分隔 + 「1080p」标签（**10pt mono**，bg bg + border，`px=6 py=1`，圆角 2）+ 大小。
- 右：`play_circle` 18pt，muted，opacity 40%（视觉图标，非主热区）。

**未选行（第 4 行）**：bg card 60% 透明 + 整行 opacity **75%**（hover 100%），边框普通 border。
- checkbox：20×20，圆角 6，bg bg + border subtle，空。
- 标题色 muted；元信息色 subtle；时长标签字色 muted；play_circle 色 subtle。

真值数据：

| # | 标题 | 时长 | 分辨率 | 大小 | 状态 |
|---|---|---|---|---|---|
| 1 | 9/14 拜厄45 合手录 | 4:12 | 1080p | 约 580 MB | 选中 |
| 2 | 9/7 哈农1 速度对照 | 3:58 | 1080p | 约 540 MB | 选中 |
| 3 | 9/1 Summer 完整弹 | 4:30 | 1080p | 约 680 MB | 选中 |
| 4 | 9/21 即兴小段 | 2:05 | 1080p | 约 290 MB | 未选（弱化，非"未到日期"） |

### 3.7 琥珀提示卡
- bg card，**左 2pt 琥珀竖边**（border-l-2），其余边 border；圆角：右 **12pt**、左 **2pt**（rounded-l-xs）。
- `p=14 gap=10`；`info` 图标 18pt 琥珀（mt=2）；文案 **12pt** / 行高 relaxed，muted：「导入后可在档案里按月回看；手型标注需要你主动发起，不会自动分析。」

### 3.8 底部操作 footer
- `p=16 pt=8 pb=24`，bg bg **95% 不透明 + backdrop-blur(md, ≈12pt)**，顶边 border 60% 透明，内部 `space-y=12`。
- 按钮行 `gap=12`：
  - 「全不选」文字按钮：h=48，`px=16`，圆角 **12pt**，14pt medium muted（hover text，active 底 card）。
  - 「导入所选 3 段」主 CTA：**flex 比例 1 撑满**，h=48，圆角 12，bg 琥珀（hover `#C2913D`），文字 bg 色 **15pt semibold** tracking-wide，前置 `download` 19pt；阴影 `shadow-lg`，琥珀色 **10% 透明**；按压缩放 0.99。
- home indicator：128×4，muted 30% 透明，全圆角，居中（`pt=4`）。

## 4. 全部状态

| 状态 | 表现（真值） |
|---|---|
| 默认（当前稿） | 3 选中 / 1 未选；CTA「导入所选 3 段」 |
| 未选行 | 整行 opacity 75%，checkbox 空、subtle 边框 |
| 按钮按压 | CTA scale 0.99；图标钮 active 底 card |
| 0 选择时 CTA disabled | **HTML 未呈现** → 待产品确认（旧 spec 要求 disabled，沿用但需复核样式） |
| 空间不足（danger、"管理存储"链） | **HTML 未呈现** → 待产品确认 |
| 导入中进度条 / 后台 / 本地通知文案 | **HTML 未呈现** → 待产品确认（旧 spec 有，保留） |

## 5. 交互热区

- 返回钮 36×36（含 -4 外扩补偿，点击热区按 44 兜底）。
- checkbox 20×20 独立按钮；整行 article 亦响应（transition-all）——点击行任意位置切换勾选。
- `play_circle` / 缩略图：预览视频（真值仅为图标，播放器形态待产品确认）。
- 「全不选」按钮热区 = 文字按钮本身（h=48）。
- CTA 全宽（扣除「全不选」宽与 12 间距），h=48。

## 6. 与旧 spec 的主要差异（施工必改）

1. **复选框**：旧 22pt、在右；真值 **20pt、行首左侧**，选中态琥珀填充圆角 6pt。
2. **缩略图**：旧"16:9、64 高"；真值 **64×44**，圆角 8，darker 底 + border。
3. **行数据全错**：旧 4:02 / 3:51 / 4:47 且第 4 行为"未到日期灰显"；真值见 3.6 表，第 4 行是存在但未选的 9/21 条目（opacity 75%）。
4. **新增组件**：相机图标说明卡、独立月份汇总卡（含存储 badge、琥珀汇总行）、右上「尼康 Zf」来源 badge、底部琥珀左竖边提示卡。
5. 旧 spec 完全缺色值/圆角/字号/间距，以本文件第 2、3 节为准。
6. 旧 spec 的 danger/存储不足、导入中进度态在真值中不存在，标注「待产品确认」，不得按旧文字直接施工。
