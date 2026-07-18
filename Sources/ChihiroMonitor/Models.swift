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

struct NowPlayingArtwork: Equatable {
    let data: Data
    let identifier: String?
}

struct NowPlayingActivity: Equatable {
    let kind: NowPlayingMediaKind
    let title: String
    let creator: String?
    let source: String?
    let sourceAppId: String?
    let positionSeconds: Double?
    let durationSeconds: Double?
    let playbackRate: Double?
    let positionUpdatedAt: Date?
    let artwork: NowPlayingArtwork?
    var artworkHash: String?

    init(
        kind: NowPlayingMediaKind,
        title: String,
        creator: String?,
        source: String?,
        sourceAppId: String?,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        playbackRate: Double? = nil,
        positionUpdatedAt: Date? = nil,
        artwork: NowPlayingArtwork? = nil,
        artworkHash: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.creator = creator
        self.source = source
        self.sourceAppId = sourceAppId
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.playbackRate = playbackRate
        self.positionUpdatedAt = positionUpdatedAt
        self.artwork = artwork
        self.artworkHash = artworkHash
    }

    static func requiresPublication(
        from previous: NowPlayingActivity?,
        to next: NowPlayingActivity?
    ) -> Bool {
        guard let previous, let next else { return previous != next }
        guard previous.kind == next.kind,
              previous.title == next.title,
              previous.creator == next.creator,
              previous.source == next.source,
              previous.sourceAppId == next.sourceAppId,
              previous.artworkHash == next.artworkHash else { return true }
        if differs(previous.durationSeconds, next.durationSeconds, tolerance: 0.5)
            || differs(previous.playbackRate, next.playbackRate, tolerance: 0.01) {
            return true
        }

        switch (previous.positionSeconds, next.positionSeconds) {
        case (nil, nil):
            return false
        case let (previousPosition?, nextPosition?):
            let elapsed = max(
                0,
                next.positionUpdatedAt?.timeIntervalSince(
                    previous.positionUpdatedAt ?? next.positionUpdatedAt ?? .distantPast
                ) ?? 0
            )
            let expectedPosition = previousPosition + elapsed * (previous.playbackRate ?? 0)
            return abs(nextPosition - expectedPosition) >= 2
        default:
            return true
        }
    }

    func preservingConfirmedArtwork(from previous: NowPlayingActivity?) -> NowPlayingActivity {
        guard let previous, let artwork, previous.artwork == artwork else { return self }
        var value = self
        value.artworkHash = previous.artworkHash
        return value
    }

    private static func differs(_ left: Double?, _ right: Double?, tolerance: Double) -> Bool {
        switch (left, right) {
        case (nil, nil): false
        case let (left?, right?): abs(left - right) > tolerance
        default: true
        }
    }
}

struct PublicActivitySlot: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let appId: String?
    let title: String
    let subtitle: String?
    let source: String?
    let positionSeconds: Double?
    let durationSeconds: Double?
    let playbackRate: Double?
    let positionUpdatedAt: Int64?
    let artworkHash: String?

    init(
        id: String,
        kind: String,
        appId: String?,
        title: String,
        subtitle: String?,
        source: String?,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        playbackRate: Double? = nil,
        positionUpdatedAt: Int64? = nil,
        artworkHash: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.appId = appId
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.playbackRate = playbackRate
        self.positionUpdatedAt = positionUpdatedAt
        self.artworkHash = artworkHash
    }
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
        capabilities: [
            "foreground-application",
            "now-playing",
            "now-playing-progress",
            "application-icons",
            "now-playing-artwork"
        ]
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
    let artworkSyncEndpoint: String?
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
        case artworkSynced
        case paused
        case resumed

        var title: String {
            switch self {
            case .monitorStarted: "Agent 已启动"
            case .connected: "WebSocket 已连接"
            case .disconnected: "连接已断开"
            case .snapshotSent: "公开状态已上报"
            case .iconsSynced: "应用图标已同步"
            case .artworkSynced: "播放封面已同步"
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
            case .artworkSynced: "photo.on.rectangle.angled"
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
