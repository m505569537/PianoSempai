# PianoSempai

纯自用钢琴自学陪练 app（iPhone / iOS 17+ / SwiftUI + SwiftData）。产品与设计真值见 `docs/`。

## 当前状态（2026-11-17）

| 项 | 值 |
|---|---|
| 版本 | 1.0.0（`MARKETING_VERSION` 单一来源） |
| 代码规模 | 125 个 Swift 文件 / 约 4.4 万行 |
| 测试 | **931 / 0**（67 个测试文件，模拟器 `iPhone 17`） |
| 随包谱 | **127 份**：拜厄 106/106、哈农 20/20、车尔尼599 **1/10** |
| 页面 | Onboarding / Today / Library / Practice / Archive / Notes / EarTraining / AI / Settings |
| 未完成 | 599 No.2–10（待导出）；指法数据源（P17）；深色谱面（P16） |

进度与待办唯一登记本：`docs/backlog.md`（含逐批变更记录）。待补项都在那里的表格里。

## 构建

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成（先 `brew install xcodegen`）：

```bash
xcodegen generate
```

### 音源（首次 clone 必做）

示范/试听用的 `MuseScore_General.sf2`（约 206MB）不入 git（超过 GitHub 单文件上限），
首次 clone 后先取回：

```bash
Scripts/fetch_soundfont.sh
```

脚本从 MuseScore 官方源下载并做 sha256 校验。缺文件时 build 仍通过，只是示范播放会
安全禁用（ADR-0002）。

### 校验脚本

```bash
# 1) 模拟器 build 必须 0 error
# 用 UDID 精确指定：多运行时并存时 `name=iPhone 17 Pro` 会被归一成 OS:latest，
# 而该机型未必装了最新运行时，name 匹配直接失败（exit 70）。
# 查 UDID：xcrun simctl list devices available | grep iPhone
SIM_ID=<你的模拟器UDID>
xcodebuild -skipMacroValidation -scheme PianoSempai -destination "platform=iOS Simulator,id=$SIM_ID" build

# 2) 单元测试
xcodebuild -skipMacroValidation -scheme PianoSempai -destination "platform=iOS Simulator,id=$SIM_ID" test

# 3) Swift 语法级严格检查（warnings 当 error；工程设置里 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES）
swiftc -swift-version 5 -warnings-as-errors $(find PianoSempai -name '*.swift') -parse
```

> 1+2 也可直接跑 `Scripts/build.sh`（自动选第一台已 boot 的 iPhone，或用 `SIM_ID=` 覆盖）。
> 部署目标仍是 iOS 17.0，模拟器版本不影响构建口径；只有 3) 完全不依赖模拟器。

### 构建卡住时（已定位根因）

2026-11-18 用 `sample` 采样卡住的 `xcodebuild` 才定位清楚，**不是代码问题，是 Xcode 26 构建引擎**：

- 主线程停在 `waitForBuildWithBuildLog`，唯一子进程 `SWBBuildService` **0% CPU**，
  且没有任何 `swift-frontend` —— 说明它不是在编译，而是死锁在
  `PruneExplicitPrecompiledModules`（显式模块裁剪）阶段。
- **规避**：加 `SWIFT_ENABLE_EXPLICIT_MODULES=NO`。实测同一构建从「卡 30 分钟无进展」
  变成「150 秒完成」。`Scripts/build.sh` 与 `Scripts/test.sh` 已内置该参数。
- **放大因素**：磁盘可用 <20GB 时该阶段显著变慢（实测 460GB 盘只剩 17GB、使用率 96%）。
  先 `df -h /System/Volumes/Data` 看一眼，清理见下。

另有两个独立的假故障：

- `Unable to find a device matching the provided destination specifier`：
  `simctl` 里设备明明是 Booted，但 `xcodebuild` 那一次解析不到——CoreSimulator 收尾竞态。
  等 `simctl bootstatus <UDID> -b` 之后再 `sleep 3` 可稳定复现成功（`Scripts/test.sh` 已内置）。
- `The test runner hung before establishing connection`：模拟器子系统状态坏了，
  `xcrun simctl shutdown all` 后重新 boot 即可。

仍无效时再重启模拟器服务（**不要当常规手段**，会打乱 destination 解析）：

```bash
pkill -9 -f xcodebuild
xcrun simctl shutdown all
killall -9 com.apple.CoreSimulator.CoreSimulatorService
sleep 10 && xcrun simctl boot <SIM_ID> && sleep 20
```

