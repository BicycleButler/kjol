import Foundation
import Combine
import SwiftUI

public enum BatteryControlTier: String, Equatable {
    case directSMC        // Pre-macOS 27 with writable SMC keys: full custom charge limit, sailing, top-up, discharge
    case systemManaged    // macOS 27+ or systems with OS-enforced battery limits: native telemetry + Settings handoff
    case desktopNoBattery // Stationary Apple Silicon hardware with no battery
}

final class TelemetryViewModel: ObservableObject {
    @Published var socTemp: Double?
    @Published var cpuTemp: Double?
    @Published var gpuTemp: Double?
    @Published var pCoreCount: Int = 0
    @Published var eCoreCount: Int = 0
    @Published var pCoreUsage: Double = 0
    @Published var eCoreUsage: Double = 0
    @Published var perCoreUsage: [Double] = []
    @Published var overallUsage: Double = 0
    @Published var fans: [FanReading] = []
    @Published var batteryCharge: Int = 0
    @Published var isCharging: Bool = false
    @Published var chargingInhibited: Bool = false
    @Published var forcedDischarge: Bool = false
    @Published var heatProtectionActive: Bool = false
    @Published var topUpActive: Bool = false
    @Published var externalConnected: Bool = false
    @Published var batteryCycles: Int = 0
    @Published var batteryTemp: Double?
    @Published var batteryHealthPercent: Double?
    @Published var hasCpuSample: Bool = false
    @Published var hardwareControlSupported: Bool = true
    @Published var nativeChargeLimitAvailable: Bool = false
    @Published var batteryTier: BatteryControlTier = .systemManaged

    func updateTelemetry(cpu: CpuState, fansDict: [String: Any], batteryDict: [String: Any]) {
        if pCoreCount != cpu.pCoreCount { pCoreCount = cpu.pCoreCount }
        if eCoreCount != cpu.eCoreCount { eCoreCount = cpu.eCoreCount }
        if pCoreUsage != cpu.pCoreUsage { pCoreUsage = cpu.pCoreUsage }
        if eCoreUsage != cpu.eCoreUsage { eCoreUsage = cpu.eCoreUsage }
        if perCoreUsage != cpu.perCore { perCoreUsage = cpu.perCore }
        if overallUsage != cpu.overallUsage { overallUsage = cpu.overallUsage }
        if hasCpuSample != cpu.hasSample { hasCpuSample = cpu.hasSample }

        let soc = fansDict["socTemp"] as? Double
        if socTemp != soc { socTemp = soc }
        let cpuT = fansDict["cpuTemp"] as? Double
        if cpuTemp != cpuT { cpuTemp = cpuT }
        let gpuT = fansDict["gpuTemp"] as? Double
        if gpuTemp != gpuT { gpuTemp = gpuT }

        if let rawFans = fansDict["fans"] as? [[Double]] {
            let parsed = rawFans.compactMap { a -> FanReading? in
                guard a.count >= 6 else { return nil }
                return FanReading(index: Int(a[0]), actualRPM: a[1], targetRPM: a[2],
                                  minRPM: a[3], maxRPM: a[4], mode: Int(a[5]))
            }
            if fans != parsed { fans = parsed }
        }

        let chg = batteryDict["chargePercent"] as? Int ?? 0
        if batteryCharge != chg { batteryCharge = chg }
        let chging = batteryDict["isCharging"] as? Bool ?? false
        if isCharging != chging { isCharging = chging }
        let inh = batteryDict["chargingInhibited"] as? Bool ?? false
        if chargingInhibited != inh { chargingInhibited = inh }
        let fDis = batteryDict["forcedDischarge"] as? Bool ?? false
        if forcedDischarge != fDis { forcedDischarge = fDis }
        let hProt = batteryDict["heatProtectionActive"] as? Bool ?? false
        if heatProtectionActive != hProt { heatProtectionActive = hProt }
        let tUp = batteryDict["topUpActive"] as? Bool ?? false
        if topUpActive != tUp { topUpActive = tUp }
        let ext = batteryDict["externalConnected"] as? Bool ?? false
        if externalConnected != ext { externalConnected = ext }
        let cyc = batteryDict["cycleCount"] as? Int ?? 0
        if batteryCycles != cyc { batteryCycles = cyc }
        let bTemp = batteryDict["temperature"] as? Double
        if batteryTemp != bTemp { batteryTemp = bTemp }
        if let hp = batteryDict["healthPercent"] as? Double {
            if batteryHealthPercent != hp { batteryHealthPercent = hp }
        }

        if let hcs = batteryDict["hardwareControlSupported"] as? Bool, hardwareControlSupported != hcs {
            hardwareControlSupported = hcs
        }
        if let ncl = batteryDict["nativeChargeLimitAvailable"] as? Bool, nativeChargeLimitAvailable != ncl {
            nativeChargeLimitAvailable = ncl
        }

        let present = batteryDict["present"] as? Bool ?? (batteryDict["chargePercent"] != nil)
        let resolvedTier: BatteryControlTier = !present ? .desktopNoBattery : (hardwareControlSupported ? .directSMC : .systemManaged)
        if batteryTier != resolvedTier {
            batteryTier = resolvedTier
        }
    }
}

