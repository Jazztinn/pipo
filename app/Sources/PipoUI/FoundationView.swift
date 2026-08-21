import AppKit
import Foundation
import PipoAppCore
import ServiceManagement
import SwiftUI

public enum PipoTab: String, CaseIterable, Identifiable {
    case today
    case courses
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Today"
        case .courses: "Courses"
        case .settings: "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .today: "sparkles"
        case .courses: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

public enum PipoAuthMethod: String, CaseIterable, Identifiable {
    case schoolAccount
    case accessToken

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .schoolAccount: "School account"
        case .accessToken: "Access token"
        }
    }
}

public enum PipoUIPhase: Equatable {
    case onboarding
    case loading
    case ready
    case empty
    case offline
    case reconnecting
    case partialFailure
    case failed(String)
}

public enum PipoAssignmentStatus: String, CaseIterable, Sendable {
    case notSubmitted = "not_submitted"
    case submitted
    case graded
    case reopened
    case unknown

    public var title: String {
        switch self {
        case .notSubmitted: "Not submitted"
        case .submitted: "Submitted"
        case .graded: "Graded"
        case .reopened: "Reopened"
        case .unknown: "Status unavailable"
        }
    }

    public var icon: String {
        switch self {
        case .notSubmitted: "circle"
        case .submitted: "checkmark.circle"
        case .graded: "checkmark.seal"
        case .reopened: "arrow.uturn.backward.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

public struct PipoScheduleItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let startsAt: Date
    public let endsAt: Date?
    public let destination: URL?

    public init(id: String, title: String, courseName: String, startsAt: Date, endsAt: Date? = nil, destination: URL? = nil) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.destination = destination
    }
}

public struct PipoAnnouncementItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let date: Date?
    public let excerpt: String?
    public let destination: URL?

    public init(id: String, title: String, courseName: String, date: Date? = nil, excerpt: String? = nil, destination: URL? = nil) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.date = date
        self.excerpt = excerpt
        self.destination = destination
    }
}

public struct PipoResourceItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let kind: String?
    public let date: Date?
    public let destination: URL?

    public init(id: String, title: String, courseName: String, kind: String? = nil, date: Date? = nil, destination: URL? = nil) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.kind = kind
        self.date = date
        self.destination = destination
    }
}

public struct PipoCalendarEntry: Equatable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let startsAt: Date
    public let endsAt: Date?
    public let destination: URL?

    public init(id: String, title: String, courseName: String, startsAt: Date, endsAt: Date? = nil, destination: URL? = nil) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.destination = destination
    }
}

public struct PipoFeatureSupport: Equatable, Sendable {
    public let schedule: Bool
    public let announcements: Bool
    public let resources: Bool
    public let submissionStatus: Bool

    public static let all = PipoFeatureSupport()

    public init(schedule: Bool = true, announcements: Bool = true, resources: Bool = true, submissionStatus: Bool = true) {
        self.schedule = schedule
        self.announcements = announcements
        self.resources = resources
        self.submissionStatus = submissionStatus
    }
}

public struct PipoTaskItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let dueDate: Date?
    public let destination: URL?
    public let excerpt: String?
    public let status: PipoAssignmentStatus

    public init(
        id: String,
        title: String,
        courseName: String,
        dueDate: Date? = nil,
        destination: URL? = nil,
        excerpt: String? = nil,
        status: PipoAssignmentStatus = .unknown
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.dueDate = dueDate
        self.destination = destination
        self.excerpt = excerpt
        self.status = status
    }
}

public struct PipoNotificationItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let date: Date?
    public let destination: URL?

    public init(
        id: String,
        title: String,
        courseName: String,
        date: Date? = nil,
        destination: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.date = date
        self.destination = destination
    }
}

public struct PipoMessageItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let date: Date?
    public let destination: URL?

    public init(
        id: String,
        title: String,
        courseName: String,
        date: Date? = nil,
        destination: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.date = date
        self.destination = destination
    }
}

public struct PipoGradeFeedbackItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let courseName: String
    public let date: Date?
    public let destination: URL?

    public init(
        id: String,
        title: String,
        courseName: String,
        date: Date? = nil,
        destination: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.date = date
        self.destination = destination
    }
}

public struct PipoCourseItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let shortName: String
    public let publishedTotal: String?
    public let upcomingCount: Int

    public init(id: String, name: String, shortName: String, publishedTotal: String? = nil, upcomingCount: Int = 0) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.publishedTotal = publishedTotal
        self.upcomingCount = upcomingCount
    }
}

public struct PipoFailureItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let section: String
    public let message: String

    public init(id: String, section: String, message: String) {
        self.id = id
        self.section = section
        self.message = message
    }
}

