import XCTest
@testable import PianoSempai

/// M7.1 多服务商 KeyStore 验收（brief 场景 8：两服务商 key 互不串）。
/// 真 Keychain 用例用每次测试独立的 service 名，不污染生产条目；用完即删。
final class ProviderKeyStoreTests: XCTestCase {

    private final class FakeProviderKeyStore: ProviderKeyStore {
        private var storage: [String: String] = [:]

        func save(_ key: String, providerId: String) throws { storage[providerId] = key }
        func read(providerId: String) -> String? { storage[providerId] }
        func delete(providerId: String) throws { storage[providerId] = nil }
        func hasKey(providerId: String) -> Bool { storage[providerId] != nil }
    }

    // MARK: ① 协议层：两服务商互不串

    func testTwoProvidersDoNotCrossOnFakeStore() throws {
        let store = FakeProviderKeyStore()

        XCTAssertFalse(store.hasKey(providerId: "ark"))
        try store.save("key-for-ark", providerId: "ark")
        try store.save("key-for-bailian", providerId: "bailian")

        XCTAssertEqual(store.read(providerId: "ark"), "key-for-ark")
        XCTAssertEqual(store.read(providerId: "bailian"), "key-for-bailian")
        XCTAssertTrue(store.hasKey(providerId: "ark"))
        XCTAssertTrue(store.hasKey(providerId: "bailian"))
        XCTAssertFalse(store.hasKey(providerId: "deepseek"))

        // 删一个不影响另一个
        try store.delete(providerId: "ark")
        XCTAssertNil(store.read(providerId: "ark"))
        XCTAssertEqual(store.read(providerId: "bailian"), "key-for-bailian", "删 ark 不得带走 bailian 的 key")
    }

    func testOverwriteKeepsOnlyLatestKey() throws {
        let store = FakeProviderKeyStore()
        try store.save("old", providerId: "ark")
        try store.save("new", providerId: "ark")
        XCTAssertEqual(store.read(providerId: "ark"), "new")
    }

    // MARK: ② 真 Keychain：每商一条 account，互不串

    func testKeychainEntriesAreIndependentPerProvider() throws {
        let store = KeychainProviderKeyStore(service: "com.eeexu.pianosempai.apikey.test.\(UUID().uuidString)")
        defer { try? store.delete(providerId: "ark"); try? store.delete(providerId: "bailian") }

        XCTAssertFalse(store.hasKey(providerId: "ark"))

        try store.save("ark-fake-key-0001", providerId: "ark")
        try store.save("bailian-fake-key-0002", providerId: "bailian")

        XCTAssertEqual(store.read(providerId: "ark"), "ark-fake-key-0001")
        XCTAssertEqual(store.read(providerId: "bailian"), "bailian-fake-key-0002", "两个服务商各读各的，不串")
        XCTAssertTrue(store.hasKey(providerId: "ark"))
        XCTAssertFalse(store.hasKey(providerId: "deepseek"))

        // 覆盖 ark 不动 bailian
        try store.save("ark-fake-key-0003", providerId: "ark")
        XCTAssertEqual(store.read(providerId: "ark"), "ark-fake-key-0003")
        XCTAssertEqual(store.read(providerId: "bailian"), "bailian-fake-key-0002")

        try store.delete(providerId: "ark")
        XCTAssertNil(store.read(providerId: "ark"))
        XCTAssertEqual(store.read(providerId: "bailian"), "bailian-fake-key-0002")
    }

    func testKeychainDeleteIsIdempotentAndBlankKeyIsNotAKey() throws {
        let store = KeychainProviderKeyStore(service: "com.eeexu.pianosempai.apikey.test.\(UUID().uuidString)")
        defer { try? store.delete(providerId: "ark") }

        // 删不存在的条目不抛错（Stage B 的"清除 Key"可安全调用）
        try store.delete(providerId: "ark")

        // 空白 key：hasKey = false（不让空串冒充"已配置"）
        try store.save("   ", providerId: "ark")
        XCTAssertFalse(store.hasKey(providerId: "ark"))

        // 空 providerId：拒绝（Keychain account 不能空，否则所有服务商共用一条）
        XCTAssertThrowsError(try store.save("k", providerId: "   "))
        XCTAssertThrowsError(try store.delete(providerId: ""))
        XCTAssertNil(store.read(providerId: ""))
    }

    // MARK: ③ 默认 service 名与红线

    func testDefaultServiceNameIsStable() {
        let store = KeychainProviderKeyStore()
        XCTAssertEqual(store.serviceName, "com.eeexu.pianosempai.apikey", "与旧单 key 存储同 service（account 区分服务商）")
    }

    func testUnknownProviderReadsAsNil() throws {
        let store = FakeProviderKeyStore()
        try store.save("k-ark", providerId: "ark")
        XCTAssertNil(store.read(providerId: "bailian"), "没存过的服务商读不到别人的 key")
        XCTAssertFalse(store.hasKey(providerId: "bailian"))
    }

    // 红线 2（Key 不入导出包）的既有覆盖见 SettingsServicesTests 的 zip 断言；
    // 本文件只验 Keychain 侧的服务商隔离。
}
