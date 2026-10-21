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
# ⚠️ 用设备 UDID 精确指定：本机装了 iOS 27.0 运行时后，name=iPhone 17 Pro 会被
# 归一成 OS:latest=27.0 而该机型只有 26.5 运行时，name 匹配直接失败（exit 70）。
# UDID 用 `xcrun simctl list devices available | grep "iPhone 17 Pro"` 查询。
xcodebuild -skipMacroValidation -scheme PianoSempai -destination 'platform=iOS Simulator,id=EC2A677A-33E9-4EF7-92AB-12438A662697' build

# 2) 单元测试
xcodebuild -skipMacroValidation -scheme PianoSempai -destination 'platform=iOS Simulator,id=EC2A677A-33E9-4EF7-92AB-12438A662697' test

# 3) Swift 语法级严格检查（warnings 当 error；工程设置里 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES）
swiftc -swift-version 5 -warnings-as-errors $(find PianoSempai -name '*.swift') -parse
```

> 本机 Xcode 26.6 只有 iOS 26.5 运行时（iPhone 17 系列），没有 iPhone 16 Pro 模拟器，
> 故 build destination 用 `iPhone 17 Pro`。部署目标仍是 iOS 17.0，真机/模拟器不受影响。
> 2026-10-12 更新：机器现已加装 iOS 27.0 运行时；`name=iPhone 17 Pro` 因 OS:latest 归一失配，
> 命令统一改用模拟器 UDID（见上方注释）。

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
