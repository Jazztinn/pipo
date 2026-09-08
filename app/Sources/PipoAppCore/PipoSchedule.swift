import CryptoKit
import Foundation

public struct ScheduleLocalDate: Codable, Hashable, Comparable, Sendable {
  public var year: Int
  public var month: Int
  public var day: Int
  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }
  public init(_ date: Date, timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    year = c.year ?? 1
    month = c.month ?? 1
    day = c.day ?? 1
  }
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.year != rhs.year { return lhs.year < rhs.year }
    if lhs.month != rhs.month { return lhs.month < rhs.month }
    return lhs.day < rhs.day
  }
  public func date(in timeZone: TimeZone) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      ScheduleLocalDate(date, timeZone: timeZone) == self
    else { return nil }
    return date
  }
}

public enum ScheduleWeekday: Int, Codable, CaseIterable, Hashable, Sendable {
  case sunday = 1
  case monday, tuesday, wednesday, thursday, friday, saturday
}

public struct ScheduleClockTime: Codable, Hashable, Comparable, Sendable {
  public var hour: Int
  public var minute: Int
  public init(hour: Int, minute: Int) {
    self.hour = hour
    self.minute = minute
  }
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.hour == rhs.hour ? lhs.minute < rhs.minute : lhs.hour < rhs.hour
  }
  public var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }
  public var minutesSinceMidnight: Int { hour * 60 + minute }
}

public struct ScheduleTerm: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var name: String
  public var startDate: ScheduleLocalDate
  public var endDate: ScheduleLocalDate
  public var timeZoneIdentifier: String
  public init(
    id: UUID = UUID(), name: String, startDate: ScheduleLocalDate, endDate: ScheduleLocalDate,
    timeZoneIdentifier: String
  ) {
    self.id = id
    self.name = name
    self.startDate = startDate
    self.endDate = endDate
    self.timeZoneIdentifier = timeZoneIdentifier
  }
  public var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
}
public struct ScheduleSubject: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var code: String
  public var name: String
  public var section: String
  public var instructor: String
  public var lmsCourseReference: String?
  public init(
    id: UUID = UUID(), code: String, name: String, section: String = "", instructor: String = "",
    lmsCourseReference: String? = nil
  ) {
    self.id = id
    self.code = code
    self.name = name
    self.section = section
    self.instructor = instructor
    self.lmsCourseReference = lmsCourseReference
  }
}
public struct ClassMeeting: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var subjectID: UUID
  public var weekdays: Set<ScheduleWeekday>
  public var startTime: ScheduleClockTime?
  public var endTime: ScheduleClockTime?
  public var location: String
  public var isTBA: Bool
  public var overnightDayOffset: Int
  public init(
    id: UUID = UUID(), subjectID: UUID, weekdays: Set<ScheduleWeekday>,
    startTime: ScheduleClockTime?, endTime: ScheduleClockTime?, location: String = "",
    isTBA: Bool = false, overnightDayOffset: Int = 0
  ) {
    self.id = id
    self.subjectID = subjectID
    self.weekdays = weekdays
    self.startTime = startTime
    self.endTime = endTime
    self.location = location
    self.isTBA = isTBA
    self.overnightDayOffset = overnightDayOffset
  }
}
public struct ScheduleOccurrence: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var meetingID: UUID
  public var subjectID: UUID
  public var start: Date?
  public var end: Date?
  public var isTBA: Bool
  public init(
    id: UUID = UUID(), meetingID: UUID, subjectID: UUID, start: Date?, end: Date?, isTBA: Bool
  ) {
    self.id = id
    self.meetingID = meetingID
    self.subjectID = subjectID
    self.start = start
    self.end = end
    self.isTBA = isTBA
  }
}
public enum ScheduleIssueSeverity: String, Codable, Sendable { case warning, error }
public struct ScheduleIssue: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var severity: ScheduleIssueSeverity
  public var message: String
  public init(id: UUID = UUID(), severity: ScheduleIssueSeverity, message: String) {
    self.id = id
    self.severity = severity
    self.message = message
  }
}
public struct ScheduleSourceSpan: Codable, Hashable, Sendable {
  public var page: Int
  public var line: Int
  public var column: Int
  public var length: Int
  public init(page: Int = 0, line: Int, column: Int = 0, length: Int) {
    self.page = page
    self.line = line
    self.column = column
    self.length = length
  }
}
public struct ScheduleReviewRow: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var rawCode: String
  public var rawName: String
  public var rawSection: String
  public var rawInstructor: String
  public var rawWeekdays: String
  public var rawTime: String
  public var rawLocation: String
  public var uncertainty: [String]
  public var uncertaintyAcknowledged: Bool
  public var issues: [ScheduleIssue]
  public var sourceSpan: ScheduleSourceSpan?
  public var subject: ScheduleSubject
  public var meetings: [ClassMeeting]
  public var manuallyCorrected: Bool
  public init(
    id: UUID = UUID(), rawCode: String = "", rawName: String = "", rawSection: String = "",
    rawInstructor: String = "", rawWeekdays: String = "", rawTime: String = "",
    rawLocation: String = "", uncertainty: [String] = [], uncertaintyAcknowledged: Bool = false,
    issues: [ScheduleIssue] = [], sourceSpan: ScheduleSourceSpan? = nil, subject: ScheduleSubject,
    meetings: [ClassMeeting] = [], manuallyCorrected: Bool = false
  ) {
    self.id = id
    self.rawCode = rawCode
    self.rawName = rawName
    self.rawSection = rawSection
    self.rawInstructor = rawInstructor
    self.rawWeekdays = rawWeekdays
    self.rawTime = rawTime
    self.rawLocation = rawLocation
    self.uncertainty = uncertainty
    self.uncertaintyAcknowledged = uncertaintyAcknowledged
    self.issues = issues
    self.sourceSpan = sourceSpan
    self.subject = subject
    self.meetings = meetings
    self.manuallyCorrected = manuallyCorrected
  }
}
public struct ScheduleDraft: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var term: ScheduleTerm
  public var rows: [ScheduleReviewRow]
  public var revision: Int
  public init(id: UUID = UUID(), term: ScheduleTerm, rows: [ScheduleReviewRow], revision: Int = 0) {
    self.id = id
    self.term = term
    self.rows = rows
    self.revision = revision
  }
}
public typealias PipoSchedule = ScheduleDraft

