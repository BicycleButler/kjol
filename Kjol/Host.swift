import Foundation
import Combine
import SwiftUI

final class Host: ObservableObject {
    /// True once the helper daemon is installed, reachable over XPC, and
    /// serving real data. Drives whether the controls UI is shown.
    @Published var helperInstalled: Bool = false
    @Published var busy: Bool = false
    @Published var errorMessage: String?

    let telemetryVM = TelemetryViewModel()
    let fanControlVM = FanControlViewModel()
    let powerVM = PowerViewModel()
    let updateVM = UpdateViewModel()

    private let xpcClient = XpcClient()
    private let cpuSampler = CpuSamplerService()
    private let helperInstaller = HelperInstaller()
    private var pollingTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.lappier.kjol.polling", qos: .utility)
    private var xpcFailedOnce = false

    init() {
        xpcClient.onReconnect = { [weak self] in
            self?.refresh()
        }
        setupViewModelCallbacks()
        xpcClient.connect()
        checkHelperInstalled()
        refresh()
    }

    deinit {
        stopPolling()
    }

    private func setupViewModelCallbacks() {
        fanControlVM.onProfileChange = { [weak self] profile, pct, subProfile, curvePoints in
            self?.setFanProfile(profile, customPercent: pct, adaptiveSubProfile: subProfile, curvePoints: curvePoints)
        }
        fanControlVM.onSafetyPolicyChange = { [weak self] policy, ceiling in
            self?.setThermalSafetyPolicy(policy, ceilingTemp: ceiling)
        }
        fanControlVM.onPresetChange = { [weak self] preset in
            self?.setSystemPreset(preset)
        }
        powerVM.onAlwaysOnToggle = { [weak self] on in
            self?.setAlwaysOn(on)
        }
        powerVM.onDaemonsToggle = { [weak self] on in
            self?.setDaemonsSuspended(on)
        }
        powerVM.onDaemonsSafetyCeilingToggle = { [weak self] enabled in
            self?.setDaemonSafetyCeiling(enabled)
        }
        powerVM.onBatteryLimitChange = { [weak self] limit, enabled in
            self?.setBatteryLimit(limit, enabled: enabled)
        }
        powerVM.onBatteryLimitAdvancedChange = { [weak self] limit, enabled, sDiff in
            self?.setBatteryLimitAdvanced(limit, enabled: enabled, sailingDiff: sDiff)
        }
        powerVM.onTopUpToggle = { [weak self] on in
            self?.setTopUpMode(on)
        }
        powerVM.onDischargeToggle = { [weak self] on in
            self?.setDischargeMode(on)
        }
        powerVM.onHeatProtectionChange = { [weak self] enabled, maxTemp in
            self?.setHeatProtection(enabled, maxTempC: maxTemp)
        }
        powerVM.onCalibrationAction = { [weak self] action in
            self?.setCalibrationMode(action)
        }
    }

    func checkHelperInstalled() {
        let present = HelperInstaller.isHelperInstalled()
        let upToDate = HelperInstaller.isHelperUpToDate()
        helperInstalled = present && upToDate
    }

    /// True when a helper binary/daemon exists but is stale (different from
    /// the bundled build).
    var needsReinstall: Bool {
        HelperInstaller.isHelperInstalled() && !HelperInstaller.isHelperUpToDate()
    }

    /// Show a diagnostic prompt when helper is unreachable.
    func flagHelperUnreachable() {
        guard helperInstalled else { return }
        helperInstalled = false
        errorMessage = "Helper daemon connection lost. Run the Kjol installer package to restore."
    }

