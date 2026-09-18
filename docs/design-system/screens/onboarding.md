# 首次链路 Onboarding（系统层）

覆盖画布：S01 欢迎 / S02 权限 / S03 MIDI 向导 / S04 定级自评 / S05 定级结果 / S07b 空状态。
视觉真值见 `design/reference/screens/S01..S05,S07b`；数据契约见 `data-model.md`。

## 流程

```
首启 → S01 欢迎
      → S02 权限（蓝牙必授权；相机/通知可跳过，入口在 S23 可补）
      → S03 MIDI 向导
           step1 准备 → step2 连接 V70 → step3 验证（弹任意音，三格实时信号）
           可 ✕ 跳过（落 S07b，连接胶囊红点）
      → 已有 PlacementResult ? S07 : S07b
S07b「开始定级」→ S04 自评(1min) → 视奏2段(无独立稿，S11 简化评估态)
      → 力度校准(2min，复用 S24 信号条) → S05 结果 → 生成第1周 DailyPlan → S07
```

## 系统权限与 Info.plist

- NSBluetoothAlwaysUsageDescription：同 S02 蓝牙卡文案（判分唯一依据）。
- NSCameraUsageDescription / NSMicrophoneUsageDescription：仅"录给 AI 看"主动模式；拒绝不影响任何核心功能（MIDI-only）。
- 通知：本地通知（周日周报/20:30 可选），无推送 token 出站。

## MIDI 连接行为（M1）

- BLE-MIDI 自动发现（CoreMIDI/MIDICapacity 封装）；USB-B 方口同栈。
- 事件：Note On/Off、velocity、CC64；hostTime 时间基；BLE 丢 Note Off 用 velocity=0 + 超时截断。
- step3 验证通过标准：2 秒内收到 ≥1 个 Note On 且 velocity 有效。
- GarageBand 验证按钮：跳外部 app（URL scheme 仅在可用时显示）。

## 定级业务规则（M3 前置）

- 自评只作选段先验，不直接决定插入点；插入点由视奏 + 规则引擎产出（PlacementResult）。
- 力度校准产出 VelocityCalibration（pp/mp/mf 映射），后续所有力度维度按个人曲线归一。
- 结果可重测（替换最新结果，保留历史一次撤销）；S05 后由课程引擎建拜厄/哈农任务序列，599 仅存 projectedWeek，不创建任务。
- 未完成定级退出：保存进度（selfReport/视奏段状态），S07b CTA 变"继续定级"。

## 数据写入

- onboardingCompleted 写 AppSettings；Placement* 三表；连接日志仅内存/本机诊断。
- Key 不在本链路采集（S25 首次需要 AI 时才引导）。

## 异常与空路径

- 蓝牙拒绝：S03 step2 显示系统设置深链；允许继续逛 S07b/S08。
- 视奏中断连：走 S11b 同逻辑，定级段可重做该段。
- 无网络：全链路可用（定级纯本地）。
