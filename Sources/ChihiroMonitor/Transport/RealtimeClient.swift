import Foundation

@MainActor
final class RealtimeClient {
    var onStateChange: ((ConnectionState) -> Void)?
    var onReady: ((Double, Double, String?) -> Void)?
    var onError: ((String) -> Void)?

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var endpoint = ""
    private var token = ""
    private var shouldReconnect = false
    private var reconnectAttempt = 0

    func connect(endpoint: String, token: String) {
        disconnect(reconnect: false)
        guard let url = Self.normalizedEndpoint(endpoint) else {
            onError?("WebSocket 地址无效")
            return
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onError?("请先设置 Agent Token")
            return
        }

        self.endpoint = url.absoluteString
        self.token = token
        shouldReconnect = true
        open(url: url)
    }

    nonisolated static func normalizedEndpoint(_ input: String) -> URL? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard var components = URLComponents(string: value), components.host != nil else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        case "wss", "ws": break
        default: return nil
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/realtime/activity/agent"
        }
        return components.url
    }

    func disconnect(reconnect: Bool) {
        shouldReconnect = reconnect
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        onStateChange?(.disconnected)
    }

    func send<T: Encodable>(_ value: T) async throws {
        guard let socket else { throw RealtimeError.notConnected }
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else { throw RealtimeError.encodingFailed }
        try await socket.send(.string(text))
    }

    private func open(url: URL) {
        onStateChange?(.connecting)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("ChihiroActivityAgent/0.1.0", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()

        receiveTask = Task { [weak self, weak task] in
            guard let self, let task else { return }
            do {
                try await self.send(AgentHello.current)
                try await self.receiveMessages(from: task)
            } catch is CancellationError {
                return
            } catch {
                self.connectionFailed(error.localizedDescription)
            }
        }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) async throws {
        while !Task.isCancelled, socket === task {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let value): data = value
            @unknown default: continue
            }

            guard let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) else { continue }
            switch serverMessage.type {
            case "server:ready":
                reconnectAttempt = 0
                onStateChange?(.connected)
                onReady?(
                    serverMessage.heartbeatInterval ?? 30,
                    serverMessage.stateTtl ?? 90,
                    serverMessage.iconSyncEndpoint
                )
            case "server:error":
                let reason = serverMessage.message ?? serverMessage.code ?? "服务端拒绝了请求"
                onError?(reason)
            default:
                continue
            }
        }
    }

    private func connectionFailed(_ message: String) {
        socket = nil
        onStateChange?(.disconnected)
        onError?(message)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = min(60.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard self.shouldReconnect, let url = URL(string: self.endpoint) else { return }
            self.open(url: url)
        }
    }
}

enum RealtimeError: LocalizedError {
    case notConnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: "WebSocket 尚未连接"
        case .encodingFailed: "无法编码上报消息"
        }
    }
}
