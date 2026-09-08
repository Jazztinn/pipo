import Foundation
import Observation

@MainActor
@Observable
public final class PipoScheduleController {
  public private(set) var accountID: String?
  public private(set) var confirmed: ScheduleDraft?
  public private(set) var draft: ScheduleDraft?
  public private(set) var preview: PipoEAFSourcePreview?
  public private(set) var isImporting = false
  public private(set) var isSaving = false
  public private(set) var isDeleting = false
  public private(set) var error: String?
  public private(set) var validationIssues: [ScheduleIssue] = []
  public private(set) var importChanges: [String] = []
  public private(set) var hasAcknowledgedUncertainty = false
  public private(set) var isEditing = false
  public private(set) var pendingRows: [ScheduleReviewRow] = []

  public var canSave: Bool {
    guard store != nil, let draft, !isImporting, !isSaving, !isDeleting,
      !draft.term.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      draft.term.timeZone != nil, draft.term.startDate <= draft.term.endDate,
      draft.rows.allSatisfy({ $0.uncertainty.isEmpty || $0.uncertaintyAcknowledged })
    else { return false }
    return !validationIssues.contains { $0.severity == .error }
  }

  private let baseDirectory: URL
  private let keychain: (any PipoKeychainBackend)?
  private var store: (any PipoEAFScheduleStoreProtocol)?
  private var generation = 0
  private var operation: Task<Void, Never>?

  public init(baseDirectory: URL? = nil, keychain: (any PipoKeychainBackend)? = nil) {
    self.baseDirectory =
      baseDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Pipo", isDirectory: true)
    self.keychain = keychain
  }

  public func activate(accountID: String) async {
    deactivate()
    let id = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else {
      error = "Schedule account is unavailable."
      return
    }
    self.accountID = id
    generation += 1
    let token = generation
    do {
      try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
      let database = baseDirectory.appendingPathComponent("schedule.sqlite")
      if let keychain {
        store = try PipoEAFScheduleStore(databaseURL: database, accountID: id, keychain: keychain)
      } else {
        store = try PipoEAFScheduleStore(databaseURL: database, accountID: id)
      }
      try await store?.prepare()
      guard token == generation, self.accountID == id else { return }
      let loaded = try await store?.load()
      guard token == generation, self.accountID == id else { return }
      confirmed = loaded
      draft = loaded
      hasAcknowledgedUncertainty = loaded?.rows.allSatisfy { $0.uncertainty.isEmpty } ?? false
      validate()
    } catch {
      guard token == generation else { return }
      self.error = error.localizedDescription
      store = nil
    }
  }

  public func deactivate() {
    generation += 1
    operation?.cancel()
    operation = nil
    accountID = nil
    confirmed = nil
    draft = nil
    preview = nil
    error = nil
    validationIssues = []
    importChanges = []
    hasAcknowledgedUncertainty = false
    isEditing = false
    pendingRows = []
    isImporting = false
    isSaving = false
    isDeleting = false
    store = nil
  }

  public func importDocument(at url: URL) async {
    guard !isSaving, !isDeleting else { return }
    guard accountID != nil else {
      error = "Sign in before importing a schedule."
      return
    }
    operation?.cancel()
    generation += 1
    isImporting = true
    error = nil
    let token = generation
    let task = Task<Void, Never> { [weak self] in
      guard let self else { return }
      await self.performImport(url: url, token: token)
    }
    operation = task
    await task.value
    if token == generation { operation = nil }
  }

  private func performImport(url: URL, token: Int) async {
    do {
      let result = try await PipoEAFImporter.importDocument(at: url)
      guard token == generation, let activeAccount = accountID else { return }
      let old = confirmed
      guard let term = draft?.term ?? old?.term else {
        preview = result.preview
        pendingRows = result.parsed.rows
        error = "Set term dates and time zone before reviewing imported rows."
        isImporting = false
        return
      }
      let incoming = ScheduleDraft(term: term, rows: result.parsed.rows)
      let merged =
        try await store?.reimport(incoming, preservingManualCorrections: true) ?? incoming
      guard token == generation, accountID == activeAccount else { return }
      preview = result.preview
      draft = merged
      isEditing = true
      importChanges = Self.describeChanges(old: old, new: merged)
      hasAcknowledgedUncertainty = merged.rows.allSatisfy { $0.uncertainty.isEmpty }
      validate()
      isImporting = false
    } catch {
      if token == generation {
        self.error = error.localizedDescription
        isImporting = false
      }
    }
  }

