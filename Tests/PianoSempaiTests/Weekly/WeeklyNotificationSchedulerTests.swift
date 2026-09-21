import UserNotifications
import XCTest

@testable import PianoSempai

/// M7.2 通知调度：内存 Fake 验 upsert/去重/ delivered 语义；
/// 请求构造走纯函数（真实 UNUserNotificationCenter 不进单测）。
@MainActor
final class WeeklyNotificationSchedulerTests: XCTestCase {

    private var fake: FakeNotificationScheduling!

    override func setUpWithError() throws {
        fake = FakeNotificationScheduling()
    }

    override func tearDown() {
        fake = nil
    }

    // MARK: upsert 语义（先 remove 再 add）

    func testUpsertSameIdentifierKeepsSinglePending() async throws {
        try await fake.upsert(identifier: "weekly-digest.2026-09-21", title: "本周练了 1 次", body: "第一次", fireComponents: Self.sunday21)
        try await fake.upsert(identifier: "weekly-digest.2026-09-21", title: "本周练了 2 次", body: "第二次", fireComponents: Self.sunday21)

        XCTAssertEqual(fake.pending.count, 1, "同 identifier 两次 upsert 只保留一条")
        XCTAssertEqual(fake.pending["weekly-digest.2026-09-21"]?.title, "本周练了 2 次", "后一次覆盖前一次")
        XCTAssertEqual(fake.pending["weekly-digest.2026-09-21"]?.body, "第二次")
        XCTAssertEqual(fake.removePendingCalls.count, 2, "每次 upsert 都先 remove 再 add")
    }

    func testUpsertDistinctIdentifiersCoexist() async throws {
        try await fake.upsert(identifier: "weekly-digest.2026-09-21", title: "t1", body: "b1", fireComponents: Self.sunday21)
        try await fake.upsert(identifier: "weekly-digest.2026-09-28", title: "t2", body: "b2", fireComponents: Self.sunday21)
        XCTAssertEqual(fake.pending.count, 2)
    }

    // MARK: 排期移除

    func testRemovePendingDropsRequest() async throws {
        try await fake.upsert(identifier: "weekly-digest.2026-09-21", title: "t", body: "b", fireComponents: Self.sunday21)
        fake.removePending("weekly-digest.2026-09-21")
        XCTAssertTrue(fake.pending.isEmpty)
        XCTAssertEqual(fake.removePendingCalls.count, 2, "upsert 内部一次 + 显式移除一次")
        XCTAssertEqual(fake.removePendingCalls.last, "weekly-digest.2026-09-21")
    }

    // MARK: delivered 查询与移除

    func testDeliveredIdentifierQueryAndRemoval() async {
        fake.delivered = ["weekly-digest.2026-09-21"]
        let hit = await fake.deliveredIdentifier("weekly-digest.2026-09-21")
        XCTAssertTrue(hit)
        let miss = await fake.deliveredIdentifier("weekly-digest.2026-09-28")
        XCTAssertFalse(miss)

        fake.removeDelivered("weekly-digest.2026-09-21")
        let removed = await fake.deliveredIdentifier("weekly-digest.2026-09-21")
        XCTAssertFalse(removed)
        XCTAssertEqual(fake.removeDeliveredCalls, ["weekly-digest.2026-09-21"])
    }

    // MARK: 授权

    func testAuthorizationStatusAndRequest() async throws {
        fake.status = .notDetermined
        let status = await fake.authorizationStatus()
        XCTAssertEqual(status, .notDetermined)
        fake.requestAuthorizationResult = true
        let granted = try await fake.requestAuthorization()
        XCTAssertTrue(granted)

        fake.requestAuthorizationResult = false
        let denied = try await fake.requestAuthorization()
        XCTAssertFalse(denied)
    }

    // MARK: 请求构造（纯函数）

    func testRequestBuilderFiresSunday21Once() {
        let request = WeeklyNotificationRequest.make(
            identifier: "weekly-digest.2026-09-21",
            title: "本周练了 3 次",
            body: "共 45 分，周目标 3 次达成 ✓",
            fireComponents: Self.sunday21
        )
        XCTAssertEqual(request.identifier, "weekly-digest.2026-09-21")
        XCTAssertEqual(request.content.title, "本周练了 3 次")
        XCTAssertEqual(request.content.body, "共 45 分，周目标 3 次达成 ✓")

        let trigger = try? XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger?.repeats ?? true, "每周最多一条：repeats=false")
        XCTAssertEqual(trigger?.dateComponents.weekday, 1, "周日")
        XCTAssertEqual(trigger?.dateComponents.hour, 21)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
        XCTAssertEqual(trigger?.dateComponents.year, 2026)
        XCTAssertEqual(trigger?.dateComponents.month, 9)
        XCTAssertEqual(trigger?.dateComponents.day, 27)
    }

    private static let sunday21 = DateComponents(year: 2026, month: 9, day: 27, hour: 21, minute: 0, weekday: 1)
}

// MARK: - 内存假实现（不碰真实通知中心）

/// 非隔离类（与 ChatStoreTests 的 Fake 同风格）：全部访问都发生在 @MainActor 测试内，
/// 无跨隔离域传递，不存在数据竞争。
final class FakeNotificationScheduling: NotificationScheduling {
    struct Request: Equatable {
        var identifier: String
        var title: String
        var body: String
        var fireComponents: DateComponents
    }

    var pending: [String: Request] = [:]
    var delivered: Set<String> = []
    var status: UNAuthorizationStatus = .authorized
    var requestAuthorizationResult = true
    private(set) var removePendingCalls: [String] = []
    private(set) var removeDeliveredCalls: [String] = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool { requestAuthorizationResult }

    func upsert(identifier: String, title: String, body: String, fireComponents: DateComponents) async throws {
        removePendingCalls.append(identifier)
        pending[identifier] = Request(identifier: identifier, title: title, body: body, fireComponents: fireComponents)
    }

    func removePending(_ identifier: String) {
        removePendingCalls.append(identifier)
        pending[identifier] = nil
    }

    func deliveredIdentifier(_ identifier: String) async -> Bool {
        delivered.contains(identifier)
    }

    func removeDelivered(_ identifier: String) {
        removeDeliveredCalls.append(identifier)
        delivered.remove(identifier)
    }
}
