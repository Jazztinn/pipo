import Foundation

public enum PipoRefreshSource: String, Sendable {
    case network
    case freshCache = "fresh_cache"
    case staleCache = "stale_cache"
}

public struct DashboardRefreshOutcome: Sendable {
    public let snapshot: DashboardSnapshot
    public let source: PipoRefreshSource
    public let refreshedSections: Set<String>
    public let preservedSections: Set<String>
    public let coalesced: Bool
}

public struct PipoRefreshMetrics: Equatable, Sendable {
    public let source: PipoRefreshSource
    public let durationMilliseconds: Int
    public let itemCount: Int
    public let failureCount: Int
    public let coalesced: Bool
}

public enum PipoRefreshTier: Sendable {
    case core
    case heavy

    public static func tier(for section: String) -> PipoRefreshTier {
        switch section {
        case "grades", "announcements", "resources": .heavy
        default: .core
        }
    }

    public func interval(settings: PipoSettings) -> TimeInterval {
        switch self {
        case .core: settings.refreshInterval
        case .heavy: 60 * 60
        }
    }
}

public actor DashboardRefreshCoordinator {
    private let transport: any PipoSidecarTransport
    private let cache: any DashboardCache
    private var usedCachedResult = false
    private var inFlight: [String: Task<DashboardRefreshOutcome, Error>] = [:]
    private var refreshTail: Task<Void, Never>?
    private var latestMetrics: PipoRefreshMetrics?

    public init(transport: any PipoSidecarTransport, cache: any DashboardCache) {
        self.transport = transport
        self.cache = cache
    }

    public func refresh(token: String, force: Bool = false, settings: PipoSettings = PipoSettings(), sections: Set<String>? = nil, session: PipoSessionContext = PipoSessionContext()) async throws -> DashboardSnapshot {
        try await refreshOutcome(token: token, force: force, settings: settings, sections: sections, session: session).snapshot
    }

    public func refreshOutcome(token: String, force: Bool = false, settings: PipoSettings = PipoSettings(), sections: Set<String>? = nil, session: PipoSessionContext = PipoSessionContext()) async throws -> DashboardRefreshOutcome {
        let sessionPrefix = "\(session.accountID)|\(session.generation)|"
        if sections != nil,
           let fullTask = inFlight.first(where: { $0.key.hasPrefix(sessionPrefix) && $0.key.hasSuffix("|") })?.value
        {
            let result = try await fullTask.value
            markLatestMetricsCoalesced()
            return DashboardRefreshOutcome(snapshot: result.snapshot, source: result.source, refreshedSections: result.refreshedSections, preservedSections: result.preservedSections, coalesced: true)
        }
        if sections == nil {
            let sectionKeys = inFlight.keys.filter { $0.hasPrefix(sessionPrefix) && !$0.hasSuffix("|") }
            for key in sectionKeys {
                inFlight.removeValue(forKey: key)?.cancel()
            }
        }
        let key = "\(session.accountID)|\(session.generation)|\(force)|\((sections ?? []).sorted().joined(separator: ","))"
        if let task = inFlight[key] {
            let result = try await task.value
            markLatestMetricsCoalesced()
            return DashboardRefreshOutcome(snapshot: result.snapshot, source: result.source, refreshedSections: result.refreshedSections, preservedSections: result.preservedSections, coalesced: true)
        }
        let predecessor = refreshTail
        let task = Task {
            if let predecessor { await predecessor.value }
            try Task.checkCancellation()
            return try await self.performRefresh(token: token, force: force, settings: settings, sections: sections, session: session)
        }
        refreshTail = Task { _ = try? await task.value }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    public func metrics() -> PipoRefreshMetrics? { latestMetrics }

    public func sectionsNeedingRefresh(in snapshot: DashboardSnapshot, settings: PipoSettings = PipoSettings(), now: Date = .now) -> Set<String> {
        Set(Self.allSections.filter { section in
            let result = snapshot.result(for: section)
            if result.status == .unsupported { return false }
            if let retryAfter = result.retryAfterSeconds, retryAfter > 0,
               let fetchedAt = result.fetchedAt,
               let retryDate = ISO8601DateFormatter().date(from: fetchedAt)?.addingTimeInterval(TimeInterval(retryAfter)),
               now < retryDate { return false }
            if result.status == .failed || result.status == .partial { return true }
            let value = result.fetchedAt ?? snapshot.sectionTimestamps[section] ?? snapshot.generatedAt
            guard let date = ISO8601DateFormatter().date(from: value) else { return true }
            return now.timeIntervalSince(date) >= PipoRefreshTier.tier(for: section).interval(settings: settings)
        })
    }

    private func performRefresh(token: String, force: Bool, settings: PipoSettings, sections: Set<String>?, session: PipoSessionContext) async throws -> DashboardRefreshOutcome {
        let started = ContinuousClock.now
        var requestedSections = sections
        if !force, requestedSections == nil, let snapshot = try await loadCache(for: session) {
            let stale = sectionsNeedingRefresh(in: snapshot, settings: settings)
            if stale.isEmpty {
                usedCachedResult = false
                recordMetrics(snapshot, source: .freshCache, started: started)
                return DashboardRefreshOutcome(snapshot: snapshot, source: .freshCache, refreshedSections: [], preservedSections: Set(Self.allSections), coalesced: false)
            }
            requestedSections = stale
        }
        do {
            let previous = try await loadCache(for: session)
            var params: [String: PipoJSONValue] = ["token": .string(token)]
            if let requestedSections {
                params["sections"] = .array(requestedSections.sorted().map(PipoJSONValue.string))
            }
            let response = try await transport.send(SidecarRequest(method: "refresh_dashboard", params: params))
            guard let result = response.result else { throw PipoCoreError.invalidResponse }
            // Keep private LMS detail in memory for the signed-in UI. Persist only the
            // privacy projection so message bodies, feedback, and grades never enter cache.
            let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: result.encodedData()).upgradedToVersionThree()
            let merged = previous.map { merge(cached: $0, refreshed: decoded, requested: requestedSections) } ?? decoded
            // Persist complete dashboard. New-assignment filtering is presentation-only;
            // caching filtered data loses assignments and breaks future diffs.
            let snapshot = merged.presentingNewAssignments(since: previous.map { Set($0.assignmentIDs) })
            try await saveCache(merged.privacyProjected(), for: session)
            usedCachedResult = false
            let requested = requestedSections ?? Set(Self.allSections)
            let preserved = Set(requested.filter { decoded.result(for: $0).status != .success })
            recordMetrics(snapshot, source: .network, started: started)
            return DashboardRefreshOutcome(snapshot: snapshot, source: .network, refreshedSections: requested.subtracting(preserved), preservedSections: preserved, coalesced: false)
        } catch {
            if error is CancellationError || (error as? PipoCoreError) == .authenticationRequired {
                throw error
            }
            if let cached = try await loadCache(for: session) {
                usedCachedResult = true
                recordMetrics(cached, source: .staleCache, started: started)
                return DashboardRefreshOutcome(snapshot: cached, source: .staleCache, refreshedSections: [], preservedSections: Set(Self.allSections), coalesced: false)
            }
            throw error
        }
    }

    public func loadCached(session: PipoSessionContext = PipoSessionContext()) async throws -> DashboardSnapshot? {
        try await loadCache(for: session)
    }

    public func lastResultUsedCache() -> Bool {
        usedCachedResult
    }

    public func clearCache() async throws {
        try await cache.delete()
        usedCachedResult = false
        cancelAll()
        latestMetrics = nil
    }

    public func cancelAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        refreshTail?.cancel()
        refreshTail = nil
    }

    private func loadCache(for session: PipoSessionContext) async throws -> DashboardSnapshot? {
        if let scoped = cache as? any AccountScopedDashboardCache { return try await scoped.load(accountID: session.accountID) }
        return try await cache.load()
    }

    private func saveCache(_ snapshot: DashboardSnapshot, for session: PipoSessionContext) async throws {
        if let scoped = cache as? any AccountScopedDashboardCache { try await scoped.save(snapshot, accountID: session.accountID) }
        else { try await cache.save(snapshot) }
    }

    private func merge(cached: DashboardSnapshot, refreshed: DashboardSnapshot, requested: Set<String>?) -> DashboardSnapshot {
        let requested = requested ?? Set(Self.allSections)
        let has = { requested.contains($0) && refreshed.result(for: $0).status == .success }
        let items: (String, [DashboardItem], [DashboardItem]) -> [DashboardItem] = { section, old, new in
            guard requested.contains(section) else { return old }
            switch refreshed.result(for: section).status {
            case .success: return new
            case .partial: return DashboardItem.deduplicated(new + old)
            default: return old
            }
        }
        let sections = DashboardSections(
            dueSoon: items("due_soon", cached.sections.dueSoon, refreshed.sections.dueSoon),
            notifications: items("notifications", cached.sections.notifications, refreshed.sections.notifications),
            newAssignments: items("assignments", cached.sections.newAssignments, refreshed.sections.newAssignments),
            messages: items("messages", cached.sections.messages, refreshed.sections.messages),
            gradeFeedback: items("grades", cached.sections.gradeFeedback, refreshed.sections.gradeFeedback)
        )
        let nextUpChanged = ["due_soon", "assignments", "schedule", "announcements"].contains { requested.contains($0) && [.success, .partial].contains(refreshed.result(for: $0).status) }
        let nextUp = nextUpChanged ? DashboardItem.deduplicated(refreshed.nextUp + cached.nextUp) : cached.nextUp
        let schedule = items("schedule", cached.schedule, refreshed.schedule)
        let announcements = items("announcements", cached.announcements, refreshed.announcements)
        let resources = items("resources", cached.resources, refreshed.resources)
        var timestamps = cached.sectionTimestamps
        for section in requested where has(section) {
            if let timestamp = refreshed.sectionTimestamps[section] ?? refreshed.result(for: section).fetchedAt {
                timestamps[section] = timestamp
            }
        }
        let failures = refreshed.failures + cached.failures.filter { failure in
            !requested.contains { failure.localizedCaseInsensitiveContains($0.replacingOccurrences(of: "_", with: " ")) }
        }
        let cachedCourses = Dictionary(uniqueKeysWithValues: cached.courses.map { ($0.id, $0) })
        let courses = refreshed.courses.isEmpty ? cached.courses : refreshed.courses.map { course in
            guard let cachedCourse = cachedCourses[course.id] else { return course }
            return Course(
                id: course.id,
                name: course.name,
                shortName: course.shortName ?? cachedCourse.shortName,
                instructor: course.instructor ?? cachedCourse.instructor,
                publishedTotal: has("grades") ? course.publishedTotal : cachedCourse.publishedTotal,
                upcomingCount: has("due_soon") ? course.upcomingCount : cachedCourse.upcomingCount
            )
        }
        let results = cached.sectionResults.merging(refreshed.sectionResults) { _, new in new }
        let assignmentIDs = refreshed.result(for: "assignments").status == .partial
            ? Array(Set(refreshed.assignmentIDs + cached.assignmentIDs)).sorted()
            : has("assignments") ? refreshed.assignmentIDs : cached.assignmentIDs
        return DashboardSnapshot(version: max(refreshed.version, 3), generatedAt: refreshed.generatedAt, siteName: refreshed.siteName, studentName: refreshed.studentName, sections: sections, supported: refreshed.supported, assignmentIDs: assignmentIDs, courses: courses, failures: failures, nextUp: nextUp, schedule: schedule, announcements: announcements, resources: resources, sectionTimestamps: timestamps, sectionResults: results, syncDiagnostics: refreshed.syncDiagnostics)
    }

    private func recordMetrics(_ snapshot: DashboardSnapshot, source: PipoRefreshSource, started: ContinuousClock.Instant) {
        let duration = started.duration(to: .now)
        latestMetrics = PipoRefreshMetrics(
            source: source,
            durationMilliseconds: Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000),
            itemCount: snapshot.presentationItems.count,
            failureCount: snapshot.failures.count,
            coalesced: false
        )
    }

    private func markLatestMetricsCoalesced() {
        guard let metrics = latestMetrics else { return }
        latestMetrics = PipoRefreshMetrics(
            source: metrics.source,
            durationMilliseconds: metrics.durationMilliseconds,
            itemCount: metrics.itemCount,
            failureCount: metrics.failureCount,
            coalesced: true
        )
    }

    private static let allSections = ["due_soon", "notifications", "assignments", "messages", "grades", "schedule", "announcements", "resources"]
}

public actor InMemoryDashboardCache: DashboardCache {
    private var snapshot: DashboardSnapshot?

    public init(snapshot: DashboardSnapshot? = nil) { self.snapshot = snapshot }
    public func load() -> DashboardSnapshot? { snapshot }
    public func save(_ snapshot: DashboardSnapshot) { self.snapshot = snapshot }
    public func delete() { snapshot = nil }
}