final class FanControlViewModel: ObservableObject {
    @Published var profile: FanProfile = .auto
    @Published var adaptiveSubProfile: AdaptiveSubProfile = .gentle
    @Published var customPercent: Double = 50
    @Published var customCurveAnchors: [CurveMilestone] = [
        CurveMilestone(temp: 45, rpmPercent: 20, label: "Cool"),
        CurveMilestone(temp: 60, rpmPercent: 35, label: "Warm"),
        CurveMilestone(temp: 75, rpmPercent: 60, label: "Hot"),
        CurveMilestone(temp: 88, rpmPercent: 90, label: "Max")
    ]

    @Published var systemPreset: SystemPreset = .none
    @Published var safetyPolicy: ThermalSafetyPolicy = .off
    @Published var thermalCeilingTemp: Double = 85.0
    @Published var isThrottlingEngaged: Bool = false
    @Published var isFanBoostEngaged: Bool = false

    var onProfileChange: ((FanProfile, Double?, AdaptiveSubProfile?, [Double]?) -> Void)?
    var onSafetyPolicyChange: ((ThermalSafetyPolicy, Double) -> Void)?
    var onPresetChange: ((SystemPreset) -> Void)?

    private var debounceWorkItem: DispatchWorkItem?

    private let defaultsKeySubProfile = "kjol.fan.adaptiveSubProfile"
    private let defaultsKeyAnchors = "kjol.fan.customCurveAnchors"

    init() {
        if let savedSub = UserDefaults.standard.string(forKey: defaultsKeySubProfile),
           let sub = AdaptiveSubProfile(rawValue: savedSub) {
            self.adaptiveSubProfile = sub
        }
        if let savedData = UserDefaults.standard.data(forKey: defaultsKeyAnchors),
           let decoded = try? JSONDecoder().decode([CurveMilestone].self, from: savedData),
           decoded.count == 4 {
            self.customCurveAnchors = decoded
        }
    }

    var flattenedCurvePoints: [Double] {
        var pts: [Double] = []
        for a in customCurveAnchors.sorted(by: { $0.temp < $1.temp }) {
            pts.append(a.temp)
            pts.append(a.rpmPercent)
        }
        return pts
    }

