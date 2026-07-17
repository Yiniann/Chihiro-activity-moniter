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
        return NowPlayingActivity(
            kind: Self.classifyMediaKind(
                mediaType: information["kMRMediaRemoteNowPlayingInfoMediaType"],
                isMusicApp: information["kMRMediaRemoteNowPlayingInfoIsMusicApp"]
            ),
            title: title,
            creator: creator?.isEmpty == true ? nil : creator,
            source: sourceApplication?.name,
            sourceAppId: sourceApplication?.bundleIdentifier
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
            return {trackTitle, trackArtist}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil,
              let title = result.atIndex(1)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let artist = result.atIndex(2)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        return NowPlayingActivity(
            kind: .music,
            title: title,
            creator: artist?.isEmpty == false ? artist : nil,
            source: "Music",
            sourceAppId: "com.apple.Music"
        )
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
