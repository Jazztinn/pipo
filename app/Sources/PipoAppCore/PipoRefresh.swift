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

    public func refresh(token: String, force: Bool = false, settings: PipoSettings = PipoSettings(), sections: Set<String>? = nil) async throws -> DashboardSnapshot {
        if !force, sections == nil, let lastSuccessfulRefresh, Date().timeIntervalSince(lastSuccessfulRefresh) < settings.refreshInterval, let snapshot = try await cache.load() {
            usedCachedResult = false
            return snapshot
        }
        do {
            let previous = try await cache.load()
            var params: [String: PipoJSONValue] = ["token": .string(token)]
            if let sections {
                params["sections"] = .array(sections.sorted().map(PipoJSONValue.string))
            }
            let response = try await transport.send(SidecarRequest(method: "refresh_dashboard", params: params))
            guard let result = response.result else { throw PipoCoreError.invalidResponse }
            let decoded = try JSONDecoder().decode(DashboardSnapshot.self, from: result.encodedData()).privacyProjected()
            let merged = previous.map { merge(cached: $0, refreshed: decoded, requested: sections) } ?? decoded
            let snapshot = merged.presentingNewAssignments(since: previous.map { Set($0.assignmentIDs) })
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

    private func merge(cached: DashboardSnapshot, refreshed: DashboardSnapshot, requested: Set<String>?) -> DashboardSnapshot {
        guard let requested else { return refreshed }
        let has = { requested.contains($0) }
        let sections = DashboardSections(
            dueSoon: has("due_soon") ? refreshed.sections.dueSoon : cached.sections.dueSoon,
            notifications: has("notifications") ? refreshed.sections.notifications : cached.sections.notifications,
            newAssignments: has("assignments") ? refreshed.sections.newAssignments : cached.sections.newAssignments,
            messages: has("messages") ? refreshed.sections.messages : cached.sections.messages,
            gradeFeedback: has("grades") ? refreshed.sections.gradeFeedback : cached.sections.gradeFeedback
        )
        let nextUp = has("due_soon") || has("assignments") || has("schedule") || has("announcements") ? refreshed.nextUp : cached.nextUp
        let schedule = has("schedule") ? refreshed.schedule : cached.schedule
        let announcements = has("announcements") ? refreshed.announcements : cached.announcements
        let resources = has("resources") ? refreshed.resources : cached.resources
        let timestamps = cached.sectionTimestamps.merging(refreshed.sectionTimestamps) { _, new in new }
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
                publishedTotal: has("grades") ? course.publishedTotal : cachedCourse.publishedTotal,
                upcomingCount: has("due_soon") ? course.upcomingCount : cachedCourse.upcomingCount
            )
        }
        return DashboardSnapshot(version: refreshed.version, generatedAt: refreshed.generatedAt, siteName: refreshed.siteName, studentName: refreshed.studentName, sections: sections, supported: refreshed.supported, assignmentIDs: has("assignments") ? refreshed.assignmentIDs : cached.assignmentIDs, courses: courses, failures: failures, nextUp: nextUp, schedule: schedule, announcements: announcements, resources: resources, sectionTimestamps: timestamps)
    }
}

public actor InMemoryDashboardCache: DashboardCache {
    private var snapshot: DashboardSnapshot?

    public init(snapshot: DashboardSnapshot? = nil) { self.snapshot = snapshot }
    public func load() -> DashboardSnapshot? { snapshot }
    public func save(_ snapshot: DashboardSnapshot) { self.snapshot = snapshot }
    public func delete() { snapshot = nil }
}
