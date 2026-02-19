import Foundation
import Network
import os

/// Result from a successful OAuth callback.
struct OAuthCallbackResult: Sendable {
    let code: String
    let state: String
}

/// Thread-safe flag for guarding single-use continuations across @Sendable closures.
private final class ContinuationGuard: @unchecked Sendable {
    private var _resumed = false
    private let lock = NSLock()

    /// Returns true the first time called, false on subsequent calls. Thread-safe.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _resumed { return false }
        _resumed = true
        return true
    }

    var isResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _resumed
    }
}

/// Localhost HTTP server that receives the OAuth callback redirect.
/// Uses NWListener (Network framework) for zero-dependency TCP serving.
///
/// Usage:
/// ```
/// let server = OAuthCallbackServer(expectedState: state)
/// let port = try await server.start()
/// // ... open browser with redirect_uri using `port` ...
/// let result = try await server.waitForCallback()
/// ```
final class OAuthCallbackServer: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "oauth-callback"
    )

    /// Preferred port (matches OpenCode). Falls back to OS-assigned if unavailable.
    static let preferredPort: UInt16 = 19876

    /// Timeout for waiting for callback (5 minutes).
    static let callbackTimeout: TimeInterval = 300

    private var listener: NWListener?
    private let expectedState: String

    /// AsyncStream that receives incoming connections from the listener.
    /// Set before `start()` so the handler exists when the listener begins.
    private var connectionStream: AsyncStream<NWConnection>?
    private var connectionContinuation: AsyncStream<NWConnection>.Continuation?

    /// The actual port the server is bound to. Available after `start()` returns.
    private(set) var port: UInt16 = 0

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    /// Starts the listener and returns the bound port.
    /// Tries the preferred port first, falls back to OS-assigned.
    func start() async throws -> UInt16 {
        let nwListener = try await startListener()
        self.listener = nwListener

        Self.logger.info("OAuth callback server started on port \(self.port)")
        return port
    }

    /// Waits for the OAuth callback with a 5-minute timeout.
    /// Must be called after `start()`.
    func waitForCallback() async throws -> OAuthCallbackResult {
        guard let connectionStream else {
            throw AppError.oauthAuthorizationFailed("Server not started")
        }

        return try await withThrowingTaskGroup(of: OAuthCallbackResult.self) { group in
            group.addTask {
                try await self.processConnections(from: connectionStream)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.callbackTimeout))
                throw AppError.oauthCallbackTimeout
            }

            guard let result = try await group.next() else {
                throw AppError.oauthCallbackTimeout
            }
            group.cancelAll()
            self.stop()
            return result
        }
    }

    /// Stops the callback server and cleans up.
    func stop() {
        connectionContinuation?.finish()
        connectionContinuation = nil
        connectionStream = nil
        listener?.cancel()
        listener = nil
        Self.logger.info("OAuth callback server stopped")
    }

    // MARK: - Private

    private func startListener() async throws -> NWListener {
        // Try preferred port first
        do {
            return try await attemptStart(port: NWEndpoint.Port(integerLiteral: Self.preferredPort))
        } catch {
            Self.logger.info("Preferred port \(Self.preferredPort) unavailable, using OS-assigned port")
            return try await attemptStart(port: .any)
        }
    }

    private func attemptStart(port: NWEndpoint.Port) async throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: port)

        // NWListener REQUIRES newConnectionHandler to be set BEFORE start().
        // macOS enforces this — omitting it causes EINVAL (error 22).
        let (stream, continuation) = AsyncStream.makeStream(of: NWConnection.self)
        self.connectionStream = stream
        self.connectionContinuation = continuation

        listener.newConnectionHandler = { connection in
            continuation.yield(connection)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let guard_ = ContinuationGuard()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if guard_.tryResume() {
                        self?.port = listener.port?.rawValue ?? 0
                        cont.resume()
                    }
                case .failed(let error):
                    if guard_.tryResume() {
                        cont.resume(throwing: error)
                    }
                case .cancelled:
                    if guard_.tryResume() {
                        cont.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        return listener
    }

    /// Processes incoming connections from the stream until a valid callback is received.
    private func processConnections(from stream: AsyncStream<NWConnection>) async throws -> OAuthCallbackResult {
        for await connection in stream {
            do {
                let result = try await handleConnection(connection)
                return result
            } catch {
                // Connection processing failed — this could be state mismatch (fatal)
                // or just a malformed request (continue waiting for next connection)
                if error is AppError {
                    throw error // Propagate OAuth-specific errors (state mismatch)
                }
                // Ignore other errors and wait for next connection
            }
        }
        throw AppError.oauthCallbackTimeout
    }

    /// Handles a single incoming connection: reads HTTP request, validates, responds.
    private func handleConnection(_ connection: NWConnection) async throws -> OAuthCallbackResult {
        try await withCheckedThrowingContinuation { continuation in
            let guard_ = ContinuationGuard()

            connection.start(queue: .global(qos: .userInitiated))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
                guard let self else {
                    connection.cancel()
                    if guard_.tryResume() {
                        continuation.resume(throwing: CancellationError())
                    }
                    return
                }

                if let error {
                    if guard_.tryResume() {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let data, let request = String(data: data, encoding: .utf8) else {
                    self.sendErrorResponse(connection: connection, message: "Invalid request")
                    if guard_.tryResume() {
                        continuation.resume(throwing: URLError(.cannotParseResponse))
                    }
                    return
                }

                guard let queryParams = Self.parseHTTPRequest(request) else {
                    self.sendErrorResponse(connection: connection, message: "Invalid HTTP request")
                    if guard_.tryResume() {
                        continuation.resume(throwing: URLError(.cannotParseResponse))
                    }
                    return
                }

                guard let code = queryParams["code"] else {
                    self.sendErrorResponse(connection: connection, message: "Missing authorization code")
                    if guard_.tryResume() {
                        continuation.resume(throwing: URLError(.cannotParseResponse))
                    }
                    return
                }

                guard let state = queryParams["state"] else {
                    self.sendErrorResponse(connection: connection, message: "Missing state parameter")
                    if guard_.tryResume() {
                        continuation.resume(throwing: URLError(.cannotParseResponse))
                    }
                    return
                }

                // Validate state matches expected value (CSRF protection)
                guard state == self.expectedState else {
                    Self.logger.error("OAuth state mismatch — expected \(self.expectedState, privacy: .private), got \(state, privacy: .private)")
                    self.sendErrorResponse(connection: connection, message: "State parameter mismatch")
                    if guard_.tryResume() {
                        continuation.resume(throwing: AppError.oauthAuthorizationFailed("State parameter mismatch"))
                    }
                    return
                }

                self.sendSuccessResponse(connection: connection)

                Self.logger.info("OAuth callback received successfully")
                if guard_.tryResume() {
                    continuation.resume(returning: OAuthCallbackResult(code: code, state: state))
                }
            }
        }
    }

    // MARK: - HTTP Parsing

    /// Parses a raw HTTP GET request and extracts query parameters from `/callback`.
    /// Returns nil if the request is not a valid GET to /callback.
    static func parseHTTPRequest(_ request: String) -> [String: String]? {
        let lines = request.split(separator: "\r\n", maxSplits: 1)
        guard let firstLine = lines.first else { return nil }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }

        let path = String(parts[1])
        guard let urlComponents = URLComponents(string: path),
              urlComponents.path == "/callback" else { return nil }

        var params: [String: String] = [:]
        for item in urlComponents.queryItems ?? [] {
            params[item.name] = item.value
        }
        return params
    }

    // MARK: - HTTP Responses

    private func sendSuccessResponse(connection: NWConnection) {
        let html = "<html><body><h1>Authorization complete</h1><p>You can close this tab and return to cc-hdrm.</p></body></html>"
        sendHTTPResponse(connection: connection, statusCode: 200, body: html)
    }

    private func sendErrorResponse(connection: NWConnection, message: String) {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let html = "<html><body><h1>Authorization failed</h1><p>\(escaped)</p></body></html>"
        sendHTTPResponse(connection: connection, statusCode: 400, body: html)
    }

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, body: String) {
        let status = statusCode == 200 ? "200 OK" : "400 Bad Request"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"

        connection.send(content: response.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
