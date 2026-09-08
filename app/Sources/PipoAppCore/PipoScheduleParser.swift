import Foundation

public struct ScheduleTextObservation: Codable, Hashable, Sendable {
  public var text: String
  public var page: Int
  public var line: Int
  public var x: Double?
  public var y: Double?
  public var width: Double?
  public var height: Double?
  public var confidence: Double?
  public var candidates: [String]
  /// Explicit delimiter column; geometry remains the source line's real bounds.
  public var columnIndex: Int?

  public init(
    text: String, page: Int = 0, line: Int, x: Double? = nil, y: Double? = nil,
    width: Double? = nil, height: Double? = nil, confidence: Double? = nil,
    candidates: [String] = [], columnIndex: Int? = nil
  ) {
    self.text = text
    self.page = page
    self.line = line
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.confidence = confidence
    self.candidates = candidates
    self.columnIndex = columnIndex
  }
}

public struct ScheduleParseResult: Sendable {
  public var rows: [ScheduleReviewRow]
  public var observations: [ScheduleTextObservation]
  public init(rows: [ScheduleReviewRow], observations: [ScheduleTextObservation]) {
    self.rows = rows
    self.observations = observations
  }
}

public enum ScheduleImportParser {
  public static func parse(text: String) -> ScheduleParseResult {
    let observations = text.split(whereSeparator: \.isNewline).enumerated().flatMap {
      lineIndex, line -> [ScheduleTextObservation] in
      let cells =
        String(line).contains("|")
        ? line.split(separator: "|", omittingEmptySubsequences: false)
        : line.split(separator: "\t", omittingEmptySubsequences: false)
      let values = cells.count > 1 ? cells.map(String.init) : [String(line)]
      return values.enumerated().map { cellIndex, value in
        ScheduleTextObservation(
          text: value.trimmingCharacters(in: .whitespaces), line: lineIndex + 1,
          x: Double(cellIndex), y: Double(lineIndex),
          columnIndex: values.count > 1 ? cellIndex : nil)
      }
    }
    return parse(observations: observations)
  }

  public static func parse(observations: [ScheduleTextObservation]) -> ScheduleParseResult {
    let grouped: [String: [ScheduleTextObservation]] = Dictionary(grouping: observations) {
      observation in
      let verticalPosition = observation.y.map { Int($0 * 100) } ?? observation.line
      return "\(observation.page):\(verticalPosition)"
    }
    var ordered: [[ScheduleTextObservation]] = grouped.values.map { cells in
      cells.sorted { lhs, rhs in position(lhs) < position(rhs) }
    }
    ordered.sort { lhs, rhs in
      let left = lhs.first
      let right = rhs.first
      let leftPage = left?.page ?? 0
      let rightPage = right?.page ?? 0
      if leftPage != rightPage { return leftPage < rightPage }
      let leftY = left?.y ?? Double(left?.line ?? 0)
      let rightY = right?.y ?? Double(right?.line ?? 0)
      return leftY < rightY
    }
    var header: [String: Double] = [:]
    var rows: [ScheduleReviewRow] = []
    for cells in ordered {
      let labels = cells.map { canonicalHeader($0.text) }
      if labels.compactMap({ $0 }).count >= 2 {
        header = [:]
        for (index, label) in labels.enumerated() where header[label ?? ""] == nil {
          if let label { header[label] = position(cells[index]) }
        }
        continue
      }
      let values: [String] = cells.map { $0.text }
      let mapped = map(cells, header: header)
      let code = mapped["code"] ?? values.first(where: isCourseCode) ?? ""
      let days = mapped["days"] ?? values.first(where: looksLikeDays) ?? ""
      let time = mapped["time"] ?? values.first(where: looksLikeTime) ?? ""
      let continuation = code.isEmpty && (!days.isEmpty || !time.isEmpty) && !rows.isEmpty
      if continuation {
        let subjectID = rows[rows.count - 1].subject.id
        rows[rows.count - 1].meetings.append(
          makeMeeting(
            days: days, time: time, subjectID: subjectID, location: mapped["location"] ?? ""))
        continue
      }
      let name = mapped["name"] ?? ""
      guard !code.isEmpty || !name.isEmpty else { continue }
      var uncertainty: [String] = []
      if header.isEmpty { uncertainty.append("Table headers were not recognized.") }
      if days.isEmpty && !time.localizedCaseInsensitiveContains("TBA") {
        uncertainty.append("Meeting days are missing.")
      }
      if time.isEmpty && !days.localizedCaseInsensitiveContains("TBA") {
        uncertainty.append("Meeting time is missing.")
      }
      let subject = ScheduleSubject(
        code: code, name: name, section: mapped["section"] ?? "",
        instructor: mapped["instructor"] ?? "")
      let meeting = makeMeeting(
        days: days, time: time, subjectID: subject.id, location: mapped["location"] ?? "")
      if !meeting.isTBA && (meeting.startTime == nil || meeting.endTime == nil) {
        uncertainty.append("Meeting time needs correction.")
      }
      if !meeting.isTBA && meeting.weekdays.isEmpty {
        uncertainty.append("Meeting days need correction.")
      }
      if let start = meeting.startTime, let end = meeting.endTime, end <= start {
        uncertainty.append("Confirm the end time or mark this meeting as overnight.")
      }
      if cells.contains(where: { ($0.confidence ?? 1) < 0.8 }) {
        uncertainty.append("Some source text had low recognition confidence.")
      }
      rows.append(
        ScheduleReviewRow(
          rawCode: code, rawName: name, rawSection: subject.section,
          rawInstructor: subject.instructor, rawWeekdays: days, rawTime: time,
          rawLocation: meeting.location, uncertainty: uncertainty,
          issues: uncertainty.map { .init(severity: .warning, message: $0) },
          sourceSpan: .init(
            page: cells.first?.page ?? 0, line: cells.first?.line ?? 0,
            length: values.joined(separator: " ").count), subject: subject, meetings: [meeting]))
    }
    return ScheduleParseResult(rows: rows, observations: observations)
  }

