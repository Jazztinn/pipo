import Foundation
import GRDB
import Testing
@testable import PipoAppCore

@Test func scheduleWeeklyRecurrenceAndOvernightOffset() throws {
    let subject = ScheduleSubject(code: "CS101", name: "Computing")
    let meeting = ClassMeeting(subjectID: subject.id, weekdays: [.monday], startTime: .init(hour: 22, minute: 0), endTime: .init(hour: 1, minute: 0), overnightDayOffset: 1)
    let occurrences = ScheduleOccurrenceGenerator.occurrences(term: scheduleTerm(), rows: [.init(subject: subject, meetings: [meeting])])
    let occurrence = try #require(occurrences.first)
    #expect(occurrences.count == 1); #expect(occurrence.start! < occurrence.end!)
}

@Test func scheduleParserFlagsAmbiguousTime() throws {
    let row = try #require(ScheduleImportParser.parse(text: "Course | Name | Days | Time\nCS101 | Computing | MWF | TBD").rows.first)
    #expect(!row.uncertainty.isEmpty)
}

@Test func finalTermOvernightAppearsOnFollowingDayWithStableIdentity() throws {
    let subject = ScheduleSubject(code: "CS101", name: "Computing")
    let meeting = ClassMeeting(subjectID: subject.id, weekdays: [.sunday], startTime: .init(hour: 23, minute: 0), endTime: .init(hour: 1, minute: 0), overnightDayOffset: 1)
    let rows = [ScheduleReviewRow(subject: subject, meetings: [meeting])]
    let term = scheduleTerm()
    let zone = try #require(term.timeZone)
    let monday = try #require(ScheduleLocalDate(year: 2026, month: 9, day: 14).date(in: zone))
    let today = DateInterval(start: monday, duration: 86400)
    let overnight = try #require(ScheduleOccurrenceGenerator.occurrences(term: term, rows: rows, in: today).first)
    let wholeTerm = try #require(ScheduleOccurrenceGenerator.occurrences(term: term, rows: rows).first)
    #expect(overnight.id == wholeTerm.id)
    #expect(overnight.end == monday.addingTimeInterval(3600))
    let afterFinish = DateInterval(start: monday.addingTimeInterval(3600), duration: 3600)
    #expect(ScheduleOccurrenceGenerator.occurrences(term: term, rows: rows, in: afterFinish).isEmpty)
}

@Test func scheduleValidationDetectsConflictAcrossMidnight() {
    let subject = ScheduleSubject(code: "CS101", name: "Computing")
    let night = ClassMeeting(subjectID: subject.id, weekdays: [.sunday], startTime: .init(hour: 23, minute: 0), endTime: .init(hour: 2, minute: 0), overnightDayOffset: 1)
    let morning = ClassMeeting(subjectID: subject.id, weekdays: [.monday], startTime: .init(hour: 1, minute: 0), endTime: .init(hour: 3, minute: 0))
    let issues = ScheduleValidator.validate(term: scheduleTerm(), rows: [.init(subject: subject, meetings: [night, morning])])
    #expect(issues.contains { $0.severity == .warning && $0.message.contains("conflict") })
}

@Test func scheduleParserReadsPipeTableAndCourseNameHeader() throws {
    let row = try #require(ScheduleImportParser.parse(text: "Course Code | Course Name | Days | Time\nCS101 | Computing | MWF | 10AM - 11:30AM").rows.first)
    let meeting = try #require(row.meetings.first)
    #expect(row.subject.code == "CS101"); #expect(row.subject.name == "Computing")
    #expect(meeting.startTime == .init(hour: 10, minute: 0)); #expect(meeting.weekdays == [.monday, .wednesday, .friday])
}

@Test func scheduleParserKeepsBackwardRangeForManualResolution() throws {
    let row = try #require(ScheduleImportParser.parse(text: "Code|Course Name|Days|Time\nCS101|Computing|TTH|10PM - 1AM").rows.first)
    #expect(try #require(row.meetings.first).overnightDayOffset == 0)
}

