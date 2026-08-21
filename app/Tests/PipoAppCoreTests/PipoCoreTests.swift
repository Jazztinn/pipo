import Foundation
import Testing
@testable import PipoAppCore

@Test func dueSoonItemsAreRemovedFromNewAssignments() {
    let duplicate = DashboardItem(id: "42", kind: "assignment", title: "Reflection", courseName: "Self", destination: "/mod/assign/view.php?id=42")
    let snapshot = DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(dueSoon: [duplicate], newAssignments: [duplicate]), courses: [])
    #expect(snapshot.sections.dueSoon.count == 1)
    #expect(snapshot.sections.newAssignments.isEmpty)
}

@Test func staleCacheIsPreservedAfterRefreshFailure() async throws {
    let cached = sampleSnapshot()
    let cache = InMemoryDashboardCache(snapshot: cached)
    let coordinator = DashboardRefreshCoordinator(transport: FailingTransport(), cache: cache)
    let result = try await coordinator.refresh(token: "token", force: true)
    let restored = await cache.load()
    #expect(result == cached)
    #expect(restored == cached)
    #expect(await coordinator.lastResultUsedCache())
}

@Test func firstObservedAssignmentBaselineDoesNotFloodDashboard() {
    let assignment = DashboardItem(id: "assignment-42", kind: "assignment", title: "Reflection", courseName: "Self")
    let snapshot = DashboardSnapshot(
        generatedAt: "2026-08-21T03:00:00Z",
        siteName: "LPU",
        studentName: "Alex",
        sections: DashboardSections(newAssignments: [assignment]),
        assignmentIDs: [assignment.id],
        courses: []
    )
    #expect(snapshot.presentingNewAssignments(since: nil).sections.newAssignments.isEmpty)
    #expect(snapshot.presentingNewAssignments(since: []).sections.newAssignments == [assignment])
}

@Test func refreshBackoffIsBounded() {
    #expect(PipoRefreshBackoff.delay(failures: 0, base: 900) == 900)
    #expect(PipoRefreshBackoff.delay(failures: 1, base: 900) == 1_800)
    #expect(PipoRefreshBackoff.delay(failures: 8, base: 900) == 3_600)
    #expect(PipoRefreshBackoff.delay(failures: -1, base: 10) == 300)
}

@Test func sidecarRejectsMismatchedResponseIdentity() throws {
    let request = SidecarRequest(method: "resolve_destination", params: ["destination": .string("/my/")])
    let data = Data("{\"version\":1,\"id\":\"different\",\"result\":{\"url\":\"https://lms.lpucavite.edu.ph/my/\"}}".utf8)
    let response = try JSONDecoder().decode(SidecarResponse.self, from: data)
    #expect(throws: PipoCoreError.invalidResponse) {
        try response.validate(for: request)
    }
}

@Test func versionOneSnapshotDecodesWithVersionTwoDefaults() throws {
    let data = Data("""
    {"version":1,"generated_at":"2026-08-21T03:00:00Z","site_name":"LPU","student_name":"Alex","sections":{"due_soon":[],"notifications":[],"new_assignments":[],"messages":[],"grade_feedback":[]},"supported":{"due_soon":true,"notifications":true,"assignments":true,"messages":true,"grades":true},"assignment_ids":[],"courses":[],"failures":[]}
    """.utf8)
    let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: data)
    #expect(snapshot.version == 1)
    #expect(snapshot.schedule.isEmpty)
    #expect(snapshot.announcements.isEmpty)
    #expect(!snapshot.supported.resources)
}

@Test func rankingPrefersOverdueUnsubmittedAssignment() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let iso = ISO8601DateFormatter()
    let overdue = DashboardItem(id: "overdue", kind: "assignment", title: "Due", courseName: "Course", timestamp: iso.string(from: now.addingTimeInterval(-60)), submissionStatus: "not_submitted")
    let soon = DashboardItem(id: "soon", kind: "assignment", title: "Soon", courseName: "Course", timestamp: iso.string(from: now.addingTimeInterval(60)))
    let snapshot = DashboardSnapshot(generatedAt: iso.string(from: now), siteName: "LPU", studentName: "Alex", sections: DashboardSections(dueSoon: [soon], newAssignments: [overdue]), courses: [])
    #expect(PipoDashboardRanking.nextUp(snapshot: snapshot, state: PipoLocalState(), now: now).first?.id == "overdue")
}