  public func beginEditing() {
    if draft == nil, let confirmed { draft = confirmed }
    isEditing = true
    validate()
  }

  public func beginManual(term: ScheduleTerm) {
    draft = ScheduleDraft(term: term, rows: [])
    isEditing = true
    preview = nil
    hasAcknowledgedUncertainty = true
    validate()
  }

  public func createDraft(term: ScheduleTerm) {
    guard !pendingRows.isEmpty else {
      draft = ScheduleDraft(term: term, rows: [])
      isEditing = true
      validate()
      return
    }
    draft = ScheduleDraft(term: term, rows: pendingRows)
    pendingRows = []
    isEditing = true
    validate()
  }

  public func cancelReview() {
    generation += 1
    operation?.cancel()
    operation = nil
    isImporting = false
    isSaving = false
    isDeleting = false
    draft = confirmed
    preview = nil
    importChanges = []
    pendingRows = []
    isEditing = false
    hasAcknowledgedUncertainty = draft?.rows.allSatisfy { $0.uncertainty.isEmpty } ?? false
    validate()
  }

  public func setTerm(
    name: String, start: ScheduleLocalDate? = nil, end: ScheduleLocalDate? = nil,
    timeZoneIdentifier: String? = nil
  ) {
    guard var value = draft else { return }
    value.term.name = name
    if let start { value.term.startDate = start }
    if let end { value.term.endDate = end }
    if let timeZoneIdentifier { value.term.timeZoneIdentifier = timeZoneIdentifier }
    updateDraft(value)
  }

  public func updateSubjectName(index: Int, name: String) {
    guard var value = draft, value.rows.indices.contains(index) else { return }
    value.rows[index].subject.name = name
    value.rows[index].rawName = name
    updateDraft(value)
  }
  public func updateSubjectCode(index: Int, code: String) {
    guard var value = draft, value.rows.indices.contains(index) else { return }
    value.rows[index].subject.code = code
    value.rows[index].rawCode = code
    updateDraft(value)
  }
  public func updateSubjectSection(index: Int, section: String) {
    guard var value = draft, value.rows.indices.contains(index) else { return }
    value.rows[index].subject.section = section
    value.rows[index].rawSection = section
    updateDraft(value)
  }
  public func updateSubjectInstructor(index: Int, instructor: String) {
    guard var value = draft, value.rows.indices.contains(index) else { return }
    value.rows[index].subject.instructor = instructor
    value.rows[index].rawInstructor = instructor
    updateDraft(value)
  }
  public func updateMeeting(
    index: Int, meetingIndex: Int, weekdays: Set<ScheduleWeekday>? = nil,
    startTime: ScheduleClockTime? = nil, endTime: ScheduleClockTime? = nil, location: String? = nil,
    isTBA: Bool? = nil, overnightDayOffset: Int? = nil
  ) {
    guard var value = draft, value.rows.indices.contains(index),
      value.rows[index].meetings.indices.contains(meetingIndex)
    else { return }
    if let weekdays { value.rows[index].meetings[meetingIndex].weekdays = weekdays }
    if let startTime { value.rows[index].meetings[meetingIndex].startTime = startTime }
    if let endTime { value.rows[index].meetings[meetingIndex].endTime = endTime }
    if let location { value.rows[index].meetings[meetingIndex].location = location }
    if let isTBA { value.rows[index].meetings[meetingIndex].isTBA = isTBA }
    if let overnightDayOffset {
      value.rows[index].meetings[meetingIndex].overnightDayOffset = overnightDayOffset
    }
    updateDraft(value)
  }