    func updateFromDaemon(
        profileString: String?,
        rpmPercent: Double?,
        subProfileString: String? = nil,
        curvePoints: [Double]? = nil,
        safetyPolicyString: String? = nil,
        ceilingTemp: Double? = nil,
        systemPresetString: String? = nil,
        throttlingEngaged: Bool? = nil,
        fanBoostEngaged: Bool? = nil
    ) {
        if let pStr = profileString {
            let normalized: String
            if pStr == "balanced" || pStr == "cool" {
                normalized = "adaptive"
            } else if pStr == "custom" || pStr == "quiet" {
                normalized = "manual"
            } else {
                normalized = pStr
            }
            if let prof = FanProfile(rawValue: normalized) {
                if profile != prof { profile = prof }
            }
        }
        if let subStr = subProfileString, let sub = AdaptiveSubProfile(rawValue: subStr) {
            if adaptiveSubProfile != sub {
                adaptiveSubProfile = sub
            }
        }
        if let pct = rpmPercent, pct > 0, profile == .manual {
            if customPercent != pct { customPercent = pct }
        }
        if let pts = curvePoints, pts.count >= 8, profile == .adaptive && adaptiveSubProfile == .custom {
            var newAnchors: [CurveMilestone] = []
            let labels = ["Cool", "Warm", "Hot", "Max"]
            var i = 0
            var idx = 0
            while i + 1 < pts.count && idx < 4 {
                let lbl = idx < labels.count ? labels[idx] : "Zone \(idx+1)"
                newAnchors.append(CurveMilestone(temp: pts[i], rpmPercent: pts[i + 1], label: lbl))
                i += 2
                idx += 1
            }
            if newAnchors.count == 4 && newAnchors != customCurveAnchors {
                customCurveAnchors = newAnchors
            }
        }

        if let sStr = safetyPolicyString, let pol = ThermalSafetyPolicy(rawValue: sStr) {
            if safetyPolicy != pol { safetyPolicy = pol }
        }
        if let ceil = ceilingTemp, ceil > 0 {
            if thermalCeilingTemp != ceil { thermalCeilingTemp = ceil }
        }
        if let prStr = systemPresetString, let pr = SystemPreset(rawValue: prStr) {
            if systemPreset != pr { systemPreset = pr }
        }
        if let th = throttlingEngaged {
            if isThrottlingEngaged != th { isThrottlingEngaged = th }
        }
        if let fb = fanBoostEngaged {
            if isFanBoostEngaged != fb { isFanBoostEngaged = fb }
        }
    }

    func selectSystemPreset(_ preset: SystemPreset) {
        systemPreset = preset
        if preset == .maxCompute {
            profile = .adaptive
            adaptiveSubProfile = .aggressive
            safetyPolicy = .boostFans
            thermalCeilingTemp = 95.0
        } else if preset == .gentle {
            profile = .manual
            customPercent = 25.0
            safetyPolicy = .throttleCPU
            thermalCeilingTemp = 75.0
        }
        onPresetChange?(preset)
    }

    func setThermalSafetyPolicy(_ policy: ThermalSafetyPolicy, ceiling: Double? = nil) {
        safetyPolicy = policy
        if let c = ceiling {
            thermalCeilingTemp = c
        }
        systemPreset = .none
        onSafetyPolicyChange?(policy, thermalCeilingTemp)
    }

    func setThermalCeilingTemp(_ temp: Double) {
        let snapped = round(temp / 5.0) * 5.0
        thermalCeilingTemp = snapped
        systemPreset = .none
        onSafetyPolicyChange?(safetyPolicy, snapped)
    }

    func selectProfile(_ newProfile: FanProfile) {
        systemPreset = .none
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        profile = newProfile
        notifyChange()
    }

    func selectAdaptiveSubProfile(_ newSubProfile: AdaptiveSubProfile) {
        systemPreset = .none
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        adaptiveSubProfile = newSubProfile
        UserDefaults.standard.set(newSubProfile.rawValue, forKey: defaultsKeySubProfile)
        notifyChange()
    }

    func setCustomPercent(_ pct: Double, immediate: Bool = false) {
        systemPreset = .none
        let snapped = round(pct / 5.0) * 5.0
        customPercent = snapped

        debounceWorkItem?.cancel()
        if immediate {
            debounceWorkItem = nil
            notifyChange()
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.notifyChange()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }
    }

    func updateCurveAnchorRPM(temp: Double, rpm: Double, immediate: Bool = false) {
        systemPreset = .none
        guard let idx = customCurveAnchors.firstIndex(where: { Int($0.temp) == Int(temp) }) else { return }
        let clamped = max(0, min(100, round(rpm / 5.0) * 5.0))
        customCurveAnchors[idx].rpmPercent = clamped
        if let data = try? JSONEncoder().encode(customCurveAnchors) {
            UserDefaults.standard.set(data, forKey: defaultsKeyAnchors)
        }
        debounceWorkItem?.cancel()
        if immediate {
            debounceWorkItem = nil
            notifyChange()
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.notifyChange()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }

    func resetCurveToRecommended() {
        customCurveAnchors = [
            CurveMilestone(temp: 45, rpmPercent: 20, label: "Cool"),
            CurveMilestone(temp: 60, rpmPercent: 35, label: "Warm"),
            CurveMilestone(temp: 75, rpmPercent: 60, label: "Hot"),
            CurveMilestone(temp: 88, rpmPercent: 90, label: "Max")
        ]
        if let data = try? JSONEncoder().encode(customCurveAnchors) {
            UserDefaults.standard.set(data, forKey: defaultsKeyAnchors)
        }
        notifyChange()
    }

    private func notifyChange() {
        onProfileChange?(
            profile,
            profile == .manual ? customPercent : nil,
            adaptiveSubProfile,
            flattenedCurvePoints
        )
    }
}

struct LastCalibrationRecord: Equatable {
    let completedAt: Date
    let cycleCount: Int
    let rawMaxCapacity: Int
    let designCapacity: Int
    let healthPercent: Double
    let temperature: Double

