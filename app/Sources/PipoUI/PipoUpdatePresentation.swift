import Foundation
import Observation

public enum PipoUpdateSeverity: String, Codable, Sendable {
    case standard
    case critical
}

public enum PipoUpdateProbePolicy {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastProbe: Date?, now: Date = .now) -> Bool {
        guard let lastProbe else { return true }
        return now.timeIntervalSince(lastProbe) >= interval
    }
}

public struct PipoUpdateNotice: Codable, Equatable, Sendable {
    public let version: String
    public let build: String
    public let severity: PipoUpdateSeverity

    public init(version: String, build: String, severity: PipoUpdateSeverity) {
        self.version = version
        self.build = build
        self.severity = severity
    }
}

public struct PipoWhatsNew: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int
    public let importance: PipoUpdateSeverity
    public let channel: String
    public let items: [String]

    public init(
        version: String,
        build: Int,
        importance: PipoUpdateSeverity = .standard,
        channel: String = "stable",
        items: [String]
    ) {
        self.version = version
        self.build = build
        self.importance = importance
        self.channel = channel
        self.items = Array(items.prefix(4))
    }

    public var isValid: Bool {
        !version.isEmpty && build > 0 && (2...4).contains(items.count) && items.allSatisfy { !$0.isEmpty }
    }
}

@MainActor
@Observable
public final class PipoUpdatePresentationModel {
    public private(set) var updateNotice: PipoUpdateNotice?
    public private(set) var whatsNew: PipoWhatsNew?

    private let defaults: UserDefaults
    private let currentBuild: Int
    private var dismissedVersions: Set<String> = []

    private enum Keys {
        static let launchedBuild = "pipo.updates.last-launched-build"
        static let whatsNewBuild = "pipo.updates.whats-new-seen-build"
    }

    public init(
        currentVersion: String? = nil,
        currentBuild: Int? = nil,
        defaults: UserDefaults = .standard,
        existingInstallation: Bool? = nil,
        whatsNew: PipoWhatsNew? = nil
    ) {
        self.defaults = defaults
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let bundleBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        let resolvedVersion = currentVersion ?? bundleVersion
        let resolvedBuild = currentBuild ?? bundleBuild
        self.currentBuild = resolvedBuild

        let manifest = whatsNew ?? Self.loadBundledWhatsNew()
        let previousBuild = defaults.integer(forKey: Keys.launchedBuild)
        let hasLaunchRecord = defaults.object(forKey: Keys.launchedBuild) != nil
        let hasExistingData = existingInstallation ?? (
            defaults.object(forKey: PipoLegal.acknowledgementKey) != nil ||
                defaults.object(forKey: PipoLegal.preReleaseAcknowledgementKey) != nil
        )

        if let manifest,
           manifest.isValid,
           manifest.version == resolvedVersion,
           manifest.build == resolvedBuild,
           defaults.integer(forKey: Keys.whatsNewBuild) < resolvedBuild,
           (hasLaunchRecord ? previousBuild < resolvedBuild : hasExistingData)
        {
            self.whatsNew = manifest
        }
        defaults.set(resolvedBuild, forKey: Keys.launchedBuild)
        if !hasLaunchRecord, !hasExistingData {
            defaults.set(resolvedBuild, forKey: Keys.whatsNewBuild)
        }
    }

    public func presentUpdate(version: String, build: String, critical: Bool) {
        guard !version.isEmpty else { return }
        if updateNotice?.severity == .critical, !critical { return }
        let notice = PipoUpdateNotice(
            version: version,
            build: build,
            severity: critical ? .critical : .standard
        )
        guard critical || !dismissedVersions.contains(Self.noticeKey(notice)) else { return }
        updateNotice = notice
    }

    public func clearUpdateNotice() {
        guard updateNotice?.severity != .critical else { return }
        updateNotice = nil
    }

    public func dismissUpdate() {
        guard let notice = updateNotice, notice.severity == .standard else { return }
        dismissedVersions.insert(Self.noticeKey(notice))
        updateNotice = nil
    }

    public func dismissWhatsNew() {
        guard let whatsNew else { return }
        defaults.set(whatsNew.build, forKey: Keys.whatsNewBuild)
        self.whatsNew = nil
    }

    public func resetForChannelChange() {
        dismissedVersions.removeAll()
        updateNotice = nil
    }

    private static func noticeKey(_ notice: PipoUpdateNotice) -> String {
        "\(notice.version):\(notice.build)"
    }

    private static func loadBundledWhatsNew() -> PipoWhatsNew? {
        guard let url = PipoResources.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(PipoWhatsNew.self, from: data),
              manifest.isValid
        else { return nil }
        return manifest
    }
}
