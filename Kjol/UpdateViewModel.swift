import Foundation
import Combine
import AppKit
import SwiftUI
import os

enum UpdateState: Equatable {
    case idle
    case checking
    case available(UpdateInfo)
    case upToDate
    case downloading(progress: Double)
    case readyToInstall(pkgLocalURL: URL)
    case error(String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate):
            return true
        case (.available(let a), .available(let b)):
            return a.version == b.version
        case (.downloading(let a), .downloading(let b)):
            return a == b
        case (.readyToInstall(let a), .readyToInstall(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

final class UpdateViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.lappier.kjol", category: "UpdateViewModel")

    @Published var state: UpdateState = .idle
    private let service = UpdateCheckerService()
    private var lastCheckDate: Date?

    func checkForUpdates(silent: Bool = false) {
        if silent {
            if let last = lastCheckDate, Date().timeIntervalSince(last) < 900 {
                return
            }
        }

        if case .downloading = state { return }
        if case .readyToInstall = state { return }

        Self.logger.info("Transitioning update state to: checking (silent: \(silent))")
        state = .checking
        lastCheckDate = Date()

        Task {
            do {
                if let updateInfo = try await service.checkForUpdates() {
                    await MainActor.run {
                        Self.logger.info("Transitioning update state to: available (v\(updateInfo.version))")
                        self.state = .available(updateInfo)
                    }
                } else {
                    await MainActor.run {
                        Self.logger.info("Transitioning update state to: upToDate")
                        self.state = .upToDate
                    }
                }
            } catch {
                await MainActor.run {
                    if !silent {
                        Self.logger.error("Transitioning update state to: error (\(error.localizedDescription))")
                        self.state = .error(error.localizedDescription)
                    } else {
                        Self.logger.info("Silent check encountered error; reverting to: idle")
                        self.state = .idle
                    }
                }
            }
        }
    }

    func startDownload(for info: UpdateInfo) {
        Self.logger.info("Transitioning update state to: downloading (v\(info.version))")
        state = .downloading(progress: 0.0)
        Task {
            do {
                let localURL = try await service.downloadInstaller(from: info.pkgDownloadURL) { progress in
                    self.state = .downloading(progress: progress)
                }
                await MainActor.run {
                    Self.logger.info("Transitioning update state to: readyToInstall (\(localURL.path))")
                    self.state = .readyToInstall(pkgLocalURL: localURL)
                    self.installUpdate(localURL: localURL)
                }
            } catch {
                await MainActor.run {
                    Self.logger.error("Download failed; transitioning to error: \(error.localizedDescription)")
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func installUpdate(localURL: URL) {
        Self.logger.info("Launching installer package via NSWorkspace: \(localURL.path)")
        NSWorkspace.shared.open(localURL)
    }
}