@Test func deadlineGroupingAndSnoozeExcludeFutureItems() {
    let now = Date()
    let item = DashboardItem(id: "later", kind: "assignment", title: "Later", courseName: "Course", timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(2 * 24 * 60 * 60)))
    var state = PipoLocalState()
    state.snoozedUntil[item.id] = now.addingTimeInterval(60 * 60)
    let snapshot = DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(dueSoon: [item]), courses: [])
    #expect(PipoDashboardRanking.nextUp(snapshot: snapshot, state: state, now: now).isEmpty)
    #expect(PipoDashboardRanking.groupedDeadlines([item], now: now)[.thisWeek]?.first?.id == item.id)
}

@Test func localStatePinsAndHidesCoursesWithoutDiscardingSnapshotData() {
    var state = PipoLocalState()
    state.pinnedCourseIDs.insert(2)
    state.hiddenCourseIDs.insert(3)
    let snapshot = DashboardSnapshot(
        generatedAt: "now",
        siteName: "LPU",
        studentName: "Alex",
        sections: DashboardSections(),
        courses: [Course(id: 1, name: "Zulu"), Course(id: 2, name: "Alpha"), Course(id: 3, name: "Hidden")]
    )
    let presented = snapshot.applyingLocalState(state)
    #expect(presented.courses.map(\.id) == [2, 1])
    #expect(snapshot.courses.map(\.id) == [1, 2, 3])
}

@Test func seenAnnouncementsDoNotWinNextUpRanking() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let formatter = ISO8601DateFormatter()
    let announcement = DashboardItem(id: "announcement", kind: "announcement", title: "Update", courseName: "Course", timestamp: formatter.string(from: now), section: "announcements")
    var state = PipoLocalState()
    state.seenIDs.insert(announcement.id)
    let snapshot = DashboardSnapshot(generatedAt: formatter.string(from: now), siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [], announcements: [announcement])
    #expect(PipoDashboardRanking.nextUp(snapshot: snapshot, state: state, now: now).isEmpty)
}

@Test func quietHourRemindersMoveToQuietEnd() {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = 2026
    components.month = 8
    components.day = 21
    components.hour = 23
    let source = components.date!
    let shifted = PipoReminderPlanner.shiftOutOfQuietHours(source, settings: PipoSettings())
    #expect(Calendar.current.component(.hour, from: shifted) == 7)
}

@Test func diagnosticsExcludeStudentAndPrivatePayloads() throws {
    let item = DashboardItem(id: "grade", kind: "grade", title: "Quiz", courseName: "Course", detail: "1.25")
    let snapshot = DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(gradeFeedback: [item]), courses: [])
    let rendered = String(decoding: try PipoDiagnostics(snapshot: snapshot, appVersion: "test", macOSVersion: "test").encoded(), as: UTF8.self)
    #expect(!rendered.contains("Alex"))
    #expect(!rendered.contains("1.25"))
}

@Test func partialRefreshMergesCachedUnrequestedSections() async throws {
    let cached = DashboardSnapshot(generatedAt: "old", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [DashboardItem(id: "message", kind: "message", title: "Teacher", courseName: "Messages")]), courses: [Course(id: 1, name: "Course", publishedTotal: "1.25")])
    let refreshed = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "Alex", sections: DashboardSections(dueSoon: [DashboardItem(id: "due", kind: "assignment", title: "Due", courseName: "Course")]), courses: [Course(id: 1, name: "Course", upcomingCount: 1)])
    let coordinator = DashboardRefreshCoordinator(transport: SnapshotTransport(snapshot: refreshed), cache: InMemoryDashboardCache(snapshot: cached))
    let result = try await coordinator.refresh(token: "token", force: true, sections: ["due_soon"])
    #expect(result.sections.dueSoon.first?.id == "due")
    #expect(result.sections.messages.first?.id == "message")
    #expect(result.courses.first?.publishedTotal == "1.25")
}

@Test func rejectsExternalDestination() throws {
    #expect(throws: PipoCoreError.originRejected) { try DestinationPolicy.resolve("https://example.edu/login") }
    let destination = try DestinationPolicy.resolve("/course/view.php?id=12")
    #expect(destination.host == "lms.lpucavite.edu.ph")
}

@Test func secretRedactionHidesTokenAndPassword() {
    let redacted = PipoSecrets.redact("wstoken=abcd password=hunter2")
    #expect(!redacted.contains("abcd"))
    #expect(!redacted.contains("hunter2"))
}

