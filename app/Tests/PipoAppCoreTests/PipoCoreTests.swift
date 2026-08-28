import Foundation
import Testing
@testable import PipoAppCore

@Test func dueSoonItemsAreRemovedFromNewAssignments() {
    let duplicate = DashboardItem(id: "42", kind: "assignment", title: "Reflection", courseName: "Self", destination: "/mod/assign/view.php?id=42")
    let snapshot = DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(dueSoon: [duplicate], newAssignments: [duplicate]), courses: [])
    #expect(snapshot.sections.dueSoon.count == 1)
    #expect(snapshot.sections.newAssignments.isEmpty)
}

@Test func versionThreeModelDecodesVersionTwoCache() throws {
    let data = Data("""
    {"version":2,"generated_at":"2026-08-21T03:00:00Z","site_name":"LPU","student_name":"Alex","sections":{"due_soon":[],"notifications":[],"new_assignments":[],"messages":[],"grade_feedback":[]},"courses":[]}
    """.utf8)
    let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: data)
    #expect(snapshot.version == 2)
    #expect(snapshot.sectionResults.isEmpty)
    #expect(snapshot.result(for: "messages").status == .success)
    #expect(sampleSnapshot().version == 3)
}

@Test func versionThreeDecodesStructuredSectionResultsAndEntityKeys() throws {
    let data = Data("""
    {"version":3,"generated_at":"2026-08-26T01:00:00Z","site_name":"LPU","student_name":"Alex","sections":{"due_soon":[],"notifications":[],"new_assignments":[],"messages":[{"id":9,"entity_key":"lms:/message/index.php?id=9","kind":"message","title":"Professor","course_name":"Messages","destination":"/message/index.php?id=9"}],"grade_feedback":[]},"courses":[],"section_results":{"messages":{"status":"partial","refreshed_at":"2026-08-26T01:00:00Z","error":"Messages: one course unavailable"}}}
    """.utf8)
    let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: data)
    #expect(snapshot.result(for: "messages").status == .partial)
    #expect(snapshot.result(for: "messages").fetchedAt == "2026-08-26T01:00:00Z")
    #expect(snapshot.sections.messages.first?.entityKey == "lms:/message/index.php?id=9")
}

@Test func instructorFieldsDecodeAndSurvivePrivacyProjection() throws {
    let data = Data("""
    {"version":3,"generated_at":"2026-08-26T01:00:00Z","site_name":"LPU","student_name":"Alex","sections":{"due_soon":[{"id":9,"entity_key":"assignment:12:9","kind":"assignment","title":"Essay","course_id":12,"course_name":"History","instructor":"Professor McGonagall","destination":""}],"notifications":[],"new_assignments":[],"messages":[],"grade_feedback":[]},"courses":[{"id":12,"name":"History","instructor":"Professor McGonagall"}]}
    """.utf8)
    let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: data)
    #expect(snapshot.courses.first?.instructor == "Professor McGonagall")
    #expect(snapshot.sections.dueSoon.first?.instructor == "Professor McGonagall")
    #expect(snapshot.privacyProjected().sections.dueSoon.first?.instructor == "Professor McGonagall")
}

@Test func stableEntityKeysDeduplicateEquivalentDestinations() {
    let first = DashboardItem(id: "one", kind: "assignment", title: "Work", courseID: 7, courseName: "Course", destination: "/mod/assign/view.php?b=2&a=1#top")
    let second = DashboardItem(id: "two", kind: "assignment", title: "Work", courseID: 7, courseName: "Course", destination: "/mod/assign/view.php?a=1&b=2")
    #expect(first.stableKey == second.stableKey)
    #expect(DashboardItem.deduplicated([first, second]) == [first])
}

