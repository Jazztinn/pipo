import AppKit
import Foundation
import Network
import Observation

@MainActor
@Observable
public final class PipoModel {
    public private(set) var phase: PipoPhase = .signedOut
    public var selectedTab: PipoTab = .dashboard
    public private(set) var snapshot: DashboardSnapshot?
    public private(set) var refreshDate: Date?
    public private(set) var secureStorageStatus: PipoSecureStorageStatus
    public var settings: PipoSettings {
        didSet { Self.persist(settings: settings) }
    }
    public private(set) var authenticationError: String?
    public private(set) var localState = PipoLocalState()

    private let transport: any PipoSidecarTransport
    private let tokenStore: any PipoTokenStore
    private let cacheKeyStore: (any PipoTokenStore)?
    private let secureVault: KeychainSecureVault?
    private let refreshCoordinator: DashboardRefreshCoordinator
    private let notificationService: any PipoNotificationService
    private let urlOpener: (URL) -> Void
    private let localStateStore: EncryptedLocalStateStore?
    private let calendarService: any PipoCalendarService
    @ObservationIgnored private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private var hasRequestedNotificationAccess = false
    @ObservationIgnored private var consecutiveRefreshFailures = 0
    @ObservationIgnored private var rawSnapshot: DashboardSnapshot?
    @ObservationIgnored private var sessionToken: String?
    @ObservationIgnored private var hasLoadedStoredToken = false