  public func newSubject() {
    beginEditing()
    guard var value = draft else { return }
    let subject = ScheduleSubject(code: "", name: "New subject")
    let meeting = ClassMeeting(
      subjectID: subject.id, weekdays: [], startTime: nil, endTime: nil, isTBA: true)
    value.rows.append(ScheduleReviewRow(subject: subject, meetings: [meeting]))
    updateDraft(value)
    hasAcknowledgedUncertainty = false
  }

  public func removeSubject(id: UUID) {
    guard var value = draft else { return }
    value.rows.removeAll { $0.id == id }
    updateDraft(value)
  }
  public func addMeeting(subjectID: UUID) {
    guard var value = draft,
      let index = value.rows.firstIndex(where: { $0.id == subjectID || $0.subject.id == subjectID })
    else { return }
    value.rows[index].meetings.append(
      ClassMeeting(
        subjectID: value.rows[index].subject.id, weekdays: [], startTime: nil, endTime: nil,
        isTBA: true))
    updateDraft(value)
  }
  public func removeMeeting(subjectID: UUID, meetingID: UUID) {
    guard var value = draft,
      let index = value.rows.firstIndex(where: { $0.id == subjectID || $0.subject.id == subjectID })
    else { return }
    value.rows[index].meetings.removeAll { $0.id == meetingID }
    updateDraft(value)
  }
  public func updateDraft(_ value: ScheduleDraft) {
    guard !isSaving, !isDeleting else { return }
    var edited = value
    for index in edited.rows.indices {
      let old = draft?.rows.first { $0.id == edited.rows[index].id }
      if old?.subject != edited.rows[index].subject || old?.meetings != edited.rows[index].meetings
      {
        edited.rows[index].manuallyCorrected = true
        if !edited.rows[index].uncertainty.isEmpty {
          edited.rows[index].uncertaintyAcknowledged = false
        }
      }
    }
    draft = edited
    hasAcknowledgedUncertainty = edited.rows.allSatisfy {
      $0.uncertainty.isEmpty || $0.uncertaintyAcknowledged
    }
    validationIssues = ScheduleValidator.validate(term: edited.term, rows: edited.rows)
    error = nil
  }
  public func acknowledgeUncertainty() {
    guard var value = draft else { return }
    for index in value.rows.indices where !value.rows[index].uncertainty.isEmpty {
      value.rows[index].uncertaintyAcknowledged = true
    }
    draft = value
    hasAcknowledgedUncertainty = true
    validate()
  }

  public func save() async {
    guard let store, let draft, canSave else {
      error = "Review schedule fields before saving."
      return
    }
    isSaving = true
    error = nil
    let token = generation
    let task = Task<Void, Never> { [weak self] in
      guard let self else { return }
      await self.performSave(draft, store: store, token: token)
    }
    operation = task
    await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    if token == generation { operation = nil }
  }

  private func performSave(
    _ value: ScheduleDraft, store: any PipoEAFScheduleStoreProtocol, token: Int
  ) async {
    var draft = value
    do {
      draft.revision += 1
      try Task.checkCancellation()
      try await store.saveConfirmed(draft)
      guard token == generation else { return }
      for index in draft.rows.indices {
        draft.rows[index].sourceSpan = nil
        draft.rows[index].rawCode = ""
        draft.rows[index].rawName = ""
        draft.rows[index].rawSection = ""
        draft.rows[index].rawInstructor = ""
        draft.rows[index].rawWeekdays = ""
        draft.rows[index].rawTime = ""
        draft.rows[index].rawLocation = ""
        draft.rows[index].uncertainty = []
        draft.rows[index].issues = []
      }
      confirmed = draft
      self.draft = draft
      preview = nil
      isEditing = false
      isSaving = false
    } catch {
      if token == generation {
        self.error = error.localizedDescription
        isSaving = false
      }
    }
  }

  public func delete() async {
    guard let store, !isSaving, !isDeleting, !isImporting else { return }
    isDeleting = true
    let token = generation
    let task = Task<Void, Never> { [weak self] in
      guard let self else { return }
      await self.performDelete(store: store, token: token)
    }
    operation = task
    await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    if token == generation { operation = nil }
  }

