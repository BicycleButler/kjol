import Foundation
import os

struct UpdateInfo: Equatable {
    let version: String
    let releaseNotes: String
    let pkgDownloadURL: URL
}

enum UpdateCheckerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noPkgAssetFound
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid update URL."
        case .invalidResponse: return "Invalid response from update server."
        case .noPkgAssetFound: return "No installer package (.pkg) found in release."
        case .downloadFailed(let reason): return "Download failed: \(reason)"
        }
    }
}

final class UpdateCheckerService {
    private static let logger = Logger(subsystem: "com.lappier.kjol", category: "UpdateChecker")
    private let releasesURL = URL(string: "https://api.github.com/repos/BicycleButler/kjol/releases/latest")!
    private let urlSession: URLSession

    init(session: URLSession = .shared) {
        self.urlSession = session
    }

    func checkForUpdates() async throws -> UpdateInfo? {
        Self.logger.info("Checking for updates from GitHub releases...")
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Kjol-Updater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Update check failed: invalid HTTP response.")
            throw UpdateCheckerError.invalidResponse
        }

        // If no releases have been published to GitHub yet (404), treat as up-to-date
        if httpResponse.statusCode == 404 {
            Self.logger.info("No releases found on GitHub repository (404). Current build is up to date.")
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            Self.logger.error("Update check failed with HTTP status code: \(httpResponse.statusCode)")
            throw UpdateCheckerError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawTag = json["tag_name"] as? String else {
            Self.logger.error("Failed to parse GitHub release JSON or missing tag_name.")
            throw UpdateCheckerError.invalidResponse
        }

        let remoteVersion = rawTag.hasPrefix("v") ? String(rawTag.dropFirst()) : rawTag
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        guard Self.isVersion(remoteVersion, newerThan: currentVersion) else {
            Self.logger.info("Current version (\(currentVersion)) is up to date with latest release (\(remoteVersion)).")
            return nil
        }

        Self.logger.info("New update discovered: v\(remoteVersion) (current: v\(currentVersion)).")

        let releaseNotes = json["body"] as? String ?? ""
        guard let assets = json["assets"] as? [[String: Any]] else {
            Self.logger.error("No release assets array found in GitHub response.")
            throw UpdateCheckerError.noPkgAssetFound
        }

        var pkgURL: URL?
        for asset in assets {
            if let name = asset["name"] as? String, name.hasSuffix(".pkg"),
               let urlString = asset["browser_download_url"] as? String,
               let url = URL(string: urlString) {
                pkgURL = url
                break
            }
        }

        guard let downloadURL = pkgURL else {
            Self.logger.error("No .pkg installer asset found in release v\(remoteVersion).")
            throw UpdateCheckerError.noPkgAssetFound
        }

        Self.logger.info("Resolved installer package download URL: \(downloadURL.absoluteString)")
        return UpdateInfo(version: remoteVersion, releaseNotes: releaseNotes, pkgDownloadURL: downloadURL)
    }

    func downloadInstaller(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        Self.logger.info("Starting installer package download from: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.setValue("Kjol-Updater/1.0", forHTTPHeaderField: "User-Agent")

        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("Kjol.pkg")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let (asyncBytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Self.logger.error("Installer download failed with HTTP status: \(code)")
            throw UpdateCheckerError.downloadFailed("HTTP \(code)")
        }

        let expectedLength = httpResponse.expectedContentLength
        var accumulatedData = Data()
        if expectedLength > 0 {
            accumulatedData.reserveCapacity(Int(expectedLength))
        }

        var downloadedBytes: Int64 = 0
        var lastReportedProgress: Double = -1.0

        for try await byte in asyncBytes {
            accumulatedData.append(byte)
            downloadedBytes += 1

            if expectedLength > 0 {
                let currentProgress = Double(downloadedBytes) / Double(expectedLength)
                // Throttle progress dispatches to 1% increments to protect UI thread responsiveness
                if currentProgress - lastReportedProgress >= 0.01 || currentProgress >= 1.0 {
                    lastReportedProgress = currentProgress
                    let p = min(1.0, currentProgress)
                    DispatchQueue.main.async {
                        progress(p)
                    }
                }
            }
        }

        try accumulatedData.write(to: destinationURL, options: .atomic)
        Self.logger.info("Installer successfully downloaded to: \(destinationURL.path)")
        return destinationURL
    }

    static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let v1Components = v1.split(separator: ".").compactMap { Int($0) }
        let v2Components = v2.split(separator: ".").compactMap { Int($0) }

        let count = max(v1Components.count, v2Components.count)
        for i in 0..<count {
            let n1 = i < v1Components.count ? v1Components[i] : 0
            let n2 = i < v2Components.count ? v2Components[i] : 0
            if n1 > n2 { return true }
            if n1 < n2 { return false }
        }
        return false
    }
}