@Test func scheduleValidationRequiresTimeZone() {
    var invalid = scheduleTerm(); invalid.timeZoneIdentifier = "invalid"
    #expect(ScheduleValidator.validate(term: invalid, rows: []).contains { $0.severity == .error })
}

@Test func scheduleExplicitTBAIsValid() {
    let subject = ScheduleSubject(code: "CS101", name: "Computing")
    let row = ScheduleReviewRow(subject: subject, meetings: [.init(subjectID: subject.id, weekdays: [], startTime: nil, endTime: nil, isTBA: true)])
    #expect(!ScheduleValidator.validate(term: scheduleTerm(), rows: [row]).contains { $0.severity == .error })
}

@Test func scheduleEncryptedStoreSeparatesAccountsAndRetainsMissingKeyData() async throws {
    let url = scheduleTempURL(); defer { try? FileManager.default.removeItem(at: url) }
    let keys = ScheduleTestKeychain(); let first = try PipoEAFScheduleStore(databaseURL: url, accountID: "a", keychain: keys)
    try await first.saveConfirmed(scheduleDraft())
    let second = try PipoEAFScheduleStore(databaseURL: url, accountID: "b", keychain: keys)
    #expect(try await second.load() == nil)
    let locked = try PipoEAFScheduleStore(databaseURL: url, accountID: "a", keychain: ScheduleTestKeychain())
    do { _ = try await locked.load(); Issue.record("Expected retained missing-key error") }
    catch let error as PipoEAFScheduleStoreError { #expect(error == .missingKeyForExistingData) }
    #expect(try await first.load() != nil)
}

@Test func scheduleStoreRefusesWritesForNewerSchema() async throws {
    let url = scheduleTempURL(); defer { try? FileManager.default.removeItem(at: url) }
    let store = try PipoEAFScheduleStore(databaseURL: url, accountID: "a", keychain: ScheduleTestKeychain())
    try await store.saveConfirmed(scheduleDraft())
    let database = try DatabaseQueue(path: url.path)
    try await database.write { db in try db.execute(sql: "UPDATE pipo_schedule SET schema_version = 2") }
    do { try await store.saveConfirmed(scheduleDraft()); Issue.record("Expected newer-schema refusal") }
    catch let error as PipoEAFScheduleStoreError { #expect(error == .unsupportedSchema(2)) }
}

@Test func scheduleParserPreservesNormalizedValuesWhenRawColumnsAreOmitted() throws {
    let row = try #require(ScheduleImportParser.parse(text: "CS101 | Computing | MWF | 10AM - 11AM").rows.first)
    #expect(row.subject.code == "CS101"); #expect(row.rawCode == "CS101")
    #expect(row.rawSection.isEmpty); #expect(row.rawInstructor.isEmpty)
}

private func scheduleTerm() -> ScheduleTerm { .init(name: "Term", startDate: .init(year: 2026, month: 9, day: 7), endDate: .init(year: 2026, month: 9, day: 13), timeZoneIdentifier: "Asia/Manila") }
private func scheduleTempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("schedule-\(UUID().uuidString).sqlite") }
private func scheduleDraft() -> ScheduleDraft { let subject = ScheduleSubject(code: "CS101", name: "Computing"); return .init(term: scheduleTerm(), rows: [.init(subject: subject, meetings: [.init(subjectID: subject.id, weekdays: [], startTime: nil, endTime: nil, isTBA: true)])]) }

private final class ScheduleTestKeychain: PipoKeychainBackend, @unchecked Sendable {
    private let lock = NSLock(); private var storage: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return storage["\(service)/\(account)"] }
    func write(_ data: Data, service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; storage["\(service)/\(account)"] = data }
    func delete(service: String, account: String) throws { lock.lock(); defer { lock.unlock() }; storage.removeValue(forKey: "\(service)/\(account)") }
}
