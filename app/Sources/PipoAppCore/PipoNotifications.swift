@preconcurrency import UserNotifications

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
        let previousIDs = Set(allItems(in: previous).map(\.id))
        return allItems(in: current)
            .filter { !previousIDs.contains($0.id) }
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
        snapshot.sections.dueSoon
            + snapshot.sections.notifications.filter(\.isUnread)
            + snapshot.sections.newAssignments
            + snapshot.sections.messages
            + snapshot.sections.gradeFeedback
            + snapshot.announcements
    }

    private static func payload(for item: DashboardItem) -> PipoNotificationPayload {
        let heading: String
        switch item.kind {
        case "message": heading = "New LMS message"
        case "grade": heading = "New grade feedback"
        case "notification": heading = "New LMS notification"
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
}

public extension PipoNotificationService {
    func scheduleDeadlineReminders(for items: [DashboardItem], settings: PipoSettings) async {}
    func scheduleSnooze(id: String, title: String, body: String, date: Date) async {}
}

public struct PipoSystemNotifications: PipoNotificationService {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public func deliver(_ payloads: [PipoNotificationPayload]) async {
        for payload in payloads {
            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: payload.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    public func scheduleDeadlineReminders(for items: [DashboardItem], settings: PipoSettings) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let identifiers = existing.map(\.identifier).filter { $0.hasPrefix("deadline-") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        for item in items.prefix(30) {
            for date in PipoReminderPlanner.reminderDates(for: item, settings: settings) {
                let content = UNMutableNotificationContent()
                content.title = "Upcoming LMS deadline"
                content.body = "\(item.courseName): \(item.title)"
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let offset = Int(item.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince(date) ?? 0)
                let request = UNNotificationRequest(identifier: "deadline-\(item.id)-\(offset)", content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    public func scheduleSnooze(id: String, title: String, body: String, date: Date) async {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: "snooze-\(id)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    public func clear() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
