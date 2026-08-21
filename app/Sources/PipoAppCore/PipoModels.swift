import Foundation

public enum PipoTab: String, CaseIterable, Codable, Sendable {
    case dashboard
    case courses
    case settings
}

public enum PipoPhase: Equatable, Sendable {
    case signedOut
    case authenticating
    case loading
    case ready
    case offline
    case failed(String)
}

public struct PipoSettings: Equatable, Sendable {
    public var refreshInterval: TimeInterval = 15 * 60
    public var notificationsEnabled: Bool = true
    public var reminderDayBefore: Bool = true
    public var reminderHourBefore: Bool = true
    public var quietHoursStart: Int = 22
    public var quietHoursEnd: Int = 7

    public init(refreshInterval: TimeInterval = 15 * 60, notificationsEnabled: Bool = true, reminderDayBefore: Bool = true, reminderHourBefore: Bool = true, quietHoursStart: Int = 22, quietHoursEnd: Int = 7) {
        self.refreshInterval = refreshInterval
        self.notificationsEnabled = notificationsEnabled
        self.reminderDayBefore = reminderDayBefore
        self.reminderHourBefore = reminderHourBefore
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let generatedAt: String
    public let siteName: String
    public let studentName: String
    public let sections: DashboardSections
    public let supported: DashboardSectionSupport
    public let assignmentIDs: [String]
    public let courses: [Course]
    public let failures: [String]
    public let nextUp: [DashboardItem]
    public let schedule: [DashboardItem]
    public let announcements: [DashboardItem]
    public let resources: [DashboardItem]
    public let sectionTimestamps: [String: String]

    public init(version: Int = 2, generatedAt: String, siteName: String, studentName: String, sections: DashboardSections, supported: DashboardSectionSupport = .all, assignmentIDs: [String] = [], courses: [Course], failures: [String] = [], nextUp: [DashboardItem] = [], schedule: [DashboardItem] = [], announcements: [DashboardItem] = [], resources: [DashboardItem] = [], sectionTimestamps: [String: String] = [:]) {
        self.version = version
        self.generatedAt = generatedAt
        self.siteName = siteName
        self.studentName = studentName
        self.sections = sections.suppressingDueSoonDuplicates()
        self.supported = supported
        self.assignmentIDs = assignmentIDs
        self.courses = courses
        self.failures = failures
        self.nextUp = nextUp
        self.schedule = schedule
        self.announcements = announcements
        self.resources = resources
        self.sectionTimestamps = sectionTimestamps
    }

    public func privacyProjected() -> DashboardSnapshot {
        DashboardSnapshot(version: version, generatedAt: generatedAt, siteName: siteName, studentName: studentName, sections: sections.privacyProjected(), supported: supported, assignmentIDs: assignmentIDs, courses: courses, failures: failures, nextUp: nextUp, schedule: schedule, announcements: announcements, resources: resources, sectionTimestamps: sectionTimestamps)
    }

    public func presentingNewAssignments(since previousIDs: Set<String>?) -> DashboardSnapshot {
        let visible = previousIDs.map { previous in
            sections.newAssignments.filter { !previous.contains($0.id) }
        } ?? []
        return DashboardSnapshot(
            version: version,
            generatedAt: generatedAt,
            siteName: siteName,
            studentName: studentName,
            sections: DashboardSections(
                dueSoon: sections.dueSoon,
                notifications: sections.notifications,
                newAssignments: visible,
                messages: sections.messages,
                gradeFeedback: sections.gradeFeedback
            ),
            supported: supported,
            assignmentIDs: assignmentIDs,
            courses: courses,
            failures: failures,
            nextUp: nextUp,
            schedule: schedule,
            announcements: announcements,
            resources: resources,
            sectionTimestamps: sectionTimestamps
        )
    }

    enum CodingKeys: String, CodingKey { case version, generatedAt = "generated_at", siteName = "site_name", studentName = "student_name", sections, supported, assignmentIDs = "assignment_ids", courses, failures, nextUp = "next_up", schedule, announcements, resources, sectionTimestamps = "section_timestamps" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        siteName = try container.decode(String.self, forKey: .siteName)
        studentName = try container.decodeIfPresent(String.self, forKey: .studentName) ?? ""
        sections = try container.decode(DashboardSections.self, forKey: .sections).suppressingDueSoonDuplicates()
        supported = try container.decodeIfPresent(DashboardSectionSupport.self, forKey: .supported) ?? .all
        assignmentIDs = try container.decodeIfPresent([String].self, forKey: .assignmentIDs) ?? []
        courses = try container.decodeIfPresent([Course].self, forKey: .courses) ?? []
        failures = try container.decodeIfPresent([String].self, forKey: .failures) ?? []
        nextUp = try container.decodeIfPresent([DashboardItem].self, forKey: .nextUp) ?? []
        schedule = try container.decodeIfPresent([DashboardItem].self, forKey: .schedule) ?? []
        announcements = try container.decodeIfPresent([DashboardItem].self, forKey: .announcements) ?? []
        resources = try container.decodeIfPresent([DashboardItem].self, forKey: .resources) ?? []
        sectionTimestamps = try container.decodeIfPresent([String: String].self, forKey: .sectionTimestamps) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(siteName, forKey: .siteName)
        try container.encode(studentName, forKey: .studentName)
        try container.encode(sections, forKey: .sections)
        try container.encode(supported, forKey: .supported)
        try container.encode(assignmentIDs, forKey: .assignmentIDs)
        try container.encode(courses, forKey: .courses)
        try container.encode(failures, forKey: .failures)
        try container.encode(nextUp, forKey: .nextUp)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(announcements, forKey: .announcements)
        try container.encode(resources, forKey: .resources)
        try container.encode(sectionTimestamps, forKey: .sectionTimestamps)
    }
}

public struct DashboardSectionSupport: Codable, Equatable, Sendable {
    public let dueSoon: Bool
    public let notifications: Bool
    public let assignments: Bool
    public let messages: Bool
    public let grades: Bool
    public let submissionStatus: Bool
    public let announcements: Bool
    public let resources: Bool
    public let schedule: Bool

