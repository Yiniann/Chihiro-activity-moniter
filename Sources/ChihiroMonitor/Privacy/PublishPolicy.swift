import Foundation

struct PublishPolicy {
    let settings: MonitorSettings

    func foregroundSlot(for application: ForegroundApplication?) -> PublicActivitySlot? {
        guard let application,
              let allowed = settings.allowlistedApplications.first(where: {
                  $0.bundleIdentifier.caseInsensitiveCompare(application.bundleIdentifier) == .orderedSame
              }) else { return nil }

        return PublicActivitySlot(
            id: "foreground",
            kind: "application",
            appId: sanitizeBundleIdentifier(application.bundleIdentifier),
            title: sanitize(allowed.title, maximumLength: 50),
            subtitle: nil,
            source: nil
        )
    }

    func mediaSlot(for media: NowPlayingActivity?) -> PublicActivitySlot? {
        guard settings.mediaEnabled, let media, settings.publishTrackTitle else { return nil }
        return PublicActivitySlot(
            id: "media",
            kind: media.kind.rawValue,
            appId: settings.publishSourceApplication ? media.sourceAppId.flatMap(sanitizeBundleIdentifier) : nil,
            title: sanitize(media.title, maximumLength: 100),
            subtitle: settings.publishArtist ? media.creator.map { sanitize($0, maximumLength: 100) } : nil,
            source: settings.publishSourceApplication ? media.source.map { sanitize($0, maximumLength: 50) } : nil,
            positionSeconds: media.positionSeconds,
            durationSeconds: media.durationSeconds,
            playbackRate: media.playbackRate,
            positionUpdatedAt: media.positionUpdatedAt.map {
                Int64($0.timeIntervalSince1970 * 1_000)
            },
            artworkHash: media.artworkHash
        )
    }

    private func sanitize(_ value: String, maximumLength: Int) -> String {
        String(value
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .prefix(maximumLength))
    }

    private func sanitizeBundleIdentifier(_ value: String) -> String? {
        let normalized = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255))
        guard normalized.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return normalized
    }
}
