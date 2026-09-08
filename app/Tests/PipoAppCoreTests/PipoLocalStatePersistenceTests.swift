import Foundation
import Testing
@testable import PipoAppCore

@MainActor @Test func localMutationReportsUnsavedWhenStoreFails() async throws {
    let model = PipoModel(
        transport: LocalStateTransport(),
        tokenStore: LocalStateTokenStore(),
        refreshCoordinator: DashboardRefreshCoordinator(transport: LocalStateTransport(), cache: InMemoryDashboardCache()),
        localStateStore: FailingLocalStateStore(),
        notificationService: LocalStateNotifications(),
        destinationOpener: { _ in true }
    )
    await model.restore()
    let result = await model.markSeen("announcement")
    guard case .failed(let message) = result else { Issue.record("Expected unsaved mutation result"); return }
    #expect(message.contains("Saved only for this session"))
    #expect(model.localState.seenIDs.contains("announcement"))
}

private struct LocalStateTokenStore: PipoTokenStore {
    func token() throws -> String? { "token" }
    func save(token: String) throws {}
    func deleteToken() throws {}
}

private struct FailingLocalStateStore: AccountScopedLocalStateStore {
    func loadLocalState(accountID: String) async throws -> PipoLocalState { PipoLocalState() }
    func saveLocalState(_ state: PipoLocalState, accountID: String) async throws { throw PipoCoreError.operationFailed("disk unavailable") }
    func deleteLocalState(accountID: String) async throws {}
    func deleteAllLocalState() async throws {}
}

private struct LocalStateNotifications: PipoNotificationService {
    func requestAuthorization() async {}
    func deliver(_ payloads: [PipoNotificationPayload]) async {}
    func clear() {}
}

private struct LocalStateTransport: PipoSidecarTransport {
    func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        let result: PipoJSONValue
        if request.method == "authenticate_with_token" {
            result = .object(["token": .string("token"), "account_id": .number(7)])
        } else {
            let snapshot = DashboardSnapshot(generatedAt: "2026-09-08T00:00:00Z", siteName: "LPU", studentName: "Student", sections: DashboardSections(), courses: [])
            result = try JSONDecoder().decode(PipoJSONValue.self, from: JSONEncoder().encode(snapshot))
        }
        return SidecarResponse(version: request.version, id: request.id, result: result, error: nil)
    }
}
