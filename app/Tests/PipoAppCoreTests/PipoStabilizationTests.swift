import Foundation
import Testing
@testable import PipoAppCore

@Test func stabilizationRedactsRepeatedQuotedSecrets() {
    let text = #"token=first password="two words" token=second {"refresh_token":"third"} Authorization: Bearer fourth"#
    let redacted = PipoSecrets.redact(text)
    for secret in ["first", "two words", "second", "third", "fourth"] {
        #expect(!redacted.contains(secret))
    }
}

@Test func stabilizationVaultReplacementCanSaveAndRestoreWithNewManager() async throws {
    let backend = StabilizationKeychain()
    let url = FileManager.default.temporaryDirectory.appending(path: "pipo-stabilization-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let firstVault = KeychainSecureVault(backend: backend, service: "stabilization")
    let firstKey = try firstVault.cacheKey()
    let first = PipoPersistenceManager(vault: firstVault, databaseURL: url)
    try await first.save(stabilizationSnapshot("first"), accountID: "account")
    await first.close()
    try firstVault.deleteToken()
    let secondVault = KeychainSecureVault(backend: backend, service: "stabilization")
    let secondKey = try secondVault.cacheKey()
    #expect(firstKey != secondKey)
    let second = PipoPersistenceManager(vault: secondVault, databaseURL: url)
    try await second.save(stabilizationSnapshot("second"), accountID: "account")
    await second.close()
    let reopened = PipoPersistenceManager(vault: secondVault, databaseURL: url)
    #expect(try await reopened.load(accountID: "account")?.studentName == "second")
}

@Test func stabilizationPersistenceDenialCanRetry() async throws {
    let backend = StabilizationKeychain(denyReads: true)
    let vault = KeychainSecureVault(backend: backend, service: "denial")
    let url = FileManager.default.temporaryDirectory.appending(path: "pipo-denial-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let manager = PipoPersistenceManager(vault: vault, databaseURL: url)
    #expect(await manager.prepare().canSave == false)
    backend.denyReads = false
    #expect(vault.retryAccess() == .ready)
    #expect(await manager.prepare().canSave)
}

@Test func stabilizationGradeProjectionRemovesPrivateValues() {
    let grade = DashboardItem(id: "grade", kind: "grade", title: "Quiz", courseName: "Course", detail: "91%")
    let projected = stabilizationSnapshot("student", grades: [grade]).privacyProjected()
    #expect(projected.sections.gradeFeedback.first?.detail == nil)
}

@Test func stabilizationCoordinatorMergeCases() async throws {
    let cached = stabilizationSnapshot("cached", messages: [DashboardItem(id: "old", kind: "message", title: "Old", courseName: "Course")])
    for (result, expected) in [(DashboardSectionResult.success, 0), (.partial, 1), (.failed, 1), (.notRequested, 1)] {
        let refreshed = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "new", sections: DashboardSections(), courses: [], sectionResults: ["messages": result])
        let coordinator = DashboardRefreshCoordinator(transport: StabilizationTransport(snapshot: refreshed), cache: InMemoryDashboardCache(snapshot: cached))
        let output = try await coordinator.refresh(token: "token", force: true, sections: ["messages"])
        #expect(output.sections.messages.count == expected)
    }
    let thirteen = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "new", sections: DashboardSections(), courses: (1...13).map { Course(id: $0, name: "Course \($0)") }, sectionResults: ["messages": .success])
    let coordinator = DashboardRefreshCoordinator(transport: StabilizationTransport(snapshot: thirteen), cache: InMemoryDashboardCache(snapshot: cached))
    #expect(try await coordinator.refresh(token: "token", force: true).courses.count == 13)
}

@Test func stabilizationReminderQuietHoursAndSubmittedItems() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
    let due = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 9))!
    let formatter = ISO8601DateFormatter(); formatter.timeZone = calendar.timeZone
    let item = DashboardItem(id: "due", kind: "assignment", title: "Work", courseName: "Course", timestamp: formatter.string(from: due))
    let overnight = PipoSettings(quietHoursStart: 22, quietHoursEnd: 7)
    let daytime = PipoSettings(quietHoursStart: 8, quietHoursEnd: 10)
    #expect(PipoReminderPlanner.reminderDates(for: item, settings: overnight, now: due.addingTimeInterval(-3 * 24 * 3600), calendar: calendar).allSatisfy { $0 < due })
    #expect(PipoReminderPlanner.reminderDates(for: item, settings: daytime, now: due.addingTimeInterval(-3 * 24 * 3600), calendar: calendar).allSatisfy { $0 < due })
    let submitted = DashboardItem(id: "done", kind: "assignment", title: "Done", courseName: "Course", timestamp: formatter.string(from: due), submissionStatus: "submitted")
    #expect(PipoReminderPlanner.reminderDates(for: submitted, settings: overnight, now: due.addingTimeInterval(-3 * 24 * 3600), calendar: calendar).isEmpty)
}

