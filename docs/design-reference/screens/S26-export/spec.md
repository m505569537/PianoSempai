# S26 导出我的全部数据（修订版 · 以 code.html 为真值）

- Screen ID：`3d9e8836b9a2441897d3ed30b0cc2a79`
- 画布元数据：2560×2048 DESKTOP；实际内容 390 逻辑宽（body 全宽 flex，内容由 `px-5` 控制，最大即 390），按 390 逻辑宽取真值
- 真值文件：/tmp/stitch-truth/screens/3d9e8836b9a2441897d3ed30b0cc2a79/code.html
- Status: Revised

## 1. 用途

生成可恢复全量 zip（课程状态/take/MIDI/乐谱/笔记；视频可选），或仅 PDF；底部 dock CTA 导出到「文件」App + 从备份恢复文字按钮。

## 2. 颜色令牌

| Hex / 值 | 语义名 | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark 主背景 | body、header/footer（梯度）、格式选择器容器底 |
| `#262220` | cardDark 卡片底 | 全部 4 张内容卡、选中格式按钮底 |
| `#332D29` | borderDark 发丝边 | 卡边、导航下边（/60）、分隔线（/60、/70）、未选 toggle 轨道、home indicator（primary/25） |
| `#3d3732` | borderMuted（config 令牌） | config 定义，DOM 未使用 |
| `#D4A24E` | amberAccent | 图标盒（底 /10）、已选勾选圆、选中格式（底无、字/边 /40）、安全卡左边 3pt、主 CTA 底（hover `#c99540`） |
| `#F5F2ED` | textLight | 标题、清单名、toggle 行名（home indicator /25） |
| `#9C948B` | textMuted | 介绍文、卡头、右值、视频行、toggle thumb、未选格式、恢复按钮 |
| `#211E1C` | 视频行底（未勾） | 视频清单行底（/60） |
| `#231F1D` | 包含视频 switch 行底 | toggle 行整行底（比 card 暗一档） |
| `#c99540` | CTA hover | 导出按钮 hover 底 |

字体：标题/卡头 Noto Serif SC（卡头实际带 uppercase tracking-wider，但属 serif）；正文 Plus Jakarta Sans；右值 JetBrains Mono + tabular-nums。

## 3. 整体结构

- body：纵向 `justify-between`，min-h 844。
- 上部容器：`flex-1` 纵向 `pb-8`（32）。
- 状态栏：`px-7 pt-3.5 pb-2`，9:41 14pt semibold primary；右组 gap 8，12pt：信号 4 格 SVG 16×14、WiFi 16×14、电池 20×10（圆角 3，内芯宽 75%，右凸点 2pt）。
- 导航头：`px-5 py-3`，下边线 border/60。
  - 返回按钮 36×36（-ml-2），chevron 24 stroke 2.2 amber；标题 ml 4，**19pt bold serif** tracking tight「导出我的全部数据」。
- main：`px-5 pt-4`，卡间 `space-y-4`（16）。
- Bottom dock：`px-5 pt-3 pb-6`（24），背景纵向渐变 surface→transparent（via surface），`space-y-3`（12）；home indicator 128×4 primary/25 mt 8。

## 4. 逐卡规范

### 4.1 介绍卡

- card / border / 圆角 16 / `p-4` / shadow-sm。
- 横向：图标盒 32×32 圆角 12（rounded-xl），底 amber/10，上传云图标 16 amber（mt 2）；右文 13.5pt muted leading-relaxed，逐字：
  > 你的所有数据只存在这台手机上。导出为一个 zip，可用于备份或换新机恢复。

### 4.2 导出内容清单卡

- card / border / 圆角 16 / overflow-hidden / shadow-sm。
- 卡头：`px-4 py-3`，下边 border/70：左 13pt semibold muted uppercase tracking-wider「导出内容」；右 12pt medium amber「共 5 项已勾选 · 约 54 MB」。
- 行通用：`px-4 py-3`（12 上下），行间 border/60，左右分布；左组 gap 12：标记 20×20 + 名称 14pt primary 常规；右值 13pt mono muted tabular。
- 已选标记：20×20 **圆形**实底 amber，内含对勾 14 stroke 2.8 surface。
  1. 「课程与路线状态」`12 KB`
  2. 「Take 元数据与分析结果」`4.8 MB`
  3. 「原始 MIDI 事件流（128 条）」`31 MB`
  4. 「乐谱文件（23 个）」`18 MB`
  5. 「练琴笔记」`96 KB`