@Test func failedSectionPreservesCachedCardsDuringFullRefresh() async throws {
    let cachedMessage = DashboardItem(id: "message", kind: "message", title: "Professor", courseName: "Messages")
    let cached = DashboardSnapshot(generatedAt: "old", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [cachedMessage]), courses: [])
    let refreshed = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [], failures: ["messages unavailable"], sectionResults: ["messages": .failed])
    let coordinator = DashboardRefreshCoordinator(transport: SnapshotTransport(snapshot: refreshed), cache: InMemoryDashboardCache(snapshot: cached))
    let outcome = try await coordinator.refreshOutcome(token: "token", force: true)
    #expect(outcome.snapshot.sections.messages == [cachedMessage])
    #expect(outcome.preservedSections.contains("messages"))
}

@Test func successfulEmptySectionReplacesCachedCards() async throws {
    let cachedMessage = DashboardItem(id: "message", kind: "message", title: "Professor", courseName: "Messages")
    let cached = DashboardSnapshot(generatedAt: "old", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [cachedMessage]), courses: [])
    let refreshed = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [], sectionResults: ["messages": .success])
    let coordinator = DashboardRefreshCoordinator(transport: SnapshotTransport(snapshot: refreshed), cache: InMemoryDashboardCache(snapshot: cached))
    let outcome = try await coordinator.refreshOutcome(token: "token", force: true, sections: ["messages"])
    #expect(outcome.snapshot.sections.messages.isEmpty)
    #expect(outcome.refreshedSections == ["messages"])
}

@Test func partialSectionPreservesCachedCards() async throws {
    let cachedMessage = DashboardItem(id: "message", kind: "message", title: "Professor", courseName: "Messages")
    let cached = DashboardSnapshot(generatedAt: "old", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [cachedMessage]), courses: [])
    let partial = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [DashboardItem(id: "other", kind: "message", title: "Other", courseName: "Messages")]), courses: [], sectionResults: ["messages": .partial])
    let coordinator = DashboardRefreshCoordinator(transport: SnapshotTransport(snapshot: partial), cache: InMemoryDashboardCache(snapshot: cached))
    let outcome = try await coordinator.refreshOutcome(token: "token", force: true, sections: ["messages"])
    #expect(outcome.snapshot.sections.messages == [cachedMessage])
    #expect(outcome.preservedSections == ["messages"])
}

@Test func concurrentRefreshesCoalesceToOneTransportRequest() async throws {
    let transport = CountingSnapshotTransport(snapshot: sampleSnapshot())
    let coordinator = DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache())
    async let first = coordinator.refreshOutcome(token: "token", force: true)
    async let second = coordinator.refreshOutcome(token: "token", force: true)
    let pair = try await (first, second)
    #expect(await transport.count == 1)
    #expect(pair.0.coalesced || pair.1.coalesced)
}

@Test func freshnessTiersOnlyRequestStaleSections() async {
    let now = Date()
    let formatter = ISO8601DateFormatter()
    let snapshot = DashboardSnapshot(
        generatedAt: formatter.string(from: now),
        siteName: "LPU",
        studentName: "Alex",
        sections: DashboardSections(),
        courses: [],
        sectionTimestamps: [
            "due_soon": formatter.string(from: now.addingTimeInterval(-901)),
            "messages": formatter.string(from: now.addingTimeInterval(-60)),
            "resources": formatter.string(from: now.addingTimeInterval(-60))
        ]
    )
    let coordinator = DashboardRefreshCoordinator(transport: FailingTransport(), cache: InMemoryDashboardCache())
    let stale = await coordinator.sectionsNeedingRefresh(in: snapshot, now: now)
    #expect(stale.contains("due_soon"))
    #expect(!stale.contains("messages"))
    #expect(!stale.contains("resources"))
}

