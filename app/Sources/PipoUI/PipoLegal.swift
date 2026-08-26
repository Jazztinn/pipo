import Foundation
import PipoAppCore
import SwiftUI

public enum PipoLegal {
    public static let acknowledgementKey = "pipo.legal.accepted-version"
    public static let currentVersion = "2026-08-23"
    public static let termsURL = URL(string: "https://pipo.jazztinn.me/terms.html")!
    public static let privacyURL = URL(string: "https://pipo.jazztinn.me/privacy.html")!
    public static let preReleaseAcknowledgementKey = "pipo.prerelease.accepted-version"
    public static let preReleaseVersion = "2026-08-26-v1"

    public static func isAcknowledged(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: acknowledgementKey) == currentVersion
    }

    public static func setAcknowledged(_ acknowledged: Bool, in defaults: UserDefaults = .standard) {
        if acknowledged {
            defaults.set(currentVersion, forKey: acknowledgementKey)
        } else {
            defaults.removeObject(forKey: acknowledgementKey)
        }
    }

    public static func isPreReleaseAcknowledged(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: preReleaseAcknowledgementKey) == preReleaseVersion
    }

    public static func setPreReleaseAcknowledged(_ acknowledged: Bool, in defaults: UserDefaults = .standard) {
        if acknowledged {
            defaults.set(preReleaseVersion, forKey: preReleaseAcknowledgementKey)
        } else {
            defaults.removeObject(forKey: preReleaseAcknowledgementKey)
        }
    }

    public static func bundledDocument(named name: String, extension fileExtension: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Legal") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public static func allowedExternalDestination(_ url: URL) -> URL? {
        if url == termsURL || url == privacyURL { return url }
        return try? DestinationPolicy.resolve(url.absoluteString)
    }
}

@MainActor
struct PipoPreReleaseNoticeView: View {
    @State private var understandsNotice = false
    @AppStorage(PipoLegal.preReleaseAcknowledgementKey) private var acceptedVersion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pre-Release & Permissions", systemImage: "testtube.2")
                .font(.headline)
            Text("Pipo is pre-release software and is currently unnotarized by Apple. macOS may show security warnings when you first open it.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                Label("Pipo is independent and unofficial. Verify important information in the official LMS.", systemImage: "checkmark.circle")
                Label("LMS access is read-only. Your password is discarded after token exchange.", systemImage: "eye")
                Label("Keychain securely stores the LMS token and encryption key.", systemImage: "key")
                Label("Notifications and Calendar are optional. Notifications are requested after sync when enabled; Calendar is requested when you use it.", systemImage: "hand.raised")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("You can decline and continue using the official LMS. Optional permissions can be denied or revoked later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("I understand Pipo is pre-release, unnotarized, may show macOS warnings, and that optional permissions are my choice.", isOn: $understandsNotice)
                .fixedSize(horizontal: false, vertical: true)

            Button("Continue") { acceptedVersion = PipoLegal.preReleaseVersion }
                .buttonStyle(.borderedProminent)
                .disabled(!understandsNotice)
                .keyboardShortcut(.defaultAction)
        }
    }
}

@MainActor
struct PipoLegalAcknowledgementView: View {
    @AppStorage(PipoLegal.acknowledgementKey) private var acceptedVersion = ""
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("I agree to Pipo’s Terms of Use and acknowledge the Privacy Policy.", isOn: Binding(
                get: { acceptedVersion == PipoLegal.currentVersion },
                set: { acceptedVersion = $0 ? PipoLegal.currentVersion : "" }
            ))
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Terms of Use") { openURL(PipoLegal.termsURL) }
                Button("Privacy Policy") { openURL(PipoLegal.privacyURL) }
            }
            .buttonStyle(.link)
        }
    }
}