    public static let all = DashboardSectionSupport()

    public init(dueSoon: Bool = true, notifications: Bool = true, assignments: Bool = true, messages: Bool = true, grades: Bool = true, submissionStatus: Bool = true, announcements: Bool = true, resources: Bool = true, schedule: Bool = true) {
        self.dueSoon = dueSoon
        self.notifications = notifications
        self.assignments = assignments
        self.messages = messages
        self.grades = grades
        self.submissionStatus = submissionStatus
        self.announcements = announcements
        self.resources = resources
        self.schedule = schedule
    }

    enum CodingKeys: String, CodingKey {
        case dueSoon = "due_soon", notifications, assignments, messages, grades, submissionStatus = "submission_status", announcements, resources, schedule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dueSoon = try container.decodeIfPresent(Bool.self, forKey: .dueSoon) ?? true
        notifications = try container.decodeIfPresent(Bool.self, forKey: .notifications) ?? true
        assignments = try container.decodeIfPresent(Bool.self, forKey: .assignments) ?? true
        messages = try container.decodeIfPresent(Bool.self, forKey: .messages) ?? true
        grades = try container.decodeIfPresent(Bool.self, forKey: .grades) ?? true
        submissionStatus = try container.decodeIfPresent(Bool.self, forKey: .submissionStatus) ?? false
        announcements = try container.decodeIfPresent(Bool.self, forKey: .announcements) ?? false
        resources = try container.decodeIfPresent(Bool.self, forKey: .resources) ?? false
        schedule = try container.decodeIfPresent(Bool.self, forKey: .schedule) ?? false
    }
}

public struct DashboardSections: Codable, Equatable, Sendable {
    public let dueSoon: [DashboardItem]
    public let notifications: [DashboardItem]
    public let newAssignments: [DashboardItem]
    public let messages: [DashboardItem]
    public let gradeFeedback: [DashboardItem]

    public init(dueSoon: [DashboardItem] = [], notifications: [DashboardItem] = [], newAssignments: [DashboardItem] = [], messages: [DashboardItem] = [], gradeFeedback: [DashboardItem] = []) {
        self.dueSoon = dueSoon
        self.notifications = notifications
        self.newAssignments = newAssignments
        self.messages = messages
        self.gradeFeedback = gradeFeedback
    }

