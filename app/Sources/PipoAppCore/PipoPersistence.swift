import Foundation
import GRDB

public enum PipoPersistenceStatus: Equatable, Sendable {
  case ready
  case unavailable(String)

  public var canSave: Bool { self == .ready }
}

/// Owns the lifetime of disposable stores and the vault key used to open them.
/// A failed Keychain read never permanently selects a memory-only dependency.
public actor PipoPersistenceManager: AccountScopedDashboardCache, AccountScopedLocalStateStore {
  private let vault: KeychainSecureVault
  private let databaseURL: URL
  private var store: EncryptedDashboardCache?
  private var loadedKey: Data?
  private var snapshots: [String: DashboardSnapshot] = [:]
  private var states: [String: PipoLocalState] = [:]
  private var currentStatus: PipoPersistenceStatus = .unavailable(
    "Secure storage has not been opened.")

  public init(vault: KeychainSecureVault, databaseURL: URL) {
    self.vault = vault
    self.databaseURL = databaseURL
  }

  public func status() -> PipoPersistenceStatus { currentStatus }

  public func migrateAccount(from legacy: String, to scoped: String) throws {
    guard prepare().canSave, let store else {
      throw PipoCoreError.operationFailed(
        "Account storage cannot be migrated yet. Retry secure storage.")
    }
    try store.migrateAccount(from: legacy, to: scoped)
  }

  @discardableResult
  public func prepare() -> PipoPersistenceStatus {
    do {
      let key = try vault.cacheKey()
      if loadedKey != key || store == nil {
        try FileManager.default.createDirectory(
          at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        store = try EncryptedDashboardCache(databaseURL: databaseURL, keyData: key)
        loadedKey = key
      }
      if let store {
        for (account, snapshot) in snapshots { try store.save(snapshot, accountID: account) }
        for (account, state) in states { try store.saveLocalState(state, accountID: account) }
      }
      snapshots.removeAll()
      states.removeAll()
      currentStatus = .ready
    } catch {
      currentStatus = .unavailable("Changes cannot be saved. Retry secure storage.")
    }
    return currentStatus
  }

  public func load() async throws -> DashboardSnapshot? { try await load(accountID: "anonymous") }
  public func save(_ snapshot: DashboardSnapshot) async throws {
    try await save(snapshot, accountID: "anonymous")
  }

  public func load(accountID: String) async throws -> DashboardSnapshot? {
    if let value = snapshots[accountID] { return value }
    guard prepare().canSave, let store else { return nil }
    return try store.load(accountID: accountID)
  }

  public func save(_ snapshot: DashboardSnapshot, accountID: String) async throws {
    guard prepare().canSave, let store else {
      snapshots[accountID] = snapshot.privacyProjected()
      return
    }
    do { try store.save(snapshot, accountID: accountID) } catch {
      currentStatus = .unavailable("Changes cannot be saved. Retry secure storage.")
      snapshots[accountID] = snapshot.privacyProjected()
    }
  }

  public func delete() async throws {
    snapshots.removeAll()
    try erase(tables: ["pipo_cache", "pipo_cache_accounts"])
  }

  public func delete(accountID: String) async throws {
    snapshots[accountID] = nil
    try store?.delete(accountID: accountID)
  }

  public func loadLocalState(accountID: String) async throws -> PipoLocalState {
    if let value = states[accountID] { return value }
    guard prepare().canSave, let store else { return PipoLocalState() }
    return try store.loadLocalState(accountID: accountID)
  }

  public func saveLocalState(_ state: PipoLocalState, accountID: String) async throws {
    guard prepare().canSave, let store else {
      states[accountID] = state
      return
    }
    do { try store.saveLocalState(state, accountID: accountID) } catch {
      // Preserve the latest local intent for retry, while exposing unavailable status to callers.
      currentStatus = .unavailable("Changes cannot be saved. Retry secure storage.")
      states[accountID] = state
    }
  }

  public func deleteLocalState(accountID: String) async throws {
    states[accountID] = nil
    try store?.deleteLocalState(accountID: accountID)
  }

  public func deleteAllLocalState() async throws {
    states.removeAll()
    try erase(tables: ["pipo_local_state", "pipo_local_state_accounts"])
  }

  private func erase(tables: [String]) throws {
    guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
    let database = try DatabaseQueue(path: databaseURL.path)
    try database.write { db in
      for table in tables where try db.tableExists(table) {
        // Names come exclusively from the fixed table lists above.
        try db.execute(sql: "DELETE FROM \(table)")
      }
    }
  }

  /// Call only after sync/local writes have drained, before deleting vault.
  public func close() {
    store = nil
    loadedKey = nil
    snapshots.removeAll()
    states.removeAll()
    currentStatus = .unavailable("Sign in to open secure storage.")
  }
}
