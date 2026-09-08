import CryptoKit
import Foundation

public enum LMSProviderID: String, Codable, Sendable { case moodle, canvas }

/// Stable provider identifier. Storage ownership is supplied separately by AccountScope.
public struct EntityID: Codable, Hashable, Sendable {
  fileprivate let value: String

  public init(remoteID: String) throws {
    guard !remoteID.isEmpty, remoteID.utf8.count <= 512, !remoteID.contains("\0") else {
      throw EntityIDError.invalidRemoteID
    }
    value = remoteID
  }
}

public enum EntityIDError: Error, Equatable, Sendable { case invalidRemoteID }

public struct AccountScope: Codable, Hashable, Sendable {
  public let providerID: LMSProviderID
  public let schoolID: String
  public let originID: String
  public let remoteAccountID: EntityID

  public init(
    providerID: LMSProviderID, schoolID: String, originID: String, remoteAccountID: EntityID
  ) {
    self.providerID = providerID
    self.schoolID = schoolID
    self.originID = originID
    self.remoteAccountID = remoteAccountID
  }

  /// Hash of length-prefixed fields: deterministic, collision-safe, and safe as Keychain account.
  public var storageID: String {
    let fields = [providerID.rawValue, schoolID, originID, remoteAccountID.value]
    let data = Data(fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|").utf8)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  var keychainAccount: String { "oauth-v1-\(storageID)" }
}

public struct SchoolDefinition: Sendable, Equatable {
  public let id: String
  public let providerID: LMSProviderID
  public let apiOrigin: URL
  public let browserOrigin: URL
  public let authorizationOrigin: URL
  public let timeZoneID: String
  public let isEnabled: Bool
  public let canvasClientID: String?

  public init(
    id: String, providerID: LMSProviderID, apiOrigin: URL, browserOrigin: URL,
    authorizationOrigin: URL, timeZoneID: String, isEnabled: Bool, canvasClientID: String? = nil
  ) {
    precondition(
      apiOrigin.scheme == "https" && browserOrigin.scheme == "https"
        && authorizationOrigin.scheme == "https")
    precondition(TimeZone(identifier: timeZoneID) != nil)
    self.id = id
    self.providerID = providerID
    self.apiOrigin = apiOrigin
    self.browserOrigin = browserOrigin
    self.authorizationOrigin = authorizationOrigin
    self.timeZoneID = timeZoneID
    self.isEnabled = isEnabled
    self.canvasClientID = canvasClientID
  }
}

public enum SchoolRegistry {
  public static let lpuCavite = SchoolDefinition(
    id: "lpu-cavite",
    providerID: .moodle,
    apiOrigin: URL(string: "https://lms.lpucavite.edu.ph")!,
    browserOrigin: URL(string: "https://lms.lpucavite.edu.ph")!,
    authorizationOrigin: URL(string: "https://lms.lpucavite.edu.ph")!,
    timeZoneID: "Asia/Manila",
    isEnabled: true
  )

  public static let approved: [SchoolDefinition] = [lpuCavite]

  public static func school(id: String) -> SchoolDefinition? {
    approved.first { $0.id == id && $0.isEnabled }
  }
}
