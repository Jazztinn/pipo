import Foundation
import Darwin

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

    public init(version: Int = 4, method: String, params: [String: PipoJSONValue]) {
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
    func shutdown() async
}

public extension PipoSidecarTransport {
    func shutdown() async {}
}

public actor PipoCoreProcessTransport: PipoSidecarTransport {
    private let executableURL: URL
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrDrain: Task<Void, Never>?
    private var pending: [String: PendingResponse] = [:]
    private var processGeneration: UInt64 = 0
    private var didHandshake = false
    private var startupTask: Task<Void, Error>?
    private var requestInProgress = false
    private var sendWaiters: [(id: String, continuation: CheckedContinuation<Void, Error>)] = []

    private struct PendingResponse {
        let continuation: CheckedContinuation<SidecarResponse, Error>
        let timeout: Task<Void, Never>
    }

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.defaultExecutableURL()
    }

    public func send(_ request: SidecarRequest) async throws -> SidecarResponse {
        guard request.version == 4 else { throw PipoCoreError.invalidResponse }
        try await acquireRequestSlot(id: request.id)
        defer { releaseRequestSlot() }
        try Task.checkCancellation()
        try await startIfNeeded()
        try Task.checkCancellation()
        let timeout: TimeInterval = request.method == "refresh_dashboard" ? 50 : request.method == "load_course" ? 35 : 25
        let response = try await sendWrittenRequest(request, timeout: timeout)
        if let failure = response.error { throw failure.classifiedError }
        return response
    }

    public func shutdown() async {
        stopSession()
        let waiters = sendWaiters
        sendWaiters.removeAll()
        for waiter in waiters { waiter.continuation.resume(throwing: CancellationError()) }
    }

    private func acquireRequestSlot(id: String) async throws {
        if !requestInProgress {
            requestInProgress = true
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sendWaiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelSendWaiter(id: id) }
        }
    }

    private func cancelSendWaiter(id: String) {
        guard let index = sendWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = sendWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseRequestSlot() {
        if sendWaiters.isEmpty {
            requestInProgress = false
        } else {
            let waiter = sendWaiters.removeFirst()
            waiter.continuation.resume()
        }
    }

    private func startIfNeeded() async throws {
        if process?.isRunning == true, didHandshake { return }
        if let startupTask {
            try await startupTask.value
            return
        }
        let task = Task { try await self.launchAndHandshake() }
        startupTask = task
        defer { startupTask = nil }
        try await task.value
    }

    private func launchAndHandshake() async throws {
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
        let generation = processGeneration
        stdin = input.fileHandleForWriting
        stdout = output.fileHandleForReading
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.consume(data, generation: generation) }
        }
        let errorHandle = errors.fileHandleForReading
        stderrDrain = Task.detached(priority: .utility) {
            _ = try? errorHandle.readToEnd()
        }
        let hello = SidecarRequest(
            method: "hello",
            params: ["wire_protocol": .number(4), "snapshot_schema": .number(3)]
        )
        do {
            let response = try await sendWrittenRequest(hello, timeout: 10)
            guard response.error == nil,
                  let result = response.result,
                  case .object(let object) = result,
                  object["wire_protocol"] == .number(4)
            else { throw PipoCoreError.invalidResponse }
            didHandshake = true
        } catch {
            stopSession(error: error)
            throw error
        }
    }

    private func sendWrittenRequest(_ request: SidecarRequest, timeout: TimeInterval) async throws -> SidecarResponse {
        guard let stdin, process?.isRunning == true else { throw PipoCoreError.sidecarUnavailable }
        try Task.checkCancellation()
        let payload = try JSONEncoder().encode(request) + Data([0x0A])
        guard payload.count <= 2 * 1024 * 1024 else { throw PipoCoreError.invalidResponse }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    await self?.timeout(requestID: request.id)
                }
                pending[request.id] = PendingResponse(continuation: continuation, timeout: timeoutTask)
                do {
                    try stdin.write(contentsOf: payload)
                } catch {
                    pending.removeValue(forKey: request.id)?.timeout.cancel()
                    continuation.resume(throwing: PipoCoreError.sidecarUnavailable)
                    stopSession(error: PipoCoreError.sidecarUnavailable)
                }
            }
        } onCancel: {
            Task { await self.cancel(requestID: request.id) }
        }
    }

    private func consume(_ data: Data, generation: UInt64) {
        guard generation == processGeneration else { return }
        guard !data.isEmpty else {
            stopSession(error: PipoCoreError.sidecarUnavailable)
            return
        }
        stdoutBuffer.append(data)
        guard stdoutBuffer.count <= 2 * 1024 * 1024 else {
            stopSession(error: PipoCoreError.invalidResponse)
            return
        }
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[..<newline])
            stdoutBuffer.removeSubrange(...newline)
            guard let response = try? JSONDecoder().decode(SidecarResponse.self, from: line),
                  response.version == 4,
                  let pendingResponse = pending.removeValue(forKey: response.id)
            else {
                stopSession(error: PipoCoreError.invalidResponse)
                return
            }
            pendingResponse.timeout.cancel()
            pendingResponse.continuation.resume(returning: response)
        }
    }

    private func timeout(requestID: String) {
        guard let pendingResponse = pending.removeValue(forKey: requestID) else { return }
        pendingResponse.timeout.cancel()
        pendingResponse.continuation.resume(throwing: PipoCoreError.timedOut)
        stopSession(error: PipoCoreError.timedOut)
    }

    private func cancel(requestID: String) {
        guard let pendingResponse = pending.removeValue(forKey: requestID) else { return }
        pendingResponse.timeout.cancel()
        pendingResponse.continuation.resume(throwing: CancellationError())
        // Rust cannot cancel a written request. End this process before another
        // request can acquire the slot and observe its late reply.
        stopSession(error: CancellationError())
    }

    private func stopSession(error: Error = PipoCoreError.sidecarUnavailable) {
        processGeneration &+= 1
        stdout?.readabilityHandler = nil
        try? stdin?.close()
        try? stdout?.close()
        if process?.isRunning == true { process?.terminate() }
        stderrDrain?.cancel()
        stderrDrain = nil
        stdoutBuffer.removeAll(keepingCapacity: true)
        stdin = nil
        stdout = nil
        process = nil
        didHandshake = false
        let waiting = pending.values
        pending.removeAll()
        for response in waiting {
            response.timeout.cancel()
            response.continuation.resume(throwing: error)
        }
    }

    nonisolated private static func defaultExecutableURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["PIPO_CORE_PATH"], !configured.isEmpty { return URL(fileURLWithPath: configured) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pipo-core")
    }
}

private extension SidecarFailure {
    var classifiedError: PipoCoreError {
        switch code {
        case "authentication_failed": .authenticationRequired
        case "network_failed": .networkUnavailable
        case "timeout": .timedOut
        case "rate_limited": .rateLimited
        case "invalid_response": .malformedServiceResponse
        case "service_unavailable": .serviceUnavailable
        default: .operationFailed(PipoSecrets.redact(message))
        }
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
