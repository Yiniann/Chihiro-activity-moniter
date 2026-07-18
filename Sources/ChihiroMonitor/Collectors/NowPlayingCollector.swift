import AppKit
import Foundation
import MediaRemoteBridge

final class NowPlayingCollector: @unchecked Sendable {
    func collect() async -> NowPlayingActivity? {
        let remoteResult = await Task.detached(priority: .utility) { [self] in
            NowPlayingActivityBox(collectMediaRemote())
        }.value
        if let media = remoteResult.value {
            return media
        }

        let fallbackResult: NowPlayingActivityBox = await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [self] in
                continuation.resume(returning: NowPlayingActivityBox(collectAppleMusic()))
            }
        }
        return fallbackResult.value
    }

    private func collectMediaRemote() -> NowPlayingActivity? {
        guard let information = ChihiroCopyNowPlayingSnapshot() as? [String: Any] else { return nil }
        let playbackRate = (information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
        let isPlaying = (information["ChihiroIsPlaying"] as? NSNumber)?.boolValue == true
            || (playbackRate ?? 0) > 0
        guard isPlaying else { return nil }

        let title = (information["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return nil }

        let creator = (information["kMRMediaRemoteNowPlayingInfoArtist"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceApplication = readSourceApplication(
            pid: (information["ChihiroApplicationPID"] as? NSNumber)?.int32Value
        )
        let now = Date()
        let durationSeconds = Self.normalizedDuration(
            (information["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue
        )
        let normalizedPlaybackRate = Self.normalizedPlaybackRate(playbackRate) ?? 1
        let positionSeconds = Self.currentPlaybackPosition(
            elapsedSeconds: (information["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue,
            durationSeconds: durationSeconds,
            playbackRate: normalizedPlaybackRate,
            timestamp: information["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
            now: now
        )
        let artwork = readArtwork(information)
        return NowPlayingActivity(
            kind: Self.classifyMediaKind(
                mediaType: information["kMRMediaRemoteNowPlayingInfoMediaType"],
                isMusicApp: information["kMRMediaRemoteNowPlayingInfoIsMusicApp"]
            ),
            title: title,
            creator: creator?.isEmpty == true ? nil : creator,
            source: sourceApplication?.name,
            sourceAppId: sourceApplication?.bundleIdentifier,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            playbackRate: normalizedPlaybackRate,
            positionUpdatedAt: positionSeconds == nil ? nil : now,
            artwork: artwork
        )
    }

    private func readArtwork(_ information: [String: Any]) -> NowPlayingArtwork? {
        guard let data = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
              !data.isEmpty,
              data.count <= 10 * 1024 * 1024 else { return nil }
        let identifier = (information["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return NowPlayingArtwork(
            data: data,
            identifier: identifier?.isEmpty == false ? identifier : nil
        )
    }

    private func collectAppleMusic() -> NowPlayingActivity? {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Music"
        ).isEmpty else { return nil }

        let source = """
        tell application "Music"
            if player state is not playing then return {}
            set trackTitle to name of current track
            set trackArtist to artist of current track
            set trackPosition to -1
            set trackDuration to -1
            set trackArtwork to missing value
            try
                set trackPosition to player position
            end try
            try
                set trackDuration to duration of current track
            end try
            try
                if (count of artworks of current track) > 0 then
                    set trackArtwork to raw data of artwork 1 of current track
                end if
            end try
            return {trackTitle, trackArtist, trackPosition, trackDuration, trackArtwork}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil,
              let title = result.atIndex(1)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let artist = result.atIndex(2)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let positionSeconds = Self.normalizedPosition(result.atIndex(3)?.doubleValue)
        let durationSeconds = Self.normalizedDuration(result.atIndex(4)?.doubleValue)
        let artwork = Self.appleMusicArtwork(from: result.atIndex(5)?.data)

        return NowPlayingActivity(
            kind: .music,
            title: title,
            creator: artist?.isEmpty == false ? artist : nil,
            source: "Music",
            sourceAppId: "com.apple.Music",
            positionSeconds: positionSeconds.map { min($0, durationSeconds ?? $0) },
            durationSeconds: durationSeconds,
            playbackRate: 1,
            positionUpdatedAt: positionSeconds == nil ? nil : Date(),
            artwork: artwork
        )
    }

    nonisolated static func appleMusicArtwork(from data: Data?) -> NowPlayingArtwork? {
        guard let data, !data.isEmpty, data.count <= 10 * 1024 * 1024 else { return nil }
        return NowPlayingArtwork(data: data, identifier: nil)
    }

    nonisolated static func currentPlaybackPosition(
        elapsedSeconds: Double?,
        durationSeconds: Double?,
        playbackRate: Double,
        timestamp: Date?,
        now: Date
    ) -> Double? {
        guard let elapsedSeconds = normalizedPosition(elapsedSeconds) else { return nil }
        let elapsedSinceSnapshot = timestamp.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let position = elapsedSeconds + elapsedSinceSnapshot * max(0, playbackRate)
        return min(position, durationSeconds ?? position)
    }

    private nonisolated static func normalizedPosition(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private nonisolated static func normalizedDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private nonisolated static func normalizedPlaybackRate(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= 16 else { return nil }
        return value
    }

    nonisolated static func classifyMediaKind(
        mediaType: Any?,
        isMusicApp: Any?
    ) -> NowPlayingMediaKind {
        if let text = mediaType as? String {
            switch text.lowercased() {
            case "audio", "music": return .music
            case "video": return .video
            default: break
            }
        }

        if let rawValue = (mediaType as? NSNumber)?.intValue {
            switch rawValue {
            case 1: return .music
            case 2: return .video
            default: break
            }
        }

        if (isMusicApp as? Bool) == true || (isMusicApp as? NSNumber)?.boolValue == true {
            return .music
        }
        return .media
    }

    private func readSourceApplication(pid: Int32?) -> SourceApplication? {
        guard let pid, pid > 0 else { return nil }
        guard let application = NSRunningApplication(processIdentifier: pid) else { return nil }
        let name = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name?.isEmpty == false || bundleIdentifier?.isEmpty == false else { return nil }
        return SourceApplication(
            name: name?.isEmpty == false ? name : nil,
            bundleIdentifier: bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
        )
    }
}

private struct SourceApplication {
    let name: String?
    let bundleIdentifier: String?
}

private final class NowPlayingActivityBox: @unchecked Sendable {
    let value: NowPlayingActivity?

    init(_ value: NowPlayingActivity?) {
        self.value = value
    }
}
