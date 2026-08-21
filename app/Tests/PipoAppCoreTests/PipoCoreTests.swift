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

private final class TestTokenStore: PipoTokenStore, @unchecked Sendable {
    var value: String?
    init(token: String?) { value = token }
    func token() throws -> String? { value }
    func save(token: String) throws { value = token }
    func deleteToken() throws { value = nil }
}
