import AppKit
import CryptoKit
import Foundation

struct NowPlayingArtworkSyncResult: Equatable {
    let enabled: Bool
    let artworkHash: String?
    let uploaded: Bool
}

@MainActor
final class NowPlayingArtworkSyncClient {
    private static let maximumUploadBytes = 512 * 1024
    private static let confirmationLifetime: TimeInterval = 24 * 60 * 60
    private static let confirmationCacheKey = "monitor.artwork-confirmations"

    func sync(
        artwork: NowPlayingArtwork,
        endpoint: URL,
        token: String
    ) async throws -> NowPlayingArtworkSyncResult {
        guard let prepared = prepareArtwork(artwork.data) else {
            return NowPlayingArtworkSyncResult(enabled: true, artworkHash: nil, uploaded: false)
        }
        if isRecentlyConfirmed(prepared.hash) {
            return NowPlayingArtworkSyncResult(enabled: true, artworkHash: prepared.hash, uploaded: false)
        }

        let checkResponse = try await check(hash: prepared.hash, endpoint: endpoint, token: token)
        guard checkResponse.enabled else {
            return NowPlayingArtworkSyncResult(enabled: false, artworkHash: nil, uploaded: false)
        }
        if !checkResponse.stored {
            try await upload(artwork: prepared, endpoint: endpoint, token: token)
        }
        confirm(prepared.hash)
        return NowPlayingArtworkSyncResult(
            enabled: true,
            artworkHash: prepared.hash,
            uploaded: !checkResponse.stored
        )
    }

    private func prepareArtwork(_ sourceData: Data) -> PreparedNowPlayingArtwork? {
        guard let source = NSImage(data: sourceData), source.size.width > 0, source.size.height > 0 else {
            return nil
        }
        let attempts: [(size: CGFloat, quality: CGFloat)] = [
            (512, 0.78),
            (384, 0.68)
        ]
        for attempt in attempts {
            guard let jpegData = renderJPEG(source, size: attempt.size, quality: attempt.quality) else {
                continue
            }
            guard jpegData.count <= Self.maximumUploadBytes else { continue }
            let hash = SHA256.hash(data: jpegData).map { String(format: "%02x", $0) }.joined()
            return PreparedNowPlayingArtwork(hash: hash, jpegData: jpegData)
        }
        return nil
    }

    private func renderJPEG(_ source: NSImage, size: CGFloat, quality: CGFloat) -> Data? {
        let targetSize = NSSize(width: size, height: size)
        let sourceSize = source.size
        let sourceAspectRatio = sourceSize.width / sourceSize.height
        let sourceRect: NSRect
        if sourceAspectRatio > 1 {
            let cropWidth = sourceSize.height
            sourceRect = NSRect(
                x: (sourceSize.width - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: sourceSize.height
            )
        } else {
            let cropHeight = sourceSize.width
            sourceRect = NSRect(
                x: 0,
                y: (sourceSize.height - cropHeight) / 2,
                width: sourceSize.width,
                height: cropHeight
            )
        }

        let target = NSImage(size: targetSize)
        target.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }

    private func check(hash: String, endpoint: URL, token: String) async throws -> ArtworkCheckResponse {
        var request = authorizedRequest(endpoint: endpoint, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ArtworkCheckRequest(artworkHash: hash))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ArtworkCheckResponse.self, from: data)
    }

    private func upload(
        artwork: PreparedNowPlayingArtwork,
        endpoint: URL,
        token: String
    ) async throws {
        let boundary = "ChihiroArtworkBoundary-\(UUID().uuidString)"
        var request = authorizedRequest(endpoint: endpoint, token: token)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(artwork: artwork, boundary: boundary)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func authorizedRequest(endpoint: URL, token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("ChihiroActivityAgent/0.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func multipartBody(artwork: PreparedNowPlayingArtwork, boundary: String) -> Data {
        var body = Data()
        body.appendFormField(name: "artworkHash", value: artwork.hash, boundary: boundary)
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(artwork.hash).jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(artwork.jpegData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NowPlayingArtworkSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(ArtworkServerError.self, from: data)
            throw NowPlayingArtworkSyncError.server(
                serverError?.error ?? "播放封面同步请求失败（HTTP \(httpResponse.statusCode)）"
            )
        }
    }

    private func isRecentlyConfirmed(_ hash: String) -> Bool {
        let cutoff = Date().timeIntervalSince1970 - Self.confirmationLifetime
        var cache = confirmationCache()
        let originalCount = cache.count
        cache = cache.filter { $0.value >= cutoff }
        if cache.count != originalCount {
            saveConfirmationCache(cache)
        }
        return cache[hash].map { $0 >= cutoff } == true
    }

    private func confirm(_ hash: String) {
        let now = Date().timeIntervalSince1970
        let cutoff = now - Self.confirmationLifetime
        var cache = confirmationCache().filter { $0.value >= cutoff }
        cache[hash] = now
        if cache.count > 1_000 {
            cache = Dictionary(uniqueKeysWithValues: cache
                .sorted { $0.value > $1.value }
                .prefix(1_000)
                .map { ($0.key, $0.value) })
        }
        saveConfirmationCache(cache)
    }

    private func confirmationCache() -> [String: TimeInterval] {
        let stored = UserDefaults.standard.dictionary(forKey: Self.confirmationCacheKey) ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            guard entry.key.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                  let timestamp = entry.value as? NSNumber else { return }
            result[entry.key] = timestamp.doubleValue
        }
    }

    private func saveConfirmationCache(_ cache: [String: TimeInterval]) {
        UserDefaults.standard.set(cache, forKey: Self.confirmationCacheKey)
    }
}

private struct PreparedNowPlayingArtwork {
    let hash: String
    let jpegData: Data
}

private struct ArtworkCheckRequest: Encodable {
    let artworkHash: String
}

private struct ArtworkCheckResponse: Decodable {
    let enabled: Bool
    let stored: Bool
}

private struct ArtworkServerError: Decodable {
    let error: String
}

private enum NowPlayingArtworkSyncError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "播放封面同步服务返回了无效响应"
        case .server(let message): message
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(Data(value.utf8))
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendUTF8(value)
        appendUTF8("\r\n")
    }
}