public struct PipoDashboardSnapshot: Equatable, Sendable {
    public let studentName: String?
    public let generatedAt: Date?
    public let cachedAt: Date?
    public let dueSoon: [PipoTaskItem]
    public let notifications: [PipoNotificationItem]
    public let newAssignments: [PipoTaskItem]
    public let messages: [PipoMessageItem]
    public let gradeFeedback: [PipoGradeFeedbackItem]
    public let courses: [PipoCourseItem]
    public let failures: [PipoFailureItem]
    public let supported: DashboardSectionSupport
    public let featureSupport: PipoFeatureSupport
    public let nextUp: [PipoTaskItem]
    public let schedule: [PipoScheduleItem]
    public let announcements: [PipoAnnouncementItem]
    public let resources: [PipoResourceItem]

    public init(
        studentName: String? = nil,
        generatedAt: Date? = nil,
        cachedAt: Date? = nil,
        dueSoon: [PipoTaskItem] = [],
        notifications: [PipoNotificationItem] = [],
        newAssignments: [PipoTaskItem] = [],
        messages: [PipoMessageItem] = [],
        gradeFeedback: [PipoGradeFeedbackItem] = [],
        courses: [PipoCourseItem] = [],
        failures: [PipoFailureItem] = [],
        supported: DashboardSectionSupport = .all,
        featureSupport: PipoFeatureSupport = .all,
        nextUp: [PipoTaskItem] = [],
        schedule: [PipoScheduleItem] = [],
        announcements: [PipoAnnouncementItem] = [],
        resources: [PipoResourceItem] = []
    ) {
        self.studentName = studentName
        self.generatedAt = generatedAt
        self.cachedAt = cachedAt
        self.dueSoon = dueSoon
        self.notifications = notifications
        self.newAssignments = newAssignments
        self.messages = messages
        self.gradeFeedback = gradeFeedback
        self.courses = courses
        self.failures = failures
        self.supported = supported
        self.featureSupport = featureSupport
        self.nextUp = nextUp
        self.schedule = schedule
        self.announcements = announcements
        self.resources = resources
    }

    public var uniqueNewAssignments: [PipoTaskItem] {
        let dueIDs = Set(dueSoon.map(\.id))
        return newAssignments.filter { !dueIDs.contains($0.id) }
    }

    public var isEmpty: Bool {
        dueSoon.isEmpty && notifications.isEmpty && uniqueNewAssignments.isEmpty && messages.isEmpty && gradeFeedback.isEmpty && courses.isEmpty && nextUp.isEmpty && schedule.isEmpty && announcements.isEmpty && resources.isEmpty
    }

    public var urgentCount: Int {
        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)
        let deadlines = dueSoon + uniqueNewAssignments
        return deadlines.filter { item in
            guard let dueDate = item.dueDate else { return false }
            return dueDate <= tomorrow && item.status != .submitted && item.status != .graded
        }.count
    }

    public func deadlineGroups(now: Date = Date(), calendar: Calendar = .current) -> [(String, [PipoTaskItem])] {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: start) ?? tomorrow
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? dayAfter
        let groups: [(String, Date, Date?)] = [
            ("Overdue", .distantPast, start),
            ("Today", start, tomorrow),
            ("Tomorrow", tomorrow, dayAfter),
            ("This week", dayAfter, weekEnd),
            ("Later", weekEnd, nil)
        ]
        let deadlines = dueSoon + uniqueNewAssignments
        return groups.compactMap { title, lower, upper in
            let items = deadlines.filter { item in
                guard let date = item.dueDate else { return title == "Later" }
                return date >= lower && (upper == nil || date < upper!)
            }
            return items.isEmpty ? nil : (title, items)
        }
    }
}

@MainActor
public struct PipoUIConfiguration {
    public var modelBacked: Bool
    public var initialPhase: PipoUIPhase
    public var initialSnapshot: PipoDashboardSnapshot?
    public var signInWithPassword: @MainActor (String, String) async throws -> Void
    public var signInWithToken: @MainActor (String) async throws -> Void
    public var refresh: @MainActor () async throws -> PipoDashboardSnapshot?
    public var refreshSection: @MainActor (String) async throws -> PipoDashboardSnapshot?
    public var signOut: @MainActor () async throws -> Void
    public var loadCourse: @MainActor (Int) async throws -> CourseDetail?
    public var openURL: @MainActor (URL) -> Void
    public var installUpdate: (@MainActor () -> Void)?
    public var clearCache: @MainActor () async throws -> Void
    public var exportDiagnostics: (@MainActor () -> Void)?
    public var addToCalendar: (@MainActor (PipoCalendarEntry) -> Void)?
    public var snooze: (@MainActor (String, Date?) -> Void)?
    public var markSeen: (@MainActor (String) -> Void)?

