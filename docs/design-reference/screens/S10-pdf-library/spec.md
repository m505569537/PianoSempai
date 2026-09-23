# S10 PDF 资料库（修订版 · 以 Stitch code.html 为真值）

- 真值文件：`6e8273c058f54243bc49983be3e43050/code.html`
- 逻辑画布：**390 × 844 pt**（DESKTOP 导出，内层容器固定 390×844，按 390 逻辑宽施工）
- 字体：Noto Serif SC（serif，标题）/ **Plus Jakarta Sans**（sans，正文；注意不是 Noto Sans SC）
- Material Symbols 全局变体：FILL 0 / wght 350 / GRAD 0 / opsz 22
- Status: Final

## 1. 用途

PDF 只读资料库：双段切换「我的 PDF / 如何获取可练谱」，明示 PDF 不跟弹、不判分。无 tab bar。

## 2. 全局布局

```
Header（状态栏 + h44 导航，px20）
Main（scroll，px20，区块间距 16）
Footer（渐变吸底脚注 + home indicator）
```

- 屏幕容器：390×844，flex-col justify-between，overflow-hidden，shadow-2xl。
- Main：flex-1 滚动，`px20 pt4 pb16`，子区块间距 **16**；滚动条全隐藏。

## 3. 逐层规范

### 3.1 Header（pt12 px20 pb8）

- 状态栏行：h32，px4。左「9:41」**14pt medium** tracking-tight；右信号 SVG（16×14）、wifi SVG（16×14）、电池（24×12，1pt 边框 main/80，圆角 4，内块圆角 2，右侧 1.5×6 电池耳）；颜色 main/90。
- 导航行：mt8，h44，flex justify-between。
  - 返回：40×40，**圆角全圆**（有 hover 底 #262220），chevron_left 24pt。
  - 标题：serif **18pt semibold** tracking-wide「PDF 资料库」。
  - 右：**搜索**按钮 40×40 圆角全圆，search 22pt（不是 ＋）。

### 3.2 顶部提示 Callout

- 容器：圆角 **12**，bg `#262220/70`，**1pt 全周边框 #D4A24E/30**，p14；flex items-start，图标与文字间距 12；shadow-sm，backdrop-blur-sm。
- 图标：info 19pt 琥珀，mt2。
- 文案：12.5pt，行高 **1.5**，muted：「PDF 仅可查看，不支持跟弹判分。想要可练的谱，请转换为 **MusicXML**。」其中「MusicXML」琥珀 medium。
- 注意：**没有**左缘 3pt 琥珀竖条（旧稿误写）。

### 3.3 双段切换控件（Segmented）

- 外框：bg `#262220`，1pt 边框 `#332D29`，p4，圆角 **12**，flex 两项各占 **flex-1（1:1）**。
- 选中态（我的 PDF）：py6 px12，圆角 **8**，bg 实琥珀 #D4A24E，文字 #1C1917 **13pt semibold**，shadow-sm；内嵌计数徽标「4」：bg `#1C1917/20`，11pt bold，px6，圆角全圆。
- 未选中（如何获取可练谱）：py6 px12 圆角 8，文字 muted 13pt normal，hover 变 main；无计数。

### 3.4 PDF 列表（pt4，行间距 10）

每行：bg `#262220`，1pt 边框 `#332D29`（**hover 变 #D4A24E/40**），圆角 **12**，p14；flex justify-between；active scale 0.99。

- 左侧：图标 40×40 ＋ 文本，间距 12；文本区 min-w-0、pr8。
  - 图标容器：40×40，圆角 **8**，bg `#1C1917`，1pt 边框 `#332D29`；picture_as_pdf **18pt 琥珀**；下方「PDF」8pt bold 琥珀/80，大写，−mt2。
  - 文件名：14pt medium，单行截断，hover 变琥珀。
  - 副信息：12pt muted，mt2，单行截断。
- 右侧：chevron_right 18pt `muted/70`，hover main。

真值 4 行数据：

| 文件名 | 副信息 |
|---|---|
| 久石让钢琴精选集.pdf | 24 页 · 导入于 9月5日 |
| Summer 原版扫描.pdf | 6 页 · 导入于 9月10日 |
| 坂本龙一合集.pdf | 41 页 · 导入于 8月28日 |
| 吉卜力钢琴谱.pdf | 18 页（无导入日期） |

### 3.5 导入虚线按钮

- 全宽，mt8，py14 px16，圆角 **12**，**1pt dashed 边框 #D4A24E/60**；bg `#D4A24E/5` → hover /10 → 按 /15。
- add 图标 20pt 琥珀（**hover 旋转 90°**，200ms）；文案 13.5pt medium 琥珀「导入 PDF（仅查看）」。

### 3.6 Footer（渐变吸底）

- 容器：pt8 pb8 px24，背景自下而上 `#1C1917 → #1C1917/95 → transparent` 三段渐变。
- 脚注：11.5pt muted 居中「PDF 不会出现在训练教材与判分流程中」。
- Home indicator：128×4，圆角全圆，main/25，mt12 mb4。

## 4. 颜色（hex + 语义 + 位置）

| Hex / 值 | config 名 | 使用位置 |
|---|---|---|
| `#1C1917` | bg | 页面底、图标容器底 |
| `#262220` | card | 切换框、行、callout（/70） |
| `#332D29` | cardBorder | 行/切换框边框 |
| `#D4A24E` | amberAccent | 选中段、PDF 图标、虚线框、强调词 |
| `#F5F2ED` | textMain | 主文字、状态栏 |
| `#9C948B` | textMuted | 副信息、未选中段 |

## 5. 交互热区与状态

- 返回（40×40 圆）：pop。
- 搜索（40×40 圆）：本屏搜索（搜索态待产品确认）。
- 双段：两项 flex-1，点按整行热区（高约 32）；「如何获取可练谱」内容页真值未画出，**待产品确认**（旧稿写的有序列表 1/2/3 在本画布不存在）。
- PDF 行：整行热区（约 68 高）→ 全屏只读 PDF 查看（缩放/翻页，无标注；阅读器形态待产品确认）。
- 导入按钮：全宽热区 → Files 选择器（多选）。
- 旧稿写「滑动删除」「空态文案」：真值 DOM 无，**待产品确认**。

## 6. 对旧 spec 的主要修正

1. **PDF 图标是琥珀 #D4A24E，不是红色 #C97064**（旧稿核心色值错误）；图标容器 40×40 圆角 8。
2. 「如何获取可练谱」是顶部双段切换的第二页，不是页内有序列表；教育列表内容真值未提供。
3. 导航右侧是搜索图标，不是 ＋。
4. Callout 为全周琥珀/30 细边框 ＋ #262220/70 底 ＋ 模糊，无左缘竖条；文案不同（「请转换为 MusicXML」，无「在 Mac 上」字样）。
5. 列表数据全部替换：4 个文件名/页数/日期按上表；「吉卜力钢琴谱.pdf」无日期。
6. 导入卡文案「导入 PDF（仅查看）」（旧稿「只存不判分」），琥珀虚线 ＋ /5 底 ＋ 图标旋转动效。
7. 字体正文为 Plus Jakarta Sans。
