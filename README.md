# PianoSempai

纯自用钢琴自学陪练 app（iPhone / iOS 17+ / SwiftUI + SwiftData）。产品与设计真值见 `docs/`。

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
