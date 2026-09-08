import CryptoKit
import Foundation
import GRDB
import Security

public enum PipoEAFScheduleStoreError: LocalizedError, Equatable, Sendable {
  case missingKeyForExistingData
  case corruptedData
  case unsupportedSchema(Int)
  case invalidKey

  public var errorDescription: String? {
    switch self {
    case .missingKeyForExistingData:
      return "Schedule encryption key is unavailable; retained schedule cannot be opened."
    case .corruptedData: return "Stored schedule is corrupted and has been retained."
    case .unsupportedSchema(let version):
      return "Schedule schema \(version) is newer than this app."
    case .invalidKey: return "Schedule encryption key is invalid."
    }
  }
}

public protocol PipoEAFScheduleStoreProtocol: Sendable {
  func prepare() async throws
  func load() async throws -> ScheduleDraft?
  func saveConfirmed(_ draft: ScheduleDraft) async throws
  func deleteSchedule() async throws
  func reimport(_ draft: ScheduleDraft, preservingManualCorrections: Bool) async throws
    -> ScheduleDraft
}

public actor PipoEAFScheduleStore: PipoEAFScheduleStoreProtocol {
  private let database: DatabaseQueue
  private let accountID: String
  private let backend: any PipoKeychainBackend
  private let service: String
  private let keyAccount: String
  private var key: SymmetricKey?
  private static let schemaVersion = 1
  public init(
    databaseURL: URL, accountID: String,
    keychain: any PipoKeychainBackend = PipoSystemKeychainBackend(),
    service: String = "com.jazztinn.pipo.schedule"
  ) throws {
    self.accountID = accountID
    backend = keychain
    self.service = service
    keyAccount = "schedule-key-v1.\(accountID)"
    database = try DatabaseQueue(path: databaseURL.path)
    try database.write { db in
      try db.execute(
        sql:
          "CREATE TABLE IF NOT EXISTS pipo_schedule (account_id TEXT PRIMARY KEY NOT NULL, schema_version INTEGER NOT NULL, payload BLOB NOT NULL, updated_at REAL NOT NULL)"
      )
      try db.execute(
        sql:
          "CREATE TABLE IF NOT EXISTS pipo_schedule_backup (account_id TEXT NOT NULL, schema_version INTEGER NOT NULL, payload BLOB NOT NULL, created_at REAL NOT NULL)"
      )
      let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
      if version > Self.schemaVersion { throw PipoEAFScheduleStoreError.unsupportedSchema(version) }
      if version < Self.schemaVersion {
        try db.execute(
          sql:
            "INSERT INTO pipo_schedule_backup(account_id, schema_version, payload, created_at) SELECT account_id, schema_version, payload, ? FROM pipo_schedule",
          arguments: [Date().timeIntervalSince1970])
        try db.execute(sql: "PRAGMA user_version = \(Self.schemaVersion)")
      }
    }
  }
  public func prepare() throws {
    _ = try keyOrCreate()
  }

  public func load() throws -> ScheduleDraft? {
    let record: Row? = try database.read { db in
      try Row.fetchOne(
        db, sql: "SELECT schema_version, payload FROM pipo_schedule WHERE account_id = ?",
        arguments: [accountID])
    }
    guard let record else { return nil }
    let version: Int = record["schema_version"]
    guard version <= Self.schemaVersion else {
      throw PipoEAFScheduleStoreError.unsupportedSchema(version)
    }
    do { return try ConfirmedSchedule.decode(from: decrypt(record["payload"] as Data)) } catch let
      error as PipoEAFScheduleStoreError
    { throw error } catch { throw PipoEAFScheduleStoreError.corruptedData }
  }
  public func saveConfirmed(_ draft: ScheduleDraft) throws {
    try Task.checkCancellation()
    let issues = ScheduleValidator.validate(term: draft.term, rows: draft.rows)
    guard !issues.contains(where: { $0.severity == .error }) else {
      throw PipoCoreError.operationFailed(
        "Schedule needs valid term dates, time zone, and meetings.")
    }
    let existingVersion: Int? = try database.read { db in
      try Int.fetchOne(
        db, sql: "SELECT schema_version FROM pipo_schedule WHERE account_id = ?",
        arguments: [accountID])
    }
    if let existingVersion, existingVersion > Self.schemaVersion {
      throw PipoEAFScheduleStoreError.unsupportedSchema(existingVersion)
    }
    let data = try JSONEncoder().encode(ConfirmedSchedule(draft))
    let ciphertext = try encrypt(data)
    try database.write { db in
      try Task.checkCancellation()
      let schema = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
      guard schema <= Self.schemaVersion else {
        throw PipoEAFScheduleStoreError.unsupportedSchema(schema)
      }
      let rowSchema =
        try Int.fetchOne(
          db, sql: "SELECT schema_version FROM pipo_schedule WHERE account_id = ?",
          arguments: [accountID]) ?? 0
      guard rowSchema <= Self.schemaVersion else {
        throw PipoEAFScheduleStoreError.unsupportedSchema(rowSchema)
      }
      try db.execute(
        sql:
          "INSERT INTO pipo_schedule(account_id, schema_version, payload, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(account_id) DO UPDATE SET schema_version = excluded.schema_version, payload = excluded.payload, updated_at = excluded.updated_at",
        arguments: [accountID, Self.schemaVersion, ciphertext, Date().timeIntervalSince1970])
    }
  }
  public func deleteSchedule() throws {
    try Task.checkCancellation()
    try database.write { db in
      try Task.checkCancellation()
      try db.execute(sql: "DELETE FROM pipo_schedule WHERE account_id = ?", arguments: [accountID])
      try db.execute(
        sql: "DELETE FROM pipo_schedule_backup WHERE account_id = ?", arguments: [accountID])
    }
    try backend.delete(service: service, account: keyAccount)
    key = nil
  }
  public func reimport(_ incoming: ScheduleDraft, preservingManualCorrections: Bool = true) throws
    -> ScheduleDraft
  {
    guard preservingManualCorrections, let old = try load() else { return incoming }
    var merged = incoming
    for i in merged.rows.indices {
      let matches = old.rows.filter {
        normalized($0.subject.code) == normalized(merged.rows[i].subject.code)
          && normalized($0.subject.section) == normalized(merged.rows[i].subject.section)
      }
      let incomingMatches = incoming.rows.filter {
        normalized($0.subject.code) == normalized(merged.rows[i].subject.code)
          && normalized($0.subject.section) == normalized(merged.rows[i].subject.section)
      }
      if matches.count == 1, incomingMatches.count == 1, let prior = matches.first {
        var row = merged.rows[i]
        row.id = prior.id
        row.subject.id = prior.subject.id
        row.meetings = row.meetings.map {
          var m = $0
          if let pm = prior.meetings.first(where: {
            $0.weekdays == m.weekdays && $0.startTime == m.startTime
          }) {
            m.id = pm.id
          }
          m.subjectID = row.subject.id
          return m
        }
        if prior.manuallyCorrected { row = prior }
        merged.rows[i] = row
      }
    }
    merged.revision = old.revision + 1
    return merged
  }
  private func keyOrCreate() throws -> SymmetricKey {
    if let key { return key }
    if let data = try backend.read(service: service, account: keyAccount) {
      guard data.count == 32 else { throw PipoEAFScheduleStoreError.invalidKey }
      let value = SymmetricKey(data: data)
      key = value
      return value
    }
    let existing = try database.read { db in
      try Bool.fetchOne(
        db, sql: "SELECT EXISTS(SELECT 1 FROM pipo_schedule WHERE account_id = ?)",
        arguments: [accountID]) ?? false
    }
    if existing { throw PipoEAFScheduleStoreError.missingKeyForExistingData }
    var data = Data(repeating: 0, count: 32)
    let status = data.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw PipoSecureStorageError.unavailable("Secure random generation failed.")
    }
    try backend.write(data, service: service, account: keyAccount)
    let value = SymmetricKey(data: data)
    key = value
    return value
  }
  private func encrypt(_ plaintext: Data) throws -> Data {
    try AES.GCM.seal(plaintext, using: keyOrCreate()).combined.unwrap(
      or: PipoCoreError.operationFailed("Schedule encryption failed"))
  }
  private func decrypt(_ ciphertext: Data) throws -> Data {
    let activeKey = try keyOrCreate()
    do {
      return try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: activeKey)
    } catch {
      throw PipoEAFScheduleStoreError.corruptedData
    }
  }
  private func normalized(_ value: String) -> String {
    value.lowercased().filter { !$0.isWhitespace }
  }
}