    func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        let leeway = DispatchTimeInterval.milliseconds(Int(interval * 500))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        timer.setEventHandler { [weak self] in
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "Kjol Telemetry Polling"
            )
            self?.refresh()
            ProcessInfo.processInfo.endActivity(activity)
        }
        pollingTimer = timer
        timer.resume()
    }

    func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    func refresh() {
        Task {
            do {
                let status = try await xpcClient.getCombinedStatus()
                let battery = try await xpcClient.getBatteryStatus()
                let cpu = cpuSampler.sample()

                let hostDict = status["host"] as? [String: Any] ?? [:]
                let fansDict = status["fans"] as? [String: Any] ?? [:]

                await MainActor.run {
                    self.helperInstalled = true
                    self.errorMessage = nil
                    self.telemetryVM.updateTelemetry(cpu: cpu, fansDict: fansDict, batteryDict: battery)
                    self.powerVM.updateHostState(hostDict: hostDict)
                    self.powerVM.updateBatteryState(batteryDict: battery)
                    self.fanControlVM.updateFromDaemon(
                        profileString: fansDict["profile"] as? String,
                        rpmPercent: fansDict["rpmPercent"] as? Double,
                        subProfileString: fansDict["adaptiveSubProfile"] as? String,
                        curvePoints: fansDict["curvePoints"] as? [Double],
                        safetyPolicyString: fansDict["safetyPolicy"] as? String,
                        ceilingTemp: fansDict["ceilingTemp"] as? Double,
                        systemPresetString: fansDict["systemPreset"] as? String,
                        throttlingEngaged: fansDict["throttlingEngaged"] as? Bool,
                        fanBoostEngaged: fansDict["fanBoostEngaged"] as? Bool
                    )
                }
            } catch {
                await MainActor.run {
                    // If XPC repeatedly fails, the helper is likely stale or
                    // not running — surface a reinstall prompt.
                    if let kjolErr = error as? KjolXPCError,
                       kjolErr.errorCode == KjolXPCError.helperUnavailable.errorCode
                        || kjolErr.errorCode == KjolXPCError.notConnected.errorCode {
                        self.xpcFailedOnce = true
                        self.flagHelperUnreachable()
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func setAlwaysOn(_ on: Bool) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setAlwaysOn(on)
        }
    }

    func syncSetAlwaysOn(_ on: Bool) {
        xpcClient.syncSetAlwaysOn(on)
    }

    func setDaemonsSuspended(_ on: Bool) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.suspendDaemons(on)
        }
    }

    func setDaemonSafetyCeiling(_ enabled: Bool) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setDaemonSafetyCeiling(enabled)
        }
    }

    func setFanProfile(
        _ profile: FanProfile,
        customPercent: Double? = nil,
        adaptiveSubProfile: AdaptiveSubProfile? = nil,
        curvePoints: [Double]? = nil
    ) {
        let pct = customPercent ?? fanControlVM.customPercent
        let sub = (adaptiveSubProfile ?? fanControlVM.adaptiveSubProfile).rawValue
        let pts = curvePoints ?? fanControlVM.flattenedCurvePoints

        performAction { [weak self] in
            var attempt = 0
            while attempt < 12 {
                do {
                    if profile == .adaptive {
                        _ = try await self?.xpcClient.setFanAdaptiveProfile(subProfile: sub, curvePoints: pts)
                    } else {
                        _ = try await self?.xpcClient.setFanProfile(profile.rawValue, rpmPercent: pct)
                    }
                    break
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == "com.lappier.kjol.smc" && nsError.code == 1 {
                        attempt += 1
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s retry
                        continue
                    }
                    throw error
                }
            }
        }
    }

    func setThermalSafetyPolicy(_ policy: ThermalSafetyPolicy, ceilingTemp: Double) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setThermalSafetyPolicy(policy: policy.rawValue, ceilingTempC: ceilingTemp)
        }
    }

    func setSystemPreset(_ preset: SystemPreset) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setSystemPreset(preset.rawValue)
        }
    }

    func setBatteryLimit(_ limit: Int, enabled: Bool) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setBatteryLimit(limit, enabled: enabled)
        }
    }

    func setBatteryLimitAdvanced(_ limit: Int, enabled: Bool, sailingDiff: Int) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setBatteryLimitAdvanced(limit, enabled: enabled, sailingDiff: sailingDiff)
        }
    }

    func setTopUpMode(_ enabled: Bool) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setTopUpMode(enabled)
        }
    }

    func setDischargeMode(_ enabled: Bool) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setDischargeMode(enabled)
        }
    }

    func setHeatProtection(_ enabled: Bool, maxTempC: Double) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setHeatProtection(enabled, maxTempC: maxTempC)
        }
    }

    func setCalibrationMode(_ action: String) {
        performAction { [weak self] in
            _ = try await self?.xpcClient.setCalibrationMode(action)
        }
    }

    private func performAction(_ block: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        Task {
            do {
                try await block()
                await MainActor.run {
                    self.busy = false
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.errorMessage = error.localizedDescription
                    self.refresh()
                }
            }
        }
    }
}
