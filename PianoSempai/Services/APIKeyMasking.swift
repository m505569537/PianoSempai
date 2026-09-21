import Foundation

// Key 掩码显示（S25 spec：末 4 位明文 + 圆点；眼睛显态 30s 自动回掩码）。
// 从旧单 key 页（APIKeyStore.swift，本 Stage 删除）迁入——S25 服务商详情仍用它。

enum APIKeyMasking {
    /// 掩码显示：末 4 位明文 + 圆点；≤4 位全圆点（永不暴露完整值）。
    /// 显态（眼睛）也只由本函数控制，且 30 秒自动回掩码（S25 spec）。
    static func mask(_ key: String, visible: Bool = false) -> String {
        guard !key.isEmpty else { return "" }
        guard key.count > 4 else { return String(repeating: "•", count: key.count) }
        if visible {
            // 显态仍不整串裸露：前 2 + 后 4，其余圆点（防旁观）
            let prefix = String(key.prefix(2))
            let suffix = String(key.suffix(4))
            let dots = String(repeating: "•", count: key.count - 6)
            return prefix + dots + suffix
        }
        return String(repeating: "•", count: key.count - 4) + key.suffix(4)
    }
}
