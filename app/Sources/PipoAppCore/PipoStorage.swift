import CryptoKit
import Foundation
import GRDB
import Security

public protocol PipoTokenStore: Sendable {
    func token() throws -> String?
    func save(token: String) throws
    func deleteToken() throws
}

public final class KeychainTokenStore: PipoTokenStore, @unchecked Sendable {
    private let service = "com.jazztinn.pipo"
    private let account: String

    public init(account: String = "lms-access-token") { self.account = account }

    public func token() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else { throw PipoCoreError.operationFailed("Keychain read failed") }
        return token
    }

    public func save(token: String) throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw PipoCoreError.operationFailed("Keychain save failed") }
        } else if status != errSecSuccess { throw PipoCoreError.operationFailed("Keychain save failed") }
    }

    public func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PipoCoreError.operationFailed("Keychain deletion failed") }
    }

    private var baseQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock] }
}

public enum PipoSecureStorageStatus: Equatable, Sendable {
    case ready
    case accessDenied
    case unavailable(String)
}

public enum PipoSecureStorageError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case unavailable(String)
    case invalidVault

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "Secure storage access was denied."
        case .unavailable(let message): return message
        case .invalidVault: return "Secure storage data is invalid."
        }
    }
}

public protocol PipoKeychainBackend: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public struct PipoSystemKeychainBackend: PipoKeychainBackend {
    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw storageError(status) }
        return data
    }

    public func write(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw storageError(addStatus) }
        } else if status != errSecSuccess {
            throw storageError(status)
        }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError(status) }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }

    private func storageError(_ status: OSStatus) -> PipoSecureStorageError {
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return .accessDenied
        default:
            return .unavailable("Secure storage failed (\(status)).")
        }
    }
}

private struct PipoVaultRecord: Codable, Sendable {
    var token: String?
    var cacheKey: Data
}

public final class KeychainSecureVault: PipoTokenStore, @unchecked Sendable {
    private let backend: any PipoKeychainBackend
    private let service: String
    private let vaultAccount = "secure-vault-v1"
    private let legacyTokenAccount = "lms-access-token"
    private let legacyCacheKeyAccount = "pipo-cache-key"
    private let lock = NSLock()
    private var cachedRecord: PipoVaultRecord?
    private var deniedThisLaunch = false
    private var currentStatus: PipoSecureStorageStatus = .ready

    public init(backend: any PipoKeychainBackend = PipoSystemKeychainBackend(), service: String = "com.jazztinn.pipo") {
        self.backend = backend
        self.service = service
    }

    public var status: PipoSecureStorageStatus {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus
    }

    public func token() throws -> String? {
        try withRecord { $0.token }
    }

    public func cacheKey() throws -> Data {
        try withRecord { $0.cacheKey }
    }

    public func save(token: String) throws {
        guard !token.isEmpty else { throw PipoCoreError.operationFailed("Token is required.") }
        try withLock {
            let record = try loadRecordLocked(allowRetry: true)
            let updated = PipoVaultRecord(token: token, cacheKey: record.cacheKey)
            try writeRecordLocked(updated)
        }
    }

    public func deleteToken() throws {
        try withLock {
            try backend.delete(service: service, account: vaultAccount)
            try backend.delete(service: service, account: legacyTokenAccount)
            try backend.delete(service: service, account: legacyCacheKeyAccount)
            cachedRecord = nil
            deniedThisLaunch = false
            currentStatus = .ready
        }
    }

    @discardableResult
    public func retryAccess() -> PipoSecureStorageStatus {
        withLock {
            deniedThisLaunch = false
            cachedRecord = nil
            do {
                _ = try loadRecordLocked(allowRetry: true)
            } catch {
                updateStatusLocked(error)
            }
            return currentStatus
        }
    }

    private func withRecord<Value>(_ body: (PipoVaultRecord) -> Value) throws -> Value {
        try withLock { body(try loadRecordLocked(allowRetry: false)) }
    }