再用 `uptime` 确认负载回落（8 核机器正常 < 20；实测出现过 load 283，是残留 app 在模拟器里空转）。
`timeout` 在 macOS 上不存在（`exit 127`），别用它包 xcodebuild。

> 日常直接跑 `Scripts/test.sh`：它会先检查磁盘/负载/模拟器，再带正确参数跑测试，
> 失败时打印对应诊断，不用每次靠人猜。

## 目录

```
project.yml            # XcodeGen 定义
PianoSempai/
  App/                 # 入口与根视图
  DesignSystem/        # Nocturne 色板（Assets.xcassets）、字体语义层、复用组件
  Features/            # Onboarding / Today / Library / Practice / Archive / Settings
  Models/              # SwiftData 模型
  Services/            # MIDI、ScoreRendering、TakeStore、Export、Clock
  Resources/           # Assets.xcassets、示例 MusicXML 等
Tests/PianoSempaiTests/
docs/                  # PRD、P1 brief、视觉系统、画布 spec、数据契约
```

## DEBUG 调试入口（Release 编译期剔除）

真机上不点屏幕就能进到指定状态，用于核对谱面/判分链路：

```bash
# 直达练习室预览随包谱（book 可写中文教材名）
xcrun devicectl device process launch --device <UDID> com.eeexu.pianosempai \
  --ui.practice c599:1 --ui.simulated
```

| 参数 | 作用 |
|---|---|
| `--ui.practice <book>:<number>` | 直接打开练习室并加载该随包谱（如 `c599:1`、`拜厄:1`） |
| `--ui.simulated` | 切到模拟 MIDI 源（真琴不在手边时验证谱面/跟随） |
| `--ui.hand both\|right\|left` | 初始分手态（核对左右手着色） |
| `--ui.tab.<tab>` | 启动后停在指定 tab：`library` / `practice` / `archive` / `settings` |
| `--ui.skipOnboarding` | 跳过引导 |

## 发布到 App Store

完整命令与两个坑（云签名、版本号必须与 ASC 记录一致）见 **[`docs/release.md`](docs/release.md)**。
当前状态：构建 `1.0.0 (2)` 已上传并挂到版本，**上架信息（描述/关键词/支持网址/截图）尚未填写**。

## 真机截屏（不用手点）

```bash
xcrun devicectl device capture screenshot --device <UDID> --destination /tmp/s.png
```

注意：**iPhone 镜像（Mac 上的「iPhone 镜像」App）占用手机时，手机本体永远停在锁屏**，
此时 `devicectl` 只能截到锁屏。两条路：
1. 退出镜像并解锁手机，直接 `devicectl` 截图；
2. 保持镜像，用窗口 ID 单独截取（窗口被别的 App 挡住也能截到）：

```bash
screencapture -l<窗口号> -o -x /tmp/win.png     # 窗口号用 CGWindowListCopyWindowInfo 查
```

## 真值与红线

- 文案：`docs/design-reference/foundation/visual-system.md` §9 + 各画布 spec
- 行为：`docs/PRD.md` + `docs/design-system/screens/*.md` 域契约
- 数据：`docs/design-system/data-model.md`
- 工程红线（违反即返工）：`docs/P1-BRIEF.md` §4
- 真机验收手册（V10 相机 / V11 视频发送真 key / V12 Zf 相册）：`docs/acceptance/2026-10-22-device-acceptance.md`

## 真机安装（Hermes 可直接执行）

```bash
# 1) 构建到真机（自动申请描述文件；无需 Xcode 界面）
xcodebuild -project PianoSempai.xcodeproj -scheme PianoSempai -configuration Debug \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates \
  -derivedDataPath build/device build

# 2) 安装 + 启动
xcrun devicectl device install app --device <UDID> build/device/Build/Products/Debug-iphoneos/PianoSempai.app
xcrun devicectl device process launch --device <UDID> com.eeexu.pianosempai
```

- `UDID`：`xcrun devicectl list devices`（用户机 = `eee xu的iPhone` / iPhone 16 Pro）
- 免费 Personal Team（4P68RDUY3F）签出的描述文件**有效期仅约 1 天**，过期后 App 打不开，重跑上面两条即可；证书本身到 2027-06-18
- 首次安装若提示未受信任：设置 › 通用 › VPN与设备管理 › 开发者 App 里信任 `505569537@qq.com`
- `build/` 已在 `.gitignore`，真机构建不会污染工作区