    public func suppressingDueSoonDuplicates() -> DashboardSections {
        let dueIdentifiers = Set(dueSoon.map(duplicateIdentifier))
        return DashboardSections(dueSoon: dueSoon, notifications: notifications, newAssignments: newAssignments.filter { !dueIdentifiers.contains(duplicateIdentifier($0)) }, messages: messages, gradeFeedback: gradeFeedback)
    }

    public func privacyProjected() -> DashboardSections {
        DashboardSections(
            dueSoon: dueSoon,
            notifications: notifications.map(privacyItem),
            newAssignments: newAssignments,
            messages: messages.map(privacyItem),
            gradeFeedback: gradeFeedback.map(privacyItem)
        )
    }

    private func duplicateIdentifier(_ item: DashboardItem) -> String {
        item.destination.isEmpty ? "id:\(item.id)" : "destination:\(item.destination)"
    }

    private func privacyItem(_ item: DashboardItem) -> DashboardItem {
        DashboardItem(id: item.id, kind: item.kind, title: item.title, courseID: item.courseID, courseName: item.courseName, timestamp: item.timestamp, isUnread: item.isUnread, destination: item.destination)
    }

    enum CodingKeys: String, CodingKey { case dueSoon = "due_soon", notifications, newAssignments = "new_assignments", messages, gradeFeedback = "grade_feedback" }
}

public struct DashboardItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let courseID: Int?
    public let courseName: String
    public let timestamp: String?
    public let isUnread: Bool
    public let destination: String
    public let detail: String?
    public let excerpt: String?
    public let submissionStatus: String?
    public let resourceKind: String?
    public let section: String?

    public init(id: String, kind: String, title: String, courseID: Int? = nil, courseName: String, timestamp: String? = nil, isUnread: Bool = false, destination: String = "", detail: String? = nil, excerpt: String? = nil, submissionStatus: String? = nil, resourceKind: String? = nil, section: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.courseID = courseID
        self.courseName = courseName
        self.timestamp = timestamp
        self.isUnread = isUnread
        self.destination = destination
        self.detail = detail
        self.excerpt = excerpt
        self.submissionStatus = submissionStatus
        self.resourceKind = resourceKind
        self.section = section
    }

    enum CodingKeys: String, CodingKey { case id, kind, title, courseID = "course_id", courseName = "course_name", timestamp, isUnread = "is_unread", destination, detail, message, feedback, excerpt, submissionStatus = "submission_status", resourceKind = "resource_kind", section }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .id) { id = string } else if let number = try? container.decode(Int.self, forKey: .id) { id = String(number) } else { id = UUID().uuidString }
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "item"
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "LMS item"
        courseID = try container.decodeIfPresent(Int.self, forKey: .courseID)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? "Course"
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        isUnread = try container.decodeIfPresent(Bool.self, forKey: .isUnread) ?? false
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? container.decodeIfPresent(String.self, forKey: .message) ?? container.decodeIfPresent(String.self, forKey: .feedback)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        submissionStatus = try container.decodeIfPresent(String.self, forKey: .submissionStatus)
        resourceKind = try container.decodeIfPresent(String.self, forKey: .resourceKind)
        section = try container.decodeIfPresent(String.self, forKey: .section)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(courseID, forKey: .courseID)
        try container.encode(courseName, forKey: .courseName)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(isUnread, forKey: .isUnread)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encodeIfPresent(submissionStatus, forKey: .submissionStatus)
        try container.encodeIfPresent(resourceKind, forKey: .resourceKind)
        try container.encodeIfPresent(section, forKey: .section)
    }
}

public struct Course: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let shortName: String?
    public let publishedTotal: String?
    public let upcomingCount: Int

    public init(id: Int, name: String, shortName: String? = nil, publishedTotal: String? = nil, upcomingCount: Int = 0) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.publishedTotal = publishedTotal
        self.upcomingCount = upcomingCount
    }

    enum CodingKeys: String, CodingKey { case id, name, shortName = "short_name", publishedTotal = "published_total", upcomingCount = "upcoming_count" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Course"
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
        publishedTotal = try container.decodeIfPresent(String.self, forKey: .publishedTotal)
        upcomingCount = try container.decodeIfPresent(Int.self, forKey: .upcomingCount) ?? 0
    }
}