    public init(transport: any PipoSidecarTransport, tokenStore: any PipoTokenStore, cacheKeyStore: (any PipoTokenStore)? = nil, secureVault: KeychainSecureVault? = nil, refreshCoordinator: DashboardRefreshCoordinator, localStateStore: EncryptedLocalStateStore? = nil, settings: PipoSettings = PipoSettings(), notificationService: any PipoNotificationService = PipoSystemNotifications(), calendarService: any PipoCalendarService = PipoEventKitCalendar(), urlOpener: @escaping (URL) -> Void = { url in NSWorkspace.shared.open(url) }) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.cacheKeyStore = cacheKeyStore
        self.secureVault = secureVault
        self.secureStorageStatus = secureVault?.status ?? .ready
        self.refreshCoordinator = refreshCoordinator
        self.localStateStore = localStateStore
        self.settings = settings
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.urlOpener = urlOpener
    }

    public static func live() -> PipoModel {
        let vault = KeychainSecureVault()
        let defaults = UserDefaults.standard
        let savedRefreshMinutes = defaults.object(forKey: "pipo.refresh.minutes") as? Double ?? 15
        let savedNotifications = defaults.object(forKey: "pipo.notifications.enabled") as? Bool ?? true
        let savedDayBefore = defaults.object(forKey: "pipo.reminders.day-before") as? Bool ?? true
        let savedHourBefore = defaults.object(forKey: "pipo.reminders.hour-before") as? Bool ?? true
        let quietStart = defaults.object(forKey: "pipo.quiet-hours.start") as? Int ?? 22
        let quietEnd = defaults.object(forKey: "pipo.quiet-hours.end") as? Int ?? 7
        let settings = PipoSettings(
            refreshInterval: min(max(savedRefreshMinutes, 5), 60) * 60,
            notificationsEnabled: savedNotifications,
            reminderDayBefore: savedDayBefore,
            reminderHourBefore: savedHourBefore,
            quietHoursStart: quietStart,
            quietHoursEnd: quietEnd,
            assignmentNotifications: defaults.object(forKey: "pipo.notifications.assignments") as? Bool ?? true,
            announcementNotifications: defaults.object(forKey: "pipo.notifications.announcements") as? Bool ?? true,
            messageNotifications: defaults.object(forKey: "pipo.notifications.messages") as? Bool ?? true,
            gradeNotifications: defaults.object(forKey: "pipo.notifications.grades") as? Bool ?? true
        )
        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Pipo/dashboard.sqlite", isDirectory: false)
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cacheKey = try? vault.cacheKey()
        let cache: any DashboardCache
        let localStateStore: EncryptedLocalStateStore?
        if let cacheKey {
            cache = (try? EncryptedDashboardCache(databaseURL: cacheURL, keyData: cacheKey)) ?? InMemoryDashboardCache()
            localStateStore = try? EncryptedLocalStateStore(databaseURL: cacheURL, keyData: cacheKey)
        } else {
            cache = InMemoryDashboardCache()
            localStateStore = nil
        }
        return PipoModel(
            transport: PipoCoreProcessTransport(),
            tokenStore: vault,
            secureVault: vault,
            refreshCoordinator: DashboardRefreshCoordinator(transport: PipoCoreProcessTransport(), cache: cache),
            localStateStore: localStateStore,
            settings: settings
        )
    }

    public func start() async {
        await restore()
        startNetworkMonitor()
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = PipoRefreshBackoff.delay(
                    failures: self.consecutiveRefreshFailures,
                    base: self.settings.refreshInterval
                )
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh(force: true)
            }
        }
    }

    public func restore() async {
        localState = (try? await localStateStore?.load()) ?? PipoLocalState()
        guard let token = storedToken() else { return }
        if let cached = try? await refreshCoordinator.loadCached() {
            rawSnapshot = cached
            snapshot = cached.applyingLocalState(localState)
            phase = .offline
        } else {
            phase = .loading
        }
        await refresh(using: token, force: false)
    }

    public func signIn(username: String, password: String) async {
        phase = .authenticating
        authenticationError = nil
        do {
            let response = try await transport.send(SidecarRequest(method: "authenticate_with_password", params: ["username": .string(username), "password": .string(password)]))
            let token = try token(from: response)
            try prepareSecureStorageForUserAction()
            try tokenStore.save(token: token)
            updateSecureStorageStatus()
            sessionToken = token
            hasLoadedStoredToken = true
            await refresh(using: token, force: true)
        } catch {
            fail(error)
        }
    }

    public func signIn(withToken token: String) async {
        phase = .authenticating
        authenticationError = nil
        do {
            _ = try await transport.send(SidecarRequest(method: "authenticate_with_token", params: ["token": .string(token)]))
            try prepareSecureStorageForUserAction()
            try tokenStore.save(token: token)
            updateSecureStorageStatus()
            sessionToken = token
            hasLoadedStoredToken = true
            await refresh(using: token, force: true)
        } catch {
            fail(error)
        }
    }

    public func refresh(force: Bool = true, sections: Set<String>? = nil) async {
        guard let token = storedToken() else { phase = .signedOut; return }
        await refresh(using: token, force: force, sections: sections)
    }

    public func openURL(for item: DashboardItem) async {
        do {
            let response = try await transport.send(SidecarRequest(method: "resolve_destination", params: ["destination": .string(item.destination)]))
            guard let result = response.result, case .object(let object) = result, case .string(let urlString)? = object["url"], let url = URL(string: urlString) else { throw PipoCoreError.invalidResponse }
            guard try DestinationPolicy.resolve(url.absoluteString) == url else { throw PipoCoreError.originRejected }
            urlOpener(url)
            await markSeen(item.id)
        } catch {
            fail(error)
        }
    }

    public func loadCourse(id: Int) async throws -> CourseDetail {
        guard let token = storedToken() else { throw PipoCoreError.operationFailed("Sign in to load this course.") }
        let response = try await transport.send(SidecarRequest(
            method: "load_course",
            params: ["token": .string(token), "course_id": .number(id)]
        ))
        guard let result = response.result else { throw PipoCoreError.invalidResponse }
        return try JSONDecoder().decode(CourseDetail.self, from: result.encodedData())
    }

    public func signOut() async {
        do {
            try tokenStore.deleteToken()
            try cacheKeyStore?.deleteToken()
            try await refreshCoordinator.clearCache()
            try await localStateStore?.delete()
        }
        catch {
            updateSecureStorageStatus()
            fail(error)
            return
        }
        snapshot = nil
        rawSnapshot = nil
        refreshDate = nil
        authenticationError = nil
        hasRequestedNotificationAccess = false
        consecutiveRefreshFailures = 0
        notificationService.clear()
        phase = .signedOut
        selectedTab = .dashboard
        localState = PipoLocalState()
        sessionToken = nil
        hasLoadedStoredToken = true
        updateSecureStorageStatus()
    }

    @discardableResult
    public func retrySecureStorage() async -> PipoSecureStorageStatus {
        guard let secureVault else {
            secureStorageStatus = .ready
            return .ready
        }
        secureStorageStatus = secureVault.retryAccess()
        guard case .ready = secureStorageStatus else { return secureStorageStatus }
        hasLoadedStoredToken = false
        if storedToken() != nil { await restore() } else { phase = .signedOut }
        return secureStorageStatus
    }

    public func markSeen(_ id: String) async {
        localState.seenIDs.insert(id)
        await persistLocalState()
        applyLocalState()
    }

    public func undoSeen(_ id: String) async {
        localState.seenIDs.remove(id)
        await persistLocalState()
        applyLocalState()
    }

    public func setPinnedCourse(_ id: Int, pinned: Bool) async {
        if pinned { localState.pinnedCourseIDs.insert(id) } else { localState.pinnedCourseIDs.remove(id) }
        await persistLocalState()
        applyLocalState()
    }

    public func setHiddenCourse(_ id: Int, hidden: Bool) async {
        if hidden { localState.hiddenCourseIDs.insert(id) } else { localState.hiddenCourseIDs.remove(id) }
        await persistLocalState()
        applyLocalState()
    }

    public func snooze(_ itemID: String, until date: Date) async {
        localState.snoozedUntil[itemID] = date
        await persistLocalState()
        applyLocalState()
        if let item = allDashboardItems.first(where: { $0.id == itemID }) {
            await notificationService.scheduleSnooze(
                id: itemID,
                title: "Pipo reminder",
                body: "\(item.courseName): \(item.title)",
                date: PipoReminderPlanner.shiftOutOfQuietHours(date, settings: settings)
            )
        }
    }

    public func diagnostics() -> PipoDiagnostics? {
        guard let snapshot else { return nil }
        return PipoDiagnostics(snapshot: snapshot)
    }

    public func clearCache() async {
        do {
            try await refreshCoordinator.clearCache()
            snapshot = nil
            rawSnapshot = nil
            refreshDate = nil
            phase = storedToken() == nil ? .signedOut : .offline
        } catch { fail(error) }
    }

    private func refresh(using token: String, force: Bool, sections: Set<String>? = nil) async {
        let previousSnapshot = snapshot
        phase = snapshot == nil ? .loading : .ready
        do {
            let refreshed = try await refreshCoordinator.refresh(token: token, force: force, settings: settings, sections: sections)
            rawSnapshot = refreshed
            snapshot = refreshed.applyingLocalState(localState)
            if await refreshCoordinator.lastResultUsedCache() {
                consecutiveRefreshFailures += 1
                phase = .offline
            } else {
                consecutiveRefreshFailures = 0
                refreshDate = Date()
                phase = .ready
                if settings.notificationsEnabled, let snapshot {
                    if !hasRequestedNotificationAccess {
                        hasRequestedNotificationAccess = true
                        await notificationService.requestAuthorization()
                    }
                    if let previousSnapshot {
                        await notificationService.deliver(
                            PipoNotificationPlanner.changes(from: previousSnapshot, to: snapshot, settings: settings)
                        )
                    }
                    await notificationService.scheduleDeadlineReminders(
                        for: snapshot.sections.dueSoon + snapshot.sections.newAssignments,
                        settings: settings
                    )
                }
            }
        } catch {
            consecutiveRefreshFailures += 1
            if snapshot != nil { phase = .offline } else { fail(error) }
        }
    }

    private func startNetworkMonitor() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.phase == .offline else { return }
                await self.refresh(force: true)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.jazztinn.pipo.network"))
        networkMonitor = monitor
    }

    private func token(from response: SidecarResponse) throws -> String {
        guard let result = response.result, case .object(let object) = result, case .string(let token)? = object["token"], !token.isEmpty else { throw PipoCoreError.invalidResponse }
        return token
    }

    private func fail(_ error: Error) {
        let message = PipoSecrets.redact(error.localizedDescription)
        authenticationError = message
        phase = snapshot == nil ? .failed(message) : .offline
    }

    private func storedToken() -> String? {
        if hasLoadedStoredToken { return sessionToken }
        hasLoadedStoredToken = true
        do {
            sessionToken = try tokenStore.token()
            updateSecureStorageStatus()
            return sessionToken
        } catch {
            updateSecureStorageStatus()
            return nil
        }
    }

    private func persistLocalState() async {
        localState.snoozedUntil = localState.snoozedUntil.filter { $0.value > .now }
        do { try await localStateStore?.save(localState) }
        catch { fail(error) }
    }

    public func copyDetails(for item: DashboardItem) {
        let destination = item.destination.isEmpty ? nil : (try? DestinationPolicy.resolve(item.destination).absoluteString)
        let text = [item.title, item.courseName, item.timestamp, destination].compactMap { $0 }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func requestCalendarAccess() async throws -> Bool {
        try await calendarService.requestAccess()
    }

    public var calendarAuthorizationDescription: String {
        switch calendarService.authorizationStatus() {
        case .fullAccess: "Full access"
        case .writeOnly: "Add events only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    public func addToCalendar(_ item: DashboardItem) async throws {
        try await calendarService.add(item)
    }

    private func applyLocalState() {
        snapshot = rawSnapshot?.applyingLocalState(localState)
    }

    private var allDashboardItems: [DashboardItem] {
        guard let rawSnapshot else { return [] }
        return rawSnapshot.sections.dueSoon
            + rawSnapshot.sections.newAssignments
            + rawSnapshot.schedule
            + rawSnapshot.announcements
            + rawSnapshot.resources
    }

    private func prepareSecureStorageForUserAction() throws {
        guard let secureVault else { return }
        switch secureVault.retryAccess() {
        case .ready:
            secureStorageStatus = .ready
        case .accessDenied:
            secureStorageStatus = .accessDenied
            throw PipoSecureStorageError.accessDenied
        case .unavailable(let message):
            secureStorageStatus = .unavailable(message)
            throw PipoSecureStorageError.unavailable(message)
        }
    }

    private func updateSecureStorageStatus() {
        secureStorageStatus = secureVault?.status ?? .ready
    }

    private static func persist(settings: PipoSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.refreshInterval / 60, forKey: "pipo.refresh.minutes")
        defaults.set(settings.notificationsEnabled, forKey: "pipo.notifications.enabled")
        defaults.set(settings.reminderDayBefore, forKey: "pipo.reminders.day-before")
        defaults.set(settings.reminderHourBefore, forKey: "pipo.reminders.hour-before")
        defaults.set(settings.quietHoursStart, forKey: "pipo.quiet-hours.start")
        defaults.set(settings.quietHoursEnd, forKey: "pipo.quiet-hours.end")
        defaults.set(settings.assignmentNotifications, forKey: "pipo.notifications.assignments")
        defaults.set(settings.announcementNotifications, forKey: "pipo.notifications.announcements")
        defaults.set(settings.messageNotifications, forKey: "pipo.notifications.messages")
        defaults.set(settings.gradeNotifications, forKey: "pipo.notifications.grades")
    }
}

enum PipoRefreshBackoff {
    static func delay(failures: Int, base: TimeInterval) -> TimeInterval {
        let base = min(max(base, 300), 3_600)
        let multiplier = pow(2.0, Double(min(max(failures, 0), 3)))
        return min(base * multiplier, 3_600)
    }
}
