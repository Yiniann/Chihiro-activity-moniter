import Foundation
import Testing
@testable import ChihiroMonitor

struct ActivityAgentTests {
    @Test func storeRoundTripsEvents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("activity.json")
        let store = ActivityStore(fileURL: url)
        let value = PersistedActivity(events: [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1_784_182_800), kind: .connected, detail: "测试")
        ])

        try store.save(value)

        #expect(store.load() == value)
    }

    @Test func storeRoundTripsReportedSnapshotDetails() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("activity.json")
        let store = ActivityStore(fileURL: url)
        let slots = [PublicActivitySlot(
            id: "foreground",
            kind: "application",
            appId: "com.microsoft.VSCode",
            title: "Visual Studio Code",
            subtitle: nil,
            source: nil
        )]
        let value = PersistedActivity(events: [
            ActivityEvent(
                timestamp: Date(timeIntervalSince1970: 1_784_182_800),
                kind: .snapshotSent,
                detail: "快照 #42 · 应用：Visual Studio Code",
                sequence: 42,
                slots: slots
            )
        ])

        try store.save(value)

        #expect(store.load() == value)
    }

    @Test func decodesEventsCreatedBeforeSnapshotDetails() throws {
        let data = Data(#"{"events":[{"id":"D982F82B-1F42-4D56-8859-0A099F844841","timestamp":0,"kind":"connected","detail":"测试"}]}"#.utf8)
        let value = try JSONDecoder().decode(PersistedActivity.self, from: data)

        #expect(value.events.first?.sequence == nil)
        #expect(value.events.first?.slots == nil)
    }

    @Test func policyOnlyPublishesAllowlistedApplications() {
        let settings = MonitorSettings(
            endpoint: "ws://localhost",
            allowlistedApplications: [
                AllowedApplication(bundleIdentifier: "com.microsoft.VSCode", title: "Visual Studio Code")
            ],
            mediaEnabled: false,
            publishTrackTitle: true,
            publishArtist: true,
            publishSourceApplication: true,
            launchAtLogin: false
        )
        let policy = PublishPolicy(settings: settings)

        let allowed = policy.foregroundSlot(for: ForegroundApplication(bundleIdentifier: "com.microsoft.VSCode", localizedName: "Code"))
        let privateApp = policy.foregroundSlot(for: ForegroundApplication(bundleIdentifier: "com.apple.MobileSMS", localizedName: "Messages"))

        #expect(allowed?.title == "Visual Studio Code")
        #expect(allowed?.appId == "com.microsoft.VSCode")
        #expect(privateApp == nil)
    }

    @Test func snapshotUsesVersionedProtocolAndCompleteSlots() throws {
        let snapshot = AgentSnapshot(
            sequence: 42,
            slots: [PublicActivitySlot(
                id: "foreground",
                kind: "application",
                appId: "com.apple.dt.Xcode",
                title: "Xcode",
                subtitle: nil,
                source: nil
            )]
        )
        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["protocol"] as? String == "activity.v1")
        #expect(object["type"] as? String == "agent:snapshot")
        #expect((object["slots"] as? [[String: Any]])?.count == 1)
    }

    @Test func advertisesAndDecodesActivityAssetSync() throws {
        #expect(AgentHello.current.capabilities.contains("application-icons"))
        #expect(AgentHello.current.capabilities.contains("now-playing-progress"))
        #expect(AgentHello.current.capabilities.contains("now-playing-artwork"))
        let data = Data(#"{"type":"server:ready","heartbeatInterval":30,"stateTtl":90,"iconSyncEndpoint":"https://blog.example.com/api/activity/icons","artworkSyncEndpoint":"https://blog.example.com/api/activity/artwork"}"#.utf8)
        let message = try JSONDecoder().decode(ServerMessage.self, from: data)

        #expect(message.iconSyncEndpoint == "https://blog.example.com/api/activity/icons")
        #expect(message.artworkSyncEndpoint == "https://blog.example.com/api/activity/artwork")
    }

    @Test func mediaPolicyCanSuppressArtist() {
        var settings = MonitorSettings.defaults
        settings.mediaEnabled = true
        settings.publishArtist = false
        let slot = PublishPolicy(settings: settings).mediaSlot(
            for: NowPlayingActivity(
                kind: .music,
                title: "Song",
                creator: "Artist",
                source: "Music",
                sourceAppId: "com.apple.Music"
            )
        )

        #expect(slot?.title == "Song")
        #expect(slot?.subtitle == nil)
        #expect(slot?.source == "Music")
        #expect(slot?.appId == "com.apple.Music")
    }

    @Test func mediaPolicyCanSuppressSourceApplication() {
        var settings = MonitorSettings.defaults
        settings.mediaEnabled = true
        settings.publishSourceApplication = false
        let slot = PublishPolicy(settings: settings).mediaSlot(
            for: NowPlayingActivity(
                kind: .video,
                title: "Video",
                creator: "Creator",
                source: "Safari",
                sourceAppId: "com.apple.Safari"
            )
        )

        #expect(slot?.kind == "video")
        #expect(slot?.source == nil)
        #expect(slot?.appId == nil)
    }

    @Test func decodesSettingsCreatedBeforeSourcePublishing() throws {
        let data = Data(#"{"endpoint":"ws://localhost","allowlistedApplications":[],"mediaEnabled":true,"publishTrackTitle":true,"publishArtist":true,"launchAtLogin":false}"#.utf8)
        let settings = try JSONDecoder().decode(MonitorSettings.self, from: data)

        #expect(settings.publishSourceApplication == true)
    }

    @Test func decodesAllowlistCreatedWithLegacyIconKey() throws {
        let data = Data(#"{"endpoint":"ws://localhost","allowlistedApplications":[{"id":"D982F82B-1F42-4D56-8859-0A099F844841","bundleIdentifier":"com.microsoft.VSCode","title":"Visual Studio Code","icon":"code"}],"mediaEnabled":false,"publishTrackTitle":true,"publishArtist":true,"publishSourceApplication":true,"launchAtLogin":false}"#.utf8)
        let settings = try JSONDecoder().decode(MonitorSettings.self, from: data)

        #expect(settings.allowlistedApplications.first?.bundleIdentifier == "com.microsoft.VSCode")
        #expect(settings.allowlistedApplications.first?.title == "Visual Studio Code")
    }

    @Test func classifiesSystemNowPlayingMediaConservatively() {
        #expect(NowPlayingCollector.classifyMediaKind(mediaType: NSNumber(value: 1), isMusicApp: nil) == .music)
        #expect(NowPlayingCollector.classifyMediaKind(mediaType: NSNumber(value: 2), isMusicApp: nil) == .video)
        #expect(NowPlayingCollector.classifyMediaKind(mediaType: "video", isMusicApp: nil) == .video)
        #expect(NowPlayingCollector.classifyMediaKind(mediaType: nil, isMusicApp: true) == .music)
        #expect(NowPlayingCollector.classifyMediaKind(mediaType: nil, isMusicApp: false) == .media)
        #expect(NowPlayingCollector.classifyMediaKind(mediaType: NSNumber(value: 99), isMusicApp: nil) == .media)
    }

    @Test func acceptsArtworkFromAppleMusicFallback() {
        let pngHeader = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

        #expect(NowPlayingCollector.appleMusicArtwork(from: pngHeader)?.data == pngHeader)
        #expect(NowPlayingCollector.appleMusicArtwork(from: Data()) == nil)
        #expect(NowPlayingCollector.appleMusicArtwork(from: nil) == nil)
    }

    @Test func derivesAndPublishesNowPlayingProgressConservatively() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let position = NowPlayingCollector.currentPlaybackPosition(
            elapsedSeconds: 40,
            durationSeconds: 120,
            playbackRate: 1,
            timestamp: observedAt.addingTimeInterval(-3),
            now: observedAt
        )
        #expect(position == 43)

        let previous = NowPlayingActivity(
            kind: .music,
            title: "Song",
            creator: "Artist",
            source: "Music",
            sourceAppId: "com.apple.Music",
            positionSeconds: 40,
            durationSeconds: 120,
            playbackRate: 1,
            positionUpdatedAt: observedAt
        )
        let normalProgress = NowPlayingActivity(
            kind: .music,
            title: "Song",
            creator: "Artist",
            source: "Music",
            sourceAppId: "com.apple.Music",
            positionSeconds: 48,
            durationSeconds: 120,
            playbackRate: 1,
            positionUpdatedAt: observedAt.addingTimeInterval(8)
        )
        let seekedProgress = NowPlayingActivity(
            kind: .music,
            title: "Song",
            creator: "Artist",
            source: "Music",
            sourceAppId: "com.apple.Music",
            positionSeconds: 80,
            durationSeconds: 120,
            playbackRate: 1,
            positionUpdatedAt: observedAt.addingTimeInterval(8)
        )

        #expect(!NowPlayingActivity.requiresPublication(from: previous, to: normalProgress))
        #expect(NowPlayingActivity.requiresPublication(from: previous, to: seekedProgress))
    }

    @Test func publishesOnlyConfirmedArtworkAndPreservesItsHash() {
        var settings = MonitorSettings.defaults
        settings.mediaEnabled = true
        let artwork = NowPlayingArtwork(data: Data([1, 2, 3]), identifier: "cover-1")
        let previous = NowPlayingActivity(
            kind: .music,
            title: "Song",
            creator: "Artist",
            source: "Music",
            sourceAppId: "com.apple.Music",
            artwork: artwork,
            artworkHash: String(repeating: "a", count: 64)
        )
        let refreshed = NowPlayingActivity(
            kind: .music,
            title: "Song",
            creator: "Artist",
            source: "Music",
            sourceAppId: "com.apple.Music",
            artwork: artwork
        ).preservingConfirmedArtwork(from: previous)

        #expect(refreshed.artworkHash == previous.artworkHash)
        #expect(PublishPolicy(settings: settings).mediaSlot(for: refreshed)?.artworkHash == previous.artworkHash)
    }

    @Test func normalizesBlogAndWebSocketURLs() {
        #expect(
            RealtimeClient.normalizedEndpoint("https://blog.example.com")?.absoluteString
                == "wss://blog.example.com/realtime/activity/agent"
        )
        #expect(
            RealtimeClient.normalizedEndpoint("http://127.0.0.1:3001")?.absoluteString
                == "ws://127.0.0.1:3001/realtime/activity/agent"
        )
        #expect(
            RealtimeClient.normalizedEndpoint("wss://blog.example.com/custom/agent")?.absoluteString
                == "wss://blog.example.com/custom/agent"
        )
        #expect(RealtimeClient.normalizedEndpoint("ftp://blog.example.com") == nil)
    }
}