    public init(
        modelBacked: Bool = false,
        initialPhase: PipoUIPhase = .onboarding,
        initialSnapshot: PipoDashboardSnapshot? = nil,
        signInWithPassword: @escaping @MainActor (String, String) async throws -> Void = { _, _ in },
        signInWithToken: @escaping @MainActor (String) async throws -> Void = { _ in },
        refresh: @escaping @MainActor () async throws -> PipoDashboardSnapshot? = { nil },
        refreshSection: @escaping @MainActor (String) async throws -> PipoDashboardSnapshot? = { _ in nil },
        signOut: @escaping @MainActor () async throws -> Void = {},
        loadCourse: @escaping @MainActor (Int) async throws -> CourseDetail? = { _ in nil },
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        installUpdate: (@MainActor () -> Void)? = nil,
        clearCache: @escaping @MainActor () async throws -> Void = {},
        exportDiagnostics: (@MainActor () -> Void)? = nil,
        addToCalendar: (@MainActor (PipoCalendarEntry) -> Void)? = nil,
        snooze: (@MainActor (String, Date?) -> Void)? = nil,
        markSeen: (@MainActor (String) -> Void)? = nil
    ) {
        self.modelBacked = modelBacked
        self.initialPhase = initialPhase
        self.initialSnapshot = initialSnapshot
        self.signInWithPassword = signInWithPassword
        self.signInWithToken = signInWithToken
        self.refresh = refresh
        self.refreshSection = refreshSection
        self.signOut = signOut
        self.loadCourse = loadCourse
        self.openURL = openURL
        self.installUpdate = installUpdate
        self.clearCache = clearCache
        self.exportDiagnostics = exportDiagnostics
        self.addToCalendar = addToCalendar
        self.snooze = snooze
        self.markSeen = markSeen
    }

    public init(model: PipoModel, installUpdate: (@MainActor () -> Void)? = nil) {
        self.init(
            modelBacked: true,
            initialPhase: Self.phase(for: model.phase),
            initialSnapshot: model.snapshot.map(Self.snapshot(from:)),
            signInWithPassword: { username, password in
                await model.signIn(username: username, password: password)
            },
            signInWithToken: { token in
                await model.signIn(withToken: token)
            },
            refresh: {
                await model.refresh(force: true)
                return model.snapshot.map(Self.snapshot(from:))
            },
            refreshSection: { _ in
                await model.refresh(force: true)
                return model.snapshot.map(Self.snapshot(from:))
            },
            signOut: {
                await model.signOut()
            },
            loadCourse: { courseID in
                try await model.loadCourse(id: courseID)
            },
            openURL: { url in
                Task { @MainActor in
                    await model.openURL(for: DashboardItem(
                        id: url.absoluteString,
                        kind: "destination",
                        title: "LMS destination",
                        courseName: "LPU Cavite LMS",
                        destination: url.absoluteString
                    ))
                }
            },
            installUpdate: installUpdate
        )
    }

    private static func phase(for phase: PipoPhase) -> PipoUIPhase {
        switch phase {
        case .signedOut: .onboarding
        case .authenticating, .loading: .loading
        case .ready: .ready
        case .offline: .offline
        case .failed(let message): .failed(message)
        }
    }

    fileprivate static func snapshot(from snapshot: DashboardSnapshot) -> PipoDashboardSnapshot {
        let generatedAt = ISO8601DateFormatter().date(from: snapshot.generatedAt)
        return PipoDashboardSnapshot(
            studentName: snapshot.studentName,
            generatedAt: generatedAt,
            cachedAt: generatedAt,
            dueSoon: snapshot.sections.dueSoon.map(item(from:)),
            notifications: snapshot.sections.notifications.map(notification(from:)),
            newAssignments: snapshot.sections.newAssignments.map(item(from:)),
            messages: snapshot.sections.messages.map(message(from:)),
            gradeFeedback: snapshot.sections.gradeFeedback.map(gradeFeedback(from:)),
            courses: snapshot.courses.map { course in
                PipoCourseItem(id: String(course.id), name: course.name, shortName: course.shortName ?? "", publishedTotal: course.publishedTotal, upcomingCount: course.upcomingCount)
            },
            failures: snapshot.failures.enumerated().map { index, failure in
                let parts = failure.split(separator: ":", maxSplits: 1).map(String.init)
                return PipoFailureItem(id: "failure-\(index)", section: parts.first ?? "LMS", message: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : failure)
            },
            supported: snapshot.supported,
            featureSupport: PipoFeatureSupport(
                schedule: snapshot.supported.schedule,
                announcements: snapshot.supported.announcements,
                resources: snapshot.supported.resources,
                submissionStatus: snapshot.supported.submissionStatus
            ),
            nextUp: snapshot.nextUp.map(item(from:)),
            schedule: snapshot.schedule.map(schedule(from:)),
            announcements: snapshot.announcements.map(announcement(from:)),
            resources: snapshot.resources.map(resource(from:))
        )
    }