- 视频行（未勾，起点 `items-start`）：底 `#211E1C`/60。
  - 左：20×20 **方形**圆角 4，1px muted/50 空框（mt 2）；文案：14pt muted「视频（8 条，可选）」+ 11.5pt muted/70「体积较大，默认不包含」mt 2。
  - 右 13pt mono muted/70 `642 MB`。
- Toggle 行：底 `#231F1D`，`px-4 py-3`。
  - 左：14pt medium primary「包含视频」+ 11.5pt muted「每曲仅保留最近 8 条」mt 2。
  - iOS 风格开关：宽 44（w-11）× 24（h-6），圆 99，**OFF 轨 `#332D29`**，`p-0.5`；thumb 20×20 圆 muted `#9C948B`，translate-x 0，transition 200ms。

### 4.3 导出格式卡

- card / border / 圆角 16 / `p-4` / shadow-sm，`space-y-3`（12）。
- 卡头 13pt semibold muted uppercase tracking-wider「导出格式」。
-  Segmented：surface 底，`p-1` 4，圆角 12，1px border/70；2 列 gap 8。
  - 左选中：`py-2.5 px-3`（高约 40），圆角 8（rounded-lg），card 底，**1px amber/40 边**，13pt semibold amber，shadow-sm，带对勾 14pt icon（同色）+「完整包（可恢复）」。
- 右未选「仅报告 PDF」：圆角 8，13pt medium muted（hover primary），无边无背景。

### 4.4 安全卡

- card / border / **左边 3pt amber（border-l-[3px]）** / 圆角 16 / `p-3.5`（14）/ shadow-sm。
- 左盾牌 16 amber（mt 2）；右文 12.5pt muted leading-relaxed，逐字：
  > 导出包不含 API Key；分享 zip 前请确认接收方可信，里面有你的全部弹奏记录。

## 5. Bottom dock CTA

- 主按钮：全宽，**高 48**，圆角 12，amber 底（hover `#c99540`），15pt semibold surface；下载到文件图标 16 stroke 2.2 +「导出到“文件” App」；shadow-lg amber/10；按压缩放 0.985。
- 文字按钮：全宽 `py-1`，13.5pt medium muted（hover primary），逐字「从备份恢复」。
- home indicator：128×4 primary/25，mt 8。

## 6. 全部状态与交互热区

- 返回 36×36；清单前 5 行整行可点（切换勾选，最小高约 48）；视频行整行联动 toggle；开关热区 44×24 起留 44×44 命中区。
- Format segmented 两个 8pt 圆角选项热区；选中态 card 底 + amber/40 边。
- 旧 spec 的「空间不足行内 danger 禁止导出」「打包进度（正在打包 54MB…可取消）」html 无 → **待产品确认**。
- 旧 spec 的恢复流程（选 zip → 差异计数 → 二次确认 + 恢复前快照）html 仅给出入口，属后续页 → **待产品确认**。
- 旧 spec「合计 54 MB（不含视频）」独立合计行 html 无（真值在清单卡头）→ 以 html 为准。

## 7. 相对旧 spec 的主要修订

1. 补全精确参数：390 宽、卡圆角 16、主 CTA 高 48 圆角 12、dock pb 24、区块间距 16、行上下内边 12。
2. 复选标记真值：已选为 **20pt 圆形 amber 实底对勾**（旧 spec「复选 22pt」，尺寸/形状错）；视频未选为 20pt 方形圆角 4。
3. 视频行与 toggle 行各有独立深色底（`#211E1C` / `#231F1D`），旧 spec 仅写整行 0.6 透明。
4. Toggle OFF 轨道 `#332D29`，thumb `#9C948B` 20pt；旧 spec 无参数。
5. 格式 segmented 真值表面 surface + `p-1` 圆角 12 + border/70，选中项 card 底 amber/40 边；文案「完整包（可恢复）」。
6. 安全卡为 3pt amber 左缘卡（旧 spec「surface-low」笼统且未锁定左缘）。
7. 标题 19pt bold serif；dock 渐变背景；无独立合计行。
