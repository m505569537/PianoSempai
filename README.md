# PianoSempai

纯自用钢琴自学陪练 app（iPhone / iOS 17+ / SwiftUI + SwiftData）。产品与设计真值见 `docs/`。

## 构建

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成（先 `brew install xcodegen`）：

```bash
xcodegen generate
```

### 校验脚本

```bash
# 1) 模拟器 build 必须 0 error
xcodebuild -scheme PianoSempai -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 2) 单元测试
xcodebuild -scheme PianoSempai -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# 3) Swift 语法级严格检查（warnings 当 error；工程设置里 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES）
swiftc -swift-version 5 -warnings-as-errors $(find PianoSempai -name '*.swift') -parse
```

> 本机 Xcode 26.6 只有 iOS 26.5 运行时（iPhone 17 系列），没有 iPhone 16 Pro 模拟器，
> 故 build destination 用 `iPhone 17 Pro`。部署目标仍是 iOS 17.0，真机/模拟器不受影响。

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