public enum ScheduleOccurrenceGenerator {
  public static func occurrences(
    term: ScheduleTerm, rows: [ScheduleReviewRow], in interval: DateInterval? = nil
  ) -> [ScheduleOccurrence] {
    guard let zone = term.timeZone, let first = term.startDate.date(in: zone),
      let last = term.endDate.date(in: zone), last >= first,
      last.timeIntervalSince(first) <= 730 * 86_400, rows.count <= 200
    else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
    // Meetings starting on the final term day may finish the following day.
    let extendedEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    let termRange = DateInterval(start: first, end: extendedEnd)
    guard
      let range = interval.flatMap({ termRange.intersection(with: $0) })
        ?? (interval == nil ? termRange : nil), range.duration > 0
    else { return [] }
    var day = max(
      first,
      calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: range.start)) ?? first)
    var output: [ScheduleOccurrence] = []
    while day < min(range.end, end) {
      guard let weekday = ScheduleWeekday(rawValue: calendar.component(.weekday, from: day)) else {
        break
      }
      for row in rows {
        for meeting in row.meetings where meeting.weekdays.contains(weekday) {
          guard !meeting.isTBA, let startTime = meeting.startTime, let endTime = meeting.endTime,
            startTime.isValid, endTime.isValid, (0...1).contains(meeting.overnightDayOffset),
            let start = calendar.date(
              bySettingHour: startTime.hour, minute: startTime.minute, second: 0, of: day),
            let endDay = calendar.date(byAdding: .day, value: meeting.overnightDayOffset, to: day),
            let finish = calendar.date(
              bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: endDay),
            finish > start
          else { continue }
          if finish > range.start && start < range.end {
            output.append(
              .init(
                id: stableID(meeting.id, start), meetingID: meeting.id,
                subjectID: meeting.subjectID, start: start, end: finish, isTBA: false))
          }
        }
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return output.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
  }
  private static func stableID(_ meetingID: UUID, _ start: Date) -> UUID {
    let value = "\(meetingID.uuidString)|\(Int64(start.timeIntervalSince1970))"
    let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }
}

