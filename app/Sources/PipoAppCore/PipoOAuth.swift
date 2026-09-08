import AuthenticationServices
import CryptoKit
import Foundation
import Security

public enum OAuthError: Error, Equatable, Sendable {
  case unsupportedSchool, invalidCallback, stateMismatch, tokenResponse, missingRefreshToken,
    requestExpired, cancelled
}

public struct OAuthAuthorizationRequest: Sendable {
  public let url: URL
  public let callbackURL: URL
  fileprivate let state: String
  fileprivate let verifier: String
  fileprivate let serviceID: UUID
  fileprivate let requestID: UUID
}

public struct OAuthTokenRecord: Codable, Equatable, Sendable {
  public let accessToken: String
  public let refreshToken: String?
  public let expiresAt: Date
}

public protocol OAuthTokenStore: Sendable {
  func load(scope: AccountScope) throws -> OAuthTokenRecord?
  func save(_ record: OAuthTokenRecord, scope: AccountScope) throws
  func delete(scope: AccountScope) throws
}

public final class KeychainOAuthTokenStore: OAuthTokenStore, @unchecked Sendable {
  private let backend: any PipoKeychainBackend
  private let service: String

  public init(
    backend: any PipoKeychainBackend = PipoSystemKeychainBackend(),
    service: String = "com.jazztinn.pipo.oauth"
  ) {
    self.backend = backend
    self.service = service
  }

  public func load(scope: AccountScope) throws -> OAuthTokenRecord? {
    guard let data = try backend.read(service: service, account: scope.keychainAccount) else {
      return nil
    }
    return try JSONDecoder().decode(OAuthTokenRecord.self, from: data)
  }

  public func save(_ record: OAuthTokenRecord, scope: AccountScope) throws {
    try backend.write(
      JSONEncoder().encode(record), service: service, account: scope.keychainAccount)
  }

  public func delete(scope: AccountScope) throws {
    try backend.delete(service: service, account: scope.keychainAccount)
  }
}

public protocol OAuthTokenClient: Sendable {
  func exchange(code: String, verifier: String, redirectURL: URL, school: SchoolDefinition)
    async throws -> OAuthTokenRecord
  func refresh(refreshToken: String, school: SchoolDefinition) async throws -> OAuthTokenRecord
}

@MainActor
public protocol OAuthBrowserSession: AnyObject, Sendable {
  @MainActor func authenticate(url: URL, callbackScheme: String) async throws -> URL
  @MainActor func cancel()
}

@MainActor
public final class SystemOAuthBrowserSession: NSObject, OAuthBrowserSession {
  private var activeSession: ASWebAuthenticationSession?

  public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) {
        callbackURL, error in
        self.activeSession = nil
        if let callbackURL {
          continuation.resume(returning: callbackURL)
        } else {
          continuation.resume(throwing: error ?? OAuthError.invalidCallback)
        }
      }
      session.presentationContextProvider = self
      self.activeSession = session
      if !session.start() {
        self.activeSession = nil
        continuation.resume(throwing: OAuthError.invalidCallback)
      }
    }
  }

  public func cancel() {
    activeSession?.cancel()
    activeSession = nil
  }
}

extension SystemOAuthBrowserSession: ASWebAuthenticationPresentationContextProviding {
  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    ASPresentationAnchor()
  }
}

public struct URLSessionOAuthTokenClient: OAuthTokenClient {
  public init() {}

  public func exchange(code: String, verifier: String, redirectURL: URL, school: SchoolDefinition)
    async throws -> OAuthTokenRecord
  {
    try await request(
      [
        "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
        "redirect_uri": redirectURL.absoluteString,
      ], school: school)
  }

  public func refresh(refreshToken: String, school: SchoolDefinition) async throws
    -> OAuthTokenRecord
  {
    try await request(
      ["grant_type": "refresh_token", "refresh_token": refreshToken], school: school)
  }

  private func request(_ values: [String: String], school: SchoolDefinition) async throws
    -> OAuthTokenRecord
  {
    guard school.providerID == .canvas, let clientID = school.canvasClientID else {
      throw OAuthError.unsupportedSchool
    }
    let endpoint = school.apiOrigin.appending(path: "login/oauth2/token")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = oauthFormEncode(values.merging(["client_id": clientID]) { $1 }).data(
      using: .utf8)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 10
    let delegate = RejectRedirects()
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OAuthError.tokenResponse }
    guard data.count <= 16 * 1024, response.url == endpoint else { throw OAuthError.tokenResponse }
    let token = try JSONDecoder().decode(CanvasToken.self, from: data)
    guard !token.accessToken.isEmpty, token.expiresIn.isFinite, token.expiresIn > 0 else {
      throw OAuthError.tokenResponse
    }
    return OAuthTokenRecord(
      accessToken: token.accessToken, refreshToken: token.refreshToken,
      expiresAt: .now.addingTimeInterval(max(0, token.expiresIn)))
  }

}

@MainActor
public final class CanvasOAuthService {
  private let school: SchoolDefinition
  public let scope: AccountScope
  private let store: any OAuthTokenStore
  private let client: any OAuthTokenClient
  private let browser: any OAuthBrowserSession
  private var refreshTask: Task<OAuthTokenRecord, Error>?
  private let serviceID = UUID()
  private var activeRequests: Set<UUID> = []
  private var generation = 0

