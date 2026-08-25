import AppKit
import PipoAppCore
import SwiftUI
import WebKit

public enum PipoWebMenuHostMode: String, Codable, Sendable {
    case menuBar, window, showcase
}

struct PipoWebMenuStateV1: Codable, Sendable {
    let version: Int
    let revision: Int
    let phase: String
    let errorMessage: String?
    let studentName: String
    let generatedAt: String?
    let refreshDate: String?
    let selectedTab: String
    let hostMode: PipoWebMenuHostMode
    let nextUp, schedule, dueSoon, newAssignments, notifications, messages, gradeFeedback, announcements, resources: [DashboardItem]
    let courses: [Course]
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
    let onInspectorVisibilityChanged: (Bool) -> Void

    init(
        model: PipoModel,
        configuration: PipoUIConfiguration,
        hostMode: PipoWebMenuHostMode = .menuBar,
        onSignOut: @escaping () -> Void,
        onInspectorVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.configuration = configuration
        self.hostMode = hostMode
        self.onSignOut = onSignOut
        self.onInspectorVisibilityChanged = onInspectorVisibilityChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, configuration: configuration, hostMode: hostMode, onSignOut: onSignOut, onInspectorVisibilityChanged: onInspectorVisibilityChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: Self.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "pipo")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = false
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        context.coordinator.loadMenu(in: view)
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

    private static let bootstrap = """
    window.pipo = Object.freeze({
      version: 1, available: true,
      request(action, payload = {}) {
        const requestID = crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random();
        window.webkit.messageHandlers.pipo.postMessage({ version: 1, requestID, action, revision: payload.revision, payload });
        return requestID;
      }
    });
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var model: PipoModel
        private let configuration: PipoUIConfiguration
        private let hostMode: PipoWebMenuHostMode
        private let onSignOut: () -> Void
        private let onInspectorVisibilityChanged: (Bool) -> Void
        private var revision = 0
        private var ready = false
        private var isClosed = false
        private var selectedTab: String
        private var windowObserver: NSObjectProtocol?

        init(model: PipoModel, configuration: PipoUIConfiguration, hostMode: PipoWebMenuHostMode, onSignOut: @escaping () -> Void, onInspectorVisibilityChanged: @escaping (Bool) -> Void) {
            self.model = model
            self.configuration = configuration
            self.hostMode = hostMode
            self.selectedTab = hostMode == .window ? "settings" : "today"
            self.onSignOut = onSignOut
            self.onInspectorVisibilityChanged = onInspectorVisibilityChanged
        }

        static var menuResourceRoot: URL? {
            if let packaged = Bundle.main.resourceURL?
                .appendingPathComponent("Pipo_PipoUI.bundle", isDirectory: true)
                .appendingPathComponent("MenuWeb", isDirectory: true),
               FileManager.default.fileExists(atPath: packaged.appendingPathComponent("index.html").path)
            {
                return packaged
            }
            let module = Bundle.module.resourceURL?.appendingPathComponent("MenuWeb", isDirectory: true)
            return module.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) ? $0 : nil }
        }

        func loadMenu(in view: WKWebView) {
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
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
            windowObserver = nil
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pipo", let data = try? JSONSerialization.data(withJSONObject: message.body), let request = try? JSONDecoder().decode(PipoWebMenuRequestV1.self, from: data), request.version == 1, !request.requestID.isEmpty else { return }
            if request.action == "ui.ready" {
                ready = true
                pushState()
                respond(request.requestID, success: true)
                return
            }
            if let requestRevision = request.revision, requestRevision < revision {
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
                switch request.action {
                case "signOut": onSignOut()
                case "refresh": await model.refresh(force: true)
                case "refreshSection":
                    guard let section = payload["section"]?.stringValue, Self.sections.contains(section) else { throw BridgeError.invalid }
                    await model.refresh(force: true, sections: [section])
                case "selectTab":
                    guard let raw = payload["tab"]?.stringValue, let tab = PipoAppCore.PipoTab(rawValue: raw == "today" ? "dashboard" : raw) else { throw BridgeError.invalid }
                    selectedTab = tab == .dashboard ? "today" : tab.rawValue
                case "loadCourse":
                    guard let courseID = validCourseID(payload) else { throw BridgeError.invalid }
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
                        let detail = try await model.loadCourse(id: courseID)
                        guard !detail.destination.isEmpty else { throw BridgeError.unsupported }
                        configuration.openURL(try DestinationPolicy.resolve(detail.destination))
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
                case "setInspectorVisible": guard let visible = payload["visible"]?.boolValue else { throw BridgeError.invalid }; onInspectorVisibilityChanged(visible)
                default: throw BridgeError.unsupported
                }
                pushState()
                respond(request.requestID, success: true, data: responseData)
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
        private enum BridgeError: Error { case invalid, unsupported }

        func pushStateIfReady() { if ready { pushState() } }

        private func pushState() {
            guard !isClosed else { return }
            revision += 1
            let snapshot = model.snapshot
            let phase = Self.phaseDescription(model.phase)
            let settings = model.settings
            let state = PipoWebMenuStateV1(
                version: 1,
                revision: revision,
                phase: phase.name,
                errorMessage: phase.error,
                studentName: snapshot?.studentName ?? "",
                generatedAt: snapshot?.generatedAt,
                refreshDate: model.refreshDate.map(ISO8601DateFormatter().string(from:)),
                selectedTab: selectedTab,
                hostMode: hostMode,
                nextUp: snapshot?.nextUp ?? [], schedule: snapshot?.schedule ?? [], dueSoon: snapshot?.sections.dueSoon ?? [],
                newAssignments: snapshot?.sections.newAssignments ?? [], notifications: snapshot?.sections.notifications ?? [],
                messages: snapshot?.sections.messages ?? [], gradeFeedback: snapshot?.sections.gradeFeedback ?? [],
                announcements: snapshot?.announcements ?? [], resources: snapshot?.resources ?? [], courses: snapshot?.courses ?? [],
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
            dispatch(event: "pipo-state", value: state)
        }

        private func respond(_ requestID: String, success: Bool, data: JSONValue? = nil, error: String? = nil) {
            guard !isClosed else { return }
            dispatch(event: "pipo-response", value: PipoWebMenuResponseV1(version: 1, requestID: requestID, success: success, data: data, error: error))
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
