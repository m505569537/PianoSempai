# ADR-0011 — V3 视频裁切发送给 Neko（Files API + 720p 片段）

- 状态：accepted
- 日期：2026-10-22
- 关联：backlog §7 V3；PRD M7「视频与隐私」；依赖 ADR-0010（录像闭环）、ADR-0001（多服务商链）。

## 背景

V3 曾是整块 blocked：无视频源、无裁切、无上传链路。ADR-0010 已落地录像与回看，视频源就绪；本轮补「裁切 → 上传 → 提问 → 删云端」这一段。S18b 是任何视频离开本机前的唯一闸口（选区间 → 核对提问 → 服务商明示 + 云端删除开关 → 确认发送）。

## 已核实的平台事实（火山方舟官方文档，2026-10-22 查证）

- Chat API `POST /api/v3/chat/completions` 的 `video_url` 支持两选一：`{"url": "公网URL 或 data:video/mp4;base64,..."}` 或 `{"file_id": "file-..."}`；`fps` 可取 0.2–5（抽帧率）。
- Files API：`POST /api/v3/files`（multipart：`purpose=user_data`、`file=@x.mp4`、`preprocess_configs[video][model]=doubao-seed-2-1-pro-260915`、`preprocess_configs[video][fps]=…`）→ 返回 `file` 对象；`GET /api/v3/files/{id}` 查 `status`（processing / active / failed）；`DELETE /api/v3/files/{id}` 删除。
- Base64 内联上限：视频 ≤50MB、请求体 ≤64MB，且**无法显式删除云端文件** —— 与「分析后删除云端视频（推荐）」开关冲突。
- 项目已有 `ContentPart.videoURL` 编码形态，但只支持 `url` 字段，需补 `fileId`；`ChatStore` 目前硬编码 `attachmentsJSON: "[]"`，纯文字。

## 决策（用户 2026-10-22 五项口径全拍）

1. **上传方式：Files API**（上传→`file_id`→提问→按开关删除云文件）。理由：只有 Files API 能让「分析后删除云端视频」开关真生效，且不受 Base64 50MB/64MB 限制。
2. **上传片段规格：720p H.264 约 2Mbps**（12 秒≈3MB）。手型细节够看；上传快、token/流量成本低。原录制保持 1080p 存档，不降质保存。
3. **三个预设 chips 全部做真功能**：「错误热点前后各 2 小节」（按当前曲目 `TakeAnalysis.hotspotMeasures` + 小节时长换算成时间）、「整段」、「手动」。
4. **时长：2–30 秒**；<2 秒行内红字报错、不发请求；上传中可取消、失败可重试。
5. **入口：只从 S16 回看页「问这段」与 Take 报告页发起**，带曲目/小节/分析上下文；全局问 Neko 不提供视频附件入口。

## 技术形态

- **裁切与转码**：`AVAssetExportSession`，`AVAssetExportPreset1280x720`，输出 `mp4` + `shouldOptimizeForNetworkUse`，`timeRange` = 用户选区；产物写临时目录，发送结束（成功/取消/失败）即删。转码不覆盖原视频。
- **热点→时间换算**：纯函数。输入 = 热点小节区间（1-based、来自 `TakeAnalysis.hotspotMeasures` 最新一条）、每小节时长（按 `take.tempoAvg` 或曲目 `referenceTempo` + 拍号计算；缺拍号按 4/4）、`take.videoStartedAtOffset`；输出 = 视频内秒数区间，前后各扩 2 小节，钳制到 [0, 视频时长]，失败（无热点/无视频/数据不足）返回 nil → chip 置灰（不造假区间）。
- **Files API 客户端**：`POST /api/v3/files`（multipart，手写 boundary，不引第三方库）→ 轮询 `GET /api/v3/files/{id}` 直至 `active`（超时 ~60s，可取消）→ `DELETE`。全部经 `URLSessionDataProtocol` 注入以便测试。
- **链式发送**：扩展 `ChainInput` 携带 `videoClip`（本地 URL + fps）；`ProviderChainRunner` 在每一跳：
  1. 该服务商是否支持视频输入（Ark 系 baseURL 判定）——不支持则记一跳「该服务商不支持视频」并跳到下一跳；
  2. 用**该跳自己的 key** 上传（不同账号的 `file_id` 不能跨账号使用）；
  3. 轮询到 `active` 后以 `parts` 发送（video_url.file_id + 文本）；
  4. 无论成功失败，若「删除云端」开启则 `DELETE` 该文件（删除失败只记诊断，不让整次提问失败）。
  服务商显示名一律运行时读取（`AIProvider.displayName`），不写死「火山方舟」；S18b 发送前展示链上第一个支持视频的服务商名 + 「失败时按链转移」，发送后消息气泡显示实际命中（已有 `providerModel`）。
- **数据**：`ChatMessage.attachmentsJSON` 落 `ChatAttachment`（本地不保存视频副本，只存 `fileId`（如需追溯）、区间秒、时长、命中服务商）；消息本体仍是文本回答。
- **隐私**：视频只在用户点「确认裁切并发送」后才离开本机；纯文字/MIDI 提问永不带附件；开关默认 ON；取消/失败不残留临时文件。

## 红线

- 不整段上传；必须走裁切闸口。
- 不造假服务商名、上传进度、云端删除结果（失败如实提示「云端文件可能仍存在」）。
- AI 仍只有建议权，不写课程/判分状态。
- 视频不落库、不进导出包、不进相册（相册写回已在 ADR-0010 保存时完成）。

## 非目标

V7 Zf 相册导入、MediaPipe 手型、视频转文字摘要、多段视频一次提问、云端长期留存。
