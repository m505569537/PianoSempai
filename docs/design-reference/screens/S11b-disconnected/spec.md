# S11b 练习室 · MIDI 断连态（修订版 · 以 Stitch code.html 为真值）

- 真值文件：`d141b071ee7343a1b086da9995c5c891/code.html`
- 逻辑画布：**390 × 844 pt**（MOBILE 780×1768 @2x 导出，body 固定 390×844）
- 字体：Noto Serif SC（serif）/ Noto Sans SC（sans；PingFang SC 兜底）
- Status: Final

## 1. 用途

练习中 BLE/USB 断连的全屏状态页：判分暂停、断点保留、谱区压遮罩；提供重新连接与 MIDI 诊断。重连续弹不丢音符。无 tab bar、无 9:41 状态栏。

## 2. 全局布局（VStack）

```
Header（pt16 pb8 px12，底边 1pt）
Main（flex-1，px12，py8，gap10，justify-between）
  ① 红色重连横幅
  ② 谱纸卡（flex-1，280–340）含整面遮罩
  ③ 四控件格 + 禁用主按钮
  ④ 诊断提示卡
```

- body：390×844，overflow-hidden，flex-col justify-between。
- 注意：tailwind config 虽为 Material Design 3 token 集（surface #161311 等），但 body 与 DOM 实际使用 App 深色系（#1C1917 / #262220 / #332D29 / #C97064 / #D4A24E），施工以 DOM 内联色为准。

## 3. Header（pt16 pb8 px12）

- 底边：1pt `#332D29/60`。
- 左：返回 **36×36 圆角 8**；arrow_back_ios_new 22pt muted；hover 变 main，按压缩放 0.9。
- 中（max-w190）：标题 serif **14pt medium** tracking-tight，单行居中截断：「拜厄 45 · 17–24小节 · ♩=**60**」；副行 10pt muted，uppercase tracking-wider：「Take 04 · 练习进行中」。
- 右（gap6）：
  - **未连接胶囊**：bg `#3A2522/80`，1pt 边框 `#C97064/50`，圆角全圆，px8 py2；1.5×1.5 圆点 bg `#C97064`，脉冲动画 **2s**：opacity 0.9↔0.45、scale 1↔1.15（cubic-bezier(.4,0,.6,1) 无限）；文字 11pt medium `#E8A59E`「未连接」。
  - smart_toy 钮：**32×32 圆角 8**，19pt muted（hover 琥珀）；语义=问 Neko/辅助设置。

## 4. ① 重连横幅

- 容器：bg **`#3A2522`**（暗红棕实底），1pt 边框 `#C97064/40`，圆角 **12**，p12，shadow-lg，overflow-hidden。
- 环境光：绝对 −right24 −bottom24，96×96，bg `#C97064/10`，圆角全圆，**blur-xl**。
- 主行（gap8）：
  - 图标盒：28×28，圆角 8，bg `#C97064/20`；bluetooth_disabled 18pt `#E8A59E`。
  - 标题：13pt medium main，tracking-wide：「MIDI 已断开 · 判分已暂停」。
  - **重新连接**钮（右侧，shrink-0）：**实底 #C97064**（hover #D67E72），白字 11pt medium，px10 py4，圆角全圆，refresh 13pt；按压缩放 0.95。
- 副行：11pt `#E8A59E/90`，mt6，**pl36**，leading-relaxed：「已弹奏的内容保留在本次 take，重连后从断点继续，不丢音符。」

## 5. ② 谱纸卡（flex-1，min-h280 max-h340）

- 容器：bg **`#FBF9F5`**（custom-score-bg），圆角 **12**，p14，shadow-md，1pt 边框 `#DCD6CA/40`，overflow-hidden；flex-col justify-between。

### 5.1 纸内头部（底边 1pt #E3DDD1，pb4）

- 左（gap8）：serif 13pt semibold `#161311`「Beyer Op. 101 No. 45」；chip：10pt `#7A7268`，bg `#ECE5D8`，px6 py2，圆角 4：「C Major · 3/4」。
- 右（gap12）：10pt mono `#7A7268`「m.17-24」；断点标记：1.5 琥珀圆点 ＋ 10pt `#A36D1F`「断点: m.21」。