private struct ConfirmedSchedule: Codable {
  struct Course: Codable {
    var rowID: UUID
    var subject: ScheduleSubject
    var meetings: [ClassMeeting]
    var manuallyCorrected: Bool
  }

  var id: UUID
  var term: ScheduleTerm
  var courses: [Course]
  var revision: Int
  var parserVersion: Int? = 1
  var confirmedAt: Date? = .now

  init(_ draft: ScheduleDraft) {
    id = draft.id
    term = draft.term
    revision = draft.revision
    courses = draft.rows.map {
      Course(
        rowID: $0.id, subject: $0.subject, meetings: $0.meetings,
        manuallyCorrected: $0.manuallyCorrected)
    }
  }

  static func decode(from data: Data) throws -> ScheduleDraft {
    let stored = try JSONDecoder().decode(Self.self, from: data)
    let rows = stored.courses.map { course in
      ScheduleReviewRow(
        id: course.rowID, rawCode: course.subject.code, rawName: course.subject.name,
        rawSection: course.subject.section, rawInstructor: course.subject.instructor,
        uncertaintyAcknowledged: true, subject: course.subject, meetings: course.meetings,
        manuallyCorrected: course.manuallyCorrected)
    }
    let draft = ScheduleDraft(
      id: stored.id, term: stored.term, rows: rows, revision: stored.revision)
    guard
      !ScheduleValidator.validate(term: draft.term, rows: draft.rows).contains(where: {
        $0.severity == .error
      })
    else {
      throw PipoEAFScheduleStoreError.corruptedData
    }
    return draft
  }
}
