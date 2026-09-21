import Foundation
import Security

// 多服务商 Key 存储（data-model §2 Keychain 段：每服务商独立条目，互不串）。
// 与旧单 key 协议 APIKeyStore 并存——APIKeySettingsView（旧 S25）仍在用旧的，
// Stage B 换视图时再统一到本协议（红线：本 Stage 不破坏现有调用点）。
//
// 铁律：Key 只在 Keychain；永不进 SwiftData / 日志 / 诊断 / 导出包。

protocol ProviderKeyStore: AnyObject {
    /// 写入/覆盖该服务商的 key（account = providerId）
    func save(_ key: String, providerId: String) throws
    func read(providerId: String) -> String?
    func delete(providerId: String) throws
    func hasKey(providerId: String) -> Bool
}

/// iOS Keychain 实现：service 固定，account = providerId（每商一条 generic password）。
/// accessible = AfterFirstUnlock（后台续传/通知场景可读；不选 ThisDeviceOnly，恢复换机时由用户重填）。
final class KeychainProviderKeyStore: ProviderKeyStore {
    private let service: String

    init(service: String = "com.eeexu.pianosempai.apikey") {
        self.service = service
    }

    var serviceName: String { service }

    func save(_ key: String, providerId: String) throws {
        guard !providerId.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ProviderKeyStoreError.emptyProviderId
        }
        guard let data = key.data(using: .utf8) else { return }

        let base = queryBase(providerId: providerId)
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

    func read(providerId: String) -> String? {
        guard !providerId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var query = queryBase(providerId: providerId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(providerId: String) throws {
        guard !providerId.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ProviderKeyStoreError.emptyProviderId
        }
        let status = SecItemDelete(queryBase(providerId: providerId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    func hasKey(providerId: String) -> Bool {
        guard let key = read(providerId: providerId) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// service + account(=providerId) 唯一确定一条；不带动任何 key 值
    private func queryBase(providerId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
        ]
    }
}

enum ProviderKeyStoreError: Error, Equatable {
    case emptyProviderId
}