  private static func map(_ cells: [ScheduleTextObservation], header: [String: Double]) -> [String:
    String]
  {
    Dictionary(
      uniqueKeysWithValues: header.compactMap { key, x in
        guard let nearest = cells.min(by: { abs(position($0) - x) < abs(position($1) - x) }),
          abs(position(nearest) - x) < 0.35
        else { return nil }
        return (key, nearest.text)
      })
  }
  private static func position(_ observation: ScheduleTextObservation) -> Double {
    observation.columnIndex.map(Double.init) ?? observation.x ?? 0
  }
  private static func canonicalHeader(_ value: String) -> String? {
    let v = value.lowercased().trimmingCharacters(in: .whitespaces)
    if v.contains("course name") || v.contains("description") || v == "subject" { return "name" }
    if v.contains("subject code") || v.contains("course code") || v == "code" || v == "course" {
      return "code"
    }
    if v.contains("day") { return "days" }
    if v.contains("time") { return "time" }
    if v.contains("room") || v.contains("location") { return "location" }
    if v.contains("instructor") || v.contains("professor") { return "instructor" }
    if v.contains("section") { return "section" }
    return nil
  }
  private static func isCourseCode(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z]{2,}[- ]?\d{2,}[A-Za-z]?$"#, options: .regularExpression) != nil
  }
  private static func looksLikeDays(_ value: String) -> Bool {
    value.range(
      of:
        #"(?i)^(M|T|W|Th|F|Sa|Su|Mon|Tue|Wed|Thu|Fri|Sat|Sun)([ /,-]*(M|T|W|Th|F|Sa|Su|Mon|Tue|Wed|Thu|Fri|Sat|Sun))*$"#,
      options: .regularExpression) != nil
  }
  private static func looksLikeTime(_ value: String) -> Bool {
    value.range(
      of: #"(?i)^\d{1,2}(:\d{2})?\s*(AM|PM)\s*[-–—]\s*\d{1,2}(:\d{2})?\s*(AM|PM)$"#,
      options: .regularExpression) != nil || value.localizedCaseInsensitiveContains("TBA")
  }
  private static func makeMeeting(days: String, time: String, subjectID: UUID, location: String)
    -> ClassMeeting
  {
    let tba =
      days.localizedCaseInsensitiveContains("TBA") || time.localizedCaseInsensitiveContains("TBA")
    let parts = time.components(separatedBy: CharacterSet(charactersIn: "-–—"))
    let times = parts.count == 2 ? (clock(parts[0]), clock(parts[1])) : (nil, nil)
    let offset = 0
    return ClassMeeting(
      subjectID: subjectID, weekdays: weekdays(days), startTime: times.0, endTime: times.1,
      location: location, isTBA: tba, overnightDayOffset: offset)
  }
  private static func clock(_ text: String) -> ScheduleClockTime? {
    let value = text.trimmingCharacters(in: .whitespaces).uppercased()
    let meridiem = value.range(
      of: #"^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)$"#, options: .regularExpression)
    let military = value.range(of: #"^(\d{2}):(\d{2})$"#, options: .regularExpression)
    guard meridiem != nil || military != nil else { return nil }
    let normalized = value.replacingOccurrences(of: "AM", with: " AM").replacingOccurrences(
      of: "PM", with: " PM")
    let parts = normalized.split(whereSeparator: { $0 == ":" || $0 == " " })
    guard let rawHour = Int(parts[0]) else { return nil }
    let minute = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
    guard (0...59).contains(minute) else { return nil }
    if meridiem != nil {
      guard (1...12).contains(rawHour), let suffix = parts.last else { return nil }
      return .init(hour: rawHour % 12 + (suffix == "PM" ? 12 : 0), minute: minute)
    }
    guard (0...23).contains(rawHour) else { return nil }
    return .init(hour: rawHour, minute: minute)
  }
  private static func weekdays(_ value: String) -> Set<ScheduleWeekday> {
    let tokenMap: [String: ScheduleWeekday] = [
      "m": .monday, "t": .tuesday, "w": .wednesday, "th": .thursday, "f": .friday, "sa": .saturday,
      "su": .sunday, "monday": .monday, "tuesday": .tuesday, "wednesday": .wednesday,
      "thursday": .thursday, "friday": .friday, "saturday": .saturday, "sunday": .sunday,
    ]
    let tokens = value.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    var result: Set<ScheduleWeekday> = []
    for token in tokens {
      if let day = tokenMap[token] {
        result.insert(day)
        continue
      }
      var index = token.startIndex
      while index < token.endIndex {
        if token[index...].hasPrefix("th") {
          result.insert(.thursday)
          index = token.index(index, offsetBy: 2)
          continue
        }
        guard let day = tokenMap[String(token[index])] else { return [] }
        result.insert(day)
        index = token.index(after: index)
      }
    }
    return result
  }
}