  private func performDelete(store: any PipoEAFScheduleStoreProtocol, token: Int) async {
    do {
      try await store.deleteSchedule()
      guard token == generation else { return }
      confirmed = nil
      draft = nil
      preview = nil
      isEditing = false
      isDeleting = false
    } catch {
      if token == generation {
        self.error = error.localizedDescription
        isDeleting = false
      }
    }
  }

  private func validate() {
    validationIssues = draft.map { ScheduleValidator.validate(term: $0.term, rows: $0.rows) } ?? []
  }

  public func items(now: Date = .now) -> [DashboardItem] {
    guard let confirmed, let zone = confirmed.term.timeZone else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let occurrences = ScheduleOccurrenceGenerator.occurrences(
      term: confirmed.term, rows: confirmed.rows,
      in: DateInterval(
        start: calendar.startOfDay(for: now),
        duration: calendar.dateInterval(of: .day, for: now)?.duration ?? 86_400))
    let subjects = Dictionary(
      uniqueKeysWithValues: confirmed.rows.map { ($0.subject.id, $0.subject) })
    return occurrences.map { occurrence in
      let subject = subjects[occurrence.subjectID]
      return DashboardItem(
        id: "schedule-\(occurrence.id.uuidString)",
        entityKey: "schedule-\(occurrence.id.uuidString)", kind: "imported_class",
        title: subject?.name ?? "Class meeting", courseID: nil, courseName: subject?.code ?? "",
        instructor: subject?.instructor,
        timestamp: occurrence.start.map { ISO8601DateFormatter().string(from: $0) },
        destination: "",
        detail: "Imported schedule · "
          + (confirmed.rows.flatMap(\.meetings).first { $0.id == occurrence.meetingID }?.location
            ?? ""),
        section: "imported_schedule")
    }
  }
  public func todayEndDates(now: Date = .now) -> [String: String] {
    guard let confirmed, let zone = confirmed.term.timeZone else { return [:] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard let interval = calendar.dateInterval(of: .day, for: now) else { return [:] }
    let occurrences = ScheduleOccurrenceGenerator.occurrences(
      term: confirmed.term, rows: confirmed.rows, in: interval)
    let formatter = ISO8601DateFormatter()
    return Dictionary(
      occurrences.compactMap { occurrence in
        occurrence.end.map { ("schedule-" + occurrence.id.uuidString, formatter.string(from: $0)) }
      }, uniquingKeysWith: { first, _ in first })
  }

  public func searchItems() -> [DashboardItem] {
    guard let confirmed else { return [] }
    return confirmed.rows.map { row in
      let locations = Set(row.meetings.map(\.location).filter { !$0.isEmpty }).sorted().joined(
        separator: ", ")
      return DashboardItem(
        id: "schedule-subject-" + row.subject.id.uuidString,
        kind: "imported_subject", title: row.subject.name, courseName: row.subject.code,
        instructor: row.subject.instructor, detail: "Imported schedule · " + locations,
        section: "imported_schedule")
    }
  }

  static func describeChanges(old: ScheduleDraft?, new: ScheduleDraft) -> [String] {
    guard let old else {
      return new.rows.isEmpty
        ? [] : ["Added \(new.rows.count) subject\(new.rows.count == 1 ? "" : "s")"]
    }
    let oldKeys = Set(old.rows.map { "\($0.subject.code)|\($0.subject.section)" })
    let newKeys = Set(new.rows.map { "\($0.subject.code)|\($0.subject.section)" })
    var changes = newKeys.subtracting(oldKeys).sorted().map {
      "Added \($0.replacingOccurrences(of: "|", with: " "))"
    }
    changes += oldKeys.subtracting(newKeys).sorted().map {
      "Removed \($0.replacingOccurrences(of: "|", with: " "))"
    }
    for row in new.rows {
      guard let previous = old.rows.first(where: { $0.subject.id == row.subject.id }) else {
        continue
      }
      if previous.subject != row.subject || previous.meetings != row.meetings {
        changes.append(
          "Updated \(row.subject.code) \(row.subject.section)".trimmingCharacters(in: .whitespaces))
      }
    }
    return changes
  }
}
