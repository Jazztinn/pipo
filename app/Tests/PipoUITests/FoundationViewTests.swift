import Foundation
import Testing
@testable import PipoUI

@Test
func newAssignmentsExcludeDueSoonDuplicates() {
    let due = PipoTaskItem(id: "assignment-1", title: "Reflection", courseName: "Self")
    let newItem = PipoTaskItem(id: "assignment-2", title: "Journal", courseName: "Self")
    let snapshot = PipoDashboardSnapshot(dueSoon: [due], newAssignments: [due, newItem])

    #expect(snapshot.uniqueNewAssignments == [newItem])
}

@Test
func emptySnapshotRecognizesAllDashboardSections() {
    #expect(PipoDashboardSnapshot().isEmpty)

    let course = PipoCourseItem(id: "course-1", name: "Humanities", shortName: "HUM")
    #expect(!PipoDashboardSnapshot(courses: [course]).isEmpty)
}

@Test
func usefulNotificationDataDoesNotContainMessageBody() {
    let notification = PipoNotificationItem(
        id: "notice-1",
        title: "New announcement",
        courseName: "Humanities"
    )

    #expect(notification.title == "New announcement")
    #expect(notification.courseName == "Humanities")
    #expect(!String(describing: notification).contains("body"))
}

@Test
@MainActor
func configurationDefaultsToOnboardingAndNoUpdateBanner() {
    let configuration = PipoUIConfiguration()

    #expect(configuration.initialPhase == .onboarding)
    #expect(configuration.initialSnapshot == nil)
    #expect(configuration.installUpdate == nil)
}

@Test
func dashboardSnapshotKeepsPublishedGradeDataAtCourseLevel() {
    let course = PipoCourseItem(id: "course-1", name: "Humanities", shortName: "HUM", publishedTotal: "1.50")
    let snapshot = PipoDashboardSnapshot(courses: [course])

    #expect(snapshot.courses.first?.publishedTotal == "1.50")
    #expect(snapshot.gradeFeedback.isEmpty)
}

@Test
func deadlineGroupsSeparateUrgentWork() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_735_689_600)
    let today = calendar.date(byAdding: .hour, value: 2, to: now)!
    let later = calendar.date(byAdding: .day, value: 3, to: now)!
    let snapshot = PipoDashboardSnapshot(
        dueSoon: [
            PipoTaskItem(id: "today", title: "Today", courseName: "Course", dueDate: today, status: .notSubmitted),
            PipoTaskItem(id: "later", title: "Later", courseName: "Course", dueDate: later, status: .submitted)
        ]
    )

    #expect(snapshot.deadlineGroups(now: now, calendar: calendar).map(\.0) == ["Today", "This week"])
    #expect(snapshot.urgentCount >= 1)
}

@Test
func v03SnapshotKeepsOptionalSectionsEmptyByDefault() {
    let snapshot = PipoDashboardSnapshot()

    #expect(snapshot.nextUp.isEmpty)
    #expect(snapshot.schedule.isEmpty)
    #expect(snapshot.announcements.isEmpty)
    #expect(snapshot.resources.isEmpty)
    #expect(snapshot.featureSupport == .all)
}

@Test
func assignmentStatusHasContractWireValues() {
    #expect(PipoAssignmentStatus(rawValue: "not_submitted") == .notSubmitted)
    #expect(PipoAssignmentStatus(rawValue: "reopened") == .reopened)
    #expect(PipoAssignmentStatus(rawValue: "future_status") == nil)
}

@Test
@MainActor
func secureStorageAdapterDefaultsToAvailable() {
    let configuration = PipoUIConfiguration()

    #expect(configuration.secureStorageStatus() == .available)
}
