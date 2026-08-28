import AppKit
import Observation
import PipoAppCore
import SwiftUI
import WebKit

public enum PipoWebMenuHostMode: String, Codable, Sendable {
    case menuBar, window, showcase
}

struct PipoWebMenuItemV2: Codable, Sendable {
    let id, entityKey, kind, title: String
    let courseID, courseKey, courseName, instructor, timestampISO: String?
    let sourceLabel, presentationLabel: String
    let isUnread: Bool
    let destinationAvailable: Bool
    let detail: String?
    let detailStatus: String
    let submissionStatus, resourceKind, section: String?

    init(_ item: DashboardItem, cached: Bool, courseInstructor: String? = nil) {
        id = item.id; entityKey = item.entityKey; kind = item.kind; title = item.title
        courseID = item.courseID.map(String.init); courseKey = item.courseID.map { "course:\($0)" }; courseName = item.courseName.isEmpty ? nil : item.courseName
        instructor = item.instructor ?? courseInstructor
        timestampISO = item.timestamp; isUnread = item.isUnread; destinationAvailable = !item.destination.isEmpty
        sourceLabel = Self.label(item.section ?? item.kind); presentationLabel = Self.label(item.kind)
        detail = item.detail ?? item.excerpt
        detailStatus = detail != nil ? "available" : cached && ["notification", "message", "grade"].contains(item.kind) ? "redacted" : "unavailable"
        submissionStatus = item.submissionStatus; resourceKind = item.resourceKind; section = item.section
    }

    private static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}

struct PipoWebMenuCourseV2: Codable, Sendable {
    let id: String
    let name: String
    let shortName, instructor, publishedTotal: String?
    let upcomingCount: Int
    init(_ course: Course) { id = String(course.id); name = course.name; shortName = course.shortName; instructor = course.instructor; publishedTotal = course.publishedTotal; upcomingCount = course.upcomingCount }
}

struct PipoWebMenuSectionStatusV2: Codable, Sendable {
    let status: String
    let dataSource: String
}

struct PipoWebMenuStateV2: Codable, Sendable {
    let version: Int
    let revision: Int
    let phase: String
    let errorMessage: String?
    let studentName: String
    let generatedAt: String?
    let refreshDate: String?
    let selectedTab: String
    let hostMode: PipoWebMenuHostMode
    let dataSource: String
    let sectionStatuses: [String: PipoWebMenuSectionStatusV2]
    let nextUp, schedule, dueSoon, newAssignments, notifications, messages, gradeFeedback, announcements, resources: [PipoWebMenuItemV2]
    let courses: [PipoWebMenuCourseV2]
    let failures: [String]
    let supported: DashboardSectionSupport?
    let settings: Settings
    let localState: LocalState
    let secureStorage: String
    let calendarAuthorization: String
    let appVersion: String
    let updateChannel: String

    struct Settings: Codable, Sendable {
        let refreshMinutes: Int
        let notificationsEnabled, reminderDayBefore, reminderHourBefore: Bool
        let quietHoursStart, quietHoursEnd: Int
        let assignmentNotifications, announcementNotifications, messageNotifications, gradeNotifications: Bool
    }

    struct LocalState: Codable, Sendable {
        let seenIDs, snoozedIDs, pinnedCourseIDs, hiddenCourseIDs: [String]
    }
}

struct PipoWebMenuRequestV1: Codable, Sendable {
    let version: Int
    let requestID: String
    let action: String
    let revision: Int?
    let payload: [String: JSONValue]?
}

struct PipoWebMenuResponseV1: Codable, Sendable {
    let version: Int
    let requestID: String
    let success: Bool
    let data: JSONValue?
    let error: String?
    let revision: Int?
    let targetID: String?

    init(version: Int, requestID: String, success: Bool, data: JSONValue?, error: String?, revision: Int? = nil, targetID: String? = nil) {
        self.version = version; self.requestID = requestID; self.success = success; self.data = data; self.error = error; self.revision = revision; self.targetID = targetID
    }
}

enum JSONValue: Codable, Sendable {
    case string(String), bool(Bool), number(Double), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
    var intValue: Int? {
        guard case .number(let value) = self, value.rounded() == value else { return nil }
        return Int(value)
    }
}

