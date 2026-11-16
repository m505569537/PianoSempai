# 随包谱接入（BundledScores）

随 app 分发的教材谱放在 `PianoSempai/Resources/BundledScores/`，命名由
`BundledScore.resourceName(book:number:)` 决定：

| 教材 | 资源名 | 当前覆盖 |
|---|---|---|
| 拜厄 | `beyer_01` … `beyer_106` | 106/106 ✅ |
| 哈农 | `hanon_01` … `hanon_20` | 20/20 ✅ |
| 车尔尼599 | `c599_01` … `c599_10` | **1/10（No.1 已接；2–10 待补）** |

> 谱源红线（PRD「版权红线」）：内置只放**公版**曲目，谱源限 Mutopia / IMSLP /
> MuseScore 导出。不要塞来路不明或明确标注版权的第三方排版。

---

## 车尔尼 599 接入步骤

目录里 599 只编排了**前 10 首**（编号 1–10，对应 Op.599 第 1–10 条）。

### 1. 从 MuseScore 导出

> MuseScore.com 需要登录且有人机验证，脚本无法代抓，必须手动导出。

1. 登录 [musescore.com](https://musescore.com/sheetmusic?text=czerny%20599)，搜 `Czerny 599`
2. 逐首打开 Op.599 No.1 … No.10，确认是**双手钢琴谱**（有低音谱表）
3. 每首点 **Download → MusicXML (.mxl)**（免费账号可能限次数，分几次下）

> 若某首只有「Sibelius / PDF」或需要 Pro，换一个上传者的版本；优先选标注
> Public Domain 的。也可以改用 `.musicxml` 未压缩格式。

### 2. 丢进一个目录，跑脚本

```bash
mkdir -p ~/Downloads/c599
# 把 10 个 .mxl 放进去后：
python3 Scripts/import_bundled_scores.py --book 599 --src ~/Downloads/c599 --dry-run
```

`--dry-run` 先看清单：每首会打印推断到的目标编号、小节数、音符数、单/双谱表。
确认无误再去掉 `--dry-run` 真正落盘：

```bash
python3 Scripts/import_bundled_scores.py --book 599 --src ~/Downloads/c599
```

脚本会做这些事：

- `.mxl` 按 `META-INF/container.xml` 解出真正的 MusicXML
- 从文件名推断编号（取最后一个独立数字，`Op599 No.3` → 3）
- 编号不对时用 `--map 源号=目标号` 覆盖，例如 `--map 3=5`
- 写盘前校验：XML 可解析、有小节、有音符；重名/越界/空谱都会报错而不是静默写坏文件
- 打印缺少哪些编号

### 3. 注册进代码（补新编号时唯一要改的地方）

`BundledScore.resourceName` 已支持 599，但**只对已落盘的编号给资源名**：

```swift
static let czerny599BundledNumbers: Set<Int> = [1]   // ← 补一首就加一个编号
```

加编号后**必须**跑 `xcodegen generate`（新 .musicxml 要重新进 copy-resources 阶段），
再跑全量测试。`BundledScoreTests.testEveryDeclaredCzerny599NumberExistsInBundle`
会断言「声明了的编号在 bundle 里真能取到文件」——忘了放文件会立刻红，不会拖到练琴时炸。

> ⚠️ 顺序很重要：**先落盘谱文件、再改这个集合**。反过来会让 `ScoreAvailability`
> 报 `bundledScore` 而 `Bundle.main.url` 取不到，练习室变成「有谱可用却加载失败」。

### 4. 验收

- 曲库 → 车尔尼599 条目不再显示「自由弹奏（不判分）」，能进练习室
- 练习室谱面正常渲染、光标能跟、能分手
- 失误标记抽屉（S13b）有真实谱条

---

## 以后要加别的教材

在 `Scripts/import_bundled_scores.py` 的 `BOOKS` 里加一行 `"849": ("c849", range(1, 31))`，
再按上面第 2–4 步走。
