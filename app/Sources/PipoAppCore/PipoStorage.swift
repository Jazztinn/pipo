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
        let box = try AES.GCM.SealedBox(combined: encrypted)
        let data = try AES.GCM.open(box, using: key)
        return try JSONDecoder().decode(DashboardSnapshot.self, from: data).privacyProjected()
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
