import Foundation

@MainActor
public final class PipoUsageTracker {
    private struct Event: Encodable {
        let event: String
        let installID: String
        let platform: String
        let version: String

        enum CodingKeys: String, CodingKey {
            case event
            case installID = "install_id"
            case platform
            case version
        }
    }

    private static let enabledKey = "pipo.usage-reporting.enabled"
    private static let installIDKey = "pipo.usage-reporting.install-id"
    private static let lastSentDayKey = "pipo.usage-reporting.last-sent-day"
    private let endpoint: URL?
    private let defaults: UserDefaults
    private let session: URLSession
    private let installID: String
    private let version: String
    private var task: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?

    public init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        endpoint = (bundle.object(forInfoDictionaryKey: "PipoUsageEndpoint") as? String)
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
        self.defaults = defaults
        self.session = session
        if let saved = defaults.string(forKey: Self.installIDKey), UUID(uuidString: saved) != nil {
            installID = saved
        } else {
            let generated = UUID().uuidString.lowercased()
            defaults.set(generated, forKey: Self.installIDKey)
            installID = generated
        }
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    public func start() {
        guard task == nil, endpoint != nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isEnabled else { return }
                self.stop()
            }
        }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.isEnabled else { return }
                if self.shouldReportToday {
                    await self.send(event: self.lastSentDay == nil ? "launch" : "heartbeat")
                }
                // Poll only to notice a new UTC day; never emit repeating heartbeats.
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private var shouldReportToday: Bool {
        lastSentDay != Self.utcDay
    }

    private var lastSentDay: String? {
        defaults.string(forKey: Self.lastSentDayKey)
    }

    private static var utcDay: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: .now)
    }

    private func send(event: String) async {
        guard let endpoint else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Event(event: event, installID: installID, platform: "macos", version: version))
        guard request.httpBody != nil else { return }
        do {
            let (_, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 202 else { return }
            defaults.set(Self.utcDay, forKey: Self.lastSentDayKey)
        } catch {
            // Usage reporting is best effort. LMS access must keep working offline.
        }
    }
}
