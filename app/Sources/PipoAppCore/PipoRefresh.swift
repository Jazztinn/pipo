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
    private struct Flight {
        let id: UUID
        let task: Task<DashboardRefreshOutcome, Error>
    }
    private var inFlight: [String: Flight] = [:]
    private var active: [UUID: Task<DashboardRefreshOutcome, Error>] = [:]
    private var generation: UInt64 = 0
    private var clearTask: Task<Void, Error>?
    private var memorySnapshots: [String: DashboardSnapshot] = [:]
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
        if let clearTask { try await clearTask.value }
        try Task.checkCancellation()
        let epoch = generation
        let sessionPrefix = "\(session.accountID)|\(session.generation)|"
        if sections != nil,
           let fullTask = inFlight.first(where: { $0.key.hasPrefix(sessionPrefix) && $0.key.hasSuffix("|") })?.value.task {
            let result = try await fullTask.value
            try checkGeneration(epoch)
            markLatestMetricsCoalesced()
            return DashboardRefreshOutcome(snapshot: result.snapshot, source: result.source, refreshedSections: result.refreshedSections, preservedSections: result.preservedSections, coalesced: true)
        }
        if sections == nil {
            for key in inFlight.keys.filter({ $0.hasPrefix(sessionPrefix) && !$0.hasSuffix("|") }) {
                inFlight.removeValue(forKey: key)?.task.cancel()
            }
        }
        let key = "\(session.accountID)|\(session.generation)|\(force)|\((sections ?? []).sorted().joined(separator: ","))"
        if let flight = inFlight[key] {
            let result = try await flight.task.value
            try checkGeneration(epoch)
            markLatestMetricsCoalesced()
            return DashboardRefreshOutcome(snapshot: result.snapshot, source: result.source, refreshedSections: result.refreshedSections, preservedSections: result.preservedSections, coalesced: true)
        }
        let predecessor = refreshTail
        let id = UUID()
        let task = Task {
            if let predecessor { await predecessor.value }
            try self.checkGeneration(epoch)
            return try await self.performRefresh(token: token, force: force, settings: settings, sections: sections, session: session, epoch: epoch)
        }
        refreshTail = Task { _ = try? await task.value }
        inFlight[key] = Flight(id: id, task: task)
        active[id] = task
        defer {
            active[id] = nil
            if inFlight[key]?.id == id { inFlight[key] = nil }
        }
        return try await task.value
    }

    private func checkGeneration(_ epoch: UInt64) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
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

    private func performRefresh(token: String, force: Bool, settings: PipoSettings, sections: Set<String>?, session: PipoSessionContext, epoch: UInt64) async throws -> DashboardRefreshOutcome {
        let started = ContinuousClock.now
        var requestedSections = sections
        if !force, requestedSections == nil, let snapshot = try await loadCache(for: session) {
            try checkGeneration(epoch)
            let stale = sectionsNeedingRefresh(in: snapshot, settings: settings)
            if stale.isEmpty {
                usedCachedResult = false
                recordMetrics(snapshot, source: .freshCache, started: started)
                return DashboardRefreshOutcome(snapshot: snapshot, source: .freshCache, refreshedSections: [], preservedSections: Set(Self.allSections), coalesced: false)
            }
            requestedSections = stale
        }
        do {
            let previous: DashboardSnapshot?
            if let memory = memorySnapshots[session.accountID] { previous = memory }
            else { previous = try await loadCache(for: session) }
            try checkGeneration(epoch)
            let day = PipoSchoolClock.dayInterval()
            var params: [String: PipoJSONValue] = [
                "token": .string(token),
                "day_start": .number(Int(day.start.timeIntervalSince1970)),
                "day_end": .number(Int(day.end.timeIntervalSince1970))
            ]
            if let requestedSections {
                params["sections"] = .array(requestedSections.sorted().map(PipoJSONValue.string))
            }
            let response = try await transport.send(SidecarRequest(method: "refresh_dashboard", params: params))
            try checkGeneration(epoch)
            guard let result = response.result else { throw PipoCoreError.invalidResponse }
            // Keep private LMS detail in memory for the signed-in UI. Persist only the
            // privacy projection so message bodies, feedback, and grades never enter cache.
            let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: result.encodedData()).upgradedToVersionThree()
            let merged = previous.map { merge(cached: $0, refreshed: decoded, requested: requestedSections) } ?? decoded
            // Persist complete dashboard. New-assignment filtering is presentation-only;
            // caching filtered data loses assignments and breaks future diffs.
            let snapshot = merged.presentingNewAssignments(since: previous.map { Set($0.assignmentIDs) })
            try checkGeneration(epoch)
            try await saveCache(merged.privacyProjected(), for: session)
            try checkGeneration(epoch)
            memorySnapshots[session.accountID] = merged
            usedCachedResult = false
            let requested = requestedSections ?? Set(Self.allSections)
            let preserved = Set(requested.filter { decoded.result(for: $0).status != .success })
            recordMetrics(snapshot, source: .network, started: started)
            return DashboardRefreshOutcome(snapshot: snapshot, source: .network, refreshedSections: requested.subtracting(preserved), preservedSections: preserved, coalesced: false)
        } catch {
            try checkGeneration(epoch)
            if error is CancellationError || (error as? PipoCoreError) == .authenticationRequired {
                throw error
            }
            if let cached = try await loadCache(for: session) {
                try checkGeneration(epoch)
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
        if let clearTask { return try await clearTask.value }
        generation &+= 1
        let tasks = Array(active.values)
        tasks.forEach { $0.cancel() }
        inFlight.removeAll()
        memorySnapshots.removeAll()
        let task = Task {
            for task in tasks { _ = await task.result }
            try await self.cache.delete()
        }
        clearTask = task
        defer { clearTask = nil }
        try await task.value
        usedCachedResult = false
        latestMetrics = nil
        refreshTail = nil
    }

    public func cancelAll() async {
        generation &+= 1
        let tasks = Array(active.values)
        tasks.forEach { $0.cancel() }
        inFlight.removeAll()
        memorySnapshots.removeAll()
        // Keep all superseded tasks until drained; dropping the tail alone does
        // not cancel a write that is already suspended inside persistence.
        for task in tasks { _ = await task.result }
        refreshTail = nil
    }

    private func loadCache(for session: PipoSessionContext) async throws -> DashboardSnapshot? {
        if let snapshot = memorySnapshots[session.accountID] { return snapshot }
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
            case .partial:
                // Partial results cannot prove deletion. Bound retained history
                // while preserving returned rows and recent cached records.
                let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
                let retained = old.filter { item in
                    guard let timestamp = item.timestamp,
                          let date = ISO8601DateFormatter().date(from: timestamp) else { return true }
                    return date >= cutoff
                }
                return Array(DashboardItem.deduplicated(new + retained).prefix(500))
            case .unsupported: return []
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
        let schedule = items("schedule", cached.schedule, refreshed.schedule)
        let announcements = items("announcements", cached.announcements, refreshed.announcements)
        let resources = items("resources", cached.resources, refreshed.resources)
        var timestamps = cached.sectionTimestamps
        for section in requested where has(section) {
            if let timestamp = refreshed.sectionTimestamps[section] ?? refreshed.result(for: section).fetchedAt {
                timestamps[section] = timestamp
            }
        }
        var results = cached.sectionResults
        for section in requested {
            let result = refreshed.result(for: section)
            if result.status != .notRequested { results[section] = result }
        }
        let failures = results.sorted(by: { $0.key < $1.key }).compactMap { section, result -> String? in
            guard result.status == .failed || result.status == .partial else { return nil }
            return result.error ?? "\(section): data is incomplete."
        }
        let cachedCourses = Dictionary(cached.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let courses = refreshed.courses.map { course in
            guard let cachedCourse = cachedCourses[course.id] else { return course }
            let total: String?
            if has("grades") { total = course.publishedTotal }
            else if requested.contains("grades"), refreshed.result(for: "grades").status == .partial {
                total = course.publishedTotal ?? cachedCourse.publishedTotal
            } else { total = cachedCourse.publishedTotal }
            return Course(
                id: course.id,
                name: course.name,
                shortName: course.shortName ?? cachedCourse.shortName,
                instructor: course.instructor ?? cachedCourse.instructor,
                publishedTotal: total,
                upcomingCount: has("due_soon") ? course.upcomingCount : cachedCourse.upcomingCount
            )
        }
        let assignmentIDs = requested.contains("assignments") && refreshed.result(for: "assignments").status == .partial
            ? Array(Set(refreshed.assignmentIDs + cached.assignmentIDs)).sorted()
            : has("assignments") ? refreshed.assignmentIDs : cached.assignmentIDs
        return DashboardSnapshot(version: max(refreshed.version, 3), generatedAt: refreshed.generatedAt, siteName: refreshed.siteName, studentName: refreshed.studentName, sections: sections, supported: refreshed.supported, assignmentIDs: assignmentIDs, courses: courses, failures: failures, nextUp: [], schedule: schedule, announcements: announcements, resources: resources, sectionTimestamps: timestamps, sectionResults: results, syncDiagnostics: refreshed.syncDiagnostics)
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

    private static let allSections = PipoSectionID.allCases.map(\.rawValue)
}

public actor InMemoryDashboardCache: DashboardCache {
    private var snapshot: DashboardSnapshot?

    public init(snapshot: DashboardSnapshot? = nil) { self.snapshot = snapshot }
    public func load() -> DashboardSnapshot? { snapshot }
    public func save(_ snapshot: DashboardSnapshot) { self.snapshot = snapshot }
    public func delete() { snapshot = nil }
}
