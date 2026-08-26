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

    public init(version: Int = 3, method: String, params: [String: PipoJSONValue]) {
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

public actor PipoCoreProcessTransport: PipoSidecarTransport {
    private let executableURL: URL
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrDrain: Task<Void, Never>?

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.defaultExecutableURL()
    }

    public func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        var finalError: Error = PipoCoreError.sidecarUnavailable
        var validResponse: SidecarResponse?
        for attempt in 0..<2 {
            do {
                try startIfNeeded()
                guard let stdin, let stdout else { throw PipoCoreError.sidecarUnavailable }
                stdin.write(try JSONEncoder().encode(request) + Data([0x0A]))
                let line = try readLine(from: stdout)
                let response = try JSONDecoder().decode(SidecarResponse.self, from: line)
                try response.validate(for: request)
                validResponse = response
                break
            } catch {
                finalError = error
                stopSession()
                if attempt == 1 { break }
            }
        }
        guard let response = validResponse else { throw finalError }
        if let failure = response.error { throw PipoCoreError.operationFailed(failure.message) }
        return response
    }

    public func shutdown() {
        stopSession()
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        stopSession()
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw PipoCoreError.sidecarUnavailable }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        self.process = process
        stdin = input.fileHandleForWriting
        stdout = output.fileHandleForReading
        let errorHandle = errors.fileHandleForReading
        stderrDrain = Task.detached(priority: .utility) {
            _ = try? errorHandle.readToEnd()
        }
    }

    private func readLine(from handle: FileHandle) throws -> Data {
        while true {
            if let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = Data(stdoutBuffer[..<newline])
                stdoutBuffer.removeSubrange(...newline)
                return line
            }
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { throw PipoCoreError.invalidResponse }
            stdoutBuffer.append(chunk)
            guard stdoutBuffer.count <= 8 * 1024 * 1024 else { throw PipoCoreError.invalidResponse }
        }
    }

    private func stopSession() {
        try? stdin?.close()
        try? stdout?.close()
        if process?.isRunning == true { process?.terminate() }
        stderrDrain?.cancel()
        stderrDrain = nil
        stdoutBuffer.removeAll(keepingCapacity: true)
        stdin = nil
        stdout = nil
        process = nil
    }

    nonisolated private static func defaultExecutableURL() -> URL {
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