    init?(dict: [String: Any]) {
        guard let epoch = dict["completedAt"] as? Double ?? (dict["completedAt"] as? NSNumber)?.doubleValue, epoch > 0 else { return nil }
        self.completedAt = Date(timeIntervalSince1970: epoch)
        self.cycleCount = dict["cycleCount"] as? Int ?? (dict["cycleCount"] as? NSNumber)?.intValue ?? 0
        self.rawMaxCapacity = dict["rawMaxCapacity"] as? Int ?? (dict["rawMaxCapacity"] as? NSNumber)?.intValue ?? 0
        self.designCapacity = dict["designCapacity"] as? Int ?? (dict["designCapacity"] as? NSNumber)?.intValue ?? 0
        self.healthPercent = dict["healthPercent"] as? Double ?? (dict["healthPercent"] as? NSNumber)?.doubleValue ?? 0.0
        self.temperature = dict["temperature"] as? Double ?? (dict["temperature"] as? NSNumber)?.doubleValue ?? 25.0
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: completedAt, relativeTo: Date())
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: completedAt)
    }
}

final class PowerViewModel: ObservableObject {
    @Published var alwaysOn: Bool = false
    @Published var daemonsSuspended: Bool = false
    @Published var daemonsSafetyCeilingEnabled: Bool = true
    @Published var daemonsFailsafeTriggered: Bool = false
    @Published var daemonsFailsafeReason: String = ""
    @Published var chargeLimit: Int = 80
    @Published var limitEnabled: Bool = false
    @Published var sailingDiff: Int = 4
    @Published var topUpActive: Bool = false
    @Published var dischargeActive: Bool = false
    @Published var heatProtectionEnabled: Bool = false
    @Published var maxTempC: Double = 36.0
    @Published var calibrationState: String = "idle"
    @Published var calibrationProgress: Double = 0.0
    @Published var calibrationMessage: String = ""
    @Published var lastCalibration: LastCalibrationRecord?
    @Published var hardwareControlSupported: Bool = true
    @Published var nativeChargeLimitAvailable: Bool = false
    @Published var batteryHealthPercent: Double?
    @Published var batteryTier: BatteryControlTier = .systemManaged

    var onAlwaysOnToggle: ((Bool) -> Void)?
    var onDaemonsToggle: ((Bool) -> Void)?
    var onDaemonsSafetyCeilingToggle: ((Bool) -> Void)?
    var onBatteryLimitChange: ((Int, Bool) -> Void)?
    var onBatteryLimitAdvancedChange: ((Int, Bool, Int) -> Void)?
    var onTopUpToggle: ((Bool) -> Void)?
    var onDischargeToggle: ((Bool) -> Void)?
    var onHeatProtectionChange: ((Bool, Double) -> Void)?
    var onCalibrationAction: ((String) -> Void)?

    func updateHostState(hostDict: [String: Any]) {
        let ao = hostDict["always_on"] as? Bool ?? false
        if alwaysOn != ao { alwaysOn = ao }
        let ds = hostDict["daemons_suspended"] as? Bool ?? false
        if daemonsSuspended != ds { daemonsSuspended = ds }
        let dsc = hostDict["daemons_safety_ceiling_enabled"] as? Bool ?? true
        if daemonsSafetyCeilingEnabled != dsc { daemonsSafetyCeilingEnabled = dsc }
        let dft = hostDict["daemons_failsafe_triggered"] as? Bool ?? false
        if daemonsFailsafeTriggered != dft { daemonsFailsafeTriggered = dft }
        let dfr = hostDict["daemons_failsafe_reason"] as? String ?? ""
        if daemonsFailsafeReason != dfr { daemonsFailsafeReason = dfr }
    }