@MainActor
struct PipoWebMenuView: NSViewRepresentable {
    let model: PipoModel
    let configuration: PipoUIConfiguration
    let hostMode: PipoWebMenuHostMode
    let onSignOut: () -> Void
    let onDismissMenu: () -> Void
    let onInspectorVisibilityChanged: (Bool) -> Void

    init(
        model: PipoModel,
        configuration: PipoUIConfiguration,
        hostMode: PipoWebMenuHostMode = .menuBar,
        onSignOut: @escaping () -> Void,
        onDismissMenu: @escaping () -> Void = {},
        onInspectorVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.configuration = configuration
        self.hostMode = hostMode
        self.onSignOut = onSignOut
        self.onDismissMenu = onDismissMenu
        self.onInspectorVisibilityChanged = onInspectorVisibilityChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, configuration: configuration, hostMode: hostMode, onSignOut: onSignOut, onDismissMenu: onDismissMenu, onInspectorVisibilityChanged: onInspectorVisibilityChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.bootstrap(hostMode: hostMode),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.add(context.coordinator, name: "pipo")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = false
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        context.coordinator.loadMenu(in: view)
        context.coordinator.observeModelChanges()
        DispatchQueue.main.async { context.coordinator.observeWindow(of: view) }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.model = model
        context.coordinator.observeWindow(of: view)
        context.coordinator.pushStateIfReady()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.close()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pipo")
        view.stopLoading()
        view.navigationDelegate = nil
    }

    static func bootstrap(hostMode: PipoWebMenuHostMode) -> String {
        """
    const root = document.documentElement;
    if (root) {
      root.dataset.hostMode = "\(hostMode.rawValue)";
      root.style.setProperty('--pipo-main-width', '\(Int(PipoMenuPanelGeometry.mainSize.width))px');
      root.style.setProperty('--pipo-main-height', '\(Int(PipoMenuPanelGeometry.mainSize.height))px');
      root.style.setProperty('--pipo-inspector-width', '\(Int(PipoMenuPanelGeometry.inspectorWidth))px');
      root.style.setProperty('--pipo-inspector-gap', '\(Int(PipoMenuPanelGeometry.inspectorGap))px');
      root.style.setProperty('--pipo-corner-radius', '\(Int(PipoMenuPanelGeometry.cornerRadius))px');
    }
    window.pipo = Object.freeze({
      version: 1, available: true,
      request(action, payload = {}) {
        const requestID = crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random();
        window.webkit.messageHandlers.pipo.postMessage({ version: 1, requestID, action, revision: payload.revision, payload });
        return requestID;
      }
    });
    """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var model: PipoModel
        private let configuration: PipoUIConfiguration
        private let hostMode: PipoWebMenuHostMode
        private let onSignOut: () -> Void
        private let onDismissMenu: () -> Void
        private let onInspectorVisibilityChanged: (Bool) -> Void
        private var revision = 0
        private var lastStateFingerprint: Data?
        private var ready = false
        private var isClosed = false
        private var initialRefreshTask: Task<Void, Never>?
        private var selectedTab: String
        private var windowObserver: NSObjectProtocol?

        init(model: PipoModel, configuration: PipoUIConfiguration, hostMode: PipoWebMenuHostMode, onSignOut: @escaping () -> Void, onDismissMenu: @escaping () -> Void, onInspectorVisibilityChanged: @escaping (Bool) -> Void) {
            self.model = model
            self.configuration = configuration
            self.hostMode = hostMode
            self.selectedTab = hostMode == .window ? "settings" : "today"
            self.onSignOut = onSignOut
            self.onDismissMenu = onDismissMenu
            self.onInspectorVisibilityChanged = onInspectorVisibilityChanged
        }

        static var menuResourceRoot: URL? {
            PipoResources.bundleURL.map {
                $0.appendingPathComponent("MenuWeb", isDirectory: true)
            }.flatMap {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) ? $0 : nil
            }
        }

        func loadMenu(in view: WKWebView) {
            // New document has a new JS runtime and revision sequence.
            ready = false
            revision = 0
            lastStateFingerprint = nil
            guard let root = Self.menuResourceRoot else {
                view.loadHTMLString("<p>Pipo menu resources are unavailable.</p>", baseURL: nil)
                return
            }
            let index = root.appendingPathComponent("index.html")
            view.loadFileURL(index, allowingReadAccessTo: root)
        }

