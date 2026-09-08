import Foundation

public enum PipoSectionID: String, CaseIterable, Codable, Sendable {
  case dueSoon = "due_soon"
  case notifications, assignments, messages, grades, schedule, announcements, resources

  public static func refreshTargets(for presentationKey: String) -> Set<PipoSectionID>? {
    if let section = Self(rawValue: presentationKey) { return [section] }
    switch presentationKey {
    case "dueSoon": return [.dueSoon]
    case "newAssignments": return [.assignments]
    case "gradeFeedback": return [.grades]
    case "nextUp": return [.dueSoon, .assignments, .schedule, .announcements]
    default: return nil
    }
  }
}

public enum PipoActionResult: Equatable, Sendable {
  case success
  case denied(String)
  case failed(String)
  case cancelled

  public func requireSuccess() throws {
    switch self {
    case .success: return
    case .denied(let message), .failed(let message): throw PipoCoreError.operationFailed(message)
    case .cancelled: throw CancellationError()
    }
  }
}

public enum PipoSchoolClock {
  public static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
    return calendar
  }

  public static func dayInterval(containing date: Date = .now) -> DateInterval {
    calendar.dateInterval(of: .day, for: date)!
  }
}