@Test func notificationProjectionDropsPrivateText() {
    let notification = DashboardItem(id: "notice", kind: "notification", title: "New item", courseName: "History", detail: "This body must stay private")
    let message = DashboardItem(id: "message", kind: "message", title: "Instructor", courseName: "Messages", detail: "Message body")
    let grade = DashboardItem(id: "grade", kind: "grade", title: "Quiz", courseName: "History", detail: "Feedback body")
    let snapshot = DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(notifications: [notification], messages: [message], gradeFeedback: [grade]), courses: []).privacyProjected()
    #expect(snapshot.sections.notifications[0].detail == nil)
    #expect(snapshot.sections.messages[0].detail == nil)
    #expect(snapshot.sections.gradeFeedback[0].detail == nil)
}

@Test func systemNotificationPlanContainsNoPrivateDetail() {
    let previous = DashboardSnapshot(generatedAt: "before", siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [])
    let message = DashboardItem(id: "message-1", kind: "message", title: "Professor Reyes", courseName: "History", detail: "Private message body")
    let grade = DashboardItem(id: "grade-1", kind: "grade", title: "Midterm", courseName: "History", detail: "1.25")
    let current = DashboardSnapshot(generatedAt: "after", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [message], gradeFeedback: [grade]), courses: [])
    let payloads = PipoNotificationPlanner.changes(from: previous, to: current)
    let rendered = payloads.map { "\($0.title) \($0.body)" }.joined(separator: " ")
    #expect(!rendered.contains("Private message body"))
    #expect(!rendered.contains("1.25"))
    #expect(rendered.contains("Professor Reyes"))
    #expect(rendered.contains("Midterm"))
}

@Test func courseDetailContractDecodesAssignmentsGradesAndFeedback() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/course-detail.json")
    let detail = try JSONDecoder().decode(CourseDetail.self, from: Data(contentsOf: fixtureURL))
    #expect(detail.course.id == 12)
    #expect(detail.assignments.count == 1)
    #expect(detail.grades.first?.publishedGrade == "1.50")
    #expect(detail.grades.first?.feedback == "Clear argument and strong references.")
    #expect(detail.supported.assignments)
    #expect(detail.supported.grades)
}

@MainActor
@Test func signOutDeletesTokenAndCachedDashboard() async {
    let tokenStore = TestTokenStore(token: "stored-token")
    let cacheKeyStore = TestTokenStore(token: "cache-key")
    let cache = InMemoryDashboardCache(snapshot: sampleSnapshot())
    let model = PipoModel(transport: FailingTransport(), tokenStore: tokenStore, cacheKeyStore: cacheKeyStore, refreshCoordinator: DashboardRefreshCoordinator(transport: FailingTransport(), cache: cache), notificationService: NoopNotificationService(), urlOpener: { _ in })
    await model.signOut()
    let cachedAfterSignOut = await cache.load()
    #expect(tokenStore.value == nil)
    #expect(cacheKeyStore.value == nil)
    #expect(cachedAfterSignOut == nil)
    #expect(model.phase == .signedOut)
}

@MainActor
@Test func repeatedRefreshesReadKeychainOncePerLaunch() async {
    let tokenStore = TestTokenStore(token: "stored-token")
    let cache = InMemoryDashboardCache(snapshot: sampleSnapshot())
    let model = PipoModel(
        transport: FailingTransport(),
        tokenStore: tokenStore,
        refreshCoordinator: DashboardRefreshCoordinator(transport: FailingTransport(), cache: cache),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    await model.refresh()
    await model.refresh()
    #expect(tokenStore.readCount == 1)
}

private func sampleSnapshot() -> DashboardSnapshot {
    DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [Course(id: 12, name: "History")])
}

private struct FailingTransport: PipoSidecarTransport {
    func send(_ request: SidecarRequest) async throws -> SidecarResponse { throw PipoCoreError.operationFailed("token=secret-password") }
}

private struct NoopNotificationService: PipoNotificationService {
    func requestAuthorization() async {}
    func deliver(_ payloads: [PipoNotificationPayload]) async {}
    func clear() {}
}

private struct SnapshotTransport: PipoSidecarTransport {
    let snapshot: DashboardSnapshot
    func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        let value = try JSONDecoder().decode(PipoJSONValue.self, from: JSONEncoder().encode(snapshot))
        return SidecarResponse(version: request.version, id: request.id, result: value, error: nil)
    }
}

private final class TestTokenStore: PipoTokenStore, @unchecked Sendable {
    var value: String?
    var readCount = 0
    init(token: String?) { value = token }
    func token() throws -> String? { readCount += 1; return value }
    func save(token: String) throws { value = token }
    func deleteToken() throws { value = nil }
}