### 5.2 SVG 谱面（viewBox 350×190，preserveAspectRatio none）

- 断点小节高亮：rect x175 y10 w85 h170 rx3，fill `#D4A24E`，**fill-opacity 0.14**；左侧 x175 虚线 `#D4A24E` 宽 1.8，dasharray **2 2**。
- 五线：高音 y30–70、低音 y110–150（步长 10），stroke `#181513` 宽 1.1；左端 x10 粗 brace 宽 2.5。
- 小节线：x10 / 95 / 175 / 260 / 340，宽 1.3（首尾 2.5）。
- 小节号：9pt serif semibold `#7A7268`：17（x14）、19（x99）、23（x264）；21 为 **`#B47A22` bold「21 ▾」**（x179 y24）。
- 谱号：𝄞 34pt、𝄢 28pt（x14），fill #181513。
- 音符状态分层：已弹/普通音符 `#181513`；断点处待续音符 `#D4A24E`（cx195）；其后音符灰 `#686058`（cx225）；未到小节 `#948D85`（cx280/310）。
- 谱面为示意，实现接记谱引擎。

### 5.3 遮罩（绝对铺满谱纸内容区）

- scrim：bg **`#1C1917/75`** ＋ **backdrop-blur(2pt)**，圆角 8，flex-col 居中，p16。
- 圆徽：**48×48 圆形**，bg `#262220`，1pt 边框 `#D4A24E/40`，shadow-xl；pause 24pt 琥珀；mb10。
- 主文：serif **14pt medium** main，tracking-wide，居中：「等待特伦斯 V70 重新连接…」
- 副文：11pt muted，mt4，居中：「保持琴盖开启并靠近手机」。

### 5.4 纸内页脚（顶边 1pt #E3DDD1，pt4）

- 10pt `#7A7268`，两端对齐。
- 左：speed 13pt `#8C847A` ＋「原速 60 BPM」。
- 右：「断点已缓存 (第 21 小节第 1 拍)」。

## 6. ③ 底部控件区（gap8）

### 6.1 四格（grid-cols-4 gap6；真值为静态 div，不可点）

每格：bg `#262220`，1pt 边框 `#332D29`，圆角 **8**，p8，flex-col 居中 gap4。

| 格 | 图标 18pt | 名称 11pt medium main | 副值 9pt mono |
|---|---|---|---|
| 节拍器 | timer muted | 节拍器 | 3/4拍（琥珀） |
| 循环 | repeat muted | 循环 | 17-24节（琥珀） |
| 预备拍 | hourglass_top muted | 预备拍 | 1小节（muted） |
| 双手 | front_hand muted | 双手 | 同步练习（muted） |

- 按压底色 active:bg `#2D2724` 虽写在 class，但断连态语义禁用；**全部不响应点击**（不用 opacity .4，而是保持原色 ＋ 禁用交互）。

### 6.2 禁用主按钮（替代 S11 的大圆钮）

- 全宽，**py12**，圆角 **12**，bg `#262220`，1pt 边框 `#332D29`，文字 14pt serif medium muted；lock_clock 18pt muted ＋ gap8；**disabled**，cursor-not-allowed，opacity 0.9，shadow-inner。
- 文案：「练习已暂停 (等待设备)」。

## 7. ④ 诊断提示卡

- 容器：bg `#262220`，1pt 边框 `#332D29`，圆角 **12**，p12，shadow-md；flex 两端对齐 gap12。
- 左：info 16pt 琥珀 mt2 ＋ 11pt muted leading-relaxed：「提示：检查蓝牙是否被其他设备占用；USB 线可直接插上替代蓝牙。」
- 右（shrink-0）：文字钮 12pt medium 琥珀（hover #E8C882）：「打开 MIDI 诊断 →」→ **S24**。

## 8. 颜色（hex + 语义 + 位置）

