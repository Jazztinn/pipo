import AppKit
import CryptoKit
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
    public let scheduleController: PipoScheduleController
    public var scheduleEnabled: Bool { PipoFeatureGates.schedulePresentation }
    public var scheduleImportEnabled: Bool { PipoFeatureGates.scheduleImport }
    public private(set) var persistenceStatus: PipoPersistenceStatus = .ready
    public var settings: PipoSettings {
        didSet {
            Self.persist(settings: settings)
            if oldValue.refreshInterval != settings.refreshInterval { resetAutomaticRefreshTimer() }
            var previous = oldValue
            previous.refreshInterval = settings.refreshInterval
            if previous != settings {
                notificationTask?.cancel()
                notificationService.clear()
                reconcileNotifications()
            }
        }
    }
    public private(set) var authenticationError: String?
    public private(set) var localState = PipoLocalState()
    public private(set) var latestRefreshMetrics: PipoRefreshMetrics?
    public private(set) var sessionContext = PipoSessionContext()

    private let transport: any PipoSidecarTransport
    private let tokenStore: any PipoTokenStore
    private let cacheKeyStore: (any PipoTokenStore)?
    private let secureVault: KeychainSecureVault?
    private let persistenceManager: PipoPersistenceManager?
    private let refreshCoordinator: DashboardRefreshCoordinator
    private let notificationService: any PipoNotificationService
    private let urlOpener: (URL) -> Bool
    private let localStateStore: (any AccountScopedLocalStateStore)?
    private let sessionIdentityStore: (any PipoSessionIdentityStore)?
    private let calendarService: any PipoCalendarService
    private let lifecycleDefaults: UserDefaults
    @ObservationIgnored private var isEndingSession = false
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    @ObservationIgnored private var localWrites: [UUID: Task<Void, Error>] = [:]
    @ObservationIgnored private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var lastReconnectAt: Date?
    @ObservationIgnored private var hasRequestedNotificationAccess = false
    @ObservationIgnored private var consecutiveRefreshFailures = 0
    @ObservationIgnored private var rawSnapshot: DashboardSnapshot?
    @ObservationIgnored private var sessionToken: String?
    @ObservationIgnored private var hasLoadedStoredToken = false
    @ObservationIgnored private var courseCache: [Int: (detail: CourseDetail, loadedAt: Date)] = [:]
    @ObservationIgnored private var courseLoads: [Int: Task<CourseDetail, Error>] = [:]
    @ObservationIgnored private var courseLoadIDs: [Int: UUID] = [:]
    @ObservationIgnored private var authenticationAttemptID: UUID?
    @ObservationIgnored private let signOutTombstoneKey = "pipo.session.sign-out-cleanup-pending"

    public init(transport: any PipoSidecarTransport, tokenStore: any PipoTokenStore, cacheKeyStore: (any PipoTokenStore)? = nil, secureVault: KeychainSecureVault? = nil, refreshCoordinator: DashboardRefreshCoordinator, localStateStore: (any AccountScopedLocalStateStore)? = nil, persistenceManager: PipoPersistenceManager? = nil, scheduleController: PipoScheduleController? = nil, settings: PipoSettings = PipoSettings(), notificationService: any PipoNotificationService = PipoSystemNotifications(), calendarService: any PipoCalendarService = PipoEventKitCalendar(), lifecycleDefaults: UserDefaults = .standard, urlOpener: ((URL) -> Void)? = nil, destinationOpener: ((URL) -> Bool)? = nil) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.cacheKeyStore = cacheKeyStore
        self.secureVault = secureVault
        self.secureStorageStatus = secureVault?.status ?? .ready
        self.refreshCoordinator = refreshCoordinator
        self.localStateStore = localStateStore
        self.persistenceManager = persistenceManager
        self.scheduleController = scheduleController ?? PipoScheduleController()
        self.sessionIdentityStore = secureVault
        self.settings = settings
        self.notificationService = notificationService
        self.calendarService = calendarService
        self.lifecycleDefaults = lifecycleDefaults
        self.urlOpener = destinationOpener ?? { url in
            if let urlOpener { urlOpener(url); return true }
            return NSWorkspace.shared.open(url)
        }
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
        let persistence = PipoPersistenceManager(vault: vault, databaseURL: cacheURL)
        let sidecar = PipoCoreProcessTransport()
        return PipoModel(
            transport: sidecar,
            tokenStore: vault,
            secureVault: vault,
            refreshCoordinator: DashboardRefreshCoordinator(transport: sidecar, cache: persistence),
            localStateStore: persistence,
            persistenceManager: persistence,
            settings: settings
        )
    }

    public func start() async {
        if lifecycleDefaults.bool(forKey: signOutTombstoneKey) {
            await retrySignOutCleanup()
        } else {
            await restore()
        }
        startNetworkMonitor()
        startAutomaticRefresh()
    }

    private func startAutomaticRefresh() {
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = PipoRefreshBackoff.delay(
                    failures: self.consecutiveRefreshFailures,
                    base: self.settings.refreshInterval
                )
                try? await Task.sleep(for: .seconds(interval * Double.random(in: 1.0...1.1)))
                guard !Task.isCancelled else { return }
                if let rawSnapshot = self.rawSnapshot {
                    let sections = await self.refreshCoordinator.sectionsNeedingRefresh(in: rawSnapshot, settings: self.settings)
                    guard !sections.isEmpty else { continue }
                    await self.refresh(force: true, sections: sections)
                } else {
                    await self.refresh(force: true)
                }
            }
        }
    }

    private func resetAutomaticRefreshTimer() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        startAutomaticRefresh()
    }

    public func restore() async {
        guard !isEndingSession, let token = storedToken() else { return }
        let generation = sessionContext.generation &+ 1
        sessionContext = PipoSessionContext(accountID: sessionContext.accountID, generation: generation)
        do {
            let accountID: String
            if let stored = try sessionIdentityStore?.accountID(), !stored.isEmpty {
                accountID = PipoAccountNamespace.lpuScope(for: stored)
                if stored != accountID {
                    try await persistenceManager?.migrateAccount(from: stored, to: accountID)
                    guard sessionContext.generation == generation, !isEndingSession else { return }
                    try sessionIdentityStore?.save(accountID: accountID)
                }
            }
            else {
                let response = try await transport.send(SidecarRequest(method: "authenticate_with_token", params: ["token": .string(token)]))
                guard sessionContext.generation == generation, !isEndingSession else { return }
                accountID = try scopedAccountID(from: response)
                try sessionIdentityStore?.save(accountID: accountID)
            }
            guard sessionContext.generation == generation, !isEndingSession else { return }
            sessionContext = PipoSessionContext(accountID: accountID, generation: generation)
            let session = sessionContext
            notificationService.beginSession(accountID)
            if scheduleEnabled || scheduleImportEnabled {
                await scheduleController.activate(accountID: accountID)
                guard session == sessionContext, !isEndingSession else { return }
            }
            if let persistenceManager {
                let status = await persistenceManager.prepare()
                guard session == sessionContext, !isEndingSession else { return }
                persistenceStatus = status
            }
            let state = (try? await localStateStore?.loadLocalState(accountID: accountID)) ?? PipoLocalState()
            guard session == sessionContext, !isEndingSession else { return }
            localState = state
            if let cached = try await refreshCoordinator.loadCached(session: session) {
                guard session == sessionContext, !isEndingSession else { return }
                rawSnapshot = cached
                snapshot = cached.applyingLocalState(localState)
                refreshDate = ISO8601DateFormatter().date(from: cached.generatedAt)
                phase = .offline
                let stale = await refreshCoordinator.sectionsNeedingRefresh(in: cached, settings: settings)
                guard session == sessionContext, !isEndingSession else { return }
                if stale.isEmpty { phase = .ready; reconcileNotifications(); return }
                await refresh(using: token, force: true, sections: stale)
            } else {
                guard session == sessionContext, !isEndingSession else { return }
                phase = .loading
                await refresh(using: token, force: true)
            }
        } catch {
            guard sessionContext.generation == generation, !isEndingSession else { return }
            handleLifecycleError(error)
        }
    }

    public func signIn(username: String, password: String) async {
        guard authenticationAttemptID == nil, !isEndingSession else { return }
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        phase = .authenticating
        authenticationError = nil
        defer {
            if authenticationAttemptID == attemptID {
                authenticationAttemptID = nil
                if phase == .authenticating { phase = snapshot == nil ? .signedOut : .ready }
            }
        }
        do {
            let response = try await transport.send(SidecarRequest(method: "authenticate_with_password", params: ["username": .string(username), "password": .string(password)]))
            try Task.checkCancellation()
            guard authenticationAttemptID == attemptID else { throw CancellationError() }
            let token = try token(from: response)
            let accountID = try scopedAccountID(from: response)
            try prepareSecureStorageForUserAction()
            try persistSession(token: token, accountID: accountID)
            updateSecureStorageStatus()
            sessionToken = token
            hasLoadedStoredToken = true
            await beginSession(accountID: accountID)
            guard authenticationAttemptID == attemptID else { throw CancellationError() }
            invalidateCourseCache()
            await refresh(using: token, force: true)
        } catch {
            guard authenticationAttemptID == attemptID, !isEndingSession else { return }
            handleLifecycleError(error, authenticationContext: .schoolAccount)
        }
    }

    public func signIn(withToken token: String) async {
        guard authenticationAttemptID == nil, !isEndingSession else { return }
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        phase = .authenticating
        authenticationError = nil
        defer {
            if authenticationAttemptID == attemptID {
                authenticationAttemptID = nil
                if phase == .authenticating { phase = snapshot == nil ? .signedOut : .ready }
            }
        }
        do {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { throw PipoCoreError.authenticationRequired }
            let response = try await transport.send(SidecarRequest(method: "authenticate_with_token", params: ["token": .string(token)]))
            try Task.checkCancellation()
            guard authenticationAttemptID == attemptID else { throw CancellationError() }
            let accountID = try scopedAccountID(from: response)
            try prepareSecureStorageForUserAction()
            try persistSession(token: token, accountID: accountID)
            updateSecureStorageStatus()
            sessionToken = token
            hasLoadedStoredToken = true
            await beginSession(accountID: accountID)
            guard authenticationAttemptID == attemptID else { throw CancellationError() }
            invalidateCourseCache()
            await refresh(using: token, force: true)
        } catch {
            guard authenticationAttemptID == attemptID, !isEndingSession else { return }
            handleLifecycleError(error, authenticationContext: .accessToken)
        }
    }

    @discardableResult
    public func refresh(force: Bool = true, sections: Set<String>? = nil) async -> PipoActionResult {
        guard !isEndingSession else { return .cancelled }
        guard let token = storedToken() else { return .denied("Sign in to refresh.") }
        return await refresh(using: token, force: force, sections: sections)
    }

    @discardableResult
    public func openURL(for item: DashboardItem) async -> PipoActionResult {
        let session = sessionContext
        guard !isEndingSession, session.accountID != "anonymous" else { return .denied("Sign in to open this item.") }
        do {
            let response = try await transport.send(SidecarRequest(method: "resolve_destination", params: ["destination": .string(item.destination)]))
            guard session == sessionContext, !Task.isCancelled, !isEndingSession else { return .cancelled }
            guard let result = response.result, case .object(let object) = result, case .string(let urlString)? = object["url"], let url = URL(string: urlString) else { throw PipoCoreError.invalidResponse }
            guard try DestinationPolicy.resolve(url.absoluteString) == url else { throw PipoCoreError.originRejected }
            guard urlOpener(url) else { return .failed("macOS could not open this destination.") }
            await markSeen(item.id)
            return session == sessionContext ? .success : .cancelled
        } catch is CancellationError { return .cancelled }
        catch { return .failed(PipoSecrets.redact(error.localizedDescription)) }
    }

    public func openTrustedDestination(_ destination: String) -> PipoActionResult {
        guard sessionContext.accountID != "anonymous", !isEndingSession else { return .denied("Sign in to open the LMS.") }
        do {
            let url = try DestinationPolicy.resolve(destination)
            return urlOpener(url) ? .success : .failed("macOS could not open this destination.")
        } catch { return .denied("This destination is unavailable.") }
    }

    public func dashboardItem(id: String) -> DashboardItem? {
        guard !isEndingSession, sessionContext.accountID != "anonymous" else { return nil }
        if let item = rawSnapshot?.presentationItems.first(where: { $0.id == id }) { return item }
        return courseCache.values.flatMap { $0.detail.assignments + $0.detail.announcements + $0.detail.resources }.first { $0.id == id }
    }

    public func loadCourse(id: Int) async throws -> CourseDetail {
        if let cached = courseCache[id], Date().timeIntervalSince(cached.loadedAt) < 300 {
            return cached.detail
        }
        if let existing = courseLoads[id] { return try await existing.value }
        guard !isEndingSession, let token = storedToken() else { throw PipoCoreError.operationFailed("Sign in to load this course.") }
        let transport = transport
        let session = sessionContext
        let loadID = UUID()
        let task = Task<CourseDetail, Error> {
            let response = try await transport.send(SidecarRequest(
                method: "load_course",
                params: ["token": .string(token), "course_id": .number(id)]
            ))
            guard let result = response.result else { throw PipoCoreError.invalidResponse }
            return try JSONDecoder().decode(CourseDetail.self, from: result.encodedData())
        }
        courseLoads[id] = task
        courseLoadIDs[id] = loadID
        defer {
            if courseLoadIDs[id] == loadID {
                courseLoads[id] = nil
                courseLoadIDs[id] = nil
            }
        }
        let detail = try await task.value
        guard session == sessionContext, courseLoadIDs[id] == loadID, !Task.isCancelled else { throw CancellationError() }
        courseCache[id] = (detail, Date())
        return detail
    }

    public func courseDestination(id: Int) async throws -> URL {
        guard id > 0,
              snapshot?.courses.contains(where: { $0.id == id }) == true || courseCache[id] != nil
        else { throw PipoCoreError.operationFailed("Course destination is unavailable.") }
        return try DestinationPolicy.resolve("/course/view.php?id=\(id)")
    }

    public func signOut() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        scheduleController.deactivate()
        defer { isEndingSession = false }
        notificationTask?.cancel()
        notificationTask = nil
        notificationService.clear()
        lifecycleDefaults.set(true, forKey: signOutTombstoneKey)
        authenticationAttemptID = nil
        sessionContext = PipoSessionContext(accountID: "anonymous", generation: sessionContext.generation &+ 1)
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        await refreshCoordinator.cancelAll()
        courseLoads.values.forEach { $0.cancel() }
        courseLoads.removeAll()
        courseLoadIDs.removeAll()
        await transport.shutdown()
        snapshot = nil
        rawSnapshot = nil
        refreshDate = nil
        latestRefreshMetrics = nil
        authenticationError = nil
        hasRequestedNotificationAccess = false
        consecutiveRefreshFailures = 0
        notificationService.clear()
        phase = .signedOut
        selectedTab = .dashboard
        localState = PipoLocalState()
        courseCache.removeAll()
        sessionToken = nil
        hasLoadedStoredToken = true
        updateSecureStorageStatus()
        await retrySignOutCleanup()
        startNetworkMonitor()
        startAutomaticRefresh()
    }

    public func stop() async {
        scheduleController.deactivate()
        notificationTask?.cancel()
        notificationTask = nil
        authenticationAttemptID = nil
        sessionContext = PipoSessionContext(accountID: "anonymous", generation: sessionContext.generation &+ 1)
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        courseLoads.values.forEach { $0.cancel() }
        courseLoads.removeAll()
        courseLoadIDs.removeAll()
        await refreshCoordinator.cancelAll()
        notificationService.clear()
        await transport.shutdown()
    }

    @discardableResult
    public func retrySecureStorage() async -> PipoSecureStorageStatus {
        guard let secureVault else {
            secureStorageStatus = .ready
            return .ready
        }
        secureStorageStatus = secureVault.retryAccess()
        guard case .ready = secureStorageStatus else { return secureStorageStatus }
        if let persistenceManager { persistenceStatus = await persistenceManager.prepare() }
        hasLoadedStoredToken = false
        if storedToken() != nil { await restore() } else { phase = .signedOut }
        return secureStorageStatus
    }

    @discardableResult
    public func markSeen(_ id: String) async -> PipoActionResult {
        guard sessionContext.accountID != "anonymous" else { return .denied("Sign in to update this item.") }
        guard !isEndingSession else { return .cancelled }
        localState.seenIDs.insert(id)
        let result = await persistLocalState()
        guard result != .cancelled else { return result }
        applyLocalState()
        return result
    }

    @discardableResult
    public func undoSeen(_ id: String) async -> PipoActionResult {
        guard sessionContext.accountID != "anonymous" else { return .denied("Sign in to update this item.") }
        guard !isEndingSession else { return .cancelled }
        localState.seenIDs.remove(id)
        let result = await persistLocalState()
        guard result != .cancelled else { return result }
        applyLocalState()
        return result
    }

    @discardableResult
    public func setPinnedCourse(_ id: Int, pinned: Bool) async -> PipoActionResult {
        guard sessionContext.accountID != "anonymous" else { return .denied("Sign in to update courses.") }
        guard !isEndingSession else { return .cancelled }
        if pinned { localState.pinnedCourseIDs.insert(id) } else { localState.pinnedCourseIDs.remove(id) }
        let result = await persistLocalState()
        guard result != .cancelled else { return result }
        applyLocalState()
        return result
    }

    @discardableResult
    public func setHiddenCourse(_ id: Int, hidden: Bool) async -> PipoActionResult {
        guard sessionContext.accountID != "anonymous" else { return .denied("Sign in to update courses.") }
        guard !isEndingSession else { return .cancelled }
        if hidden { localState.hiddenCourseIDs.insert(id) } else { localState.hiddenCourseIDs.remove(id) }
        let result = await persistLocalState()
        guard result != .cancelled else { return result }
        applyLocalState()
        return result
    }

    @discardableResult
    public func snooze(_ itemID: String, until date: Date) async -> PipoActionResult {
        guard sessionContext.accountID != "anonymous" else { return .denied("Sign in to snooze this item.") }
        guard !isEndingSession else { return .cancelled }
        guard settings.notificationsEnabled else { return .denied("Enable notifications to snooze this item.") }
        let session = sessionContext
        localState.snoozedUntil[itemID] = date
        let result = await persistLocalState()
        guard result != .cancelled else { return result }
        applyLocalState()
        guard result == .success else { return result }
        if session == sessionContext, !isEndingSession, let item = allDashboardItems.first(where: { $0.id == itemID }) {
            await notificationService.scheduleSnooze(
                id: itemID,
                title: "Pipo reminder",
                body: "\(item.courseName): \(item.title)",
                date: PipoReminderPlanner.shiftOutOfQuietHours(date, settings: settings)
            )
        }
        return session == sessionContext && !isEndingSession ? .success : .cancelled
    }

    public func diagnostics() -> PipoDiagnostics? {
        guard let snapshot else { return nil }
        return PipoDiagnostics(snapshot: snapshot, refreshMetrics: latestRefreshMetrics)
    }

    @discardableResult
    public func clearCache() async -> PipoActionResult {
        guard !isEndingSession else { return .cancelled }
        sessionContext = PipoSessionContext(accountID: sessionContext.accountID, generation: sessionContext.generation &+ 1)
        let session = sessionContext
        notificationTask?.cancel()
        notificationService.clear()
        do {
            try await refreshCoordinator.clearCache()
            guard session == sessionContext else { return .cancelled }
            snapshot = nil
            rawSnapshot = nil
            refreshDate = nil
            latestRefreshMetrics = nil
            phase = storedToken() == nil ? .signedOut : .offline
            invalidateCourseCache()
            return .success
        } catch {
            guard session == sessionContext, !isEndingSession else { return .cancelled }
            fail(error)
            return .failed("Saved LMS data could not be cleared.")
        }
    }

    @discardableResult
    private func refresh(using token: String, force: Bool, sections: Set<String>? = nil) async -> PipoActionResult {
        guard !isEndingSession else { return .cancelled }
        let session = sessionContext
        let previousSnapshot = snapshot
        phase = snapshot == nil ? .loading : .ready
        do {
            let outcome = try await refreshCoordinator.refreshOutcome(token: token, force: force, settings: settings, sections: sections, session: session)
            let metrics = await refreshCoordinator.metrics()
            let storageStatus = await persistenceManager?.status()
            guard session == sessionContext, !isEndingSession, !Task.isCancelled else { return .cancelled }
            latestRefreshMetrics = metrics
            if let storageStatus { persistenceStatus = storageStatus }
            rawSnapshot = outcome.snapshot
            snapshot = outcome.snapshot.applyingLocalState(localState)
            if outcome.source == .staleCache {
                consecutiveRefreshFailures += 1
                phase = .offline
                return .failed("Could not refresh. Showing saved data.")
            }
            consecutiveRefreshFailures = 0
            refreshDate = ISO8601DateFormatter().date(from: outcome.snapshot.generatedAt)
            phase = .ready
            authenticationError = nil
            reconcileNotifications(previous: previousSnapshot)
            if !outcome.preservedSections.isEmpty && outcome.source == .network {
                return .failed("Some sections could not refresh. Available data is still shown.")
            }
            return .success
        } catch {
            guard session == sessionContext, !isEndingSession, !Task.isCancelled else { return .cancelled }
            if error is CancellationError { return .cancelled }
            consecutiveRefreshFailures += 1
            handleLifecycleError(error)
            return .failed(PipoSecrets.redact(error.localizedDescription))
        }
    }

    private func reconcileNotifications(previous: DashboardSnapshot? = nil) {
        notificationTask?.cancel()
        guard settings.notificationsEnabled, let snapshot, sessionContext.accountID != "anonymous", !isEndingSession else { return }
        let session = sessionContext
        let preferences = settings
        let state = localState
        notificationTask = Task { [weak self] in
            guard let self, session == self.sessionContext, !Task.isCancelled else { return }
            if !self.hasRequestedNotificationAccess {
                self.hasRequestedNotificationAccess = true
                await self.notificationService.requestAuthorization()
            }
            guard session == self.sessionContext, !self.isEndingSession, !Task.isCancelled else { return }
            if let previous {
                await self.notificationService.deliver(PipoNotificationPlanner.changes(from: previous, to: snapshot, settings: preferences))
            }
            guard session == self.sessionContext, !self.isEndingSession, !Task.isCancelled else { return }
            let deadlines = (snapshot.sections.dueSoon + snapshot.sections.newAssignments)
                .filter { state.snoozedUntil[$0.id].map { $0 <= .now } ?? true }
            await self.notificationService.scheduleDeadlineReminders(for: deadlines, settings: preferences)
            guard session == self.sessionContext, !self.isEndingSession, !Task.isCancelled else { return }
            for (id, date) in state.snoozedUntil where date > .now {
                guard session == self.sessionContext, !Task.isCancelled else { return }
                guard let item = self.dashboardItem(id: id) else { continue }
                await self.notificationService.scheduleSnooze(id: id, title: "Pipo reminder", body: "\(item.courseName): \(item.title)", date: PipoReminderPlanner.shiftOutOfQuietHours(date, settings: preferences))
            }
        }
    }

    private func startNetworkMonitor() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconnectTask?.cancel()
                self.reconnectTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let self, !Task.isCancelled, self.phase == .offline else { return }
                    if let lastReconnectAt = self.lastReconnectAt, Date().timeIntervalSince(lastReconnectAt) < 60 { return }
                    self.lastReconnectAt = .now
                    await self.refreshAfterReconnect()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.jazztinn.pipo.network"))
        networkMonitor = monitor
    }

    private func refreshAfterReconnect() async {
        if let rawSnapshot {
            let sections = await refreshCoordinator.sectionsNeedingRefresh(in: rawSnapshot, settings: settings)
            if !sections.isEmpty { await refresh(force: true, sections: sections) }
            else { phase = .ready }
        } else {
            await refresh(force: true)
        }
    }

    private func retrySignOutCleanup() async {
        guard lifecycleDefaults.bool(forKey: signOutTombstoneKey) else { return }
        var cleanupSucceeded = true
        for task in localWrites.values { task.cancel() }
        for task in Array(localWrites.values) { _ = await task.result }
        do { try await refreshCoordinator.clearCache() } catch { cleanupSucceeded = false }
        do { try await localStateStore?.deleteAllLocalState() } catch { cleanupSucceeded = false }
        await persistenceManager?.close()
        do { try tokenStore.deleteToken() } catch { cleanupSucceeded = false }
        do { try cacheKeyStore?.deleteToken() } catch { cleanupSucceeded = false }
        if cleanupSucceeded {
            lifecycleDefaults.removeObject(forKey: signOutTombstoneKey)
        }
        updateSecureStorageStatus()
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

    private enum AuthenticationContext {
        case schoolAccount
        case accessToken
    }

    private func handleLifecycleError(_ error: Error, authenticationContext: AuthenticationContext? = nil) {
        if error is CancellationError {
            phase = snapshot == nil ? .signedOut : .ready
            return
        }
        let classified = error as? PipoCoreError ?? .operationFailed(error.localizedDescription)
        switch classified {
        case .authenticationRequired:
            scheduleController.deactivate()
            notificationTask?.cancel()
            notificationService.clear()
            sessionContext = PipoSessionContext(accountID: "anonymous", generation: sessionContext.generation &+ 1)
            rawSnapshot = nil
            snapshot = nil
            localState = PipoLocalState()
            try? tokenStore.deleteToken()
            sessionToken = nil
            hasLoadedStoredToken = true
            invalidateCourseCache()
            let message = switch authenticationContext {
            case .schoolAccount: "The LMS rejected that username or password. Check your details and try again."
            case .accessToken: "That access token is invalid or expired. Create a new token and try again."
            case nil: classified.localizedDescription
            }
            authenticationError = message
            phase = authenticationContext == nil ? .signedOut : .failed(message)
        case .networkUnavailable, .timedOut, .rateLimited, .serviceUnavailable:
            authenticationError = authenticationContext == nil ? nil : classified.localizedDescription
            phase = snapshot == nil ? .failed(classified.localizedDescription) : .offline
        case .malformedServiceResponse, .invalidResponse, .sidecarUnavailable:
            authenticationError = authenticationContext == nil ? nil : classified.localizedDescription
            phase = snapshot == nil ? .failed(classified.localizedDescription) : .offline
        default:
            fail(classified)
        }
    }

    private func storedToken() -> String? {
        if hasLoadedStoredToken { return sessionToken }
        hasLoadedStoredToken = true
        do {
            sessionToken = try tokenStore.token()?.trimmingCharacters(in: .whitespacesAndNewlines)
            if sessionToken?.isEmpty == true {
                try? tokenStore.deleteToken()
                sessionToken = nil
            }
            updateSecureStorageStatus()
            return sessionToken
        } catch {
            updateSecureStorageStatus()
            return nil
        }
    }

    private func persistLocalState() async -> PipoActionResult {
        localState.snoozedUntil = localState.snoozedUntil.filter { $0.value > .now }
        let session = sessionContext
        guard session.accountID != "anonymous", !isEndingSession else { return .cancelled }
        let state = localState
        let id = UUID()
        let store = localStateStore
        let task = Task {
            try Task.checkCancellation()
            try await store?.saveLocalState(state, accountID: session.accountID)
        }
        localWrites[id] = task
        defer { localWrites[id] = nil }
        do {
            try await task.value
            let status = await persistenceManager?.status()
            guard session == sessionContext, !isEndingSession else { return .cancelled }
            if let status {
                persistenceStatus = status
                if !status.canSave { return .failed("Saved only for this session. Secure storage is unavailable.") }
            }
            return .success
        } catch {
            guard session == sessionContext, !isEndingSession else { return .cancelled }
            guard !(error is CancellationError) else { return .cancelled }
            fail(error)
            return .failed("Saved only for this session. \(PipoSecrets.redact(error.localizedDescription))")
        }
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

    private func invalidateCourseCache() {
        courseLoads.values.forEach { $0.cancel() }
        courseLoads.removeAll()
        courseLoadIDs.removeAll()
        courseCache.removeAll()
    }

    private func beginSession(accountID: String) async {
        sessionContext = PipoSessionContext(accountID: accountID, generation: sessionContext.generation &+ 1)
        let session = sessionContext
        snapshot = nil
        rawSnapshot = nil
        refreshDate = nil
        notificationTask?.cancel()
        notificationService.beginSession(accountID)
        if scheduleEnabled || scheduleImportEnabled {
            await scheduleController.activate(accountID: accountID)
            guard session == sessionContext, !isEndingSession else { return }
        }
        if let persistenceManager {
            let status = await persistenceManager.prepare()
            guard session == sessionContext, !isEndingSession else { return }
            persistenceStatus = status
        }
        if let legacy = PipoAccountNamespace.legacyLPUIdentifier(in: accountID) {
            do { try await persistenceManager?.migrateAccount(from: legacy, to: accountID) }
            catch { persistenceStatus = .unavailable("Account storage could not be migrated. Retry secure storage.") }
            guard session == sessionContext, !isEndingSession else { return }
        }
        let state = (try? await localStateStore?.loadLocalState(accountID: accountID)) ?? PipoLocalState()
        guard session == sessionContext, !isEndingSession else { return }
        localState = state
    }

    private func scopedAccountID(from response: SidecarResponse) throws -> String {
        guard let result = response.result, case .object(let object) = result else { throw PipoCoreError.invalidResponse }
        let raw: String
        switch object["account_id"] {
        case .number(let value): raw = String(value)
        case .string(let value) where !value.isEmpty: raw = value
        default: throw PipoCoreError.invalidResponse
        }
        let digest = SHA256.hash(data: Data(raw.utf8))
        let legacy = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return PipoAccountNamespace.lpuScope(for: legacy)
    }

    private func persistSession(token: String, accountID: String) throws {
        if let sessionIdentityStore {
            try sessionIdentityStore.saveSession(token: token, accountID: accountID)
        } else {
            try tokenStore.save(token: token)
        }
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
