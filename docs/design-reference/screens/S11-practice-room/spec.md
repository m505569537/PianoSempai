# S11 全屏练习室（修订版 · 以 Stitch code.html 为真值）

- 真值文件：`65f044723e6a4fb8aba32ec46412075e/code.html`
- 逻辑画布：**390 × 844 pt**（DESKTOP 导出；body max-w390，全屏 100h，按 390 逻辑宽施工）
- 字体：Noto Serif SC（serif）/ Plus Jakarta Sans（sans）
- Material Symbols：FILL 0 / wght 350；`.fill-1` = FILL 1 / wght 400
- Status: Final（谱面音符为视觉示意；实现接真实记谱引擎）

## 1. 用途

跟弹练习主战场：纸白五线谱占主屏 ＋ 当前小节高亮/扫描光标 ＋ 连续循环进度 ＋ 四控件坞 ＋ 大圆钮。零 Alert 打断。无 tab bar、**无 iOS 9:41 状态栏**（真值直接是练习顶栏，系统状态栏需真机隐藏/由系统承载，设计稿不画）。

## 2. 全局布局（VStack 四段）

```
Header 练习顶栏（pt12 pb8 px14，约 52 高）
Main 谱区（flex-1，px12 py6）
Progress 连续循环条（px16 py6）
Footer 控件坞 + 圆钮（px16 pt4 pb24）
```

- body：flex-col justify-between，overflow-hidden，左右各 1pt `stone-800/40` 边框（仅桌面预览用，App 内不要）。

## 3. Header（练习顶栏）

- 容器：`pt12 pb8 px14`，底边 1pt **white/5**，bg `#1C1917/95` ＋ **backdrop-blur-md**。
- 左侧组（gap6）：
  - **问 Neko** 幽灵钮：py4 px8，圆角全圆，bg `white/0.05`，1pt 边框 white/10；猫头 SVG 14×14（stroke 2，琥珀）；文字 **serif 11pt main/90**「问 Neko」；hover bg white/0.1，按压缩放 0.95。
  - **MIDI 已连接** pill：px8 py2，圆角全圆，bg `#262220`，1pt 边框 amber/25；1.5×1.5 琥珀圆点；10.5pt amber/90 medium（整体 scale .95）。
- 中部：标题 serif **14pt semibold** tracking-wide「拜厄 第45条」；副行 **10pt** muted「17–24 小节 · ♩=72」。
- 右侧组（gap4）：两个 **28×28 圆形**钮，bg white/0.04，图标 18pt muted（hover 变 main，按压缩放）：equalizer（混音/均衡，功能待产品确认）、close（退出）。

## 4. Main 谱区

- 容器：flex-1，flex-col 居中，`px12 py6`，overflow-hidden。
- **纸张卡**：全宽，bg `score #FBF8F2`，文字 ink `#1A1815`，圆角 **16**，p12，**shadow-2xl**，1pt 边框 `#EBE4D5`；**min-h 480 / max-h 520**；overflow-hidden。

### 4.1 纸张纹理与当前小节覆盖层

- 颗粒层：绝对铺满，**opacity 0.035**，mix-blend-multiply，圆点径向纹理 `#1A1815`、间距 8×8。
- 当前小节框（21 小节）：绝对定位 **left38 top246 w156 h228**；bg `#D4A24E/15`；**左右各 2pt 边框 amber/60**（border-x-2，无上下边）；圆角 2；不拦截点击。
  - 扫描光标线：相对框 **left44**，宽 **2.5pt**，上下铺满，bg 琥珀，阴影 `0 0 8px #D4A24E`；呼吸动画 1.2s：opacity 0.95 ↔ 0.45（ease-in-out 无限）。
  - 角标：top4 right6，px4，8.5pt bold，字 `#845A17`，bg `#D4A24E/30`，文案「当前小节」。

### 4.2 谱头（纸内）

- 行：底边 1pt `#DCD3C1`，pb4 px4，两端底对齐。
- 左：「No. 45」serif **16pt bold** ink；「Moderato cantabile」serif italic **11pt** stone-600，间距 8。
- 右（间距 6）：♩ 12pt bold sans ＋「= 72」11pt semibold；右侧 chip：9.5pt，px6 py2，圆角 4，bg `#EFE9DC`，stone-600，文案「双手协同」。

### 4.3 SVG 乐谱（viewBox 354×440，铺满弹性区）

