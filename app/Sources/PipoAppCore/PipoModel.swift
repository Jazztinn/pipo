import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class PipoModel {
    public private(set) var phase: PipoPhase = .signedOut
    public var selectedTab: PipoTab = .dashboard
    public private(set) var snapshot: DashboardSnapshot?
    public private(set) var refreshDate: Date?
    public var settings: PipoSettings
    public private(set) var authenticationError: String?

    private let transport: any PipoSidecarTransport
    private let tokenStore: any PipoTokenStore
    private let cacheKeyStore: (any PipoTokenStore)?
    private let refreshCoordinator: DashboardRefreshCoordinator
    private let urlOpener: (URL) -> Void
    @ObservationIgnored private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var hasRequestedNotificationAccess = false

    public init(transport: any PipoSidecarTransport, tokenStore: any PipoTokenStore, cacheKeyStore: (any PipoTokenStore)? = nil, refreshCoordinator: DashboardRefreshCoordinator, settings: PipoSettings = PipoSettings(), urlOpener: @escaping (URL) -> Void = { url in NSWorkspace.shared.open(url) }) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.cacheKeyStore = cacheKeyStore
        self.refreshCoordinator = refreshCoordinator
        self.settings = settings
        self.urlOpener = urlOpener
    }

    public static func live() -> PipoModel {
        let store = KeychainTokenStore()
        let cacheKeyStore = KeychainTokenStore(account: "pipo-cache-key")
        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Pipo/dashboard.sqlite", isDirectory: false)
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cacheKey = cacheKeyData(store: cacheKeyStore)
        let cache: any DashboardCache = (try? EncryptedDashboardCache(databaseURL: cacheURL, keyData: cacheKey)) ?? InMemoryDashboardCache()
        return PipoModel(transport: PipoCoreProcessTransport(), tokenStore: store, cacheKeyStore: cacheKeyStore, refreshCoordinator: DashboardRefreshCoordinator(transport: PipoCoreProcessTransport(), cache: cache))
    }

    public func start() async {
        await restore()
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(300, self.settings.refreshInterval)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh(force: true)
            }
        }
    }

    public func restore() async {
        guard let token = storedToken() else { return }
        if let cached = try? await refreshCoordinator.loadCached() {
            snapshot = cached
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
            try tokenStore.save(token: token)
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
            try tokenStore.save(token: token)
            await refresh(using: token, force: true)
        } catch {
            fail(error)
        }
    }

    public func refresh(force: Bool = true) async {
        guard let token = storedToken() else { phase = .signedOut; return }
        await refresh(using: token, force: force)
    }

    public func openURL(for item: DashboardItem) async {
        do {
            let response = try await transport.send(SidecarRequest(method: "resolve_destination", params: ["destination": .string(item.destination)]))
            guard let result = response.result, case .object(let object) = result, case .string(let urlString)? = object["url"], let url = URL(string: urlString) else { throw PipoCoreError.invalidResponse }
            guard try DestinationPolicy.resolve(url.absoluteString) == url else { throw PipoCoreError.originRejected }
            urlOpener(url)
        } catch {
            fail(error)
        }
    }

    public func signOut() async {
        do {
            try tokenStore.deleteToken()
            try cacheKeyStore?.deleteToken()
            try await refreshCoordinator.clearCache()
        }
        catch { fail(error); return }
        snapshot = nil
        refreshDate = nil
        authenticationError = nil
        hasRequestedNotificationAccess = false
        PipoSystemNotifications.clear()
        phase = .signedOut
        selectedTab = .dashboard
    }

    private func refresh(using token: String, force: Bool) async {
        let previousSnapshot = snapshot
        phase = snapshot == nil ? .loading : .ready
        do {
            snapshot = try await refreshCoordinator.refresh(token: token, force: force, settings: settings)
            if await refreshCoordinator.lastResultUsedCache() {
                phase = .offline
            } else {
                refreshDate = Date()
                phase = .ready
                if settings.notificationsEnabled, let snapshot {
                    if !hasRequestedNotificationAccess {
                        hasRequestedNotificationAccess = true
                        await PipoSystemNotifications.requestAuthorization()
                    }
                    if let previousSnapshot {
                        await PipoSystemNotifications.deliver(
                            PipoNotificationPlanner.changes(from: previousSnapshot, to: snapshot)
                        )
                    }
                }
            }
        } catch {
            if snapshot != nil { phase = .offline } else { fail(error) }
        }
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
        do { return try tokenStore.token() }
        catch { return nil }
    }

    private static func cacheKeyData(store: any PipoTokenStore) -> Data {
        if let stored = try? store.token(), let data = Data(base64Encoded: stored), data.count == 32 { return data }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        try? store.save(token: data.base64EncodedString())
        return data
    }
}
