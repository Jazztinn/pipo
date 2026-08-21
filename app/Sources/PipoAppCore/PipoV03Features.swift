import CryptoKit
import EventKit
import Foundation
import GRDB

public struct PipoLocalState: Codable, Equatable, Sendable {
    public var seenIDs: Set<String> = []
    public var snoozedUntil: [String: Date] = [:]
    public var pinnedCourseIDs: Set<Int> = []
    public var hiddenCourseIDs: Set<Int> = []

    public init() {}
}

public actor EncryptedLocalStateStore {
    private let database: DatabaseQueue
    private let key: SymmetricKey

    public init(databaseURL: URL, keyData: Data) throws {
        guard keyData.count == 32 else { throw PipoCoreError.operationFailed("Cache key is invalid") }
        database = try DatabaseQueue(path: databaseURL.path)
        key = SymmetricKey(data: keyData)
        try database.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS pipo_local_state (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
        }
    }

    public func load() throws -> PipoLocalState {
        let encrypted: Data? = try database.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM pipo_local_state WHERE id = 1")
        }
        guard let encrypted else { return PipoLocalState() }
        let box = try AES.GCM.SealedBox(combined: encrypted)
        return try JSONDecoder().decode(PipoLocalState.self, from: AES.GCM.open(box, using: key))
    }

    public func save(_ state: PipoLocalState) throws {
        let data = try JSONEncoder().encode(state)
        let encrypted = try AES.GCM.seal(data, using: key).combined.unwrap(or: PipoCoreError.operationFailed("State encryption failed"))
        try database.write { db in
            try db.execute(sql: "INSERT INTO pipo_local_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [encrypted])
        }
    }

    public func delete() throws {
        try database.write { db in try db.execute(sql: "DELETE FROM pipo_local_state") }
    }
}

public enum PipoDeadlineGroup: String, CaseIterable, Codable, Sendable {
    case overdue = "Overdue"
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case later = "Later"
}

public enum PipoDashboardRanking {
    public static func nextUp(snapshot: DashboardSnapshot, state: PipoLocalState, now: Date = .now, calendar: Calendar = .current) -> [DashboardItem] {
        let candidates = snapshot.sections.dueSoon + snapshot.sections.newAssignments + snapshot.schedule + snapshot.announcements
        return candidates
            .filter { state.snoozedUntil[$0.id].map { $0 <= now } ?? true }
            .filter { $0.kind != "announcement" || !state.seenIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let left = rank(lhs, state: state, now: now, calendar: calendar)
                let right = rank(rhs, state: state, now: now, calendar: calendar)
                if left.0 != right.0 { return left.0 < right.0 }
                if left.1 != right.1 { return left.1 < right.1 }
                return left.2 < right.2
            }
            .prefix(5)
            .map { $0 }
    }

