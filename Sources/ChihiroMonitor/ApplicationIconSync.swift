import AppKit
import CryptoKit
import Foundation

struct ApplicationIconCandidate: Equatable {
    let appId: String
    let displayName: String
}

struct ApplicationIconSyncResult: Equatable {
    let enabled: Bool
    let uploadedCount: Int
    let unchangedCount: Int
}

@MainActor
final class ApplicationIconSyncClient {
    private static let maximumIconBytes = 128 * 1024

    func sync(
        applications: [ApplicationIconCandidate],
        endpoint: URL,
        token: String
    ) async throws -> ApplicationIconSyncResult {
        let icons = applications.compactMap(prepareIcon)
        guard !icons.isEmpty else {
            return ApplicationIconSyncResult(enabled: true, uploadedCount: 0, unchangedCount: 0)
        }

        let checkResponse = try await check(icons: icons, endpoint: endpoint, token: token)
        guard checkResponse.enabled else {
            return ApplicationIconSyncResult(enabled: false, uploadedCount: 0, unchangedCount: icons.count)
        }

        let requiredAppIds = Set(checkResponse.required.map { $0.lowercased() })
        var uploadedCount = 0
        for icon in icons where requiredAppIds.contains(icon.appId.lowercased()) {
            try Task.checkCancellation()
            try await upload(icon: icon, endpoint: endpoint, token: token)
            uploadedCount += 1
        }
        return ApplicationIconSyncResult(
            enabled: true,
            uploadedCount: uploadedCount,
            unchangedCount: icons.count - uploadedCount
        )
    }

    private func prepareIcon(for application: ApplicationIconCandidate) -> PreparedApplicationIcon? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: application.appId
        ) else { return nil }

        let sourceIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        let pngData: Data?
        if let largeIcon = renderPNG(sourceIcon, size: 128),
           largeIcon.count <= Self.maximumIconBytes {
            pngData = largeIcon
        } else {
            pngData = renderPNG(sourceIcon, size: 64)
        }
        guard let pngData, pngData.count <= Self.maximumIconBytes else { return nil }
        let hash = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        return PreparedApplicationIcon(
            appId: application.appId,
            displayName: application.displayName,
            iconHash: hash,
            pngData: pngData
        )
    }

    private func renderPNG(_ source: NSImage, size: CGFloat) -> Data? {
        let targetSize = NSSize(width: size, height: size)
        let target = NSImage(size: targetSize)
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func check(
        icons: [PreparedApplicationIcon],
        endpoint: URL,
        token: String
    ) async throws -> IconCheckResponse {
        var request = authorizedRequest(endpoint: endpoint, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            IconCheckRequest(icons: icons.map { IconDescriptor(appId: $0.appId, iconHash: $0.iconHash) })
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(IconCheckResponse.self, from: data)
    }

    private func upload(
        icon: PreparedApplicationIcon,
        endpoint: URL,
        token: String
    ) async throws {
        let boundary = "ChihiroIconBoundary-\(UUID().uuidString)"
        var request = authorizedRequest(endpoint: endpoint, token: token)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(icon: icon, boundary: boundary)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func authorizedRequest(endpoint: URL, token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("ChihiroActivityAgent/0.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func multipartBody(icon: PreparedApplicationIcon, boundary: String) -> Data {
        var body = Data()
        body.appendFormField(name: "appId", value: icon.appId, boundary: boundary)
        body.appendFormField(name: "displayName", value: icon.displayName, boundary: boundary)
        body.appendFormField(name: "iconHash", value: icon.iconHash, boundary: boundary)
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(icon.appId).png\"\r\n")
        body.appendUTF8("Content-Type: image/png\r\n\r\n")
        body.append(icon.pngData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApplicationIconSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(IconServerError.self, from: data)
            throw ApplicationIconSyncError.server(
                serverError?.error ?? "图标同步请求失败（HTTP \(httpResponse.statusCode)）"
            )
        }
    }
}

private struct PreparedApplicationIcon {
    let appId: String
    let displayName: String
    let iconHash: String
    let pngData: Data
}

private struct IconDescriptor: Encodable {
    let appId: String
    let iconHash: String
}

private struct IconCheckRequest: Encodable {
    let icons: [IconDescriptor]
}

private struct IconCheckResponse: Decodable {
    let enabled: Bool
    let required: [String]
}

private struct IconServerError: Decodable {
    let error: String
}

private enum ApplicationIconSyncError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "图标同步服务返回了无效响应"
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
