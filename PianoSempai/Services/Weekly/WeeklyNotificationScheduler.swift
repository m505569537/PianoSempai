import Foundation
import UserNotifications

// M7.2 本地通知（PRD M9：每周最多一条，全可关）。
// UNUserNotificationCenter 的薄包装 + 协议可注入：单测用内存假实现，真实通知中心不进单测。

protocol NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    /// 同 identifier 先 remove 再 add：一周一条，本周内重复 refresh 只覆盖内容
    func upsert(identifier: String, title: String, body: String, fireComponents: DateComponents) async throws
    /// 移除尚未触发的排期（开关关闭 / 周报已落库后调用）
    func removePending(_ identifier: String)
    /// 该通知是否已送达（出现在通知中心）
    func deliveredIdentifier(_ identifier: String) async -> Bool
    /// 从通知中心移除已送达的通知
    func removeDelivered(_ identifier: String)
}

struct SystemNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func upsert(identifier: String, title: String, body: String, fireComponents: DateComponents) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = WeeklyNotificationRequest.make(
            identifier: identifier,
            title: title,
            body: body,
            fireComponents: fireComponents
        )
        try await center.add(request)
    }

    func removePending(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func deliveredIdentifier(_ identifier: String) async -> Bool {
        let delivered = await center.deliveredNotifications()
        return delivered.contains { $0.request.identifier == identifier }
    }

    func removeDelivered(_ identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

// MARK: - 请求构造（纯函数：不碰通知中心，可完整单测）

enum WeeklyNotificationRequest {
    /// 周日 21:00 单次触发（repeats=false）+ 默认声音。
    /// 不设 interruptionLevel=.timeSensitive：该值需 time-sensitive entitlement，
    /// 无 entitlement 时 add 可能整条失败（brief：可选、失败不影响）——周报一条而已，
    /// 普通横幅足够，不值得为它加签名 entitlement 冒排期失败的风险。
    static func make(identifier: String, title: String, body: String, fireComponents: DateComponents) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
