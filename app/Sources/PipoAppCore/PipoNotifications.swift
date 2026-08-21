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
        let previousIDs = Set(allItems(in: previous).map(\.id))
        return allItems(in: current)
            .filter { !previousIDs.contains($0.id) }
            .prefix(10)
            .map(payload)
    }

    private static func allItems(in snapshot: DashboardSnapshot) -> [DashboardItem] {
        snapshot.sections.dueSoon
            + snapshot.sections.notifications.filter(\.isUnread)
            + snapshot.sections.newAssignments
            + snapshot.sections.messages
            + snapshot.sections.gradeFeedback
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

public enum PipoSystemNotifications {
    public static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public static func deliver(_ payloads: [PipoNotificationPayload]) async {
        for payload in payloads {
            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: payload.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    public static func clear() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