| Hex / 值 | 语义 | 使用位置 |
|---|---|---|
| `#1C1917` | bg | 页面底、遮罩 /75 |
| `#262220` | card | 四控件、禁用按钮、诊断卡、遮罩圆徽 |
| `#332D29` | cardBorder | header 底线/60、控件与卡片边框 |
| `#2D2724` | active 底 | 控件按压色（断连态不触发） |
| `#3A2522` | danger 容器底 | 重连横幅、未连接胶囊 /80 |
| `#C97064` | danger 主色 | 胶囊/横幅边框（/40 /50）、圆点、重连钮实底、图标底 /20 |
| `#E8A59E` | danger 浅色文字 | 胶囊字、横幅标题图标、副文 /90 |
| `#D67E72` | 重连钮 hover | 重新连接 hover |
| `#D4A24E` | amber | 断点高亮、谱号标记、圆徽/按钮图标、诊断强调 |
| `#A36D1F` / `#B47A22` | 琥珀深字 | 断点: m.21 / 小节号 21▾ |
| `#FBF9F5` | 谱纸色 | 谱纸卡底（注意与 S11 的 #FBF8F2 微差） |
| `#DCD6CA` / `#E3DDD1` | 纸边框/分隔 | 纸卡边框 /40、纸内线 |
| `#ECE5D8` | 纸内 chip 底 | C Major · 3/4 |
| `#181513` | ink | 谱线、小节线、普通音符 |
| `#161311` | 深墨 | 纸内标题字 |
| `#7A7268` | 纸内 muted | chip 字、页脚、小节号 |
| `#8C847A` | 页脚图标 | speed |
| `#686058` / `#948D85` | 灰音符 | 断点后/未到音符 |
| `#F5F2ED` | text | 主文字 |
| `#9C948B` | muted | 返回、副行、禁用按钮字 |

## 9. 交互热区与状态

- 返回 36×36：退出断连页（返回即 pop；是否等同结束练习待产品确认）。
- smart_toy 32×32：问 Neko（断连下是否可用待产品确认）。
- 重新连接（约 28 高 pill 热区）：发起 CoreMIDI/BLE 重连，按钮进入 spinner（真值未画）；成功后续弹。
- 四控件格：**断连期间全部禁用**（整格热区约 62 高但不响应）。
- 主按钮：禁用态无点击。
- 打开 MIDI 诊断：整行文字热区 → S24。
- 旧稿写但真值无（**待产品确认**）：成功后「已重连，从断点继续」1s 成功态文案；10s 未重连追加提示行；用户主动结束的二次确认弹窗；「节拍器例外可继续出声」。

## 10. 对旧 spec 的主要修正

1. 横幅底色真值为实底 **#3A2522** ＋ #C97064/40 边框，不是「#C97064 14% 底」；高度约 72（旧稿 44）；带 blur-xl 环境光斑。
2. 「重新连接」是**白字实底 danger 钮**（#C97064，圆角全圆），不是描边款。
3. 遮罩为 `#1C1917/75` ＋ **2pt 背景模糊**；居中是 48pt 圆形 ＋ 琥珀 pause 图标（旧稿写 32pt muted 图标）；双行文案锁定。
4. 禁用方式：四控件**保持原色不点击**（非 opacity .4）；S11 圆钮位置替换为全宽禁用按钮「练习已暂停 (等待设备)」，无独立「结束」钮。
5. Header 全新内容：返回箭头、♩=60、「Take 04 · 练习进行中」、红色「未连接」脉冲胶囊、smart_toy。
6. 新增纸内断点元信息：「断点: m.21」徽标、「21 ▾」小节号、「断点已缓存 (第 21 小节第 1 拍)」「原速 60 BPM」页脚。
7. 「打开 MIDI 诊断」不是幽灵入口，是独立卡片 ＋ 蓝牙占用/USB 替代排查文案。
8. 控件内容与 S11 不同：本稿四格为 节拍器/循环/预备拍/双手（S11 为 速度/循环/分手/节拍器）。