    private static func destination(from item: DashboardItem) -> URL? {
        guard !item.destination.isEmpty else { return nil }
        return URL(string: item.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL
    }

    private static func date(from item: DashboardItem) -> Date? {
        guard let timestamp = item.timestamp else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
    }

    private static func item(from item: DashboardItem) -> PipoTaskItem {
        PipoTaskItem(id: item.id, title: item.title, courseName: item.courseName, dueDate: date(from: item), destination: destination(from: item), excerpt: item.excerpt, status: PipoAssignmentStatus(rawValue: item.submissionStatus ?? "") ?? .unknown)
    }

    private static func schedule(from item: DashboardItem) -> PipoScheduleItem {
        PipoScheduleItem(id: item.id, title: item.title, courseName: item.courseName, startsAt: date(from: item) ?? .now, destination: destination(from: item))
    }

    private static func announcement(from item: DashboardItem) -> PipoAnnouncementItem {
        PipoAnnouncementItem(id: item.id, title: item.title, courseName: item.courseName, date: date(from: item), excerpt: item.excerpt, destination: destination(from: item))
    }

    private static func resource(from item: DashboardItem) -> PipoResourceItem {
        PipoResourceItem(id: item.id, title: item.title, courseName: item.courseName, kind: item.resourceKind, date: date(from: item), destination: destination(from: item))
    }

    private static func notification(from item: DashboardItem) -> PipoNotificationItem {
        PipoNotificationItem(id: item.id, title: item.title, courseName: item.courseName, date: date(from: item), destination: destination(from: item))
    }

    private static func message(from item: DashboardItem) -> PipoMessageItem {
        PipoMessageItem(id: item.id, title: item.title, courseName: item.courseName, date: date(from: item), destination: destination(from: item))
    }

    private static func gradeFeedback(from item: DashboardItem) -> PipoGradeFeedbackItem {
        PipoGradeFeedbackItem(id: item.id, title: item.title, courseName: item.courseName, date: date(from: item), destination: destination(from: item))
    }
}

@MainActor
public struct PipoCompanionView: View {
    @Bindable private var model: PipoModel
    private let installUpdate: (@MainActor () -> Void)?

    public init(model: PipoModel, installUpdate: (@MainActor () -> Void)? = nil) {
        self._model = Bindable(model)
        self.installUpdate = installUpdate
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .signedOut:
                onboarding()
            case .authenticating, .loading:
                VStack(spacing: 18) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("Connecting to LPU Cavite LMS")
                        .font(.title3.weight(.semibold))
                    PipoSkeletonLine(width: 280, height: 18)
                    PipoSkeletonLine(width: 220, height: 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Connecting to LPU Cavite LMS")
            case .failed(_):
                onboarding(error: model.authenticationError)
            default:
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .frame(width: 54, height: 54)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Pipo")
                                .font(.title2.bold())
                            Text(model.snapshot?.studentName.isEmpty == false ? model.snapshot?.studentName ?? "LPU Cavite student" : "LPU Cavite student")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Label(model.phase == .offline ? "Offline" : "Connected", systemImage: model.phase == .offline ? "wifi.slash" : "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(model.phase == .offline ? PipoPalette.warning : .green)
                    }
                    .padding(20)

                    Divider()

                    PipoV03SettingsView(
                        model: model,
                        onSignOut: {
                            Task { @MainActor in await model.signOut() }
                        },
                        configuration: PipoUIConfiguration(model: model, installUpdate: installUpdate)
                    )
                }
            }
        }
        .background(PipoPalette.windowBackground)
    }

    @ViewBuilder
    private func onboarding(error: String? = nil) -> some View {
        PipoOnboardingView(
            externalError: error,
            onPasswordSignIn: { username, password in
                Task { @MainActor in await model.signIn(username: username, password: password) }
            },
            onTokenSignIn: { token in
                Task { @MainActor in await model.signIn(withToken: token) }
            },
            onOpenURL: { NSWorkspace.shared.open($0) }
        )
    }
}

@MainActor
public struct PipoRootView: View {
    private let model: PipoModel
    private let configuration: PipoUIConfiguration
    @State private var phase: PipoUIPhase
    @State private var snapshot: PipoDashboardSnapshot?
    @State private var selectedTab: PipoTab = .today
    @State private var selectedCourseID: String?
    @State private var isSignOutConfirmationPresented = false

    public init(model: PipoModel, configuration: PipoUIConfiguration = PipoUIConfiguration()) {
        self.model = model
        let resolvedConfiguration = configuration.modelBacked ? configuration : PipoUIConfiguration(model: model)
        self.configuration = resolvedConfiguration
        _phase = State(initialValue: resolvedConfiguration.initialPhase)
        _snapshot = State(initialValue: resolvedConfiguration.initialSnapshot)
        _selectedTab = State(initialValue: {
            switch model.selectedTab {
            case .dashboard: .today
            case .courses: .courses
            case .settings: .settings
            }
        }())
    }