public enum ScheduleValidator {
  public static func validate(term: ScheduleTerm, rows: [ScheduleReviewRow]) -> [ScheduleIssue] {
    var issues: [ScheduleIssue] = []
    if term.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(severity: .error, message: "Term name is required."))
    }
    guard let zone = term.timeZone, term.startDate.date(in: zone) != nil,
      term.endDate.date(in: zone) != nil
    else {
      return issues + [
        .init(severity: .error, message: "Valid term dates and time zone are required.")
      ]
    }
    if term.startDate > term.endDate {
      issues.append(.init(severity: .error, message: "Term end date is before start date."))
    }
    if let first = term.startDate.date(in: zone), let last = term.endDate.date(in: zone),
      last.timeIntervalSince(first) > 730 * 86_400
    {
      issues.append(.init(severity: .error, message: "Term must be two years or shorter."))
    }
    if rows.count > 200 {
      issues.append(.init(severity: .error, message: "Schedule exceeds 200 subjects."))
    }
    if Set(rows.map(\.subject.id)).count != rows.count || Set(rows.map(\.id)).count != rows.count {
      issues.append(.init(severity: .error, message: "Duplicate subject identities."))
    }
    let meetings = rows.flatMap(\.meetings)
    if Set(meetings.map(\.id)).count != meetings.count {
      issues.append(.init(severity: .error, message: "Duplicate meeting identities."))
    }
    if rows.isEmpty {
      issues.append(.init(severity: .error, message: "At least one class is required."))
    }
    var byDay: [ScheduleWeekday: [(Int, Int)]] = [:]
    for row in rows {
      if row.subject.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(severity: .error, message: "Course code is required."))
      }
      if row.subject.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(severity: .error, message: "Course name is required."))
      }
      if !row.uncertainty.isEmpty && !row.uncertaintyAcknowledged {
        issues.append(.init(severity: .error, message: "Review schedule uncertainty."))
      }
      if row.meetings.isEmpty {
        issues.append(.init(severity: .error, message: "At least one meeting is required."))
      }
      if row.meetings.count > 16 {
        issues.append(.init(severity: .error, message: "Subject exceeds 16 meetings."))
      }
      if row.meetings.contains(where: { $0.subjectID != row.subject.id }) {
        issues.append(.init(severity: .error, message: "Meeting belongs to another subject."))
      }
      for meeting in row.meetings where !meeting.isTBA {
        guard let start = meeting.startTime, let end = meeting.endTime, start.isValid, end.isValid,
          !meeting.weekdays.isEmpty, (0...1).contains(meeting.overnightDayOffset),
          meeting.overnightDayOffset == 1 ? end <= start : end > start
        else {
          issues.append(.init(severity: .error, message: "Invalid meeting time."))
          continue
        }
        for day in meeting.weekdays {
          if meeting.overnightDayOffset == 1 {
            byDay[day, default: []].append((start.minutesSinceMidnight, 1440))
            let followingDay = ScheduleWeekday(rawValue: day.rawValue % 7 + 1)!
            if end.minutesSinceMidnight > 0 {
              byDay[followingDay, default: []].append((0, end.minutesSinceMidnight))
            }
          } else {
            byDay[day, default: []].append((start.minutesSinceMidnight, end.minutesSinceMidnight))
          }
        }
      }
    }
    for intervals in byDay.values {
      let sorted = intervals.sorted { $0.0 < $1.0 }
      var latestEnd = -1
      for (start, end) in sorted {
        if start < latestEnd {
          issues.append(.init(severity: .warning, message: "Schedule conflict detected."))
          break
        }
        latestEnd = max(latestEnd, end)
      }
    }
    return issues
  }
}
