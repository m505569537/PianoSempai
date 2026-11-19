import Foundation

/// S03 连接步推进判定（idb 走查发现的真实 bug：模拟源路径按钮可点但不动）。
/// 判定必须与按钮 enabled 条件一致：选定了真机设备，或已切到模拟源。
enum MIDIWizardFlow {
    static func canAdvanceFromConnect(
        systemDevices: [String],
        selectedDevice: String?,
        mode: MIDIHub.Mode
    ) -> Bool {
        selectedDevice != nil || mode == .simulated
    }

    /// 从系统暴露的 MIDI 源里挑一个作为"当前设备"。
    ///
    /// 历史实现的问题（2026-11-19 测试者反馈"电钢琴连不上"）：只有
    ///   ① 恰好 1 个源 → 直接认；② 多源时**只认名字含 TERENCE / 钢琴 的**，否则给 nil。
    /// 而 `canAdvanceFromConnect` 要求 `selectedDevice != nil`，于是**任何非特伦斯品牌、
    /// 又恰好暴露了多个源的琴（BLE-MIDI 常见两个端点、同机还有网络会话源等）会被永久卡死**：
    /// 设备明明连上了、列表里也看得见，但"下一步"永远是灰的，用户只能认为"连不上"。
    ///
    /// 现规则（顺序即优先级）：
    ///   1. 用户手动选过且该源仍在 → 保留（手动优先，不覆盖用户意图）；
    ///   2. 只有一个源 → 就是它；
    ///   3. 名字命中 TERENCE / 钢琴 → 优先（本仓主力机型的好恶，仅作锦上添花）；
    ///   4. 其余情况取第一个源——连接本身是真的（来电源已由 CoreMIDI 枚举得到），
    ///      此时只是"给这次连接起个名字"，不该把用户挡在门外。
    static func preferredSource(_ names: [String], keeping current: String?) -> String? {
        guard !names.isEmpty else { return nil }
        if let current, names.contains(current) { return current }
        if names.count == 1 { return names[0] }
        // 注意必须同时认中文「特伦斯」：本机设备名就是「特伦斯 V70」，
        // 只匹配英文 TERENCE 会漏掉（2026-11-19 新增用例抓到的）。
        if let preferred = names.first(where: {
            $0.localizedCaseInsensitiveContains("TERENCE")
                || $0.localizedCaseInsensitiveContains("特伦斯")
                || $0.localizedCaseInsensitiveContains("钢琴")
        }) {
            return preferred
        }
        return names[0]
    }
}

/// S03 验证步判定（PRD：首次连接向导「弹两音验证信号」——2 秒监听窗内收到 ≥2 个不同音名的有效 Note On）。
/// 纯函数：View 只把监听窗状态与窗内去重后的音名集合喂进来，规则集中在此、可单测。
enum MIDIVerifyGate {
    /// 监听窗内收到 ≥2 个不同音名的有效 Note On → 通过（弹两音验证；同一音重复不算第二个）。
    /// 窗外到达（窗口已过期 / 未武装）只更新三格实时反馈，不放行——用户可「再听一次」重开窗口。
    static func passes(windowArmed: Bool, windowExpired: Bool, pitches: [UInt8]) -> Bool {
        windowArmed && !windowExpired && Set(pitches).count >= 2
    }
}
