# S01 欢迎页 Welcome（修订版 · 以 Stitch code.html 为真值）

- Screen ID：`ae612d6f748c438f8c1eca4e51ddaea7`
- 画布：Stitch 元数据 MOBILE 780×1768；HTML 实际逻辑画布 **390×844 pt**（`max-w-[390px] h-[844px]`），全部数值按 390 基准。
- 字体：Noto Serif SC（serif）/ Noto Sans SC（sans）；图标 Material Symbols Outlined（`FILL 0, wght 300`）。
- 注意：本屏 Tailwind 自定义了 borderRadius（`DEFAULT 2 / lg 4 / xl 8 / full 12`，单位 pt），不要用 Tailwind 默认圆角值。

## 1. 页面结构总览

```
main 390×844，flex col justify-between，左右内边距 20pt（px-margin-sm），pb 8pt，背景 #161311
├ 环境光层（z-0，不拦截点击）
│   ├ amber-bloom：整屏径向渐变，圆心(50%,32%)，rgba(212,162,78,0.12) → 70% 处 rgba(22,19,17,0)
│   └ 顶部光晕：288×288pt 圆，top −64pt、水平居中，#D4A24E 10% 透明，blur 64pt
├ 状态栏 header：h44，pt12，左右各 1pt 内边距
├ 内容区：flex-1，纵向 flex，justify-between，上下 2pt 内边距
│   ├ 品牌区：徽标 96pt 容器（SVG 80pt）+ 标题 + slogan
│   ├ 三特性列表：3 张带描边卡片，卡间距 8pt
│   └ CTA 区：全宽琥珀按钮 + 免责两行小字
└ footer：版本号 11pt + Home Indicator 128×4pt
```

## 2. 状态栏

- 高 44pt，pt 12；9:41 与右侧图标纵向居中、两端对齐。
- 左：`9:41`，Noto Sans SC，**12pt，weight 500**，字距 −0.025em（tracking-tight），色 #E9E1DD。
- 中：仿灵动岛胶囊，**96×20pt**，圆角 12pt，填充 #100E0C 80%，1pt 描边 #4F4537 30%；内边距 8pt，两个元素：6×6pt 圆点 #D4A24E 40%、10×4pt 胶囊条 #383432。
- 右：系统图标组，间距 6pt；蜂窝 `signal_cellular_alt` 15pt、`wifi` 15pt（不透明度 80%），`battery_full` 17pt（不透明度 90%），色均 #E9E1DD。

## 3. 品牌区（水平居中，mt 8pt）

### 3.1 徽标

- 外容器 **96×96pt**，居中，mb 16pt；内含一层绝对定位的全尺寸圆形光晕：#D4A24E 10%、blur 12pt。
- SVG 本体 **80×80pt**（viewBox 100×100），投影 `0 4 16 rgba(212,162,78,0.35)`。构成：
  - 猫头外轮廓：描边 **#D4A24E，线宽 1.75**，圆角连接/端点（round），无填充。
  - 胡须（左右各 2 根）：#D4A24E，线宽 1.25，不透明度 60%。
  - 面部钢琴键床：矩形 34×24（viewBox 单位），x33 y44，rx 2；填充 **#1C1917 80%**，描边 #D4A24E 线宽 1.5。
  - 白键分隔线 4 条：#D4A24E 不透明度 50%，线宽 1。
  - 黑键 3 个：填充 #D4A24E，每键 4.2×13。
  - 鼻尖圆点：#D4A24E，r 1.5。
- SwiftUI 落地：整套路径用 SwiftUI `Path`/SVG 矢量资源复刻，线宽按 80/100 比例换算（外轮廓 ≈1.4pt）。

### 3.2 文字

- 标题 `PianoSempai`：Noto Serif SC，**32pt / 行高 40pt / weight 500**，字距 −0.01em，色 #E9E1DD；投影 `0 2 12 rgba(212,162,78,0.20)`。
- Slogan `你的钢琴前辈，住在手机里`：Noto Sans SC，**15pt / weight 400**，字距 +0.025em（tracking-wide），色 #9C8F7E，mt 6pt。

## 4. 三特性列表

