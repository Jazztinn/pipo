import Foundation
import Testing
@testable import PipoAppCore

@MainActor @Test func scheduleControllerCreatesSavesAndRestoresAccountSchedule() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "pipo-controller-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let keychain = ControllerKeychain()
    let controller = PipoScheduleController(baseDirectory: directory, keychain: keychain)
    await controller.activate(accountID: "student-a")
    controller.createDraft(term: controllerTerm())
    controller.newSubject()
    controller.updateSubjectCode(index: 0, code: "CS101")
    controller.updateSubjectName(index: 0, name: "Computing")
    controller.updateMeeting(index: 0, meetingIndex: 0, weekdays: [.monday, .wednesday], startTime: .init(hour: 10, minute: 0), endTime: .init(hour: 11, minute: 30), isTBA: false)
    #expect(controller.canSave)
    #expect(controller.draft?.rows.first?.manuallyCorrected == true)
    let draftID = try #require(controller.draft?.id)
    let subjectID = try #require(controller.draft?.rows.first?.subject.id)
    let meetingID = try #require(controller.draft?.rows.first?.meetings.first?.id)
    await controller.save()
    #expect(controller.confirmed?.id == draftID)
    #expect(controller.confirmed?.rows.first?.subject.id == subjectID)
    #expect(controller.confirmed?.rows.first?.meetings.first?.id == meetingID)
    #expect(controller.confirmed?.rows.first?.subject.code == "CS101")
    controller.deactivate()
    #expect(controller.confirmed == nil && controller.draft == nil)
    await controller.activate(accountID: "student-a")
    #expect(controller.confirmed?.id == draftID)
    #expect(controller.confirmed?.rows.first?.subject.name == "Computing")
    await controller.activate(accountID: "student-b")
    #expect(controller.confirmed == nil && controller.draft == nil)
}

@MainActor @Test func scheduleControllerCancelRestoresConfirmedWithoutSavingEdits() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "pipo-controller-cancel-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = PipoScheduleController(baseDirectory: directory, keychain: ControllerKeychain())
    await controller.activate(accountID: "student")
    controller.createDraft(term: controllerTerm())
    controller.newSubject()
    controller.updateSubjectCode(index: 0, code: "MATH1")
    controller.updateMeeting(index: 0, meetingIndex: 0, weekdays: [.tuesday], startTime: .init(hour: 9, minute: 0), endTime: .init(hour: 10, minute: 0), isTBA: false)
    await controller.save()
    let confirmed = try #require(controller.confirmed)
    controller.beginEditing()
    controller.updateSubjectCode(index: 0, code: "CHANGED")
    #expect(controller.draft?.rows.first?.subject.code == "CHANGED")
    #expect(controller.confirmed?.rows.first?.subject.code == "MATH1")
    controller.cancelReview()
    #expect(controller.draft == confirmed)
    #expect(controller.confirmed == confirmed)
    #expect(controller.preview == nil)
    #expect(!controller.isEditing)
}

private func controllerTerm() -> ScheduleTerm {
    ScheduleTerm(name: "Term", startDate: .init(year: 2026, month: 9, day: 7), endDate: .init(year: 2026, month: 12, day: 20), timeZoneIdentifier: "Asia/Manila")
}

@MainActor @Test func reimportReportsEditsAlongsideAdditionsAndRemovals() {
    let existing = ScheduleReviewRow(subject: ScheduleSubject(code: "CS101", name: "Computing"))
    let removed = ScheduleReviewRow(subject: ScheduleSubject(code: "MATH1", name: "Math"))
    let old = ScheduleDraft(term: controllerTerm(), rows: [existing, removed])
    var changed = existing
    changed.subject.name = "Updated computing"
    let added = ScheduleReviewRow(subject: ScheduleSubject(code: "HIST1", name: "History"))
    let new = ScheduleDraft(term: controllerTerm(), rows: [changed, added])
    let changes = PipoScheduleController.describeChanges(old: old, new: new)
    #expect(changes.contains("Updated CS101"))
    #expect(changes.contains { $0.hasPrefix("Added HIST1") })
    #expect(changes.contains { $0.hasPrefix("Removed MATH1") })
}

private final class ControllerKeychain: PipoKeychainBackend, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values["\(service)/\(account)"] }
    func write(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values["\(service)/\(account)"] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: "\(service)/\(account)") }
}