- 两组大谱表：System 1 = 17–20 小节（translate y10），System 2 = 21–24（translate y220）。
- 五线：stroke **#3A3630**，宽 1；小节线：**#2C2824，宽 1.2**；终止复纵线 1 ＋ **2.5**。
- 谱号/拍号/未弹音符：ink `#1A1815`；21 小节当前目标音符带琥珀辉光滤镜（feDropShadow stdDeviation 2，flood 琥珀 0.8）与 1.2 琥珀描边。
- 已弹音符（17–20 全部 ＋ 21 第 1 拍）：**琥珀 #D4A24E**（含符杆、连音线；空符头为琥珀描边空心）。
- 指法提示：7.5pt semibold `#8C8479`（1/3/5），左手「5!」琥珀 bold。
- 21 小节号为琥珀填充 16×12 圆角 3 小徽标 ＋ 深色数字；其余小节号 8.5pt `#7A746B`。
- 实现：以上音符位置仅为示意，必须用真实记谱引擎渲染 MusicXML。

### 4.4 纸内页脚

- 顶边 1pt `#EBE4D5`，pt4 px1，10pt stone-600，两端对齐。
- 左：1.5 琥珀圆点 ＋ serif 提示「提示：第21小节注意左手3指转指提前就位」。
- 右：「Beyer Op.101」**9pt** stone-500 sans medium，大写，tracking-wider。

## 5. 连续循环进度条（Progress）

- 外框（px16 py6）：bg `panel/70 = #262220/70`，圆角 **12**，px12 py8，1pt 边框 `borderDim = rgba(245,242,237,0.08)`，backdrop-blur-sm；内部 gap6。
- 信息行：
  - 左：11pt medium muted；all_inclusive 13pt 琥珀；文案「连续循环 **3/5** 遍」（3/5 用 text 色 semibold）。
  - 右：10pt 琥珀 **mono**，bg amber/10，px6 py2，圆角 4，1pt 边框 amber/20：「目标 5 遍全绿通关」。
- 8 小节格：**grid-cols-8 gap4**，pt2；每列上下两个元素 gap4：
  - 进度条：全宽 **h6** 圆角全圆。
  - 数字：9.5pt mono。
  - 17–20 已完成：bg 琥珀 ＋ 辉光 `0 0 6px rgba(212,162,78,0.5)`；数字琥珀 medium。
  - 21 进行中：bg 琥珀 ＋ **脉冲环动画**（box-shadow 自 0 扩散到 6pt、1.8s 无限）；数字 bold text 色，bg amber/30，px4 圆角 4。
  - 22–24 未到：bg `stone-700/60`；数字 muted/70。

## 6. Footer 控件坞 ＋ 大圆钮（px16 pt4 pb24，gap12）

### 6.1 控件坞

- 容器：全宽，bg `#262220`，1pt 边框 `#3C3530`，圆角 **16**，p6，shadow-xl；**grid-cols-4 gap6**（四格 1:1:1:1）。

| # | 控件 | 容器 | 内容 |
|---|---|---|---|
| 1 | **速度**（非按钮） | p6，圆角 12，bg white/0.03，边框 white/5 | 10pt muted「速度」；−/＋ 钮各 **20×20** 圆角 4 bg white/5（hover white/10），12pt bold；值 **12pt bold** text「72」；8.5pt muted/80「♩ 拍/分」 |
| 2 | **循环**（按钮，激活态） | p6 圆角 12，**bg amber/10，边框 amber/70**，内阴影 `inset 0 0 8px rgba(212,162,78,0.15)` | repeat 16pt 琥珀 ＋ expand_more 12pt amber/80；11pt semibold text「循环」；8.5pt 琥珀 mono「17–24小节」 |
| 3 | **分手**（按钮） | bg white/0.03 边框 white/5 | front_hand 16pt muted；11pt medium text「双手」；8.5pt muted「原速同步」 |
| 4 | **节拍器**（按钮，开启态） | bg white/0.03，**边框 amber/40** | metronome 16pt 琥珀；右上 1.5 琥珀圆点；11pt semibold text「节拍器」；8.5pt 琥珀 mono「3/4 拍 开」 |

- 按压：按钮控件 scale 0.95。

### 6.2 大圆钮行

- 主钮：**56×56 圆形**，bg 琥珀（hover amber-bright `#E5B869`），图标 filled **32pt** ink；当前为「pause」（练习进行中）；阴影 `0 8px 24px rgba(212,162,78,0.4)`；按压缩放 0.9。
- 右侧状态（绝对定位 right8）：**emerald-400 #34D399** 1.5 圆点带 animate-ping 扩散 ＋「识别中」10pt muted。

## 7. 颜色（hex + 语义 + 位置）

