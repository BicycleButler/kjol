import Foundation

final class XpcClient {
    private var connection: NSXPCConnection?
    var onReconnect: (() -> Void)?

    private let backoffDelays: [TimeInterval] = [0.0, 0.2, 0.5, 1.0, 2.0, 4.0]
    private var reconnectAttempt = 0
    private var isReconnecting = false
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.lappier.kjol.xpcclient", qos: .userInitiated)

    func connect() {
        lock.lock()
        if connection != nil {
            lock.unlock()
            return
        }
        let conn = NSXPCConnection(machServiceName: "com.lappier.kjol.helper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: KjolHelperProtocol.self)

        conn.interruptionHandler = { [weak self] in
            self?.handleDisconnection()
        }
        conn.invalidationHandler = { [weak self] in
            self?.handleDisconnection()
        }

        self.connection = conn
        conn.resume()
        lock.unlock()
    }

    private func handleDisconnection() {
        lock.lock()
        connection = nil
        lock.unlock()
        scheduleReconnection()
    }

    private func scheduleReconnection() {
        lock.lock()
        guard !isReconnecting else {
            lock.unlock()
            return
        }
        isReconnecting = true
        let delay = reconnectAttempt < backoffDelays.count ? backoffDelays[reconnectAttempt] : backoffDelays.last!
        reconnectAttempt = min(reconnectAttempt + 1, backoffDelays.count - 1)
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.isReconnecting = false
            self.lock.unlock()
            self.connect()
            DispatchQueue.main.async {
                self.onReconnect?()
            }
        }
    }

    private func remoteProxy(errorHandler: @escaping (Error) -> Void) -> KjolHelperProtocol? {
        connect()
        lock.lock()
        let conn = connection
        lock.unlock()

        guard let conn = conn else {
            errorHandler(KjolXPCError.notConnected)
            return nil
        }
        return conn.remoteObjectProxyWithErrorHandler { error in
            errorHandler(KjolXPCError.helperError(error.localizedDescription))
        } as? KjolHelperProtocol
    }

    func syncSetAlwaysOn(_ on: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        guard let proxy = remoteProxy(errorHandler: { _ in semaphore.signal() }) else { return }
        proxy.setAlwaysOn(on) { _, _ in
            semaphore.signal()
        }
        let result = semaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut {
            fputs("Kjol/XpcClient: syncSetAlwaysOn timed out after 2.0s\n", stderr)
        }
    }

    func setAlwaysOn(_ on: Bool) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setAlwaysOn(on) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func suspendDaemons(_ on: Bool) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.suspendDaemons(on) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setDaemonSafetyCeiling(_ enabled: Bool) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setDaemonSafetyCeiling(enabled) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func getCombinedStatus() async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.getCombinedStatus { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let status = status {
                    continuation.resume(returning: status)
                } else {
                    continuation.resume(throwing: KjolXPCError.invalidResponse)
                }
            }
        }
    }

    func getFanStatus() async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.getFanStatus { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let status = status {
                    continuation.resume(returning: status)
                } else {
                    continuation.resume(throwing: KjolXPCError.invalidResponse)
                }
            }
        }
    }

    func setFanProfile(_ profile: String, rpmPercent: Double, targetTempC: Double = 0) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setFanProfile(profile, rpmPercent: rpmPercent, targetTempC: targetTempC) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setFanAdaptiveProfile(subProfile: String, curvePoints: [Double] = []) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setFanAdaptiveProfile(subProfile: subProfile, curvePoints: curvePoints) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setThermalSafetyPolicy(policy: String, ceilingTempC: Double) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setThermalSafetyPolicy(policy: policy, ceilingTempC: ceilingTempC) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setSystemPreset(_ preset: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setSystemPreset(preset: preset) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setBatteryLimit(_ limit: Int, enabled: Bool) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setBatteryLimit(limit, enabled: enabled) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setBatteryLimitAdvanced(_ limit: Int, enabled: Bool, sailingDiff: Int) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setBatteryLimitAdvanced(limit, enabled: enabled, sailingDiff: sailingDiff) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setTopUpMode(_ enabled: Bool) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setTopUpMode(enabled) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setDischargeMode(_ enabled: Bool) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setDischargeMode(enabled) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setHeatProtection(_ enabled: Bool, maxTempC: Double) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setHeatProtection(enabled, maxTempC: maxTempC) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setCalibrationMode(_ action: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.setCalibrationMode(action) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func getBatteryStatus() async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            guard let proxy = remoteProxy(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else { return }

            proxy.getBatteryStatus { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let status = status {
                    continuation.resume(returning: status)
                } else {
                    continuation.resume(throwing: KjolXPCError.invalidResponse)
                }
            }
        }
    }
}
