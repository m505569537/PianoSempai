# PianoSempai · Stitch 屏幕登记（定稿 2026-09-18）

项目 ID：`4122205180823255125`（Stitch: PianoSempai）
设计系统：Nocturne Minimal `assets/f7597603e13249e3bcf37960533ffb92`
视觉方向：A 夜琴房（用户拍板）。基准屏 `93a55fdf0f954a59bcc8c314b0c98d16`。

## 下游取用

- 视觉合同：`docs/design-reference/foundation/visual-system.md`（token/全局组件/文案锁定总表）
- 每屏视觉真值：`docs/design-reference/screens/Sxx-*/spec.md`（32 份）
- 系统契约：`docs/design-system/screen-index.md`、`docs/design-system/data-model.md`、`docs/design-system/screens/*.md`（7 份）
- 本地参考图：`docs/design-reference/samples/*.png`（512px 缩略；高清可对 lh3 链接加 `=w1600`）

## 已知平台问题（不阻塞，spec 已消化）

1. Stitch 随机路由：figaro_agent 出 780×1768 竖屏；create_datastore_entry 元数据标 DESKTOP 2560×2048 但强 prompt 后内容仍是全屏手机版。实现一律以 390pt 视口 + spec 文字为准。
2. 第 4 tab 被多次画成 商城/社区/榜单/收藏/统计/训练营/电子琴 → 全部作废，tab 写死"今日/曲库/练习室/档案/我的"。
3. edit_screens 对纯文案修改多次只返回文字结论不落盘（重新 get_screen 哈希未变），已停止重试，差异进文案锁定。
4. list_screens 对本项目持续返回空 `{}`；download_assets 报成功但文件落远端不落本机。HTML 源码可经 get_screen 给的 contribution 签名 URL 直接 urllib 下载（S1 已验证 14KB、viewport 390×844）；需要某屏精确 code.html 时按此方式逐屏取。
5. 设计稿五线谱是 AI 示意，实现必须接真实记谱引擎（M2 spike）。

## 屏幕总账（32 份画布）

| ID | 名称 | 参考图 | Stitch screen id |
|---|---|---|---|
| S01 | 欢迎 | S1-welcome.png | ae612d6f748c438f8c1eca4e51ddaea7 |
| S02 | 权限请求 | S2-permissions.png | 68fa63a8a4df4a0e83c4440f27757e72 |
| S03 | MIDI 连接向导 | S3-midi-wizard.png | db115510cee34196816b5d61eca0df48 |
| S04 | 定级·自评 | S4-placement-step1.png | 0d379eb49de24bbba420f6375775e378 |
| S05 | 定级结果 | S5-placement-result.png | e7be272ba979488cabbe7d30e945768b |
| S06 | App Frame 骨架 | S6-frame-wireframe.png | 06edb68d401a4c81bb4ab2b9931328b4 |
| S07 | 今日（常态） | S7-today-v2.png | 2dc1b76824cb410da73bdc96534f23eb |
| S07b | 今日·定级前空状态 | S7-empty-firstday-v2.png（v1 同目录） | 77dac08ffad34f609407273d38998a60 |
| S07c | 热身强开确认 | S-gate-override.png | 取 Stitch 画布"热身还没完成" |
| S08 | 曲库 | S8-library-v2.png（v1 作废） | da5df787496749e59f4ebc68a11b4781 |
| S08b | 导入失败 | S-import-fail.png | 取 Stitch 画布"这个文件没能解析" |
| S09 | 曲目详情 | S9-piece-detail-v3.png（v1/v2 作废） | 56e0e80e9c8a4432b7dd8970fa0fe2a9 系列 |
| S10 | PDF 资料库 | S10-pdf-library.png | 取 Stitch 画布"PDF 资料库" |
| S11 | 全屏练习室 | S11-practice-room.png | 65f044723e6a4fb8aba32ec46412075e |
| S11b | 断连态 | S11-disconnected.png | 取 Stitch 画布"MIDI 已断开" |
| S12 | 段落循环 sheet | S12-loop-settings.png | 取 Stitch 画布"段落循环设置" |
| S13 | Take 全量报告 | S13-take-report.png | e7ca79a0929b42a590cfad9b41bdc02f |
| S13b | 疑似谱错标记 | S-score-error-mark.png | 取 Stitch 画布"标记疑似谱面错误" |
| S14 | 自由弹奏 | S14-freeplay.png | 取 Stitch 画布"自由弹奏" |
| S15 | 机位校准向导 | S15-camera-calib.png | 取 Stitch 画布"机位校准" |
| S16 | 侧拍回看 | S16-video-review-v2.png（v1 作废） | 取 Stitch 画布"侧拍回看" |
| S17 | Zf 月度导入 | S17-zf-import.png | 取 Stitch 画布"导入月度录像" |
| S18 | 问 Neko 对话 | S18-chat.png | 取 Stitch 画布"问 Neko" |
| S18b | 视频裁切上传 sheet | S18b-video-upload-sheet.png | 取 Stitch 画布"裁切并发送给 Neko" |
| S19 | 练琴笔记 | S19-notes.png | 取 Stitch 画布"练琴笔记" |
| S20 | 档案 | S20-archive.png | 取 Stitch 画布"档案" |
| S21 | 双 take 对比 | S21-compare.png | 771fe17b29204a688c2301026195582a |
| S22 | 月报详情 | S22-monthly.png | c8dbc7cdf98046efbb1169c091324f5b |
| S23 | 我的 | S-settings.png | 取 Stitch 画布"我的" |
| S24 | MIDI 诊断 | S-midi-diag.png | 取 Stitch 画布"MIDI 诊断" |
| S25 | 方舟 API Key | S-apikey.png | 取 Stitch 画布"AI助教·火山方舟" |
| S26 | 导出全部数据 | S-export.png | 取 Stitch 画布"导出我的全部数据" |

> "取 Stitch 画布"= id 未在本轮记录（list API 故障），实现前用 get_screen 按 title 取回；视觉/系统真值已全部固化在 spec，不影响开工。

## 自审通过结论

- 六红线在屏幕上的落点全部可视化（门禁强开留痕、弱总分、AI 建议权脚注、视频裁切+火山方舟具名、手型免责×3 处、不施压文案）。
- 无商城/社区/账号/真人老师/麦克风评判/瀑布流入口。
- 走样项（tab 词、节拍器 MNOME、S11 热点 19→21、S13 脚注与时长、强开 Meiko、S22 ♩=70、空状态胶囊幻觉）全部进 visual-system.md §9 文案锁定。
