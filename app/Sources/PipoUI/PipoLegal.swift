import Foundation
import PipoAppCore
import SwiftUI

public enum PipoLegal {
    public static let acknowledgementKey = "pipo.legal.accepted-version"
    public static let currentVersion = "2026-08-23"
    public static let termsURL = URL(string: "https://pipo.jazztinn.me/terms.html")!
    public static let privacyURL = URL(string: "https://pipo.jazztinn.me/privacy.html")!
    public static let preReleaseAcknowledgementKey = "pipo.prerelease.accepted-version"

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

    public static func bundledDocument(named name: String, extension fileExtension: String) -> String? {
        guard let url = PipoResources.url(forResource: name, withExtension: fileExtension, subdirectory: "Legal") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public static func allowedExternalDestination(_ url: URL) -> URL? {
        if url == termsURL || url == privacyURL { return url }
        return try? DestinationPolicy.resolve(url.absoluteString)
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