@Test @MainActor func courseDetailsUseFiveMinuteMemoryCacheAndDirectDestination() async throws {
    let transport = CountingCourseTransport()
    let model = PipoModel(
        transport: transport,
        tokenStore: TestTokenStore(token: "token"),
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    _ = try await model.loadCourse(id: 12)
    let destination = try await model.courseDestination(id: 12)
    #expect(await transport.count == 1)
    #expect(destination.absoluteString == "https://lms.lpucavite.edu.ph/course/view.php?id=12")
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
    #expect(request.version == 4)
    let data = Data("{\"version\":1,\"id\":\"different\",\"result\":{\"url\":\"https://lms.lpucavite.edu.ph/my/\"}}".utf8)
    let response = try JSONDecoder().decode(SidecarResponse.self, from: data)
    #expect(throws: PipoCoreError.invalidResponse) {
        try response.validate(for: request)
    }
}

@Test func sidecarRequiresHelloCompatibilityResponse() async throws {
    let transport = PipoCoreProcessTransport(executableURL: URL(fileURLWithPath: "/bin/cat"))
    let request = SidecarRequest(method: "probe", params: [:])
    await #expect(throws: PipoCoreError.self) {
        _ = try await transport.send(request)
    }
    await transport.shutdown()
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

@Test func refreshShowsPrivateDetailButCachesOnlyPrivacyProjection() async throws {
    let message = DashboardItem(id: "message", kind: "message", title: "Professor", courseName: "Messages", detail: "Private reply")
    let refreshed = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "Alex", sections: DashboardSections(messages: [message]), courses: [])
    let cache = InMemoryDashboardCache()
    let coordinator = DashboardRefreshCoordinator(transport: SnapshotTransport(snapshot: refreshed), cache: cache)

    let visible = try await coordinator.refresh(token: "token", force: true)
    let cached = await cache.load()

    #expect(visible.sections.messages.first?.detail == "Private reply")
    #expect(cached?.sections.messages.first?.detail == nil)
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

