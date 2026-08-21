import Foundation

public enum PipoJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Int)
    case bool(Bool)
    case object([String: PipoJSONValue])
    case array([PipoJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: PipoJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([PipoJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct SidecarRequest: Codable, Sendable {
    public let version: Int
    public let id: String
    public let method: String
    public let params: [String: PipoJSONValue]

    public init(version: Int = 2, method: String, params: [String: PipoJSONValue]) {
        self.version = version
        self.id = UUID().uuidString
        self.method = method
        self.params = params
    }
}

public struct SidecarResponse: Codable, Sendable {
    public let version: Int
    public let id: String
    public let result: PipoJSONValue?
    public let error: SidecarFailure?

    public init(version: Int, id: String, result: PipoJSONValue?, error: SidecarFailure?) {
        self.version = version
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct SidecarFailure: Codable, Sendable {
    public let code: String
    public let message: String
}

public protocol PipoSidecarTransport: Sendable {
    func send(_ request: SidecarRequest) async throws -> SidecarResponse
}

public struct PipoCoreProcessTransport: PipoSidecarTransport {
    private let executableURL: URL

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.defaultExecutableURL()
    }

    public func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        let executableURL = executableURL
        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw PipoCoreError.sidecarUnavailable }
            let input = try JSONEncoder().encode(request) + Data([0x0A])
            let process = Process()
            process.executableURL = executableURL
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            stdin.fileHandleForWriting.write(input)
            try stdin.fileHandleForWriting.close()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw PipoCoreError.operationFailed(PipoSecrets.redact(String(decoding: errorData, as: UTF8.self)))
            }
            guard let line = data.split(separator: 0x0A).first else { throw PipoCoreError.invalidResponse }
            let response = try JSONDecoder().decode(SidecarResponse.self, from: Data(line))
            try response.validate(for: request)
            if let failure = response.error { throw PipoCoreError.operationFailed(failure.message) }
            return response
        }.value
    }

    private static func defaultExecutableURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["PIPO_CORE_PATH"], !configured.isEmpty { return URL(fileURLWithPath: configured) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pipo-core")
    }
}

extension SidecarResponse {
    func validate(for request: SidecarRequest) throws {
        guard version == request.version, id == request.id else {
            throw PipoCoreError.invalidResponse
        }
    }
}

extension PipoJSONValue {
    func objectValue() throws -> [String: PipoJSONValue] {
        guard case .object(let value) = self else { throw PipoCoreError.invalidResponse }
        return value
    }

    func stringValue() throws -> String {
        guard case .string(let value) = self else { throw PipoCoreError.invalidResponse }
        return value
    }

    func encodedData() throws -> Data { try JSONEncoder().encode(self) }
}
