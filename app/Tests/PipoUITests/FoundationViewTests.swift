import CoreGraphics
import Foundation
import Testing
@testable import PipoUI

@Test
func menuPanelGeometryKeepsMainPaneAnchoredWhenInspectorOpens() {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    let status = CGRect(x: 1200, y: 1050, width: 24, height: 24)
    let compact = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: false)
    let expanded = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: true)

    let compactMainMidX = compact.midX
    let expandedMainMidX = expanded.minX + 12 + 340 + 16 + 190
    #expect(compact.size == PipoMenuPanelGeometry.compactSize)
    #expect(expanded.size == PipoMenuPanelGeometry.expandedSize)
    #expect(compactMainMidX == expandedMainMidX)
}

@Test
func menuPanelGeometryClampsAcrossNegativeScreenCoordinates() {
    let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    let status = CGRect(x: -1438, y: 876, width: 24, height: 24)
    let frame = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: true)

    #expect(frame.size == PipoMenuPanelGeometry.compactSize)
    #expect(frame.minX == screen.minX)
    #expect(frame.minY >= screen.minY)
    #expect(frame.maxX <= screen.maxX)
    #expect(frame.maxY <= screen.maxY)
}

@Test
func menuPanelGeometryUsesOverlayInspectorOnNarrowScreens() {
    let screen = CGRect(x: 0, y: 0, width: 700, height: 800)
    let status = CGRect(x: 338, y: 776, width: 24, height: 24)
    let frame = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: true)

    #expect(!PipoMenuPanelGeometry.usesExpandedInspector(anchoredTo: status, in: screen))
    #expect(frame.size == PipoMenuPanelGeometry.compactSize)
}

@Test
func menuPanelGeometryUsesOverlayWhenInspectorCannotFitLeft() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let status = CGRect(x: 8, y: 876, width: 24, height: 24)
    let compact = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: false)
    let attemptedExpansion = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: true)

    #expect(!PipoMenuPanelGeometry.usesExpandedInspector(anchoredTo: status, in: screen))
    #expect(attemptedExpansion == compact)
}

@Test
func menuPanelGeometryClampsHeightWithoutHidingNavigation() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 600)
    let status = CGRect(x: 1000, y: 576, width: 24, height: 24)
    let frame = PipoMenuPanelGeometry.frame(anchoredTo: status, in: screen, inspectorVisible: false)

    #expect(frame.height == screen.height)
    #expect(frame.minY == screen.minY)
    #expect(frame.maxY == screen.maxY)
}

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

@Test
@MainActor
func secureStorageRecoveryRemainsExplicit() async {
    var retryCount = 0
    let configuration = PipoUIConfiguration(
        secureStorageStatus: { .denied },
        retrySecureStorageAccess: { retryCount += 1 }
    )

    #expect(configuration.secureStorageStatus() == .denied)
    #expect(retryCount == 0)

    await configuration.retrySecureStorageAccess()

    #expect(retryCount == 1)
}

@Test
@MainActor
func bundledWebMenuUsesOnlyLocalRuntimeAssets() throws {
    let url = try #require(PipoWebMenuView.Coordinator.menuResourceURL)
    let html = try String(contentsOf: url, encoding: .utf8)
    let runtimeURL = url.deletingLastPathComponent().appendingPathComponent("menu.js")
    let runtime = try String(contentsOf: runtimeURL, encoding: .utf8)

    #expect(html.contains("./menu.css"))
    #expect(html.contains("./menu.js"))
    #expect(!html.contains("https://"))
    #expect(!html.contains("http://"))
    #expect(!runtime.contains("https://"))
    #expect(!runtime.contains("http://"))
    #expect(!runtime.contains("innerHTML"))
    #expect(runtime.contains("mode === 'demo'"))
    #expect(runtime.contains("./demo-fixture.json"))
}

@Test
func bridgeRequestRequiresVersionedTypedEnvelope() throws {
    let valid = #"{"version":1,"requestID":"request-1","action":"refresh","payload":{}}"#.data(using: .utf8)!
    let request = try JSONDecoder().decode(PipoWebMenuRequestV1.self, from: valid)

    #expect(request.version == 1)
    #expect(request.requestID == "request-1")
    #expect(request.action == "refresh")

    let missingVersion = #"{"requestID":"request-2","action":"refresh"}"#.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PipoWebMenuRequestV1.self, from: missingVersion)
    }
}

@Test
func bridgeResponseKeepsRequestIdentityAndSafeError() throws {
    let response = PipoWebMenuResponseV1(
        version: 1,
        requestID: "request-3",
        success: false,
        data: nil,
        error: "This action is unavailable."
    )
    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])

    #expect(object["version"] as? Int == 1)
    #expect(object["requestID"] as? String == "request-3")
    #expect(object["success"] as? Bool == false)
    #expect(object["error"] as? String == "This action is unavailable.")
}
