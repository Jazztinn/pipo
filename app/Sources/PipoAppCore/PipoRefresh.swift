import Foundation

public actor DashboardRefreshCoordinator {
    private let transport: any PipoSidecarTransport
    private let cache: any DashboardCache
    private var lastSuccessfulRefresh: Date?
    private var usedCachedResult = false

    public init(transport: any PipoSidecarTransport, cache: any DashboardCache) {
        self.transport = transport
        self.cache = cache
    }

    public func refresh(token: String, force: Bool = false, settings: PipoSettings = PipoSettings()) async throws -> DashboardSnapshot {
        if !force, let lastSuccessfulRefresh, Date().timeIntervalSince(lastSuccessfulRefresh) < settings.refreshInterval, let snapshot = try await cache.load() {
            usedCachedResult = false
            return snapshot
        }
        do {
            let previous = try await cache.load()
            let response = try await transport.send(SidecarRequest(method: "refresh_dashboard", params: ["token": .string(token)]))
            guard let result = response.result else { throw PipoCoreError.invalidResponse }
            let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: result.encodedData()).privacyProjected()
            let snapshot = decoded.presentingNewAssignments(since: previous.map { Set($0.assignmentIDs) })
            try await cache.save(snapshot)
            lastSuccessfulRefresh = Date()
            usedCachedResult = false
            return snapshot
        } catch {
            if let cached = try await cache.load() {
                usedCachedResult = true
                return cached
            }
            throw error
        }
    }

    public func loadCached() async throws -> DashboardSnapshot? {
        try await cache.load()
    }

    public func lastResultUsedCache() -> Bool {
        usedCachedResult
    }

    public func clearCache() async throws {
        try await cache.delete()
        lastSuccessfulRefresh = nil
        usedCachedResult = false
    }
}

public actor InMemoryDashboardCache: DashboardCache {
    private var snapshot: DashboardSnapshot?

    public init(snapshot: DashboardSnapshot? = nil) { self.snapshot = snapshot }
    public func load() -> DashboardSnapshot? { snapshot }
    public func save(_ snapshot: DashboardSnapshot) { self.snapshot = snapshot }
    public func delete() { snapshot = nil }
}