| Hex / 值 | config / 语义 | 使用位置 |
|---|---|---|
| `#1C1917` | bg | 页面底、顶栏 /95 |
| `#262220` | panel | 控件坞、循环进度条 /70、MIDI pill |
| `#312C29` | panel-subtle | 仅 config 声明，DOM 未直接使用 |
| `#3C3530` | 坞边框（内联） | 控件坞边框 |
| `#D4A24E` | amber DEFAULT | 已弹音符、当前小节、循环激活、节拍器、圆钮 |
| `#E5B869` | amber-bright | 圆钮 hover |
| `#9E742E` | amber-dim | 仅 config 声明 |
| `rgba(212,162,78,0.25)` | amber-glow | config 声明；多处辉光阴影的来源色 |
| `rgba(212,162,78,0.16)` | amber-translucent | config 声明 |
| `#FBF8F2` | score 纸色 | 纸张卡底 |
| `#EBE4D5` | 纸边框（内联） | 纸张卡边框、纸内页脚线 |
| `#DCD3C1` | 谱头分隔（内联） | 纸内谱头底线 |
| `#EFE9DC` | 纸内 chip 底（内联） | 「双手协同」 |
| `#1A1815` | ink / scoreNote | 谱线音符文字、圆钮图标 |
| `#3A3630` | 五线（内联，注意 config 的 scoreStaff `#4A463F` 未被使用） | 五线 |
| `#2C2824` | 小节线（内联） | 小节线/连音线 |
| `#7A746B` | 小节号（内联） | 小节号 |
| `#8C8479` | 指法（内联） | 指法数字 |
| `#845A17` | 角标字（内联） | 当前小节角标字 |
| `#F5F2ED` | text | 主文字 |
| `#9C948B` | muted | 次级文字 |
| `rgba(245,242,237,0.08)` | borderDim | 循环进度条边框 |
| `#34D399`（emerald-400） | 识别指示 | 识别中 ping 点 |
| white 各透明度 | 叠加 | 顶栏线 /5、幽灵钮底 /5 边 /10、控件格 /3 与 /5 |

## 8. 全部状态 与 交互热区

- 问 Neko（约 28 高 pill）：页内唤起 Neko 输入条（不跳页；具体展开形态待产品确认）。
- MIDI pill：状态展示，点按是否进 S24 诊断待产品确认。
- equalizer 28×28：功能待产品确认；close 28×28：退出练习（退出即结算/保存流程待产品确认）。
- 速度 −/＋：20×20 热区，步长 1；范围 60–84、长按连改为旧稿约定，真值未画，**待产品确认**。
- 循环格（整格，约 60 高）：→ **S12**。
- 分手格：切换 双手/右手/左手（旧稿约定，真值未画态，待产品确认）。
- 节拍器格：整格切换；开启即响/即停（iPhone 本机出声）。
- 大圆钮 56×56：暂停/继续；暂停语义（真值图标 pause），旧稿写「■ 停止即结算」与真值不符，**以 pause 为准**；停止/结算入口真值未提供，待产品确认。
- 弹奏零打断：错音/慢了无 Alert、无红屏、不中止。
- 速度自适应 toast（±5、2s）：旧稿约定，真值 DOM 无，**待产品确认**。
- 时间到自动保存底部条：旧稿约定，真值 DOM 无，**待产品确认**。
- 不录像：本页任何状态不出现摄像头红点/取景 UI（红线）。

## 9. 对旧 spec 的主要修正

1. 整体结构差异大：真值无 9:41 状态栏；无「下一小节 22」行；无时间轴 0:47/2:14；无「标记」控件；无「结束并生成报告」按钮；新增连续循环进度条（3/5 遍、目标 5 遍全绿通关）。
2. 顶栏三段式：问 Neko ＋ MIDI pill 在左，标题居中，equalizer/close 在右；旧稿的左右排布全部重写。
3. 谱区纸色 `#FBF8F2`（旧稿 `#F5F0E6`）；圆角 16（旧稿 8）；p12；min 480/max 520；边框 `#EBE4D5` ＋ shadow-2xl ＋ 颗粒纹理 0.035。
4. 当前小节：amber/15 底 ＋ **左右 2pt amber/60 边框**（非四周 2pt 框），光标线 2.5pt 带辉光、1.2s 呼吸，位置 left38/top246/w156/h228；角标「当前小节」#845A17 on amber/30。
5. 四控件不是等高 56 的独立描边方卡，而是**同一个坞内四格**（坞圆角 16、边框 #3C3530、p6、gap6）；速度格是内嵌 −/＋/72 三段；循环格含 expand_more；节拍器格右上小圆点。
6. 圆钮 **56pt**（旧稿 64），当前显示 pause 图标 32pt；右侧「识别中」翠绿 ping。
7. 已弹音符用琥珀表示（旧稿未提此机制）；21 小节号是琥珀实体徽标。
8. 错误热点在本稿没有淡红底（红色机制全部移到 S11b/S13b）。
