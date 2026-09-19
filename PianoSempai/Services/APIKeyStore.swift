import Foundation
import Security

// API Key 存储（凭据铁律：Key 只在 Keychain；永不进 SwiftData/日志/导出包）。
// 协议化以便测试用假存储（测试中不产生真实密钥）。

protocol APIKeyStore: AnyObject {
    var hasKey: Bool { get }
    func save(_ key: String) throws
    func read() -> String?
    func delete() throws
}

/// iOS Keychain 实现（generic password，service 固定）
final class KeychainAPIKeyStore: APIKeyStore {
    private let service: String

    init(service: String = "com.eeexu.pianosempai.apikey") {
        self.service = service
    }

    var hasKey: Bool { read() != nil }

    func save(_ key: String) throws {
        guard let data = key.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: Error {
    let status: OSStatus
}

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