    public var body: some View {
        let visiblePhase = configuration.modelBacked ? phase(for: model.phase) : phase
        let visibleSnapshot = configuration.modelBacked ? model.snapshot.map(PipoUIConfiguration.snapshot(from:)) : snapshot

        Group {
            if visiblePhase == .onboarding {
                PipoOnboardingView(
                    onPasswordSignIn: signInWithPassword,
                    onTokenSignIn: signInWithToken,
                    onOpenURL: openURL
                )
            } else {
                PipoWorkspaceView(
                    model: model,
                    configuration: configuration,
                    phase: visiblePhase,
                    snapshot: visibleSnapshot,
                    selectedTab: $selectedTab,
                    selectedCourseID: $selectedCourseID,
                    onRefresh: refresh,
                    onReconnect: refresh,
                    onLoadCourse: configuration.loadCourse,
                    onOpenURL: openURL,
                    onSnapshot: { snapshot = $0 },
                    onSettings: { selectedTab = .settings },
                    onSignOut: { isSignOutConfirmationPresented = true },
                    onInstallUpdate: configuration.installUpdate
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipoPalette.windowBackground)
        .confirmationDialog(
            "Sign out of Pipo?",
            isPresented: $isSignOutConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: signOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pipo will remove your LMS token and saved dashboard from this Mac.")
        }
    }

    private func signInWithPassword(username: String, password: String) {
        phase = .loading
        Task { @MainActor in
            do {
                try await configuration.signInWithPassword(username, password)
                snapshot = configuration.initialSnapshot
                phase = snapshot?.isEmpty == false ? .ready : .empty
            } catch {
                phase = .failed("Sign-in failed. Check your details and try again.")
            }
        }
    }

    private func signInWithToken(token: String) {
        phase = .loading
        Task { @MainActor in
            do {
                try await configuration.signInWithToken(token)
                snapshot = configuration.initialSnapshot
                phase = snapshot?.isEmpty == false ? .ready : .empty
            } catch {
                phase = .failed("Token sign-in failed. Check the token and try again.")
            }
        }
    }

    private func refresh() {
        guard phase != .reconnecting else { return }
        phase = .reconnecting
        Task { @MainActor in
            do {
                if let refreshed = try await configuration.refresh() {
                    snapshot = refreshed
                }
                phase = snapshot?.isEmpty == false ? .ready : .empty
            } catch {
                phase = .offline
            }
        }
    }

    private func signOut() {
        Task { @MainActor in
            try? await configuration.signOut()
            phase = .onboarding
            snapshot = nil
            selectedCourseID = nil
        }
    }

    private func openURL(_ url: URL) {
        configuration.openURL(url)
    }

    private func phase(for phase: PipoPhase) -> PipoUIPhase {
        switch phase {
        case .signedOut: .onboarding
        case .authenticating, .loading: .loading
        case .ready: .ready
        case .offline: .offline
        case .failed(let message): .failed(message)
        }
    }
}

@MainActor
private struct PipoOnboardingView: View {
    @State private var authMethod: PipoAuthMethod = .schoolAccount
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var validationMessage: String?
    var externalError: String? = nil
    let onPasswordSignIn: (String, String) -> Void
    let onTokenSignIn: (String) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(PipoPalette.maroon)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pipo")
                            .font(.title.bold())
                        Text("Your LMS, close at hand")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect to LPU Cavite LMS")
                        .font(.headline)
                    Text("Pipo reads courses, deadlines, notices, messages, and published grades from the school LMS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Sign-in method", selection: $authMethod) {
                    ForEach(PipoAuthMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if authMethod == .schoolAccount {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("LMS username", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.username)
                        SecureField("LMS password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                        Button(action: submitPassword) {
                            Label("Sign in", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PipoPalette.maroon)
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Paste access token", text: $token)
                            .textFieldStyle(.roundedBorder)
                        Button(action: submitToken) {
                            Label("Use token", systemImage: "key.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PipoPalette.maroon)
                        .keyboardShortcut(.defaultAction)
                    }
                }

                if let message = validationMessage ?? externalError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(PipoPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(message)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Read-only access", systemImage: "eye.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Your password is used once for token exchange and is discarded. Pipo does not submit work or change LMS records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    onOpenURL(PipoFoundation.lmsOrigin)
                } label: {
                    Label("Open LPU Cavite LMS", systemImage: "safari")
                }
                .buttonStyle(.link)
                .help("Open the school LMS in your browser")
            }
            .padding(24)
        }
    }

    private func submitPassword() {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Enter your LMS username."
            return
        }
        guard !password.isEmpty else {
            validationMessage = "Enter your LMS password."
            return
        }
        validationMessage = nil
        let submittedPassword = password
        password = ""
        onPasswordSignIn(username, submittedPassword)
    }

    private func submitToken() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Paste an access token to continue."
            return
        }
        validationMessage = nil
        let submittedToken = token
        token = ""
        onTokenSignIn(submittedToken)
    }
}

