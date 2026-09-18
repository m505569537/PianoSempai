# 我的 Settings（系统层）

覆盖：S23 设置 / S24 MIDI 诊断 / S25 方舟 Key / S26 导出恢复。

## S23 行为单元

- 设备：连接状态（首行实时）、S24、力度校准（同 onboarding 校准流程，结果覆盖 VelocityCalibration 并标记时间）、视频保留规则（每曲 8 条；可调 3/8/不自动清；仅作用 active）。
- 课程与提醒：路线总览（拜厄/哈农/599 状态只读 + 预计周）、通知配置（周报开关+周日 21:00；工作日提醒 20:30 开关；只用本地通知）、周目标（次×分钟，仅统计展示用，不产生惩罚）。
- AI 助教：S25；模型版本展示（文字/视觉两行）；S19 笔记入口。
- 数据：S26；恢复（选 zip → 差异计数 → 确认 → 自动恢复前快照）；存储占用（active 视频 LRU 清理入口）。
- 关于：隐私与六条红线静态页（内容取 PRD 第 6 章）、版本号。
- 明确没有：账号、登录、云同步、会员、商店、反馈社区。

## S24 MIDI 诊断

- 实时订阅 CoreMIDI 流：最近音名/MIDI note、velocity、CC64、hostTime；设备信息（传输类型/估算延迟/事件计数）。
- 全部本机内存展示，不持久化、不上传；"没信号"是引导不是错误。
- V70 特性备注：BLE 已验证；USB-B/GarageBand 蓝牙弹音待用户真机确认（UI 不给未经验证的延迟承诺值）。

## S25 API Key

- Keychain item `ark.apiKey`；UI 掩码末 4 位；替换即发最小校验请求（标准 /api/v3，P3 spike 确认；coding 套餐入口不用于本 app）。
- 配置：endpoint、textModel（doubao-seed-2.0-pro）、visionModel（豆包视觉理解，版本 id 可更新不写死）。
- 删除 Key：二次确认；删除后 AI 入口降级（S18 显示未配置引导）。
- 安全：Key 不入日志、崩溃信息、导出包、AI 请求之外的任何出站。

## S26 导出/恢复

- zip 内容：SwiftData 导出 JSON（课程/take 元数据/分析/笔记/设置）、midi/、scores/、pdfs/、video 可选；清单与大小实时统计。
- 格式开放（.mid/.musicxml/.mxl/.pdf/.mp4/.json）；无 Key；无设备绑定加密（用户可自选系统文件加密）。
- 恢复策略：整库恢复（非合并）；恢复前自动快照到 exports/；恢复后重启数据栈。
- 仅 PDF：月报 + take 汇总报告（无视频）。