    private func loadRecordLocked(allowRetry: Bool) throws -> PipoVaultRecord {
        if let cachedRecord { return cachedRecord }
        if deniedThisLaunch && !allowRetry { throw PipoSecureStorageError.accessDenied }
        do {
            if let encoded = try backend.read(service: service, account: vaultAccount) {
                let record = try JSONDecoder().decode(PipoVaultRecord.self, from: encoded)
                guard record.cacheKey.count == 32 else { throw PipoSecureStorageError.invalidVault }
                cachedRecord = record
                currentStatus = .ready
                return record
            }
            let record = try migrateLegacyRecordLocked()
            try writeRecordLocked(record)
            return record
        } catch {
            updateStatusLocked(error)
            throw error
        }
    }

    private func migrateLegacyRecordLocked() throws -> PipoVaultRecord {
        let token = try backend.read(service: service, account: legacyTokenAccount).flatMap { String(data: $0, encoding: .utf8) }
        // Legacy cache-key access can trigger an additional Keychain prompt. The old
        // encrypted cache is disposable; generate a fresh vault-owned key instead.
        return PipoVaultRecord(token: token, cacheKey: try Self.newCacheKey())
    }

    private func writeRecordLocked(_ record: PipoVaultRecord) throws {
        let encoded = try JSONEncoder().encode(record)
        try backend.write(encoded, service: service, account: vaultAccount)
        try backend.delete(service: service, account: legacyTokenAccount)
        cachedRecord = record
        deniedThisLaunch = false
        currentStatus = .ready
    }

    private func updateStatusLocked(_ error: Error) {
        if let error = error as? PipoSecureStorageError {
            switch error {
            case .accessDenied:
                deniedThisLaunch = true
                currentStatus = .accessDenied
            case .unavailable(let message): currentStatus = .unavailable(message)
            case .invalidVault: currentStatus = .unavailable(error.localizedDescription)
            }
        } else {
            currentStatus = .unavailable(error.localizedDescription)
        }
    }

    private func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func newCacheKey() throws -> Data {
        var key = Data(repeating: 0, count: 32)
        let status = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PipoSecureStorageError.unavailable("Secure random generation failed (\(status)).")
        }
        return key
    }
}

public protocol DashboardCache: Sendable {
    func load() async throws -> DashboardSnapshot?
    func save(_ snapshot: DashboardSnapshot) async throws
    func delete() async throws
}

public actor EncryptedDashboardCache: DashboardCache {
    private let database: DatabaseQueue
    private let key: SymmetricKey

    public init(databaseURL: URL, keyData: Data) throws {
        guard keyData.count == 32 else { throw PipoCoreError.operationFailed("Cache key is invalid") }
        database = try DatabaseQueue(path: databaseURL.path)
        key = SymmetricKey(data: keyData)
        try database.write { database in
            try database.execute(sql: "CREATE TABLE IF NOT EXISTS pipo_cache (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL)")
        }
    }

    public func load() throws -> DashboardSnapshot? {
        let encrypted: Data? = try database.read { database in try Data.fetchOne(database, sql: "SELECT payload FROM pipo_cache WHERE id = 1") }
        guard let encrypted else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let data = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode(DashboardSnapshot.self, from: data).privacyProjected()
        } catch {
            // Cache data is disposable. A key rotation or interrupted migration
            // must not block sign-in or surface a CryptoKit error to the user.
            try database.write { database in
                try database.execute(sql: "DELETE FROM pipo_cache")
            }
            return nil
        }
    }

    public func save(_ snapshot: DashboardSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot.privacyProjected())
        let encrypted = try AES.GCM.seal(data, using: key).combined.unwrap(or: PipoCoreError.operationFailed("Cache encryption failed"))
        try database.write { database in try database.execute(sql: "INSERT INTO pipo_cache (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [encrypted]) }
    }

    public func delete() throws {
        try database.write { database in try database.execute(sql: "DELETE FROM pipo_cache") }
    }
}

extension Optional where Wrapped == Data {
    func unwrap(or error: Error) throws -> Data { guard let self else { throw error }; return self }
}