  public init(
    schoolID: String, scope: AccountScope, store: any OAuthTokenStore = KeychainOAuthTokenStore(),
    client: any OAuthTokenClient = URLSessionOAuthTokenClient(),
    browser: any OAuthBrowserSession = SystemOAuthBrowserSession()
  ) throws {
    guard let school = SchoolRegistry.school(id: schoolID), school.providerID == .canvas,
      school.canvasClientID != nil, scope.schoolID == schoolID, scope.providerID == .canvas
    else { throw OAuthError.unsupportedSchool }
    self.school = school
    self.scope = scope
    self.store = store
    self.client = client
    self.browser = browser
  }

  // Internal test seam. Production entry point above always resolves bundled registry.
  init(
    testSchool school: SchoolDefinition, scope: AccountScope, store: any OAuthTokenStore,
    client: any OAuthTokenClient, browser: any OAuthBrowserSession
  ) throws {
    guard school.providerID == .canvas, school.isEnabled, school.canvasClientID != nil,
      scope.schoolID == school.id, scope.providerID == .canvas
    else { throw OAuthError.unsupportedSchool }
    self.school = school
    self.scope = scope
    self.store = store
    self.client = client
    self.browser = browser
  }

  public func makeAuthorizationRequest() -> OAuthAuthorizationRequest {
    let state = randomURLSafeString()
    let verifier = randomURLSafeString()
    let callbackURL = URL(string: "pipo://oauth/callback")!
    var components = URLComponents(
      url: school.authorizationOrigin.appending(path: "login/oauth2/auth"),
      resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: school.canvasClientID),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: pkceChallenge(verifier)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    let requestID = UUID()
    activeRequests.insert(requestID)
    return OAuthAuthorizationRequest(
      url: components.url!, callbackURL: callbackURL, state: state, verifier: verifier,
      serviceID: serviceID, requestID: requestID)
  }

  public func authorize(_ request: OAuthAuthorizationRequest) async throws -> OAuthTokenRecord {
    guard request.serviceID == serviceID, activeRequests.remove(request.requestID) != nil else {
      throw OAuthError.requestExpired
    }
    let startGeneration = generation
    let callback = try await withTaskCancellationHandler(
      operation: {
        try await browser.authenticate(
          url: request.url, callbackScheme: request.callbackURL.scheme!)
      }, onCancel: { [weak browser] in Task { @MainActor in browser?.cancel() } })
    try Task.checkCancellation()
    guard callback.scheme == request.callbackURL.scheme, callback.host == request.callbackURL.host,
      callback.path == request.callbackURL.path, callback.user == nil, callback.password == nil,
      callback.port == nil, callback.fragment == nil
    else { throw OAuthError.invalidCallback }
    let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard !values.contains(where: { $0.name == "error" }),
      values.filter({ $0.name == "state" }).count == 1,
      values.filter({ $0.name == "code" }).count == 1
    else { throw OAuthError.invalidCallback }
    guard values.first(where: { $0.name == "state" })?.value == request.state else {
      throw OAuthError.stateMismatch
    }
    guard let code = values.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
      throw OAuthError.invalidCallback
    }
    let token = try await client.exchange(
      code: code, verifier: request.verifier, redirectURL: request.callbackURL, school: school)
    try Task.checkCancellation()
    guard generation == startGeneration else { throw OAuthError.cancelled }
    try store.save(token, scope: scope)
    return token
  }

  public func bearerToken() async throws -> String {
    guard let record = try store.load(scope: scope) else { throw OAuthError.missingRefreshToken }
    if record.expiresAt > .now.addingTimeInterval(60) { return record.accessToken }
    return try await refresh(record).accessToken
  }

  private func refresh(_ record: OAuthTokenRecord) async throws -> OAuthTokenRecord {
    if let refreshTask { return try await refreshTask.value }
    guard let refreshToken = record.refreshToken else { throw OAuthError.missingRefreshToken }
    let client = client
    let school = school
    let store = store
    let scope = scope
    let startGeneration = generation
    let task = Task { () throws -> OAuthTokenRecord in
      let fresh = try await client.refresh(refreshToken: refreshToken, school: school)
      guard let rotated = fresh.refreshToken, !rotated.isEmpty,
        fresh.expiresAt.timeIntervalSinceReferenceDate.isFinite
      else { throw OAuthError.tokenResponse }
      try Task.checkCancellation()
      guard self.generation == startGeneration else { throw OAuthError.cancelled }
      try store.save(fresh, scope: scope)
      return fresh
    }
    refreshTask = task
    defer { refreshTask = nil }
    return try await task.value
  }

  public func revokeLocalCredentials() throws {
    generation += 1
    activeRequests.removeAll()
    browser.cancel()
    refreshTask?.cancel()
    refreshTask = nil
    try store.delete(scope: scope)
  }
}

private struct CanvasToken: Decodable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: TimeInterval
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
  }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private func randomURLSafeString() -> String {
  var bytes = [UInt8](repeating: 0, count: 32)
  precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
  return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

private func pkceChallenge(_ verifier: String) -> String {
  Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(
    of: "+", with: "-"
  ).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

extension String {
  fileprivate var formEscaped: String {
    let allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return unicodeScalars.map { scalar in
      allowed.contains(scalar)
        ? String(scalar) : String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
    }.joined()
  }
}

func oauthFormEncode(_ values: [String: String]) -> String {
  values.map { key, value in "\(key.formEscaped)=\(value.formEscaped)" }.sorted().joined(
    separator: "&")
}