public struct CourseDetail: Codable, Equatable, Sendable {
    public let version: Int
    public let course: Course
    public let assignments: [DashboardItem]
    public let grades: [CourseGradeItem]
    public let supported: CourseSectionSupport
    public let destination: String
    public let failures: [String]
    public let announcements: [DashboardItem]
    public let resources: [DashboardItem]

    enum CodingKeys: String, CodingKey { case version, course, assignments, grades, supported, destination, failures, announcements, resources }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        course = try container.decode(Course.self, forKey: .course)
        assignments = try container.decodeIfPresent([DashboardItem].self, forKey: .assignments) ?? []
        grades = try container.decodeIfPresent([CourseGradeItem].self, forKey: .grades) ?? []
        supported = try container.decodeIfPresent(CourseSectionSupport.self, forKey: .supported) ?? CourseSectionSupport()
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
        failures = try container.decodeIfPresent([String].self, forKey: .failures) ?? []
        announcements = try container.decodeIfPresent([DashboardItem].self, forKey: .announcements) ?? []
        resources = try container.decodeIfPresent([DashboardItem].self, forKey: .resources) ?? []
    }
}

public struct CourseSectionSupport: Codable, Equatable, Sendable {
    public let assignments: Bool
    public let grades: Bool
    public let submissionStatus: Bool
    public let announcements: Bool
    public let resources: Bool

    public init(assignments: Bool = true, grades: Bool = true, submissionStatus: Bool = false, announcements: Bool = false, resources: Bool = false) {
        self.assignments = assignments
        self.grades = grades
        self.submissionStatus = submissionStatus
        self.announcements = announcements
        self.resources = resources
    }

    enum CodingKeys: String, CodingKey { case assignments, grades, submissionStatus = "submission_status", announcements, resources }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try container.decodeIfPresent(Bool.self, forKey: .assignments) ?? true
        grades = try container.decodeIfPresent(Bool.self, forKey: .grades) ?? true
        submissionStatus = try container.decodeIfPresent(Bool.self, forKey: .submissionStatus) ?? false
        announcements = try container.decodeIfPresent(Bool.self, forKey: .announcements) ?? false
        resources = try container.decodeIfPresent(Bool.self, forKey: .resources) ?? false
    }
}

public struct CourseGradeItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let publishedGrade: String?
    public let feedback: String?
    public let timestamp: String?
    public let destination: String

    enum CodingKeys: String, CodingKey {
        case id, title, publishedGrade = "published_grade", feedback, timestamp, destination
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .id) {
            id = string
        } else if let number = try? container.decode(Int.self, forKey: .id) {
            id = String(number)
        } else {
            throw PipoCoreError.invalidResponse
        }
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Published grade"
        publishedGrade = try container.decodeIfPresent(String.self, forKey: .publishedGrade)
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(publishedGrade, forKey: .publishedGrade)
        try container.encodeIfPresent(feedback, forKey: .feedback)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(destination, forKey: .destination)
    }
}

public enum DestinationPolicy {
    public static func resolve(_ destination: String) throws -> URL {
        let origin = PipoFoundation.lmsOrigin
        guard let url = URL(string: destination, relativeTo: origin)?.absoluteURL,
              url.scheme == origin.scheme,
              url.host == origin.host,
              url.port == origin.port else { throw PipoCoreError.originRejected }
        return url
    }
}

public enum PipoCoreError: LocalizedError, Equatable, Sendable {
    case sidecarUnavailable
    case invalidResponse
    case originRejected
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sidecarUnavailable: return "Pipo Core is unavailable."
        case .invalidResponse: return "Pipo Core returned an invalid response."
        case .originRejected: return "The destination is outside the LPU LMS origin."
        case .operationFailed(let message): return PipoSecrets.redact(message)
        }
    }
}

public enum PipoSecrets {
    public static func redact(_ value: String) -> String {
        var result = value
        for key in ["token", "wstoken", "password"] {
            guard let range = result.range(of: key, options: .caseInsensitive) else { continue }
            let suffix = result[range.upperBound...]
            let end = suffix.firstIndex(where: { $0 == "&" || $0 == " " || $0 == "\n" || $0 == "\"" }) ?? result.endIndex
            result.replaceSubrange(range.lowerBound..<end, with: "[REDACTED]")
        }
        return result
    }
}