@MainActor
private struct PipoWorkspaceView: View {
    let model: PipoModel
    let configuration: PipoUIConfiguration
    let phase: PipoUIPhase
    let snapshot: PipoDashboardSnapshot?
    @Binding var selectedTab: PipoTab
    @Binding var selectedCourseID: String?
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onLoadCourse: @MainActor (Int) async throws -> CourseDetail?
    let onOpenURL: (URL) -> Void
    let onSnapshot: (PipoDashboardSnapshot) -> Void
    let onSettings: () -> Void
    let onSignOut: () -> Void
    let onInstallUpdate: (@MainActor () -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let snapshot, !snapshot.failures.isEmpty {
                    PipoPartialBanner(failures: snapshot.failures, onRefresh: onRefresh)
                }

                Group {
                    switch selectedTab {
                    case .today:
                        PipoV03TodayView(
                            phase: phase,
                            snapshot: snapshot,
                            onRefresh: onRefresh,
                            onReconnect: onReconnect,
                            onOpenURL: onOpenURL,
                            onInstallUpdate: onInstallUpdate,
                            configuration: configuration,
                            onSnapshot: onSnapshot
                        )
                    case .courses:
                        PipoV03CoursesView(
                            phase: phase,
                            courses: snapshot?.courses ?? [],
                            selectedCourseID: $selectedCourseID,
                            onRefresh: onRefresh,
                            onReconnect: onReconnect,
                            onLoadCourse: onLoadCourse,
                            onOpenURL: onOpenURL,
                            configuration: configuration,
                            onSnapshot: onSnapshot
                        )
                    case .settings:
                        PipoV03SettingsView(
                            model: model,
                            onSignOut: onSignOut,
                            onInstallUpdate: onInstallUpdate,
                            configuration: configuration
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                Picker("Section", selection: $selectedTab) {
                    ForEach(PipoTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityLabel("Main section")
            }
            .navigationTitle(selectedTab.title)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    PipoToolbarButton(
                        title: phase == .reconnecting ? "Refreshing" : "Refresh",
                        systemImage: "arrow.clockwise",
                        isDisabled: phase == .reconnecting,
                        action: onRefresh
                    )
                }
                ToolbarItem(placement: .automatic) {
                    PipoToolbarButton(
                        title: "Settings",
                        systemImage: "gearshape",
                        action: onSettings
                    )
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Open LMS") { onOpenURL(PipoFoundation.lmsOrigin) }
                        Divider()
                        Button("Sign out", role: .destructive, action: onSignOut)
                        Button("Quit Pipo") { NSApplication.shared.terminate(nil) }
                    } label: {
                        Image(systemName: "flag.fill")
                    }
                    .help("Pipo menu")
                    .accessibilityLabel("Pipo menu")
                }
            }
        }
    }
}

@MainActor
private struct PipoTodayView: View {
    let phase: PipoUIPhase
    let snapshot: PipoDashboardSnapshot?
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onOpenURL: (URL) -> Void
    let onInstallUpdate: (@MainActor () -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let snapshot, let cachedAt = snapshot.cachedAt, phase == .offline {
                    PipoOfflineBanner(cachedAt: cachedAt, onReconnect: onReconnect)
                } else if phase == .reconnecting {
                    PipoStateBanner(title: "Refreshing", message: "Checking the LMS for changes.", systemImage: "arrow.clockwise")
                }

                if phase == .loading {
                    PipoDashboardSkeleton()
                } else if let snapshot, !snapshot.isEmpty {
                    if let studentName = snapshot.studentName, !studentName.isEmpty {
                        Text("Hello, \(studentName)")
                            .font(.title3.weight(.semibold))
                    }

                    if snapshot.supported.dueSoon {
                        PipoSection(title: "Due soon", systemImage: "calendar.badge.clock") {
                            PipoItemList(items: snapshot.dueSoon.map { PipoDisplayItem(id: $0.id, title: $0.title, subtitle: $0.courseName, date: $0.dueDate, destination: $0.destination, icon: "calendar") }, onOpenURL: onOpenURL)
                        }
                    }
                    if snapshot.supported.notifications {
                        PipoSection(title: "Unread notifications", systemImage: "bell.badge") {
                            PipoItemList(items: snapshot.notifications.map { PipoDisplayItem(id: $0.id, title: $0.title, subtitle: $0.courseName, date: $0.date, destination: $0.destination, icon: "bell") }, onOpenURL: onOpenURL)
                        }
                    }
                    if snapshot.supported.assignments, !snapshot.uniqueNewAssignments.isEmpty {
                        PipoSection(title: "New assignments", systemImage: "doc.text") {
                            PipoItemList(items: snapshot.uniqueNewAssignments.map { PipoDisplayItem(id: $0.id, title: $0.title, subtitle: $0.courseName, date: $0.dueDate, destination: $0.destination, icon: "doc.text") }, onOpenURL: onOpenURL)
                        }
                    }
                    if snapshot.supported.messages {
                        PipoSection(title: "Recent messages", systemImage: "bubble.left.and.bubble.right") {
                            PipoItemList(items: snapshot.messages.map { PipoDisplayItem(id: $0.id, title: $0.title, subtitle: $0.courseName, date: $0.date, destination: $0.destination, icon: "bubble.left") }, onOpenURL: onOpenURL)
                        }
                    }
                    if snapshot.supported.grades {
                        PipoSection(title: "Grade feedback", systemImage: "checkmark.seal") {
                            PipoItemList(items: snapshot.gradeFeedback.map { PipoDisplayItem(id: $0.id, title: $0.title, subtitle: $0.courseName, date: $0.date, destination: $0.destination, icon: "checkmark.seal") }, onOpenURL: onOpenURL)
                        }
                    }
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
                    .tint(PipoPalette.gold)
                    .help("Check for a signed Pipo update")
                }
            }
            .padding(16)
        }
    }
}

@MainActor
private struct PipoCoursesView: View {
    let phase: PipoUIPhase
    let courses: [PipoCourseItem]
    @Binding var selectedCourseID: String?
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onLoadCourse: @MainActor (Int) async throws -> CourseDetail?
    let onOpenURL: (URL) -> Void