    public static func groupedDeadlines(_ items: [DashboardItem], now: Date = .now, calendar: Calendar = .current) -> [PipoDeadlineGroup: [DashboardItem]] {
        Dictionary(grouping: items) { item in
            guard let date = date(item) else { return .later }
            if date < now { return .overdue }
            if calendar.isDateInToday(date) { return .today }
            if calendar.isDateInTomorrow(date) { return .tomorrow }
            let week = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))!
            return date < week ? .thisWeek : .later
        }
    }

    public static func urgentCount(snapshot: DashboardSnapshot, state: PipoLocalState, now: Date = .now) -> Int {
        let deadline = now.addingTimeInterval(24 * 60 * 60)
        return Set((snapshot.sections.dueSoon + snapshot.sections.newAssignments)
            .filter { state.snoozedUntil[$0.id].map { $0 <= now } ?? true }
            .filter { $0.submissionStatus != "submitted" && $0.submissionStatus != "graded" }
            .filter { date($0).map { $0 <= deadline } ?? false }
            .map(\.id)).count
    }

    private static func rank(_ item: DashboardItem, state: PipoLocalState, now: Date, calendar: Calendar) -> (Int, Date, String) {
        let date = date(item) ?? .distantFuture
        let status = item.submissionStatus
        if status == "not_submitted", date < now { return (0, date, item.id) }
        if date <= now.addingTimeInterval(24 * 60 * 60) { return (1, date, item.id) }
        if date <= now.addingTimeInterval(7 * 24 * 60 * 60) { return (2, date, item.id) }
        if item.section == "schedule" && calendar.isDateInToday(date) { return (3, date, item.id) }
        if item.section == "announcements" && !state.seenIDs.contains(item.id) { return (4, date, item.id) }
        return (5, date, item.id)
    }

    private static func date(_ item: DashboardItem) -> Date? {
        item.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

public extension DashboardSnapshot {
    func applyingLocalState(_ state: PipoLocalState, now: Date = .now) -> DashboardSnapshot {
        let visibleCourses = courses
            .filter { !state.hiddenCourseIDs.contains($0.id) }
            .sorted { left, right in
                let leftPinned = state.pinnedCourseIDs.contains(left.id)
                let rightPinned = state.pinnedCourseIDs.contains(right.id)
                if leftPinned != rightPinned { return leftPinned }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
        return DashboardSnapshot(
            version: version,
            generatedAt: generatedAt,
            siteName: siteName,
            studentName: studentName,
            sections: sections,
            supported: supported,
            assignmentIDs: assignmentIDs,
            courses: visibleCourses,
            failures: failures,
            nextUp: PipoDashboardRanking.nextUp(snapshot: self, state: state, now: now),
            schedule: schedule,
            announcements: announcements,
            resources: resources,
            sectionTimestamps: sectionTimestamps
        )
    }
}

public enum PipoReminderPlanner {
    public static func reminderDates(for item: DashboardItem, settings: PipoSettings, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        guard let due = item.timestamp.flatMap({ ISO8601DateFormatter().date(from: $0) }) else { return [] }
        let offsets = [settings.reminderDayBefore ? TimeInterval(24 * 60 * 60) : nil, settings.reminderHourBefore ? TimeInterval(60 * 60) : nil].compactMap { $0 }
        return offsets.map { shiftOutOfQuietHours(due.addingTimeInterval(-$0), settings: settings, calendar: calendar) }.filter { $0 > now }
    }

    public static func shiftOutOfQuietHours(_ date: Date, settings: PipoSettings, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        let starts = settings.quietHoursStart
        let ends = settings.quietHoursEnd
        let quiet = starts > ends ? hour >= starts || hour < ends : hour >= starts && hour < ends
        guard quiet else { return date }
        return calendar.date(bySettingHour: ends, minute: 0, second: 0, of: hour >= starts ? calendar.date(byAdding: .day, value: 1, to: date)! : date) ?? date
    }
}

public protocol PipoCalendarService: Sendable {
    func authorizationStatus() -> EKAuthorizationStatus
    func requestAccess() async throws -> Bool
    func add(_ item: DashboardItem) async throws
}

public final class PipoEventKitCalendar: PipoCalendarService, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func authorizationStatus() -> EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func add(_ item: DashboardItem) async throws {
        guard let due = item.timestamp.flatMap({ ISO8601DateFormatter().date(from: $0) }) else { throw PipoCoreError.operationFailed("Item has no date") }
        guard authorizationStatus() == .fullAccess || authorizationStatus() == .writeOnly else { throw PipoCoreError.operationFailed("Calendar access is required") }
        let identifier = "pipo://calendar/\(item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id)"
        let predicate = store.predicateForEvents(withStart: due.addingTimeInterval(-60), end: due.addingTimeInterval(60), calendars: nil)
        guard !store.events(matching: predicate).contains(where: { $0.url?.absoluteString == identifier }) else { return }
        let event = EKEvent(eventStore: store)
        event.title = item.title
        event.calendar = store.defaultCalendarForNewEvents
        event.startDate = due
        event.endDate = due.addingTimeInterval(30 * 60)
        event.notes = item.courseName
        event.url = URL(string: identifier)
        try store.save(event, span: .thisEvent)
    }
}

public struct PipoDiagnostics: Codable, Equatable, Sendable {
    public let appVersion: String
    public let macOSVersion: String
    public let supported: DashboardSectionSupport
    public let failures: [String]
    public let generatedAt: String
    public let sectionTimestamps: [String: String]

    public init(snapshot: DashboardSnapshot, appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev", macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        supported = snapshot.supported
        failures = snapshot.failures
        generatedAt = snapshot.generatedAt
        sectionTimestamps = snapshot.sectionTimestamps
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
