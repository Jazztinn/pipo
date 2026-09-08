@preconcurrency import UserNotifications
import Foundation

public struct PipoNotificationPayload: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public enum PipoNotificationPlanner {
    public static func changes(from previous: DashboardSnapshot, to current: DashboardSnapshot) -> [PipoNotificationPayload] {
        changes(from: previous, to: current, settings: PipoSettings())
    }

    public static func changes(from previous: DashboardSnapshot, to current: DashboardSnapshot, settings: PipoSettings) -> [PipoNotificationPayload] {
        let previousIDs = Set(allItems(in: previous).map(\.stableKey))
        return allItems(in: current)
            .filter { !previousIDs.contains($0.stableKey) }
            .filter { item in
                switch item.kind {
                case "message": settings.messageNotifications
                case "grade": settings.gradeNotifications
                case "announcement": settings.announcementNotifications
                default: settings.assignmentNotifications
                }
            }
            .prefix(10)
            .map(payload)
    }

    private static func allItems(in snapshot: DashboardSnapshot) -> [DashboardItem] {
        DashboardItem.deduplicated(snapshot.sections.dueSoon
            + snapshot.sections.notifications.filter(\.isUnread)
            + snapshot.sections.newAssignments
            + snapshot.sections.messages
            + snapshot.sections.gradeFeedback
            + snapshot.announcements)
    }

    private static func payload(for item: DashboardItem) -> PipoNotificationPayload {
        let heading: String
        switch item.kind {
        case "message": heading = "New LMS message"
        case "grade": heading = "New grade feedback"
        case "notification": heading = "New LMS notification"
        case "announcement": heading = "New announcement"
        default: heading = "New assignment"
        }
        return PipoNotificationPayload(
            id: "\(item.kind)-\(item.id)",
            title: heading,
            body: "\(item.courseName): \(item.title)"
        )
    }
}

public protocol PipoNotificationService: Sendable {
    func requestAuthorization() async
    func deliver(_ payloads: [PipoNotificationPayload]) async
    func scheduleDeadlineReminders(for items: [DashboardItem], settings: PipoSettings) async
    func scheduleSnooze(id: String, title: String, body: String, date: Date) async
    func clear()
    func beginSession(_ accountID: String)
}

public extension PipoNotificationService {
    func beginSession(_ accountID: String) {}
    func scheduleDeadlineReminders(for items: [DashboardItem], settings: PipoSettings) async {}
    func scheduleSnooze(id: String, title: String, body: String, date: Date) async {}
}

/// Generation-stamped requests prevent an async add from reviving an ended session.
public final class PipoSystemNotifications: PipoNotificationService, @unchecked Sendable {
    private let lock = NSLock()
    private var generation = UUID().uuidString
    private var accountID = "anonymous"

    public init() {}

    private func scope() -> String {
        lock.lock()
        defer { lock.unlock() }
        return "\(accountID)-\(generation)"
    }

    private func isCurrent(_ value: String) -> Bool { !Task.isCancelled && scope() == value }

    public func beginSession(_ accountID: String) {
        clear()
        lock.lock()
        self.accountID = accountID
        lock.unlock()
    }

    public func requestAuthorization() async {
        guard !Task.isCancelled else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func add(_ request: UNNotificationRequest, scope value: String) async {
        guard isCurrent(value) else { return }
        let center = UNUserNotificationCenter.current()
        try? await center.add(request)
        if !isCurrent(value) {
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
        }
    }

    public func deliver(_ payloads: [PipoNotificationPayload]) async {
        let value = scope()
        for payload in payloads {
            guard isCurrent(value) else { return }
            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.body
            content.sound = .default
            await add(UNNotificationRequest(identifier: "\(value)-\(payload.id)", content: content, trigger: nil), scope: value)
        }
    }

    public func scheduleDeadlineReminders(for items: [DashboardItem], settings: PipoSettings) async {
        let value = scope()
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        guard isCurrent(value) else { return }
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("deadline-\(value)-") })
        guard settings.notificationsEnabled, settings.assignmentNotifications else { return }
        let reminders = DashboardItem.deduplicated(items)
            .filter { $0.submissionStatus != "submitted" && $0.submissionStatus != "graded" }
            .flatMap { item in PipoReminderPlanner.reminderDates(for: item, settings: settings).map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
        for (item, date) in reminders.prefix(60) {
            guard isCurrent(value) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Upcoming LMS deadline"
            content.body = "\(item.courseName): \(item.title)"
            content.sound = .default
            var components = PipoSchoolClock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            components.timeZone = PipoSchoolClock.calendar.timeZone
            let request = UNNotificationRequest(identifier: "deadline-\(value)-\(item.stableKey)-\(Int(date.timeIntervalSince1970))", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            await add(request, scope: value)
        }
    }

    public func scheduleSnooze(id: String, title: String, body: String, date: Date) async {
        let value = scope()
        guard date > .now, isCurrent(value) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var components = PipoSchoolClock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.timeZone = PipoSchoolClock.calendar.timeZone
        let request = UNNotificationRequest(identifier: "snooze-\(value)-\(id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        await add(request, scope: value)
    }

    public func clear() {
        lock.lock()
        generation = UUID().uuidString
        lock.unlock()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