        func observeWindow(of view: WKWebView) {
            guard hostMode == .menuBar, windowObserver == nil, let window = view.window else { return }
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self, weak view] _ in
                guard let self, let view else { return }
                Task { @MainActor in
                    self.ready = false
                    self.selectedTab = "today"
                    self.onInspectorVisibilityChanged(false)
                    self.loadMenu(in: view)
                }
            }
        }

        func close() {
            isClosed = true
            initialRefreshTask?.cancel()
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
            windowObserver = nil
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pipo", let data = try? JSONSerialization.data(withJSONObject: message.body), let request = try? JSONDecoder().decode(PipoWebMenuRequestV1.self, from: data), request.version == 1, !request.requestID.isEmpty else { return }
            if request.action == "ui.ready" {
                ready = true
                pushState()
                refreshMissingInitialSnapshot()
                respond(request.requestID, success: true)
                return
            }
            if Self.revisionSensitiveActions.contains(request.action), let requestRevision = request.revision, requestRevision < revision {
                respond(request.requestID, success: false, error: "This view changed. Try again.")
                return
            }
            Task { @MainActor [weak self] in await self?.perform(request) }
        }

        private func perform(_ request: PipoWebMenuRequestV1) async {
            guard !isClosed else { return }
            let payload = request.payload ?? [:]
            do {
                var responseData: JSONValue?
                var responseTargetID: String?
                switch request.action {
                case "signOut": onSignOut()
                case "dismissMenu": onDismissMenu()
                case "refresh": await model.refresh(force: true)
                case "refreshSection":
                    guard let section = payload["section"]?.stringValue, Self.sections.contains(section) else { throw BridgeError.invalid }
                    await model.refresh(force: true, sections: [section])
                case "selectTab":
                    guard let raw = payload["tab"]?.stringValue, let tab = PipoAppCore.PipoTab(rawValue: raw == "today" ? "dashboard" : raw) else { throw BridgeError.invalid }
                    selectedTab = tab == .dashboard ? "today" : tab.rawValue
                case "loadCourse":
                    guard let courseID = validCourseID(payload) else { throw BridgeError.invalid }
                    responseTargetID = String(courseID)
                    responseData = try Self.jsonValue(from: await model.loadCourse(id: courseID))
                case "markSeen": guard let item = validItem(payload) else { throw BridgeError.invalid }; await model.markSeen(item.id)
                case "undoSeen": guard let item = validItem(payload) else { throw BridgeError.invalid }; await model.undoSeen(item.id)
                case "snooze":
                    guard let item = validItem(payload) else { throw BridgeError.invalid }
                    let seconds = payload["seconds"]?.intValue.map { min(max($0, 300), 604_800) } ?? 3_600
                    await model.snooze(item.id, until: .now.addingTimeInterval(TimeInterval(seconds)))
                case "openDestination":
                    if let item = validItem(payload) {
                        await model.openURL(for: item)
                    } else if payload["lmsRoot"]?.boolValue == true {
                        configuration.openURL(PipoFoundation.lmsOrigin)
                    } else if let courseID = validCourseID(payload) {
                        configuration.openURL(try await model.courseDestination(id: courseID))
                    } else {
                        throw BridgeError.invalid
                    }
                case "copyDetails":
                    if let item = validItem(payload) {
                        model.copyDetails(for: item)
                    } else if let courseID = validCourseID(payload), let course = model.snapshot?.courses.first(where: { $0.id == courseID }) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString([course.name, course.shortName, course.publishedTotal].compactMap { $0 }.joined(separator: "\n"), forType: .string)
                    } else {
                        throw BridgeError.invalid
                    }
                case "addToCalendar": guard let item = validItem(payload) else { throw BridgeError.invalid }; try await model.addToCalendar(item)
                case "requestCalendarAccess": _ = try await model.requestCalendarAccess()
                case "pinCourse", "unpinCourse", "hideCourse", "restoreCourse":
                    guard let courseID = validCourseID(payload, includingHidden: request.action == "restoreCourse") else { throw BridgeError.invalid }
                    if request.action == "pinCourse" || request.action == "unpinCourse" { await model.setPinnedCourse(courseID, pinned: request.action == "pinCourse") }
                    else { await model.setHiddenCourse(courseID, hidden: request.action == "hideCourse") }
                case "updateSettings": applySettings(payload)
                case "updateChannel":
                    guard let channel = payload["channel"]?.stringValue, ["stable", "beta"].contains(channel) else { throw BridgeError.invalid }
                    UserDefaults.standard.set(channel, forKey: "pipo.updates.channel")
                    NotificationCenter.default.post(name: Notification.Name("com.jazztinn.pipo.update-channel-changed"), object: nil)
                case "clearCache": await model.clearCache()
                case "checkForUpdates": guard let action = configuration.installUpdate else { throw BridgeError.unsupported }; action()
                case "exportDiagnostics": guard let action = configuration.exportDiagnostics else { throw BridgeError.unsupported }; action()
                case "retrySecureStorage": _ = await model.retrySecureStorage()
                case "setInspectorVisible":
                    guard let visible = payload["visible"]?.boolValue else { throw BridgeError.invalid }
                    resizeMenuBarWindowForInspector(visible)
                default: throw BridgeError.unsupported
                }
                pushState()
                respond(request.requestID, success: true, data: responseData, targetID: responseTargetID)
            } catch BridgeError.unsupported {
                respond(request.requestID, success: false, error: "This action is unavailable.")
            } catch {
                respond(request.requestID, success: false, error: "Pipo could not complete that action.")
            }
        }

        private func applySettings(_ payload: [String: JSONValue]) {
            var value = model.settings
            if let setting = payload["notificationsEnabled"]?.boolValue { value.notificationsEnabled = setting }
            if let setting = payload["reminderDayBefore"]?.boolValue { value.reminderDayBefore = setting }
            if let setting = payload["reminderHourBefore"]?.boolValue { value.reminderHourBefore = setting }
            if let setting = payload["assignmentNotifications"]?.boolValue { value.assignmentNotifications = setting }
            if let setting = payload["announcementNotifications"]?.boolValue { value.announcementNotifications = setting }
            if let setting = payload["messageNotifications"]?.boolValue { value.messageNotifications = setting }
            if let setting = payload["gradeNotifications"]?.boolValue { value.gradeNotifications = setting }
            if let setting = payload["refreshMinutes"]?.intValue { value.refreshInterval = TimeInterval(min(max(setting, 5), 60) * 60) }
            if let setting = payload["quietHoursStart"]?.intValue { value.quietHoursStart = min(max(setting, 0), 23) }
            if let setting = payload["quietHoursEnd"]?.intValue { value.quietHoursEnd = min(max(setting, 0), 23) }
            model.settings = value
        }

        private func resizeMenuBarWindowForInspector(_ visible: Bool) {
            onInspectorVisibilityChanged(visible)
        }

        private func validItem(_ payload: [String: JSONValue]) -> DashboardItem? {
            guard let itemID = payload["itemID"]?.stringValue else { return nil }
            return allItems.first { $0.id == itemID }
        }

        private func validCourseID(_ payload: [String: JSONValue], includingHidden: Bool = false) -> Int? {
            let courseID = payload["courseID"]?.intValue ?? payload["courseID"]?.stringValue.flatMap(Int.init)
            guard let courseID else { return nil }
            if model.snapshot?.courses.contains(where: { $0.id == courseID }) == true { return courseID }
            return includingHidden && model.localState.hiddenCourseIDs.contains(courseID) ? courseID : nil
        }

        private var allItems: [DashboardItem] {
            guard let snapshot = model.snapshot else { return [] }
            return snapshot.sections.dueSoon + snapshot.sections.newAssignments + snapshot.sections.notifications + snapshot.sections.messages + snapshot.sections.gradeFeedback + snapshot.nextUp + snapshot.schedule + snapshot.announcements + snapshot.resources
        }

        private static let sections: Set<String> = ["due_soon", "notifications", "assignments", "messages", "grades", "schedule", "announcements", "resources"]
        private static let revisionSensitiveActions: Set<String> = ["loadCourse", "markSeen", "undoSeen", "snooze", "openDestination", "copyDetails", "addToCalendar", "pinCourse", "unpinCourse", "hideCourse", "restoreCourse"]
        private enum BridgeError: Error { case invalid, unsupported }

        func pushStateIfReady() { if ready { pushState() } }

        func observeModelChanges() {
            guard !isClosed else { return }
            withObservationTracking {
                _ = model.phase
                _ = model.snapshot
                _ = model.refreshDate
                _ = model.settings
                _ = model.localState
                _ = model.secureStorageStatus
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self, !self.isClosed else { return }
                    self.observeModelChanges()
                    self.pushStateIfReady()
                }
            }
        }

        private func refreshMissingInitialSnapshot() {
            guard initialRefreshTask == nil, model.snapshot == nil, case .offline = model.phase else { return }
            initialRefreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.model.refresh(force: true)
                self.initialRefreshTask = nil
                self.pushStateIfReady()
            }
        }

        private func pushState() {
            guard !isClosed else { return }
            let fingerprintState = makeState(revision: 0)
            let fingerprintEncoder = JSONEncoder(); fingerprintEncoder.outputFormatting = .sortedKeys
            guard let fingerprint = try? fingerprintEncoder.encode(fingerprintState), fingerprint != lastStateFingerprint else { return }
            lastStateFingerprint = fingerprint
            revision += 1
            dispatch(event: "pipo-state", value: makeState(revision: revision))
        }

        private func makeState(revision: Int) -> PipoWebMenuStateV2 {
            let snapshot = model.snapshot
            let modelPhase = Self.phaseDescription(model.phase)
            let phase = snapshot == nil && modelPhase.name == "offline"
                ? (name: "loading", error: nil)
                : modelPhase
            let settings = model.settings
            let cached = snapshot != nil && phase.name == "offline"
            let source = cached ? "offlineCache" : "live"
            let courses = snapshot?.courses ?? []
            let instructorsByID = courses.reduce(into: [Int: String]()) { result, course in
                if let instructor = course.instructor { result[course.id] = instructor }
            }
            let instructorsByName = courses.reduce(into: [String: String]()) { result, course in
                if let instructor = course.instructor {
                    result[course.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = instructor
                }
            }
            let item: (DashboardItem) -> PipoWebMenuItemV2 = { dashboardItem in
                let nameKey = dashboardItem.courseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let courseInstructor = dashboardItem.courseID.flatMap { instructorsByID[$0] } ?? instructorsByName[nameKey]
                return PipoWebMenuItemV2(dashboardItem, cached: cached, courseInstructor: courseInstructor)
            }
            let statuses = Self.sectionStatuses(snapshot: snapshot, phase: phase.name, source: source)
            return PipoWebMenuStateV2(
                version: 2,
                revision: revision,
                phase: phase.name,
                errorMessage: phase.error,
                studentName: snapshot?.studentName ?? "",
                generatedAt: snapshot?.generatedAt,
                refreshDate: model.refreshDate.map(ISO8601DateFormatter().string(from:)),
                selectedTab: selectedTab,
                hostMode: hostMode,
                dataSource: source, sectionStatuses: statuses,
                nextUp: (snapshot?.nextUp ?? []).map(item), schedule: (snapshot?.schedule ?? []).map(item), dueSoon: (snapshot?.sections.dueSoon ?? []).map(item),
                newAssignments: (snapshot?.sections.newAssignments ?? []).map(item), notifications: (snapshot?.sections.notifications ?? []).map(item),
                messages: (snapshot?.sections.messages ?? []).map(item), gradeFeedback: (snapshot?.sections.gradeFeedback ?? []).map(item),
                announcements: (snapshot?.announcements ?? []).map(item), resources: (snapshot?.resources ?? []).map(item), courses: courses.map(PipoWebMenuCourseV2.init),
                failures: snapshot?.failures ?? [], supported: snapshot?.supported,
                settings: .init(
                    refreshMinutes: Int(settings.refreshInterval / 60), notificationsEnabled: settings.notificationsEnabled,
                    reminderDayBefore: settings.reminderDayBefore, reminderHourBefore: settings.reminderHourBefore,
                    quietHoursStart: settings.quietHoursStart, quietHoursEnd: settings.quietHoursEnd,
                    assignmentNotifications: settings.assignmentNotifications, announcementNotifications: settings.announcementNotifications,
                    messageNotifications: settings.messageNotifications, gradeNotifications: settings.gradeNotifications
                ),
                localState: .init(
                    seenIDs: model.localState.seenIDs.sorted(), snoozedIDs: model.localState.snoozedUntil.filter { $0.value > .now }.keys.sorted(),
                    pinnedCourseIDs: model.localState.pinnedCourseIDs.sorted().map(String.init), hiddenCourseIDs: model.localState.hiddenCourseIDs.sorted().map(String.init)
                ),
                secureStorage: String(describing: model.secureStorageStatus), calendarAuthorization: model.calendarAuthorizationDescription,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
                updateChannel: UserDefaults.standard.string(forKey: "pipo.updates.channel") ?? "stable"
            )
        }

        private static func sectionStatuses(snapshot: DashboardSnapshot?, phase: String, source: String) -> [String: PipoWebMenuSectionStatusV2] {
            let loading = snapshot == nil && ["loading", "authenticating"].contains(phase)
            let failed = snapshot == nil && phase == "failed"
            let values: [(String, Bool, Int)] = [
                ("nextUp", true, snapshot?.nextUp.count ?? 0), ("schedule", snapshot?.supported.schedule ?? true, snapshot?.schedule.count ?? 0),
                ("dueSoon", snapshot?.supported.dueSoon ?? true, snapshot?.sections.dueSoon.count ?? 0), ("newAssignments", snapshot?.supported.assignments ?? true, snapshot?.sections.newAssignments.count ?? 0),
                ("notifications", snapshot?.supported.notifications ?? true, snapshot?.sections.notifications.count ?? 0), ("messages", snapshot?.supported.messages ?? true, snapshot?.sections.messages.count ?? 0),
                ("gradeFeedback", snapshot?.supported.grades ?? true, snapshot?.sections.gradeFeedback.count ?? 0), ("announcements", snapshot?.supported.announcements ?? true, snapshot?.announcements.count ?? 0),
                ("resources", snapshot?.supported.resources ?? true, snapshot?.resources.count ?? 0), ("courses", true, snapshot?.courses.count ?? 0)
            ]
            return Dictionary(uniqueKeysWithValues: values.map { key, supported, count in
                let resultKeys: [String: [String]] = ["nextUp": ["due_soon", "assignments", "schedule"], "dueSoon": ["due_soon"], "newAssignments": ["assignments"], "gradeFeedback": ["grades"]]
                let results = (resultKeys[key] ?? [key]).compactMap { snapshot?.result(for: $0).status }
                let resultStatus: String? = results.contains(.failed) ? "failed" : results.contains(.partial) ? "partial" : results.allSatisfy({ $0 == .unsupported }) && !results.isEmpty ? "unsupported" : nil
                let status = !supported ? "unsupported" : loading ? "loading" : failed ? "failed" : resultStatus == "failed" && count > 0 ? "partial" : resultStatus ?? (count == 0 ? "empty" : "ready")
                return (key, PipoWebMenuSectionStatusV2(status: status, dataSource: source))
            })
        }

        private func respond(_ requestID: String, success: Bool, data: JSONValue? = nil, error: String? = nil, targetID: String? = nil) {
            guard !isClosed else { return }
            dispatch(event: "pipo-response", value: PipoWebMenuResponseV1(version: 1, requestID: requestID, success: success, data: data, error: error, revision: revision, targetID: targetID))
        }

        private func dispatch<Value: Encodable>(event: String, value: Value) {
            guard let view = webView, let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("window.dispatchEvent(new CustomEvent('\(event)', { detail: \(json) }));")
        }

        private static func phaseDescription(_ phase: PipoPhase) -> (name: String, error: String?) {
            switch phase {
            case .signedOut: ("signedOut", nil)
            case .authenticating: ("authenticating", nil)
            case .loading: ("loading", nil)
            case .ready: ("ready", nil)
            case .offline: ("offline", nil)
            case .failed(let message): ("failed", message)
            }
        }

        private static func jsonValue<Value: Encodable>(from value: Value) throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        }

        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            decisionHandler(url?.isFileURL == true || url?.scheme == "about" ? .allow : .cancel)
        }
    }
}