@Test func courseGradeEntityKeysDecodeBackwardsAndDeduplicateOnlyEqualRecords() throws {
    let data = Data("""
    {"course":{"id":12,"name":"History"},"grades":[
      {"id":91,"entity_key":"grade:12:91","title":"Quiz","published_grade":"18 / 20"},
      {"id":91,"entity_key":"grade:12:91","title":"Duplicate","published_grade":"18 / 20"},
      {"id":92,"entity_key":"grade:12:92","title":"Quiz","published_grade":"92%"},
      {"id":93,"title":"Essay","published_grade":"1.50"},
      {"id":94,"title":"Unavailable"}
    ]}
    """.utf8)
    let detail = try JSONDecoder().decode(CourseDetail.self, from: data)
    #expect(detail.grades.count == 4)
    #expect(detail.grades.map(\.publishedGrade) == ["18 / 20", "92%", "1.50", nil])
    #expect(detail.grades[0].entityKey == "grade:12:91")
    #expect(detail.grades[1].entityKey == "grade:12:92")
    #expect(detail.grades[1].title == "Quiz")
    #expect(detail.grades[2].entityKey == "93")
    #expect(detail.grades[3].publishedGrade == nil)
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
@Test func signOutClearsVisibleStateBeforeFailedCleanupAndLeavesTombstone() async {
    let tombstone = "pipo.session.sign-out-cleanup-pending"
    let suiteName = "PipoSignOutTombstoneTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let transport = SnapshotTransport(snapshot: sampleSnapshot())
    let tokenStore = FailingDeleteTokenStore(token: "stored-token")
    let model = PipoModel(
        transport: transport,
        tokenStore: tokenStore,
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        lifecycleDefaults: defaults,
        urlOpener: { _ in }
    )
    await model.refresh()
    #expect(model.snapshot != nil)
    await model.signOut()
    #expect(model.snapshot == nil)
    #expect(model.phase == .signedOut)
    #expect(defaults.bool(forKey: tombstone))
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

@Test func secureVaultMigratesLegacyTokenWithoutReadingLegacyCacheKey() throws {
    let backend = TestKeychainBackend()
    backend.set(Data("legacy-token".utf8), account: "lms-access-token")
    backend.set(Data(Data(repeating: 4, count: 32).base64EncodedString().utf8), account: "pipo-cache-key")
    let vault = KeychainSecureVault(backend: backend)

    #expect(try vault.token() == "legacy-token")
    let vaultCacheKey = try vault.cacheKey()
    #expect(vaultCacheKey.count == 32)
    #expect(vaultCacheKey != Data(repeating: 4, count: 32))
    #expect(backend.readAccounts == ["secure-vault-v1", "lms-access-token"])
    #expect(!backend.readAccounts.contains("pipo-cache-key"))
    #expect(backend.data(account: "secure-vault-v1") != nil)
    #expect(backend.data(account: "lms-access-token") == nil)
    #expect(backend.data(account: "pipo-cache-key") != nil)

    let readsAfterMigration = backend.readAccounts.count
    _ = try vault.token()
    _ = try vault.cacheKey()
    #expect(backend.readAccounts.count == readsAfterMigration)
}

@Test func secureVaultDoesNotRetryDeniedKeychainUntilExplicitRetry() throws {
    let backend = TestKeychainBackend()
    backend.deniesAccess = true
    let vault = KeychainSecureVault(backend: backend)

    do {
        _ = try vault.token()
        Issue.record("Expected secure storage denial")
    } catch {
        #expect(error as? PipoSecureStorageError == .accessDenied)
    }
    let readsAfterDenial = backend.readAccounts.count

    do {
        _ = try vault.token()
        Issue.record("Expected cached secure storage denial")
    } catch {
        #expect(error as? PipoSecureStorageError == .accessDenied)
    }
    #expect(backend.readAccounts.count == readsAfterDenial)
    #expect(vault.status == .accessDenied)

    backend.deniesAccess = false
    #expect(vault.retryAccess() == .ready)
    #expect(vault.status == .ready)
    #expect(backend.readAccounts.count > readsAfterDenial)
}

@Test func encryptedDashboardCacheDiscardsCiphertextFromPreviousKey() async throws {
    let url = temporaryDatabaseURL("dashboard-key-rotation")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let oldCache = try EncryptedDashboardCache(databaseURL: url, keyData: Data(repeating: 1, count: 32))
    try await oldCache.save(sampleSnapshot())

    let migratedCache = try EncryptedDashboardCache(databaseURL: url, keyData: Data(repeating: 2, count: 32))
    #expect(try await migratedCache.load() == nil)
    #expect(try await migratedCache.load() == nil)
}

@Test func encryptedPersistenceScopesDashboardAndLocalStateByAccount() async throws {
    let url = temporaryDatabaseURL("account-scoping")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let store = try EncryptedDashboardCache(databaseURL: url, keyData: Data(repeating: 7, count: 32))
    let accountA = DashboardSnapshot(generatedAt: "a", siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [])
    let accountB = DashboardSnapshot(generatedAt: "b", siteName: "LPU", studentName: "Blair", sections: DashboardSections(), courses: [])
    try await store.save(accountA, accountID: "account-a")
    try await store.save(accountB, accountID: "account-b")
    var localA = PipoLocalState(); localA.seenIDs.insert("a-only")
    var localB = PipoLocalState(); localB.seenIDs.insert("b-only")
    try await store.saveLocalState(localA, accountID: "account-a")
    try await store.saveLocalState(localB, accountID: "account-b")

    #expect(try await store.load(accountID: "account-a")?.studentName == "Alex")
    #expect(try await store.load(accountID: "account-b")?.studentName == "Blair")
    #expect(try await store.loadLocalState(accountID: "account-a").seenIDs == ["a-only"])
    #expect(try await store.loadLocalState(accountID: "account-b").seenIDs == ["b-only"])
}

@Test func legacyDashboardMigratesOnlyIntoVerifiedAccountScope() async throws {
    let url = temporaryDatabaseURL("legacy-account-migration")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let store = try EncryptedDashboardCache(databaseURL: url, keyData: Data(repeating: 8, count: 32))
    try await store.save(sampleSnapshot())
    #expect(try await store.load(accountID: "verified-account")?.studentName == "Alex")
    #expect(try await store.load() == nil)
    #expect(try await store.load(accountID: "verified-account")?.studentName == "Alex")
}

@Test func encryptedLocalStateDiscardsCiphertextFromPreviousKey() async throws {
    let url = temporaryDatabaseURL("state-key-rotation")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let oldStore = try EncryptedLocalStateStore(databaseURL: url, keyData: Data(repeating: 3, count: 32))
    var state = PipoLocalState()
    state.seenIDs.insert("seen-item")
    try await oldStore.save(state)

    let migratedStore = try EncryptedLocalStateStore(databaseURL: url, keyData: Data(repeating: 4, count: 32))
    #expect(try await migratedStore.load() == PipoLocalState())
    #expect(try await migratedStore.load() == PipoLocalState())
}

@MainActor
@Test func modelExposesSecureStorageStatusAndExplicitRetry() async {
    let backend = TestKeychainBackend()
    backend.deniesAccess = true
    let vault = KeychainSecureVault(backend: backend)
    let cache = InMemoryDashboardCache()
    let model = PipoModel(
        transport: FailingTransport(),
        tokenStore: vault,
        secureVault: vault,
        refreshCoordinator: DashboardRefreshCoordinator(transport: FailingTransport(), cache: cache),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )

    await model.refresh()
    #expect(model.secureStorageStatus == .accessDenied)
    backend.deniesAccess = false
    let retryStatus = await model.retrySecureStorage()
    #expect(retryStatus == .ready)
    #expect(model.secureStorageStatus == .ready)
}

@MainActor
@Test func duplicateSignInAttemptsCoalesce() async {
    let transport = AuthenticationLifecycleTransport(snapshot: sampleSnapshot())
    let tokenStore = TestTokenStore(token: nil)
    let model = PipoModel(
        transport: transport,
        tokenStore: tokenStore,
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    async let first: Void = model.signIn(username: "alex", password: "secret")
    async let second: Void = model.signIn(username: "alex", password: "secret")
    _ = await (first, second)
    #expect(await transport.authenticationCount == 1)
    #expect(model.phase == .ready)
}

@MainActor
@Test func expiredStoredTokenClearsSessionAndReturnsSignedOut() async {
    let transport = ExpiredTokenTransport()
    let tokenStore = TestTokenStore(token: "expired")
    let model = PipoModel(
        transport: transport,
        tokenStore: tokenStore,
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    await model.restore()
    #expect(model.phase == .signedOut)
    #expect(tokenStore.value == nil)
    #expect(model.authenticationError == "Your LMS session expired. Sign in again.")
}

@MainActor
@Test func rejectedSchoolAccountExplainsHowToRecover() async {
    let transport = ExpiredTokenTransport()
    let model = PipoModel(
        transport: transport,
        tokenStore: TestTokenStore(token: nil),
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    await model.signIn(username: "alex", password: "wrong")
    #expect(model.phase == .failed("The LMS rejected that username or password. Check your details and try again."))
}

@MainActor
@Test func rejectedAccessTokenExplainsHowToRecover() async {
    let transport = ExpiredTokenTransport()
    let model = PipoModel(
        transport: transport,
        tokenStore: TestTokenStore(token: nil),
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    await model.signIn(withToken: "expired")
    #expect(model.phase == .failed("That access token is invalid or expired. Create a new token and try again."))
}

@MainActor
@Test func networkFailureRetainsStoredTokenForReconnect() async {
    let transport = NetworkFailureTransport()
    let tokenStore = TestTokenStore(token: "valid")
    let model = PipoModel(
        transport: transport,
        tokenStore: tokenStore,
        refreshCoordinator: DashboardRefreshCoordinator(transport: transport, cache: InMemoryDashboardCache()),
        notificationService: NoopNotificationService(),
        urlOpener: { _ in }
    )
    await model.restore()
    #expect(model.phase == .failed("Pipo could not reach the LMS. Check your connection and try again."))
    #expect(tokenStore.value == "valid")
}

private func sampleSnapshot() -> DashboardSnapshot {
    DashboardSnapshot(generatedAt: "now", siteName: "LPU", studentName: "Alex", sections: DashboardSections(), courses: [Course(id: 12, name: "History")])
}

private func temporaryDatabaseURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("pipo-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("\(name).sqlite")
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

private actor CountingSnapshotTransport: PipoSidecarTransport {
    let snapshot: DashboardSnapshot
    private(set) var count = 0
    init(snapshot: DashboardSnapshot) { self.snapshot = snapshot }
    func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        count += 1
        try await Task.sleep(for: .milliseconds(40))
        let value = try JSONDecoder().decode(PipoJSONValue.self, from: JSONEncoder().encode(snapshot))
        return SidecarResponse(version: request.version, id: request.id, result: value, error: nil)
    }
}

private actor AuthenticationLifecycleTransport: PipoSidecarTransport {
    let snapshot: DashboardSnapshot
    private(set) var authenticationCount = 0
    init(snapshot: DashboardSnapshot) { self.snapshot = snapshot }
    func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        if request.method == "authenticate_with_password" {
            authenticationCount += 1
            try await Task.sleep(for: .milliseconds(40))
            return SidecarResponse(version: request.version, id: request.id, result: .object(["token": .string("valid"), "account_id": .number(42)]), error: nil)
        }
        let value = try JSONDecoder().decode(PipoJSONValue.self, from: JSONEncoder().encode(snapshot))
        return SidecarResponse(version: request.version, id: request.id, result: value, error: nil)
    }
}

private struct ExpiredTokenTransport: PipoSidecarTransport {
    func send(_ request: SidecarRequest) async throws -> SidecarResponse { throw PipoCoreError.authenticationRequired }
}

private struct NetworkFailureTransport: PipoSidecarTransport {
    func send(_ request: SidecarRequest) async throws -> SidecarResponse { throw PipoCoreError.networkUnavailable }
}

private actor CountingCourseTransport: PipoSidecarTransport {
    private(set) var count = 0
    func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        count += 1
        let result: PipoJSONValue = .object([
            "version": .number(2),
            "course": .object(["id": .number(12), "name": .string("History")]),
            "assignments": .array([]),
            "grades": .array([]),
            "destination": .string("/course/view.php?id=12"),
            "failures": .array([])
        ])
        return SidecarResponse(version: request.version, id: request.id, result: result, error: nil)
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

private final class FailingDeleteTokenStore: PipoTokenStore, @unchecked Sendable {
    private var value: String?
    init(token: String?) { value = token }
    func token() throws -> String? { value }
    func save(token: String) throws { value = token }
    func deleteToken() throws { throw PipoSecureStorageError.unavailable("cleanup failed") }
}

private final class TestKeychainBackend: PipoKeychainBackend, @unchecked Sendable {
    var deniesAccess = false
    private var values: [String: Data] = [:]
    private(set) var readAccounts: [String] = []

    func read(service: String, account: String) throws -> Data? {
        readAccounts.append(account)
        try checkAccess()
        return values[key(service: service, account: account)]
    }

    func write(_ data: Data, service: String, account: String) throws {
        try checkAccess()
        values[key(service: service, account: account)] = data
    }

    func delete(service: String, account: String) throws {
        try checkAccess()
        values.removeValue(forKey: key(service: service, account: account))
    }

    func set(_ data: Data, account: String, service: String = "com.jazztinn.pipo") {
        values[key(service: service, account: account)] = data
    }

    func data(account: String, service: String = "com.jazztinn.pipo") -> Data? {
        values[key(service: service, account: account)]
    }

    private func checkAccess() throws {
        if deniesAccess { throw PipoSecureStorageError.accessDenied }
    }

    private func key(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}
