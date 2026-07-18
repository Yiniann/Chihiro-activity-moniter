import Foundation

enum ConnectionState: String {
    case disconnected
    case connecting
    case connected

    var title: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "连接中"
        case .connected: "已连接"
        }
    }
}

struct AllowedApplication: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var bundleIdentifier: String
    var title: String

    init(id: UUID = UUID(), bundleIdentifier: String, title: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}

struct MonitorSettings: Codable, Equatable {
    var endpoint: String
    var allowlistedApplications: [AllowedApplication]
    var mediaEnabled: Bool
    var publishTrackTitle: Bool
    var publishArtist: Bool
    var publishSourceApplication: Bool
    var launchAtLogin: Bool

    init(
        endpoint: String,
        allowlistedApplications: [AllowedApplication],
        mediaEnabled: Bool,
        publishTrackTitle: Bool,
        publishArtist: Bool,
        publishSourceApplication: Bool = true,
        launchAtLogin: Bool
    ) {
        self.endpoint = endpoint
        self.allowlistedApplications = allowlistedApplications
        self.mediaEnabled = mediaEnabled
        self.publishTrackTitle = publishTrackTitle
        self.publishArtist = publishArtist
        self.publishSourceApplication = publishSourceApplication
        self.launchAtLogin = launchAtLogin
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case allowlistedApplications
        case mediaEnabled
        case publishTrackTitle
        case publishArtist
        case publishSourceApplication
        case launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? Self.defaults.endpoint
        allowlistedApplications = try container.decodeIfPresent([AllowedApplication].self, forKey: .allowlistedApplications) ?? []
        mediaEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaEnabled) ?? false
        publishTrackTitle = try container.decodeIfPresent(Bool.self, forKey: .publishTrackTitle) ?? true
        publishArtist = try container.decodeIfPresent(Bool.self, forKey: .publishArtist) ?? true
        publishSourceApplication = try container.decodeIfPresent(Bool.self, forKey: .publishSourceApplication) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    static let defaults = MonitorSettings(
        endpoint: "ws://127.0.0.1:3001/realtime/activity/agent",
        allowlistedApplications: [],
        mediaEnabled: false,
        publishTrackTitle: true,
        publishArtist: true,
        publishSourceApplication: true,
        launchAtLogin: false
    )
}

struct ForegroundApplication: Equatable {
    let bundleIdentifier: String
    let localizedName: String
}

enum NowPlayingMediaKind: String, Codable, Equatable {
    case music
    case video
    case media
}

struct NowPlayingActivity: Equatable {
    let kind: NowPlayingMediaKind
    let title: String
    let creator: String?
    let source: String?
    let sourceAppId: String?
}

struct PublicActivitySlot: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let appId: String?
    let title: String
    let subtitle: String?
    let source: String?
}

struct AgentHello: Codable, Equatable {
    let `protocol`: String
    let type: String
    let agentVersion: String
    let capabilities: [String]

    static let current = AgentHello(
        protocol: "activity.v1",
        type: "agent:hello",
        agentVersion: "0.1.0",
        capabilities: ["foreground-application", "now-playing", "application-icons"]
    )
}

struct AgentSnapshot: Codable, Equatable {
    let `protocol`: String
    let type: String
    let sequence: UInt64
    let slots: [PublicActivitySlot]

    init(sequence: UInt64, slots: [PublicActivitySlot]) {
        self.protocol = "activity.v1"
        self.type = "agent:snapshot"
        self.sequence = sequence
        self.slots = slots
    }
}

struct AgentHeartbeat: Encodable, Equatable {
    let `protocol` = "activity.v1"
    let type = "agent:heartbeat"
    let sequence: UInt64
}

struct ServerMessage: Decodable {
    let type: String
    let heartbeatInterval: Double?
    let stateTtl: Double?
    let iconSyncEndpoint: String?
    let code: String?
    let message: String?
}

struct ActivityEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case monitorStarted
        case connected
        case disconnected
        case snapshotSent
        case iconsSynced
        case paused
        case resumed

        var title: String {
            switch self {
            case .monitorStarted: "Agent 已启动"
            case .connected: "WebSocket 已连接"
            case .disconnected: "连接已断开"
            case .snapshotSent: "公开状态已上报"
            case .iconsSynced: "应用图标已同步"
            case .paused: "监测已暂停"
            case .resumed: "监测已恢复"
            }
        }

        var symbol: String {
            switch self {
            case .monitorStarted: "waveform"
            case .connected: "link"
            case .disconnected: "link.badge.plus"
            case .snapshotSent: "arrow.up.circle.fill"
            case .iconsSynced: "photo.badge.checkmark"
            case .paused: "pause.fill"
            case .resumed: "play.fill"
            }
        }
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let detail: String
    let sequence: UInt64?
    let slots: [PublicActivitySlot]?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        detail: String,
        sequence: UInt64? = nil,
        slots: [PublicActivitySlot]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.detail = detail
        self.sequence = sequence
        self.slots = slots
    }
}

struct PersistedActivity: Codable, Equatable {
    var events: [ActivityEvent]
    static let empty = PersistedActivity(events: [])
}