    var body: some View {
        Group {
            if phase == .loading || phase == .reconnecting {
                PipoCoursesSkeleton()
            } else if phase == .offline && courses.isEmpty {
                PipoEmptyState(title: "Courses unavailable", message: "Reconnect to load your courses.", systemImage: "wifi.slash", actionTitle: "Reconnect", action: onReconnect)
            } else if courses.isEmpty {
                PipoEmptyState(title: "No courses yet", message: "Published courses from the LMS will appear here.", systemImage: "books.vertical", actionTitle: "Refresh", action: onRefresh)
            } else {
                List(courses) { course in
                    NavigationLink(value: course.id) {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(PipoPalette.maroon)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.name)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(2)
                                Text(course.shortName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if let publishedTotal = course.publishedTotal {
                                Text(publishedTotal)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(PipoPalette.gold)
                                    .accessibilityLabel("Published grade \(publishedTotal)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .tag(course.id)
                    .accessibilityLabel(course.name)
                }
                .listStyle(.inset)
                .navigationDestination(for: String.self) { courseID in
                    if let course = courses.first(where: { $0.id == courseID }) {
                        PipoCourseDetailView(course: course, onLoadCourse: onLoadCourse, onOpenURL: onOpenURL)
                    }
                }
            }
        }
    }
}

@MainActor
private struct PipoCourseDetailView: View {
    let course: PipoCourseItem
    let onLoadCourse: @MainActor (Int) async throws -> CourseDetail?
    let onOpenURL: (URL) -> Void
    @State private var detail: CourseDetail?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(PipoPalette.maroon)
                    .accessibilityHidden(true)
                Text(course.name)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(course.shortName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let destination = detail.flatMap({ URL(string: $0.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL }) {
                    Button {
                        onOpenURL(destination)
                    } label: {
                        Label("Open course in LMS", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Published grade")
                        .font(.headline)
                    if let publishedTotal = detail?.course.publishedTotal ?? course.publishedTotal {
                        Text(publishedTotal)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(PipoPalette.gold)
                            .accessibilityLabel("Published grade \(publishedTotal)")
                    } else {
                        Text("No published grade")
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoading {
                    PipoCourseDetailSkeleton()
                } else if let loadError {
                    PipoStateBanner(title: "Course details unavailable", message: loadError, systemImage: "exclamationmark.triangle")
                } else if let detail {
                    if detail.supported.assignments {
                        PipoSection(title: "Assignments", systemImage: "doc.text") {
                            PipoItemList(
                                items: detail.assignments.map { item in
                                    PipoDisplayItem(
                                        id: item.id,
                                        title: item.title,
                                        subtitle: item.courseName,
                                        date: item.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) },
                                        destination: URL(string: item.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL,
                                        icon: "doc.text"
                                    )
                                },
                                onOpenURL: onOpenURL
                            )
                        }
                    }

                    if detail.supported.grades {
                        PipoSection(title: "Published grades", systemImage: "checkmark.seal") {
                            PipoCourseGrades(grades: detail.grades, onOpenURL: onOpenURL)
                        }
                    }

                    if !detail.failures.isEmpty {
                        Text(detail.failures.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Course")
        .task(id: course.id) {
            guard let courseID = Int(course.id) else {
                loadError = "This course identifier is invalid."
                isLoading = false
                return
            }
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
private struct PipoCourseGrades: View {
    let grades: [CourseGradeItem]
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if grades.isEmpty {
                Text("No published grade items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(grades) { grade in
                    Button {
                        if let destination = URL(string: grade.destination, relativeTo: PipoFoundation.lmsOrigin)?.absoluteURL {
                            onOpenURL(destination)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(grade.title)
                                    .font(.body.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if let publishedGrade = grade.publishedGrade {
                                    Text(publishedGrade)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(PipoPalette.gold)
                                }
                            }
                            if let feedback = grade.feedback, !feedback.isEmpty {
                                Text(feedback)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(PipoPalette.rowBackground, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel([grade.title, grade.publishedGrade, grade.feedback].compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
    }
}

@MainActor
public struct PipoSettingsView: View {
    @Bindable private var model: PipoModel
    private let onSignOut: () -> Void
    private let onInstallUpdate: (@MainActor () -> Void)?
    @AppStorage("pipo.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("pipo.launch-at-login") private var launchAtLogin = false
    @AppStorage("pipo.refresh.minutes") private var refreshMinutes = 15.0
    @State private var isSignOutConfirmationPresented = false
    @State private var launchAtLoginError: String?

    public init(
        model: PipoModel,
        onSignOut: @escaping () -> Void = {},
        onInstallUpdate: (@MainActor () -> Void)? = nil
    ) {
        self._model = Bindable(model)
        self.onSignOut = onSignOut
        self.onInstallUpdate = onInstallUpdate
    }

    public var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("LMS origin") {
                    Text(PipoFoundation.lmsOrigin.host ?? "lms.lpucavite.edu.ph")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button {
                    NSWorkspace.shared.open(PipoFoundation.lmsOrigin)
                } label: {
                    Label("Open LMS in browser", systemImage: "safari")
                }
            }

            Section("Refresh") {
                Toggle("Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        model.settings.notificationsEnabled = enabled
                    }
                Toggle("Launch Pipo at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
                HStack {
                    Text("Every \(Int(refreshMinutes)) minutes")
                    Slider(value: $refreshMinutes, in: 5...60, step: 5)
                        .accessibilityValue("\(Int(refreshMinutes)) minutes")
                        .onChange(of: refreshMinutes) { _, minutes in
                            model.settings.refreshInterval = minutes * 60
                        }
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Updates") {
                if let onInstallUpdate {
                    Button(action: onInstallUpdate) {
                        Label("Check for updates", systemImage: "arrow.down.circle")
                    }
                } else {
                    LabeledContent("Automatic updates") {
                        Text("Available after the next release")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Sign out", role: .destructive) {
                    isSignOutConfirmationPresented = true
                }
                    .accessibilityHint("Removes the current LMS session")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            model.settings.notificationsEnabled = notificationsEnabled
            model.settings.refreshInterval = refreshMinutes * 60
        }
        .confirmationDialog(
            "Sign out of Pipo?",
            isPresented: $isSignOutConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pipo will remove your LMS token and saved dashboard from this Mac.")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at login could not be changed."
        }
    }
}

private struct PipoDisplayItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let date: Date?
    let destination: URL?
    let icon: String
}

@MainActor
private struct PipoSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(PipoPalette.maroon)
            content
        }
    }
}

@MainActor
private struct PipoItemList: View {
    let items: [PipoDisplayItem]
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if items.isEmpty {
                Text("Nothing new")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(items) { item in
                    Button {
                        if let destination = item.destination {
                            onOpenURL(destination)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .foregroundStyle(PipoPalette.maroon)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let date = item.date {
                                Text(date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if item.destination != nil {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PipoPalette.gold)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .background(PipoPalette.rowBackground, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("\(item.title), \(item.subtitle)")
                    .accessibilityHint(item.destination == nil ? "No LMS link available" : "Open in the LMS")
                }
            }
        }
    }
}

@MainActor
private struct PipoEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(PipoPalette.maroon)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(PipoPalette.maroon)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

@MainActor
private struct PipoDashboardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PipoSkeletonLine(width: 190, height: 24)
            ForEach(0..<3, id: \.self) { section in
                VStack(alignment: .leading, spacing: 10) {
                    PipoSkeletonLine(width: section == 1 ? 180 : 130, height: 18)
                    PipoSkeletonRow()
                    PipoSkeletonRow(short: section == 2)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your LMS dashboard")
    }
}

@MainActor
private struct PipoCoursesSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    PipoSkeletonLine(width: 22, height: 28)
                    VStack(alignment: .leading, spacing: 7) {
                        PipoSkeletonLine(width: index.isMultiple(of: 2) ? 250 : 210, height: 17)
                        PipoSkeletonLine(width: 150, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider().padding(.leading, 54)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading courses")
    }
}

@MainActor
private struct PipoCourseDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PipoSkeletonLine(width: 120, height: 18)
            PipoSkeletonRow()
            PipoSkeletonRow(short: true)
            PipoSkeletonLine(width: 140, height: 18)
            PipoSkeletonRow()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading course details")
    }
}

@MainActor
private struct PipoSkeletonRow: View {
    var short = false

    var body: some View {
        HStack(spacing: 10) {
            PipoSkeletonLine(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 7) {
                PipoSkeletonLine(width: short ? 190 : 250, height: 16)
                PipoSkeletonLine(width: short ? 120 : 180, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

@MainActor
private struct PipoSkeletonLine: View {
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: min(5, height / 2))
            .fill(Color.secondary.opacity(isDimmed ? 0.12 : 0.25))
            .frame(width: width, height: height)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                value: isDimmed
            )
            .onAppear {
                guard !reduceMotion else { return }
                isDimmed = true
            }
    }
}

@MainActor
private struct PipoStateBanner: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PipoPalette.rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct PipoOfflineBanner: View {
    let cachedAt: Date
    let onReconnect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label("Offline", systemImage: "wifi.slash")
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing the last saved dashboard")
                    .font(.callout)
                Text("Saved \(cachedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Reconnect", action: onReconnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(PipoPalette.rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private struct PipoPartialBanner: View {
    let failures: [PipoFailureItem]
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PipoPalette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Some sections could not load")
                    .font(.callout.weight(.semibold))
                Text(failures.map(\.section).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Retry", action: onRefresh)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(PipoPalette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct PipoToolbarButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
        .modifier(PipoToolbarChrome())
    }
}

private struct PipoToolbarChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        } else {
            content
                .padding(4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private enum PipoPalette {
    static let maroon = Color(red: 0.43, green: 0.08, blue: 0.12)
    static let gold = Color(red: 0.70, green: 0.48, blue: 0.10)
    static let warning = Color.orange
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let rowBackground = Color(nsColor: .controlBackgroundColor)
}
