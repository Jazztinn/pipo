import Foundation
import Testing
@testable import PipoAppCore

@Test func approvedRegistryContainsOnlyEnabledLPUCavite() {
    #expect(SchoolRegistry.approved == [SchoolRegistry.lpuCavite])
    #expect(SchoolRegistry.lpuCavite.providerID == .moodle)
    #expect(SchoolRegistry.lpuCavite.apiOrigin.absoluteString == "https://lms.lpucavite.edu.ph")
    #expect(SchoolRegistry.lpuCavite.browserOrigin.absoluteString == "https://lms.lpucavite.edu.ph")
    #expect(SchoolRegistry.lpuCavite.authorizationOrigin.absoluteString == "https://lms.lpucavite.edu.ph")
    #expect(SchoolRegistry.lpuCavite.timeZoneID == "Asia/Manila")
    #expect(SchoolRegistry.school(id: "unapproved") == nil)
}

@MainActor @Test func canvasOAuthRejectsApprovedNonCanvasSchool() throws {
    let scope = AccountScope(providerID: .canvas, schoolID: "lpu-cavite", originID: "lpu", remoteAccountID: try EntityID(remoteID: "remote-user"))
    #expect(throws: OAuthError.unsupportedSchool) {
        try CanvasOAuthService(schoolID: "lpu-cavite", scope: scope)
    }
}

@Test func scopedOAuthRecordsDoNotShareKeychainEntry() throws {
    let backend = OAuthTestKeychain()
    let store = KeychainOAuthTokenStore(backend: backend)
    let first = AccountScope(providerID: .canvas, schoolID: "first", originID: "origin", remoteAccountID: try EntityID(remoteID: "same-user"))
    let second = AccountScope(providerID: .canvas, schoolID: "second", originID: "origin", remoteAccountID: try EntityID(remoteID: "same-user"))
    try store.save(OAuthTokenRecord(accessToken: "one", refreshToken: "rotate", expiresAt: .now), scope: first)
    #expect(try store.load(scope: second) == nil)
    #expect(try store.load(scope: first)?.accessToken == "one")
}

@Test func scopeStorageIDIsStableAndProviderIsolated() throws {
    let remote = try EntityID(remoteID: "canvas-user-7")
    let one = AccountScope(providerID: .canvas, schoolID: "school", originID: "one", remoteAccountID: remote)
    let same = AccountScope(providerID: .canvas, schoolID: "school", originID: "one", remoteAccountID: try EntityID(remoteID: "canvas-user-7"))
    let otherProvider = AccountScope(providerID: .moodle, schoolID: "school", originID: "one", remoteAccountID: remote)
    #expect(one.storageID == same.storageID)
    #expect(one.storageID != otherProvider.storageID)
}

@Test func formEncodingEscapesReservedCharacters() {
    #expect(oauthFormEncode(["v": "a&b+c=d /ü"]) == "v=a%26b%2Bc%3Dd%20%2F%C3%BC")
}

@MainActor @Test func canvasFlowValidatesStateAndIsSingleUse() async throws {
    let scope = AccountScope(providerID: .canvas, schoolID: "fixture", originID: "fixture-origin", remoteAccountID: try EntityID(remoteID: "student"))
    let browser = OAuthTestBrowser()
    let client = OAuthTestClient()
    let service = try CanvasOAuthService(testSchool: canvasFixture, scope: scope, store: KeychainOAuthTokenStore(backend: OAuthTestKeychain()), client: client, browser: browser)
    let request = service.makeAuthorizationRequest()
    let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    browser.callback = URL(string: "pipo://oauth/callback?state=wrong&code=code")!
    await #expect(throws: OAuthError.stateMismatch) { try await service.authorize(request) }
    await #expect(throws: OAuthError.requestExpired) { try await service.authorize(request) }
}

@MainActor @Test func expiredTokensRefreshOnceAndPersistRotatedToken() async throws {
    let scope = AccountScope(providerID: .canvas, schoolID: "fixture", originID: "fixture-origin", remoteAccountID: try EntityID(remoteID: "student"))
    let backend = OAuthTestKeychain()
    let store = KeychainOAuthTokenStore(backend: backend)
    try store.save(OAuthTokenRecord(accessToken: "old", refreshToken: "rotate-me", expiresAt: .now.addingTimeInterval(-1)), scope: scope)
    let client = CountingOAuthClient()
    let service = try CanvasOAuthService(testSchool: canvasFixture, scope: scope, store: store, client: client, browser: OAuthTestBrowser())
    async let first = service.bearerToken()
    async let second = service.bearerToken()
    #expect(try await first == "fresh")
    #expect(try await second == "fresh")
    #expect(client.refreshCount == 1)
    #expect(try store.load(scope: scope)?.refreshToken == "rotated")
}

private let canvasFixture = SchoolDefinition(
    id: "fixture", providerID: .canvas,
    apiOrigin: URL(string: "https://api.fixture.example")!,
    browserOrigin: URL(string: "https://browser.fixture.example")!,
    authorizationOrigin: URL(string: "https://auth.fixture.example")!,
    timeZoneID: "Asia/Manila", isEnabled: true, canvasClientID: "public-client"
)

@MainActor private final class OAuthTestBrowser: OAuthBrowserSession {
    var callback = URL(string: "pipo://oauth/callback?state=unset&code=code")!
    func authenticate(url: URL, callbackScheme: String) async throws -> URL { callback }
    func cancel() {}
}

private final class OAuthTestClient: OAuthTokenClient, @unchecked Sendable {
    func exchange(code: String, verifier: String, redirectURL: URL, school: SchoolDefinition) async throws -> OAuthTokenRecord { OAuthTokenRecord(accessToken: "access", refreshToken: "refresh", expiresAt: .now.addingTimeInterval(3600)) }
    func refresh(refreshToken: String, school: SchoolDefinition) async throws -> OAuthTokenRecord { OAuthTokenRecord(accessToken: "fresh", refreshToken: "rotated", expiresAt: .now.addingTimeInterval(3600)) }
}

private final class CountingOAuthClient: OAuthTokenClient, @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var refreshCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func exchange(code: String, verifier: String, redirectURL: URL, school: SchoolDefinition) async throws -> OAuthTokenRecord { throw OAuthError.tokenResponse }
    func refresh(refreshToken: String, school: SchoolDefinition) async throws -> OAuthTokenRecord {
        lock.withLock { count += 1 }
        try await Task.sleep(for: .milliseconds(20))
        return OAuthTokenRecord(accessToken: "fresh", refreshToken: "rotated", expiresAt: .now.addingTimeInterval(3600))
    }
}

private final class OAuthTestKeychain: PipoKeychainBackend, @unchecked Sendable {
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { values["\(service)/\(account)"] }
    func write(_ data: Data, service: String, account: String) throws { values["\(service)/\(account)"] = data }
    func delete(service: String, account: String) throws { values.removeValue(forKey: "\(service)/\(account)") }
}
