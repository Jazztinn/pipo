import AppKit
import Foundation
import PipoAppCore
import ServiceManagement
import SwiftUI

@MainActor
private enum PipoV03Palette {
    static let maroon = Color(red: 0.43, green: 0.08, blue: 0.12)
    static let gold = Color(red: 0.70, green: 0.48, blue: 0.10)
    static let warning = Color.orange
    static let row = Color(nsColor: .controlBackgroundColor)
}

private enum PipoV03ItemFilter: String, CaseIterable, Identifiable {
    case all
    case assignments
    case announcements
    case resources
    case messages

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct PipoV03DisplayItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let date: Date?
    let destination: URL?
    let icon: String
    let excerpt: String?
    let status: PipoAssignmentStatus?
    let calendarEntry: PipoCalendarEntry?
}

@MainActor
struct PipoV03TodayView: View {
    let phase: PipoUIPhase
    let snapshot: PipoDashboardSnapshot?
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onOpenURL: (URL) -> Void
    let onInstallUpdate: (@MainActor () -> Void)?
    let configuration: PipoUIConfiguration
    let onSnapshot: (PipoDashboardSnapshot) -> Void

    @State private var query = ""
    @State private var courseFilter = "All courses"
    @State private var itemFilter: PipoV03ItemFilter = .all
    private var seenIDs: Set<String> { configuration.seenIDs() }
    private var snoozedIDs: Set<String> { configuration.snoozedIDs() }
    private var courseNames: [String] {
        guard let snapshot else { return [] }
        let names = snapshot.courses.map(\.name)
            + snapshot.dueSoon.map(\.courseName)
            + snapshot.announcements.map(\.courseName)
            + snapshot.resources.map(\.courseName)
        return Array(Set(names)).sorted()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PipoV03FilterBar(query: $query, courseFilter: $courseFilter, itemFilter: $itemFilter, courses: courseNames)

                if let snapshot, let cachedAt = snapshot.cachedAt, phase == .offline {
                    PipoOfflineBanner(cachedAt: cachedAt, onReconnect: onReconnect)
                } else if phase == .reconnecting {
                    PipoStateBanner(title: "Refreshing", message: "Checking the LMS for changes.", systemImage: "arrow.clockwise")
                }

                if phase == .loading {
                    PipoV03DashboardSkeleton()
                } else if let snapshot, !snapshot.isEmpty {
                    if let studentName = snapshot.studentName, !studentName.isEmpty {
                        Text("Hello, \(studentName)")
                            .font(.title3.weight(.semibold))
                    }
                    content(snapshot)
                } else if phase == .offline {
                    PipoEmptyState(title: "No cached dashboard", message: "Reconnect when the LMS is available.", systemImage: "wifi.slash", actionTitle: "Reconnect", action: onReconnect)
                } else if case let .failed(message) = phase {
                    PipoEmptyState(title: "Could not load Pipo", message: message, systemImage: "exclamationmark.triangle", actionTitle: "Try again", action: onRefresh)
                } else {
                    PipoEmptyState(title: "Your day is clear", message: "New deadlines, notices, messages, and grades will appear here.", systemImage: "checkmark.circle", actionTitle: "Refresh", action: onRefresh)
                }

                if let onInstallUpdate {
                    Button(action: onInstallUpdate) {
                        Label("Check for updates", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(PipoV03Palette.gold)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: PipoDashboardSnapshot) -> some View {
        let next = filteredTasks(snapshot.nextUp.isEmpty ? Array(snapshot.dueSoon.prefix(1)) : snapshot.nextUp)
        if !next.isEmpty && itemFilter == .all {
            PipoV03Section(title: "Next up", systemImage: "sparkles", retry: retryAction(for: "assignments")) {
                PipoV03ItemList(items: next.map(taskDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
            }
        }

        let schedule = snapshot.schedule.filter { matches($0.title, $0.courseName) }
        if snapshot.featureSupport.schedule && !schedule.isEmpty && (itemFilter == .all) {
            PipoV03Section(title: "Schedule", systemImage: "calendar", retry: retryAction(for: "schedule")) {
                PipoV03ItemList(items: schedule.map(scheduleDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
            }
        }

        if snapshot.supported.dueSoon && itemFilter == .all || itemFilter == .assignments {
            ForEach(snapshot.deadlineGroups().filter { !$0.1.filter { matches($0.title, $0.courseName) && !snoozedIDs.contains($0.id) }.isEmpty }, id: \.0) { group in
                let items = group.1.filter { matches($0.title, $0.courseName) && !snoozedIDs.contains($0.id) }
                if !items.isEmpty {
                    PipoV03Section(title: group.0, systemImage: "calendar.badge.clock", retry: retryAction(for: "due_soon")) {
                        PipoV03ItemList(items: items.map(taskDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
                    }
                }
            }
        }

        if snapshot.featureSupport.announcements && (itemFilter == .all || itemFilter == .announcements) {
            let announcements = snapshot.announcements.filter { matches($0.title, $0.courseName) }
            if !announcements.isEmpty {
                PipoV03Section(title: "Announcements", systemImage: "megaphone", retry: retryAction(for: "announcements")) {
                    PipoV03ItemList(items: announcements.map(announcementDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
                }
            }
        }

        if itemFilter == .all || itemFilter == .messages {
            let messages = snapshot.messages.filter { matches($0.title, $0.courseName) }
            if snapshot.supported.messages && !messages.isEmpty {
                    PipoV03Section(title: "Recent messages", systemImage: "bubble.left.and.bubble.right", retry: retryAction(for: "messages")) {
                    PipoV03ItemList(items: messages.map(messageDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
                }
            }
        }

        if snapshot.supported.grades && itemFilter == .all {
            let grades = snapshot.gradeFeedback.filter { matches($0.title, $0.courseName) }
            if !grades.isEmpty {
                PipoV03Section(title: "Grade feedback", systemImage: "checkmark.seal", retry: retryAction(for: "grades")) {
                    PipoV03ItemList(items: grades.map(gradeDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
                }
            }
        }

        if snapshot.featureSupport.resources && (itemFilter == .all || itemFilter == .resources) {
            let resources = snapshot.resources.filter { matches($0.title, $0.courseName) }
            if !resources.isEmpty {
                PipoV03Section(title: "Recent resources", systemImage: "folder", retry: retryAction(for: "resources")) {
                    PipoV03ItemList(items: resources.map(resourceDisplay), configuration: configuration, onOpenURL: onOpenURL, seenIDs: seenIDs, onSeen: markSeen, onSnooze: snooze)
                }
            }
        }
    }

    private func matches(_ title: String, _ course: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let queryMatches = normalizedQuery.isEmpty || title.lowercased().contains(normalizedQuery) || course.lowercased().contains(normalizedQuery)
        let courseMatches = courseFilter == "All courses" || course == courseFilter
        return queryMatches && courseMatches
    }

    private func filteredTasks(_ tasks: [PipoTaskItem]) -> [PipoTaskItem] {
        tasks.filter { matches($0.title, $0.courseName) && !snoozedIDs.contains($0.id) }
    }

    private func retryAction(for section: String) -> (() -> Void)? {
        let hasFailure = snapshot?.failures.contains { failure in
            let normalized = failure.section.lowercased()
            return normalized.contains(section.replacingOccurrences(of: "_", with: " ")) || normalized.contains(section)
        } ?? false
        guard hasFailure else { return nil }
        return {
            Task { @MainActor in
                do {
                    if let refreshed = try await configuration.refreshSection(section) { onSnapshot(refreshed) }
                } catch { }
            }
        }
    }

    private func taskDisplay(_ item: PipoTaskItem) -> PipoV03DisplayItem {
        PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.dueDate, destination: item.destination, icon: "doc.text", excerpt: item.excerpt, status: item.status, calendarEntry: item.dueDate.map { PipoCalendarEntry(id: item.id, title: item.title, courseName: item.courseName, startsAt: $0, destination: item.destination) })
    }

    private func scheduleDisplay(_ item: PipoScheduleItem) -> PipoV03DisplayItem {
        PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.startsAt, destination: item.destination, icon: "calendar", excerpt: nil, status: nil, calendarEntry: PipoCalendarEntry(id: item.id, title: item.title, courseName: item.courseName, startsAt: item.startsAt, endsAt: item.endsAt, destination: item.destination))
    }

    private func announcementDisplay(_ item: PipoAnnouncementItem) -> PipoV03DisplayItem {
        PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.date, destination: item.destination, icon: "megaphone", excerpt: item.excerpt, status: nil, calendarEntry: nil)
    }

    private func messageDisplay(_ item: PipoMessageItem) -> PipoV03DisplayItem {
        PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.date, destination: item.destination, icon: "bubble.left", excerpt: nil, status: nil, calendarEntry: nil)
    }

    private func gradeDisplay(_ item: PipoGradeFeedbackItem) -> PipoV03DisplayItem {
        PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.date, destination: item.destination, icon: "checkmark.seal", excerpt: nil, status: nil, calendarEntry: nil)
    }

    private func resourceDisplay(_ item: PipoResourceItem) -> PipoV03DisplayItem {
        let subtitle = item.kind.map { "\($0) - \(item.courseName)" } ?? item.courseName
        return PipoV03DisplayItem(id: item.id, title: item.title, subtitle: subtitle, date: item.date, destination: item.destination, icon: "folder", excerpt: nil, status: nil, calendarEntry: nil)
    }

    private func markSeen(_ id: String) {
        configuration.markSeen?(id)
    }

    private func snooze(_ id: String, date: Date?) {
        configuration.snooze?(id, date)
    }
}

@MainActor
struct PipoV03CoursesView: View {
    let phase: PipoUIPhase
    let courses: [PipoCourseItem]
    @Binding var selectedCourseID: String?
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onLoadCourse: @MainActor (Int) async throws -> CourseDetail?
    let onOpenURL: (URL) -> Void
    let configuration: PipoUIConfiguration
    let onSnapshot: (PipoDashboardSnapshot) -> Void

    @State private var query = ""
    private var pinnedIDs: Set<String> { configuration.pinnedCourseIDs() }
    private var hiddenIDs: Set<String> { configuration.hiddenCourseIDs() }
    private var visibleCourses: [PipoCourseItem] {
        courses.filter { !hiddenIDs.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.shortName.localizedCaseInsensitiveContains(query)) }
            .sorted { left, right in
                let leftPinned = pinnedIDs.contains(left.id)
                let rightPinned = pinnedIDs.contains(right.id)
                if leftPinned != rightPinned { return leftPinned }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if phase == .loading || phase == .reconnecting {
                PipoV03CoursesSkeleton()
            } else if phase == .offline && visibleCourses.isEmpty {
                PipoEmptyState(title: "Courses unavailable", message: "Reconnect to load your courses.", systemImage: "wifi.slash", actionTitle: "Reconnect", action: onReconnect)
            } else if visibleCourses.isEmpty {
                PipoEmptyState(title: query.isEmpty ? "No courses yet" : "No matching courses", message: query.isEmpty ? "Published courses from LMS appear here." : "Try another search.", systemImage: "books.vertical", actionTitle: "Refresh", action: onRefresh)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search courses", text: $query)
                            .textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(PipoV03Palette.row, in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)

                    List(visibleCourses) { course in
                        NavigationLink(value: course.id) {
                            HStack(spacing: 12) {
                                Image(systemName: pinnedIDs.contains(course.id) ? "pin.fill" : "book.closed.fill")
                                    .foregroundStyle(pinnedIDs.contains(course.id) ? PipoV03Palette.gold : PipoV03Palette.maroon)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(course.name)
                                        .font(.body.weight(.semibold))
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        if !course.shortName.isEmpty { Text(course.shortName) }
                                        if course.upcomingCount > 0 { Text("\(course.upcomingCount) upcoming") }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if let publishedTotal = course.publishedTotal {
                                    Text(publishedTotal)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(PipoV03Palette.gold)
                                }
                            }
                        }
                        .contextMenu {
                            Button(pinnedIDs.contains(course.id) ? "Unpin course" : "Pin course", systemImage: pinnedIDs.contains(course.id) ? "pin.slash" : "pin") { togglePin(course.id) }
                            Button("Hide course", systemImage: "eye.slash") { hide(course.id) }
                        }
                        .tag(course.id)
                    }
                    .listStyle(.inset)
                }
                .navigationDestination(for: String.self) { courseID in
                    if let course = courses.first(where: { $0.id == courseID }) {
                        PipoV03CourseDetailView(course: course, onLoadCourse: onLoadCourse, onOpenURL: onOpenURL, configuration: configuration, onSnapshot: onSnapshot)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    let hidden = courses.filter { hiddenIDs.contains($0.id) }
                    if hidden.isEmpty {
                        Text("No hidden courses")
                    } else {
                        ForEach(hidden) { course in
                            Button("Show \(course.shortName.isEmpty ? course.name : course.shortName)") { unhide(course.id) }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .help("Manage hidden courses")
                .accessibilityLabel("Manage hidden courses")
            }
        }
    }

    private func togglePin(_ id: String) {
        configuration.setPinnedCourse?(id, !pinnedIDs.contains(id))
    }

    private func hide(_ id: String) {
        configuration.setHiddenCourse?(id, true)
    }

    private func unhide(_ id: String) {
        configuration.setHiddenCourse?(id, false)
    }
}

@MainActor
private struct PipoV03CourseDetailView: View {
    let course: PipoCourseItem
    let onLoadCourse: @MainActor (Int) async throws -> CourseDetail?
    let onOpenURL: (URL) -> Void
    let configuration: PipoUIConfiguration
    let onSnapshot: (PipoDashboardSnapshot) -> Void
    @State private var detail: CourseDetail?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(PipoV03Palette.maroon)
                    .accessibilityHidden(true)
                Text(course.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if !course.shortName.isEmpty { Text(course.shortName).font(.subheadline).foregroundStyle(.secondary) }
                if let destination = detail.flatMap({ URL(string: $0.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL }) {
                    Button { onOpenURL(destination) } label: { Label("Open course in LMS", systemImage: "arrow.up.right") }
                        .buttonStyle(.bordered)
                }
                Divider()
                Text("Published grade").font(.headline)
                Text(detail?.course.publishedTotal ?? course.publishedTotal ?? "-")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(PipoV03Palette.gold)

                if isLoading {
                    PipoV03CourseDetailSkeleton()
                } else if let loadError {
                    PipoStateBanner(title: "Course details unavailable", message: loadError, systemImage: "exclamationmark.triangle")
                } else if let detail {
                    if detail.supported.assignments {
                        PipoV03Section(title: "Assignments", systemImage: "doc.text") {
                            PipoV03ItemList(items: detail.assignments.map { item in
                                PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }, destination: URL(string: item.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL, icon: "doc.text", excerpt: item.detail, status: .unknown, calendarEntry: nil)
                            }, configuration: configuration, onOpenURL: onOpenURL, seenIDs: [], onSeen: { _ in }, onSnooze: { _, _ in })
                        }
                    }
                    if detail.supported.grades {
                        PipoV03Section(title: "Published grades", systemImage: "checkmark.seal") {
                            PipoCourseGrades(grades: detail.grades, onOpenURL: onOpenURL)
                        }
                    }
                    if detail.supported.announcements && !detail.announcements.isEmpty {
                        PipoV03Section(title: "Announcements", systemImage: "megaphone") {
                            PipoV03ItemList(items: detail.announcements.map { item in
                                PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.courseName, date: item.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }, destination: URL(string: item.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL, icon: "megaphone", excerpt: item.excerpt, status: nil, calendarEntry: nil)
                            }, configuration: configuration, onOpenURL: onOpenURL, seenIDs: [], onSeen: { _ in }, onSnooze: { _, _ in })
                        }
                    }
                    if detail.supported.resources && !detail.resources.isEmpty {
                        PipoV03Section(title: "Resources", systemImage: "folder") {
                            PipoV03ItemList(items: detail.resources.map { item in
                                PipoV03DisplayItem(id: item.id, title: item.title, subtitle: item.resourceKind ?? item.courseName, date: item.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }, destination: URL(string: item.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL, icon: "folder", excerpt: item.excerpt, status: nil, calendarEntry: nil)
                            }, configuration: configuration, onOpenURL: onOpenURL, seenIDs: [], onSeen: { _ in }, onSnooze: { _, _ in })
                        }
                    }
                    if !detail.failures.isEmpty {
                        PipoStateBanner(title: "Some course sections unavailable", message: detail.failures.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Course")
        .task(id: course.id) {
            guard let courseID = Int(course.id) else { loadError = "This course identifier is invalid."; isLoading = false; return }
            do {
                detail = try await onLoadCourse(courseID)
                loadError = nil
            } catch {
                loadError = "Reconnect and try again."
            }
            isLoading = false
        }
    }
}

@MainActor
public struct PipoV03SettingsView: View {
    @Bindable private var model: PipoModel
    private let onSignOut: () -> Void
    private let onInstallUpdate: (@MainActor () -> Void)?
    private let configuration: PipoUIConfiguration
    @AppStorage("pipo.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("pipo.reminders.day-before") private var reminder24Hours = true
    @AppStorage("pipo.reminders.hour-before") private var reminderOneHour = true
    @AppStorage("pipo.quiet-hours.start") private var quietStart = 22
    @AppStorage("pipo.quiet-hours.end") private var quietEnd = 7
    @AppStorage("pipo.updates.channel") private var updateChannel = "stable"
    @State private var isSignOutConfirmationPresented = false
    @State private var storageMessage: String?
    @State private var isRetryingSecureStorage = false

    public init(model: PipoModel, onSignOut: @escaping () -> Void = {}, onInstallUpdate: (@MainActor () -> Void)? = nil, configuration: PipoUIConfiguration) {
        self._model = Bindable(model)
        self.onSignOut = onSignOut
        self.onInstallUpdate = onInstallUpdate
        self.configuration = configuration
    }

    public var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("LMS origin") { Text(PipoFoundation.lmsOrigin.host ?? "lms.lpucavite.edu.ph").foregroundStyle(.secondary).textSelection(.enabled) }
                Button { NSWorkspace.shared.open(PipoFoundation.lmsOrigin) } label: { Label("Open LMS in browser", systemImage: "safari") }
                LabeledContent("Last successful sync") {
                    if let refreshDate = model.refreshDate {
                        Text(refreshDate, style: .relative).foregroundStyle(.secondary)
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Sync") {
                Toggle("Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, value in model.settings.notificationsEnabled = value }
                HStack {
                    Text("Refresh every \(Int(model.settings.refreshInterval / 60)) minutes")
                    Slider(value: Binding(get: { model.settings.refreshInterval / 60 }, set: { model.settings.refreshInterval = $0 * 60 }), in: 5...60, step: 5)
                }
                Button { Task { try? await configuration.refresh() } } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
            }

            Section("Reminders") {
                Toggle("24 hours before deadline", isOn: $reminder24Hours)
                    .onChange(of: reminder24Hours) { _, value in model.settings.reminderDayBefore = value }
                Toggle("1 hour before deadline", isOn: $reminderOneHour)
                    .onChange(of: reminderOneHour) { _, value in model.settings.reminderHourBefore = value }
                Picker("Quiet hours start", selection: $quietStart) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .onChange(of: quietStart) { _, value in model.settings.quietHoursStart = value }
                Picker("Quiet hours end", selection: $quietEnd) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .onChange(of: quietEnd) { _, value in model.settings.quietHoursEnd = value }
            }

            Section("Notification categories") {
                Toggle("Assignments", isOn: $model.settings.assignmentNotifications)
                Toggle("Announcements", isOn: $model.settings.announcementNotifications)
                Toggle("Messages", isOn: $model.settings.messageNotifications)
                Toggle("Grade feedback", isOn: $model.settings.gradeNotifications)
            }

            Section("Courses") {
                if model.localState.pinnedCourseIDs.isEmpty && model.localState.hiddenCourseIDs.isEmpty {
                    Text("No pinned or hidden courses").foregroundStyle(.secondary)
                }
                ForEach(model.localState.pinnedCourseIDs.sorted(), id: \.self) { id in
                    Button("Unpin course \(id)", systemImage: "pin.slash") {
                        Task { await model.setPinnedCourse(id, pinned: false) }
                    }
                }
                ForEach(model.localState.hiddenCourseIDs.sorted(), id: \.self) { id in
                    Button("Show hidden course \(id)", systemImage: "eye") {
                        Task { await model.setHiddenCourse(id, hidden: false) }
                    }
                }
            }

            Section("Calendar") {
                LabeledContent("Authorization", value: model.calendarAuthorizationDescription)
                Button("Allow Calendar access", systemImage: "calendar.badge.plus") {
                    Task { _ = try? await model.requestCalendarAccess() }
                }
            }

            Section("Capabilities") {
                PipoV03CapabilityRow(title: "Schedule", supported: model.snapshot?.supported.schedule ?? false)
                PipoV03CapabilityRow(title: "Submission status", supported: model.snapshot?.supported.submissionStatus ?? false)
                PipoV03CapabilityRow(title: "Announcements", supported: model.snapshot?.supported.announcements ?? false)
                PipoV03CapabilityRow(title: "Resources", supported: model.snapshot?.supported.resources ?? false)
                if let failures = model.snapshot?.failures, !failures.isEmpty { Text(failures.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Storage") {
                if secureStorageNeedsRecovery {
                    PipoV03SecureStorageRecoveryRow(
                        isRetrying: isRetryingSecureStorage,
                        message: secureStorageGuidance,
                        retry: retrySecureStorage
                    )
                }
                Button { Task { do { try await configuration.clearCache(); storageMessage = "Saved dashboard cleared." } catch { storageMessage = "Could not clear saved dashboard." } } } label: { Label("Clear saved dashboard", systemImage: "trash") }
                if let storageMessage { Text(storageMessage).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Updates") {
                Picker("Channel", selection: $updateChannel) { Text("Stable").tag("stable"); Text("Beta").tag("beta") }
                    .onChange(of: updateChannel) { _, value in
                        UserDefaults.standard.set(value, forKey: "pipo.updates.channel")
                        NotificationCenter.default.post(name: Notification.Name("com.jazztinn.pipo.update-channel-changed"), object: nil)
                    }
                if let onInstallUpdate { Button(action: onInstallUpdate) { Label("Check for updates", systemImage: "arrow.down.circle") } }
                LabeledContent("Version") { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development").foregroundStyle(.secondary) }
            }

            Section("Diagnostics") {
                if let exportDiagnostics = configuration.exportDiagnostics { Button(action: exportDiagnostics) { Label("Export redacted diagnostics", systemImage: "doc.badge.gearshape") } }
                Text("Diagnostics exclude tokens, message bodies, grades, excerpts, and student identity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                LabeledContent("Pipo", value: "LPU Cavite LMS companion")
                Text("Read-only access. Pipo does not submit work or change LMS records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section { Button("Sign out", role: .destructive) { isSignOutConfirmationPresented = true } }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            model.settings.notificationsEnabled = notificationsEnabled
            model.settings.reminderDayBefore = reminder24Hours
            model.settings.reminderHourBefore = reminderOneHour
            model.settings.quietHoursStart = quietStart
            model.settings.quietHoursEnd = quietEnd
        }
        .confirmationDialog("Sign out of Pipo?", isPresented: $isSignOutConfirmationPresented, titleVisibility: .visible) {
            Button("Sign out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pipo will remove your LMS token and saved dashboard from this Mac.")
        }
    }

    private var secureStorageNeedsRecovery: Bool {
        switch configuration.secureStorageStatus() {
        case .denied, .unavailable:
            true
        default:
            false
        }
    }

    private var secureStorageGuidance: String {
        switch configuration.secureStorageStatus() {
        case .denied:
            "Pipo cannot access saved login right now. Allow Keychain access, then try again."
        case .unavailable:
            "Pipo cannot reach macOS secure storage right now. Try again when Keychain is available."
        default:
            ""
        }
    }

    private func retrySecureStorage() {
        guard !isRetryingSecureStorage else { return }
        isRetryingSecureStorage = true
        Task { @MainActor in
            await configuration.retrySecureStorageAccess()
            isRetryingSecureStorage = false
        }
    }
}

@MainActor
private struct PipoV03SecureStorageRecoveryRow: View {
    let isRetrying: Bool
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Secure storage needs attention", systemImage: "key.slash")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .disabled(isRetrying)
            .accessibilityHint("Checks secure storage again. No access is requested until you choose this button.")
        }
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private struct PipoV03CapabilityRow: View {
    let title: String
    let supported: Bool

    var body: some View {
        Label(title, systemImage: supported ? "checkmark.circle" : "minus.circle")
            .foregroundStyle(supported ? .primary : .secondary)
            .accessibilityValue(supported ? "Supported" : "Unavailable")
    }
}

@MainActor
private struct PipoV03FilterBar: View {
    @Binding var query: String
    @Binding var courseFilter: String
    @Binding var itemFilter: PipoV03ItemFilter
    let courses: [String]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search today", text: $query).textFieldStyle(.plain)
            if !query.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly).buttonStyle(.plain) }
            Menu {
                Button("All courses") { courseFilter = "All courses" }
                Divider()
                ForEach(courses, id: \.self) { course in Button(course) { courseFilter = course } }
                Divider()
                ForEach(PipoV03ItemFilter.allCases) { filter in Button(filter.title) { itemFilter = filter } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .help("Filter dashboard")
            .accessibilityLabel("Filter dashboard")
        }
        .padding(10)
        .background(PipoV03Palette.row, in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
private struct PipoV03Section<Content: View>: View {
    let title: String
    let systemImage: String
    let retry: (() -> Void)?
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, retry: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.retry = retry
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(PipoV03Palette.maroon)
                Spacer()
                if let retry {
                    Button("Retry \(title)", systemImage: "arrow.clockwise", action: retry)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Retry \(title)")
                }
            }
            content
        }
    }
}

@MainActor
private struct PipoV03ItemList: View {
    let items: [PipoV03DisplayItem]
    let configuration: PipoUIConfiguration
    let onOpenURL: (URL) -> Void
    let seenIDs: Set<String>
    let onSeen: (String) -> Void
    let onSnooze: (String, Date?) -> Void
    @State private var customSnoozeItem: PipoV03DisplayItem?
    @State private var customSnoozeDate = Date().addingTimeInterval(3_600)

    var body: some View {
        VStack(spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        onSeen(item.id)
                        if let destination = item.destination { onOpenURL(destination) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .foregroundStyle(PipoV03Palette.maroon)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(item.title).font(.body.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    if !seenIDs.contains(item.id) { Circle().fill(PipoV03Palette.gold).frame(width: 6, height: 6).accessibilityLabel("New") }
                                }
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let excerpt = item.excerpt, !excerpt.isEmpty { Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                if let status = item.status, status != .unknown { Label(status.title, systemImage: status.icon).font(.caption2).foregroundStyle(status == .submitted || status == .graded ? .green : .secondary) }
                            }
                            Spacer(minLength: 4)
                            if let date = item.date { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            if item.destination != nil { Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(PipoV03Palette.gold).accessibilityHidden(true) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Menu {
                        if let destination = item.destination { Button("Open in LMS", systemImage: "arrow.up.right") { onSeen(item.id); onOpenURL(destination) } }
                        Button("Copy details", systemImage: "doc.on.doc") { copy(item) }
                        if let entry = item.calendarEntry, configuration.addToCalendar != nil { Button("Add to Calendar", systemImage: "calendar.badge.plus") { configuration.addToCalendar?(entry) } }
                        if configuration.snooze != nil {
                            Divider()
                            Button("Snooze 1 hour", systemImage: "clock") { onSnooze(item.id, Date().addingTimeInterval(3_600)) }
                            Button("Snooze until tomorrow", systemImage: "sunrise") {
                                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? .now
                                onSnooze(item.id, Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow))
                            }
                            Button("Choose date", systemImage: "calendar") {
                                customSnoozeDate = Date().addingTimeInterval(3_600)
                                customSnoozeItem = item
                            }
                        }
                        if seenIDs.contains(item.id), let undoSeen = configuration.undoSeen {
                            Button("Mark as new", systemImage: "eye.slash") { undoSeen(item.id) }
                        } else {
                            Button("Mark as seen", systemImage: "eye") { onSeen(item.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Actions")
                    .accessibilityLabel("Actions for \(item.title)")
                }
                .padding(10)
                .background(PipoV03Palette.row, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityElement(children: .contain)
            }
        }
        .sheet(item: $customSnoozeItem) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text("Snooze reminder").font(.headline)
                Text(item.title).lineLimit(2).foregroundStyle(.secondary)
                DatePicker("Remind me", selection: $customSnoozeDate, in: Date()...)
                HStack {
                    Spacer()
                    Button("Cancel") { customSnoozeItem = nil }
                    Button("Snooze") {
                        onSnooze(item.id, customSnoozeDate)
                        customSnoozeItem = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 340)
        }
    }

    private func copy(_ item: PipoV03DisplayItem) {
        let details = [item.title, item.subtitle, item.date.map { $0.formatted(date: .abbreviated, time: .shortened) }, item.destination?.absoluteString].compactMap { $0 }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }
}

@MainActor
private struct PipoV03DashboardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PipoV03SkeletonLine(width: 190, height: 24)
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 9) {
                    PipoV03SkeletonLine(width: index.isMultiple(of: 2) ? 150 : 190, height: 18)
                    PipoV03SkeletonRow()
                    PipoV03SkeletonRow(short: true)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading dashboard")
    }
}

@MainActor
private struct PipoV03CoursesSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            PipoV03SkeletonLine(width: 260, height: 32).padding(14)
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    PipoV03SkeletonLine(width: 22, height: 28)
                    VStack(alignment: .leading, spacing: 7) {
                        PipoV03SkeletonLine(width: index.isMultiple(of: 2) ? 250 : 210, height: 17)
                        PipoV03SkeletonLine(width: 150, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider().padding(.leading, 54)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading courses")
    }
}

@MainActor
private struct PipoV03CourseDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PipoV03SkeletonLine(width: 130, height: 18)
            PipoV03SkeletonRow()
            PipoV03SkeletonRow(short: true)
            PipoV03SkeletonLine(width: 150, height: 18)
            PipoV03SkeletonRow()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading course details")
    }
}

@MainActor
private struct PipoV03SkeletonLine: View {
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: min(5, height / 2))
            .fill(Color.secondary.opacity(isDimmed ? 0.12 : 0.25))
            .frame(width: width, height: height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: isDimmed)
            .onAppear {
                guard !reduceMotion else { return }
                isDimmed = true
            }
    }
}

@MainActor
private struct PipoV03SkeletonRow: View {
    var short = false

    var body: some View {
        HStack(spacing: 10) {
            PipoV03SkeletonLine(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 7) {
                PipoV03SkeletonLine(width: short ? 190 : 250, height: 16)
                PipoV03SkeletonLine(width: short ? 120 : 180, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}