- 容器：左右各 4pt 内边距；`my-auto`（在内容区中占弹性中段）；卡间距 **8pt**。
- 每张卡（3 张同构）：
  - 容器：圆角 **4pt**；填充 #221F1D **60% 不透明度**；1pt 描边 #4F4537 30%；**内顶部高光阴影 `inset 0 1 0 rgba(255,255,255,0.04)`**；内边距：左右 16pt、上下 14pt。
  - 左图标盒：**32×32pt**，圆角 2pt，填充 #2D2927，1pt 描边 #D4A24E 20%；图标 19pt，色 **#F3BE67**（注意：不是 #D4A24E）。
  - 图标盒与文案间距 14pt。
  - 主文案：Noto Sans SC，**14pt weight 500**，色 #E9E1DD，字距 0。
  - 右侧注记：等宽字体（font-mono），**11pt**，大写，字距 +0.05em，色 #4F4537。
- 三行内容（逐字）：
  1. 图标 `piano` ｜ `只听 MIDI，不乱猜` ｜ `SIGNAL`
  2. 图标 `menu_book` ｜ `课程锚定拜厄·哈农·车尔尼` ｜ `OPUS`
  3. 图标 `lock` ｜ `数据只在你手机里` ｜ `LOCAL`
- 交互：HTML 中为纯展示 `div`（仅 hover 填充变 #2D2927），**整行无点击行为**；iOS 不做高亮态。右侧英文注记装饰性，可省略但不得改中文。

## 5. CTA 区（pt 8，pb 4）

- 主按钮「开始」：
  - 全宽；圆角 **8pt**；填充 **#D4A24E**（hover #E2C37D）；文字色 #100E0C。
  - 内边距上下 16pt；Noto Sans SC，文字 **17pt weight 700**，字距 +0.1em；文字左还有 4pt 缩进。
  - 文案与图标间距 8pt；右箭头 `arrow_forward` 20pt weight 700。
  - 阴影 `0 4 24 rgba(212,162,78,0.22)`；pressed 缩放 0.985（150–200ms）。
- 免责小字：`继续即表示同意：视频只在你主动录制时工作，手型建议永不决定过关`
  - **11pt weight 400**，色 #9C8F7E，居中，行高 1.625（leading-relaxed），mt 12pt，左右 1pt；最多两行。

## 6. Footer

- 版本行 `v0.1.0 · 纯自用，无账号，无服务器`：**11pt**，色 #9C8F7E **60%**，字距 +0.05em，mb 8pt。
- Home Indicator：**128×4pt**，色 #E9E1DD 30%，圆角全圆，mt 4pt。

## 7. 颜色清单（hex / 语义 / 落点）

| Hex | 语义 | 使用位置 |
|---|---|---|
| `#161311` | surface 页面底色 | main 背景、环境渐变终点 |
| `#100E0C` | surface-container-lowest | 按钮文字、灵动岛填充(80%) |
| `#E9E1DD` | on-surface 主文字 | 标题、特性文案、状态栏、Home 条(30%) |
| `#9C8F7E` | outline 弱文字 | slogan、免责字、版本号 |
| `#4F4537` | outline-variant 描边 | 卡片描边(30%)、灵动岛描边、英文注记 |
| `#221F1D` | surface-container | 特性卡填充(60%) |
| `#2D2927` | surface-container-high | 图标盒底、特性卡 hover |
| `#383432` | surface-variant | 灵动岛内部胶囊条 |
| `#D4A24E` | primary-container 琥珀主色 | 按钮、徽标全部描边、光晕 |
| `#F3BE67` | primary 浅琥珀 | 特性行小图标 |
| `#E2C37D` | tertiary | 按钮 hover |
| `#1C1917` | （内联 hex，未在本屏 config 命名） | 徽标钢琴键床填充(80%) |

## 8. 动效与红线

- 徽标可做极慢琥珀呼吸（透明度 0.85↔1.0，周期 ≥3s）；旧 spec 提到该动效，HTML 未内置，**保留为建议项**，进入按下前结束。
- 无横屏；无登录/注册/账号入口；按钮下两行告知字（视频最小必要 + 手型不裁判）不可删。
- 所有文案（标题、slogan、三特性、SIGNAL/OPUS/LOCAL、按钮、小字、版本行）逐字锁定。