    func updateBatteryState(batteryDict: [String: Any]) {
        let lim = batteryDict["limit"] as? Int ?? 80
        if chargeLimit != lim { chargeLimit = lim }
        let en = batteryDict["enabled"] as? Bool ?? false
        if limitEnabled != en { limitEnabled = en }
        let sDiff = batteryDict["sailingDiff"] as? Int ?? 4
        if sailingDiff != sDiff { sailingDiff = sDiff }
        let tUp = batteryDict["topUpActive"] as? Bool ?? false
        if topUpActive != tUp { topUpActive = tUp }
        let dis = batteryDict["dischargeActive"] as? Bool ?? false
        if dischargeActive != dis { dischargeActive = dis }
        let hpEn = batteryDict["heatProtectionEnabled"] as? Bool ?? false
        if heatProtectionEnabled != hpEn { heatProtectionEnabled = hpEn }
        let mTemp = batteryDict["maxTempC"] as? Double ?? 36.0
        if maxTempC != mTemp { maxTempC = mTemp }
        let calState = batteryDict["calibrationState"] as? String ?? "idle"
        if calibrationState != calState { calibrationState = calState }
        let calProg = batteryDict["calibrationProgress"] as? Double ?? 0.0
        if calibrationProgress != calProg { calibrationProgress = calProg }
        let calMsg = batteryDict["calibrationMessage"] as? String ?? ""
        if calibrationMessage != calMsg { calibrationMessage = calMsg }

        if let lastCalDict = batteryDict["lastCalibration"] as? [String: Any] {
            let parsed = LastCalibrationRecord(dict: lastCalDict)
            if lastCalibration != parsed { lastCalibration = parsed }
        } else if lastCalibration != nil {
            lastCalibration = nil
        }

        if let hp = batteryDict["healthPercent"] as? Double {
            if batteryHealthPercent != hp { batteryHealthPercent = hp }
        }

        if let hcs = batteryDict["hardwareControlSupported"] as? Bool, hardwareControlSupported != hcs {
            hardwareControlSupported = hcs
        }
        if let ncl = batteryDict["nativeChargeLimitAvailable"] as? Bool, nativeChargeLimitAvailable != ncl {
            nativeChargeLimitAvailable = ncl
        }

        let present = batteryDict["present"] as? Bool ?? (batteryDict["chargePercent"] != nil)
        let resolvedTier: BatteryControlTier = !present ? .desktopNoBattery : (hardwareControlSupported ? .directSMC : .systemManaged)
        if batteryTier != resolvedTier {
            batteryTier = resolvedTier
        }
    }

    func toggleAlwaysOn(_ on: Bool) {
        alwaysOn = on
        onAlwaysOnToggle?(on)
    }

    func toggleDaemons(_ on: Bool) {
        daemonsSuspended = on
        onDaemonsToggle?(on)
    }

    func toggleDaemonsSafetyCeiling(_ enabled: Bool) {
        daemonsSafetyCeilingEnabled = enabled
        onDaemonsSafetyCeilingToggle?(enabled)
    }

    func setChargeLimit(_ limit: Int, enabled: Bool) {
        chargeLimit = limit
        limitEnabled = enabled
        onBatteryLimitAdvancedChange?(limit, enabled, sailingDiff)
    }

    func setSailingDiff(_ diff: Int) {
        sailingDiff = diff
        onBatteryLimitAdvancedChange?(chargeLimit, limitEnabled, diff)
    }

    func toggleTopUp(_ on: Bool) {
        topUpActive = on
        onTopUpToggle?(on)
    }

    func toggleDischarge(_ on: Bool) {
        dischargeActive = on
        onDischargeToggle?(on)
    }

    func setHeatProtection(enabled: Bool, maxTemp: Double) {
        heatProtectionEnabled = enabled
        maxTempC = maxTemp
        onHeatProtectionChange?(enabled, maxTemp)
    }

    func triggerCalibration(action: String) {
        if action == "start" {
            calibrationState = "charging100"
        } else {
            calibrationState = "idle"
        }
        onCalibrationAction?(action)
    }
}