@Test func partialGradeRefreshOverlaysCoveredCoursesAndRetainsOthers() async throws {
    let cached = DashboardSnapshot(generatedAt: "old", siteName: "LPU", studentName: "Student", sections: DashboardSections(), courses: [Course(id: 1, name: "One", publishedTotal: "50"), Course(id: 2, name: "Two", publishedTotal: "80")])
    let incoming = DashboardSnapshot(generatedAt: "new", siteName: "LPU", studentName: "Student", sections: DashboardSections(), courses: [Course(id: 1, name: "One", publishedTotal: "75"), Course(id: 2, name: "Two")], sectionResults: ["grades": .partial])
    let coordinator = DashboardRefreshCoordinator(transport: StabilizationTransport(snapshot: incoming), cache: InMemoryDashboardCache(snapshot: cached))
    let result = try await coordinator.refresh(token: "token", force: true, sections: ["grades"])
    #expect(result.courses.map(\.publishedTotal) == ["75", "80"])
}

@Test func freshRefreshKeepsPrivateDetailInSignedInMemory() async throws {
    let grade = DashboardItem(id: "grade", kind: "grade", title: "Quiz", courseName: "Course", detail: "Private feedback")
    let incoming = DashboardSnapshot(generatedAt: ISO8601DateFormatter().string(from: .now), siteName: "LPU", studentName: "Student", sections: DashboardSections(gradeFeedback: [grade]), courses: [])
    let cache = InMemoryDashboardCache()
    let coordinator = DashboardRefreshCoordinator(transport: StabilizationTransport(snapshot: incoming), cache: cache)
    _ = try await coordinator.refresh(token: "token", force: true)
    #expect(await cache.load()?.sections.gradeFeedback.first?.detail == nil)
    let refreshed = try await coordinator.refresh(token: "token")
    #expect(refreshed.sections.gradeFeedback.first?.detail == "Private feedback")
}

@Test func stabilizationSidecarCancellationLeavesNextRequestUsable() async throws {
    let script = FileManager.default.temporaryDirectory.appending(path: "pipo-sidecar-fixture-\(UUID().uuidString).sh")
    let body = """
    #!/bin/sh
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
      method=$(printf '%s' "$line" | sed -n 's/.*"method":"\\([^"]*\\)".*/\\1/p')
      if [ "$method" = hello ]; then
        printf '{"version":4,"id":"%s","result":{"wire_protocol":4}}\\n' "$id"
      elif [ "$method" = slow ]; then
        sleep 1
        printf '{"version":4,"id":"%s","result":{"ok":true}}\\n' "$id"
      else
        printf '{"version":4,"id":"%s","result":{"ok":true}}\\n' "$id"
      fi
    done
    """
    try body.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    defer { try? FileManager.default.removeItem(at: script) }
    let transport = PipoCoreProcessTransport(executableURL: script)
    let active = Task { try await transport.send(SidecarRequest(method: "slow", params: [:])) }
    try await Task.sleep(for: .milliseconds(80))
    active.cancel()
    _ = await active.result
    let next = try await transport.send(SidecarRequest(method: "probe", params: [:]))
    #expect(next.error == nil)
    await transport.shutdown()
}

private func stabilizationSnapshot(_ student: String, messages: [DashboardItem] = [], grades: [DashboardItem] = []) -> DashboardSnapshot {
    DashboardSnapshot(generatedAt: "2026-09-08T00:00:00Z", siteName: "LPU", studentName: student, sections: DashboardSections(messages: messages, gradeFeedback: grades), courses: [])
}

private final class StabilizationKeychain: PipoKeychainBackend, @unchecked Sendable {
    var denyReads: Bool; private var values: [String: Data] = [:]
    init(denyReads: Bool = false) { self.denyReads = denyReads }
    func read(service: String, account: String) throws -> Data? { if denyReads { throw PipoSecureStorageError.accessDenied }; return values["\(service)/\(account)"] }
    func write(_ data: Data, service: String, account: String) throws { values["\(service)/\(account)"] = data }
    func delete(service: String, account: String) throws { values.removeValue(forKey: "\(service)/\(account)") }
}

private struct StabilizationTransport: PipoSidecarTransport {
    let snapshot: DashboardSnapshot
    func send(_ request: SidecarRequest) async throws -> SidecarResponse { SidecarResponse(version: request.version, id: request.id, result: try JSONEncoder().encode(snapshot).jsonValue(), error: nil) }
}

private extension Data { func jsonValue() throws -> PipoJSONValue { try JSONDecoder().decode(PipoJSONValue.self, from: self) } }
