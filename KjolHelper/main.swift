import Foundation
import XPC
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Security
import CoreGraphics

private let kIOMsgCommon: UInt32 = 0x38 << 26
private let kMsgCanSleep = kIOMsgCommon | 0x270
private let kMsgWillSleep = kIOMsgCommon | 0x280
private let kMsgHasPoweredOn = kIOMsgCommon | 0x300

final class KjolHelper: NSObject, KjolHelperProtocol, NSXPCListenerDelegate {

    private let stateDir = "/var/db/kjol"
    private var stateCache: [String: String] = [:]
    private let stateQueue = DispatchQueue(label: "com.lappier.kjol.helper.state")

    private var iopsRunLoopSource: CFRunLoopSource?
    private var rootPowerPort: io_connect_t = 0
    private var powerNotifyPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var clamshellNotifier: io_object_t = 0
    private var clamshellTimer: DispatchSourceTimer?
    private var lastClamshellClosed: Bool? = nil

    private var topUpActive = false
    private var dischargeActive = false
    private var calibrationState = "idle"
    private var calibrationHoldStartTime: Double = 0
    private var calibrationProgress: Double = 0
    private var calibrationMessage = ""

    override init() {
        super.init()
        setupStateDir()
        cleanupOrphanedCaffeinate()
        let alwaysOn = readState("always_on")
        if alwaysOn == "1" {
            alwaysOnActive = true
            startCaffeinate()
            runPmset(["-a", "disablesleep", "1", "lowpowermode", "0", "powernap", "0", "sleep", "0", "displaysleep", "10", "disksleep", "0", "standby", "0", "hibernatemode", "0", "ttyskeepawake", "1", "lessbright", "0"])
            startClamshellWatchdogIfNeeded()
            checkClamshellState()
        }

        topUpActive = readState("top_up_active") == "1"
        dischargeActive = readState("discharge_active") == "1"
        calibrationState = readState("calibration_state").isEmpty ? "idle" : readState("calibration_state")
        if calibrationState == "holding100" {
            let savedHold = Double(readState("calibration_hold_start_time")) ?? 0
            if savedHold > 0 {
                calibrationHoldStartTime = savedHold
            }
        }
        evaluateBatteryState()
        try? evaluateFanManagement()
        if readState("daemons_suspended") == "1" {
            checkDaemonFailsafe()
            if readState("daemons_suspended") == "1" {
                startDaemonFailsafeTimerIfNeeded()
            }
        }
        setupPowerMonitoring()
    }

    private func setupPowerMonitoring() {
        // 1. Event-driven power source change notification (fired on battery %, charger connect/disconnect)
        let iopsCallback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let helper = Unmanaged<KjolHelper>.fromOpaque(context).takeUnretainedValue()
            helper.onPowerSourceChanged()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(iopsCallback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            iopsRunLoopSource = source
        }

        // 2. Kernel sleep/wake notifications (re-evaluates limit immediately upon system wake)
        let powerCallback: IOServiceInterestCallback = { refCon, service, messageType, messageArgument in
            guard let refCon = refCon else { return }
            let helper = Unmanaged<KjolHelper>.fromOpaque(refCon).takeUnretainedValue()
            helper.onSystemPowerMessage(messageType: messageType, argument: messageArgument)
        }

        var notifier: io_object_t = 0
        let rootPort = IORegisterForSystemPower(context, &powerNotifyPort, powerCallback, &notifier)
        if rootPort != 0, let notifyPort = powerNotifyPort {
            rootPowerPort = rootPort
            powerNotifier = notifier
            if let rlSource = IONotificationPortGetRunLoopSource(notifyPort)?.takeRetainedValue() {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), rlSource, .commonModes)
            }

            // 3. Clamshell notifications on IOPMrootDomain
            let clamshellCallback: IOServiceInterestCallback = { refCon, service, messageType, messageArgument in
                guard let refCon = refCon else { return }
                let helper = Unmanaged<KjolHelper>.fromOpaque(refCon).takeUnretainedValue()
                helper.checkClamshellState()
            }
            let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            if rootDomain != 0 {
                IOServiceAddInterestNotification(notifyPort, rootDomain, kIOGeneralInterest, clamshellCallback, context, &clamshellNotifier)
                IOObjectRelease(rootDomain)
            }
        }
    }

    private var calibrationTimer: DispatchSourceTimer?
    private var batteryWatchdogTimer: DispatchSourceTimer?

    private func startBatteryWatchdogIfNeeded() {
        let enabled = readState("battery_limit_enabled") == "1"
        let active = enabled || topUpActive || dischargeActive || calibrationState != "idle"
        guard active else {
            stopBatteryWatchdog()
            return
        }
        guard batteryWatchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 15.0, repeating: 15.0)
        timer.setEventHandler { [weak self] in
            self?.evaluateBatteryState()
        }
        timer.resume()
        batteryWatchdogTimer = timer
    }

    private func stopBatteryWatchdog() {
        batteryWatchdogTimer?.cancel()
        batteryWatchdogTimer = nil
    }

    private func recordCalibrationCompletion() {
        let info = BatteryController.shared.getBatteryInfo()
        let cycles = (info["cycleCount"] as? Int) ?? 0
        let rawMax = (info["rawMaxCapacity"] as? Int) ?? 0
        let design = (info["designCapacity"] as? Int) ?? 0
        let temp = (info["temperature"] as? Double) ?? 25.0
        let hp = (info["healthPercent"] as? Double) ?? (design > 0 ? (Double(rawMax) / Double(design)) * 100.0 : 100.0)

        let record: [String: Any] = [
            "completedAt": Date().timeIntervalSince1970,
            "cycleCount": cycles,
            "rawMaxCapacity": rawMax,
            "designCapacity": design,
            "healthPercent": max(0.0, min(100.0, (hp * 10.0).rounded() / 10.0)),
            "temperature": temp
        ]

        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted]) {
            let path = "\(stateDir)/last_calibration.json"
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private func readLastCalibrationRecord() -> [String: Any]? {
        let path = "\(stateDir)/last_calibration.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func evaluateBatteryState() {
        let batLimit = Int(readState("battery_limit")) ?? 80
        let batEnabled = readState("battery_limit_enabled") == "1"
        let sailingDiff = Int(readState("battery_sailing_diff")) ?? 4
        let heatProtEnabled = readState("heat_protection_enabled") == "1"
        let maxTempC = Double(readState("heat_protection_temp")) ?? 36.0

        let oldTopUp = topUpActive
        let oldDischarge = dischargeActive
        let oldCalState = calibrationState
        let oldHoldTime = calibrationHoldStartTime

        BatteryController.shared.evaluateBatteryManagement(
            limit: batLimit,
            enabled: batEnabled,
            sailingDiff: sailingDiff,
            topUpActive: &topUpActive,
            dischargeActive: &dischargeActive,
            heatProtectionEnabled: heatProtEnabled,
            maxTempC: maxTempC,
            calibrationState: &calibrationState,
            calibrationHoldStartTime: &calibrationHoldStartTime,
            calibrationProgress: &calibrationProgress,
            calibrationMessage: &calibrationMessage
        )

        if oldTopUp != topUpActive { writeState("top_up_active", topUpActive ? "1" : "0") }
        if oldDischarge != dischargeActive { writeState("discharge_active", dischargeActive ? "1" : "0") }
        if oldCalState != calibrationState {
            writeState("calibration_state", calibrationState)
            if calibrationState == "completed" {
                recordCalibrationCompletion()
            }
        }
        if oldHoldTime != calibrationHoldStartTime {
            writeState("calibration_hold_start_time", calibrationHoldStartTime > 0 ? String(calibrationHoldStartTime) : "")
        }

        // Run timer only during active multi-phase calibration
        if calibrationState != "idle" && calibrationState != "completed" {
            startCalibrationTimerIfNeeded()
        } else {
            stopCalibrationTimer()
        }

        startBatteryWatchdogIfNeeded()
    }

    private func startCalibrationTimerIfNeeded() {
        guard calibrationTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10.0)
        timer.setEventHandler { [weak self] in
            self?.evaluateBatteryState()
        }
        timer.resume()
        calibrationTimer = timer
    }

    private func stopCalibrationTimer() {
        calibrationTimer?.cancel()
        calibrationTimer = nil
    }

    private var daemonFailsafeTimer: DispatchSourceTimer?

    private func checkDaemonFailsafe() {
        let suspended = readState("daemons_suspended") == "1"
        guard suspended else { return }

        // 1. Mandatory Health Arbiter (Always active, even in Persistent Mode):
        // A. Critical Battery (<=8% on battery power without AC adapter)
        let isBattery = readState("power_source") == "battery"
        let batteryPct = Int(readState("battery_percent")) ?? 100
        if isBattery && batteryPct <= 8 {
            fputs("KjolHelper: Critical battery safety trigger (<=8%). Auto-resuming suspended daemons to allow graceful system sleep.\n", stderr)
            suspendNonEssentialDaemons(false)
            writeState("daemons_suspended", "0")
            writeState("failsafe_triggered", "1")
            writeState("failsafe_reason", "critical_battery")
            stopDaemonFailsafeTimer()
            return
        }

        // B. Extreme Thermal Runaway (Max junction temp >= 105C)
        let socT = FanController.shared.socTemperature() ?? 0
        let cpuT = FanController.shared.cpuTemperatures() ?? 0
        let gpuT = FanController.shared.gpuTemperatures() ?? 0
        let maxJunctionT = max(socT, max(cpuT, gpuT))
        if maxJunctionT >= 105.0 {
            fputs("KjolHelper: Extreme thermal runaway (>=105C). Auto-resuming suspended daemons.\n", stderr)
            suspendNonEssentialDaemons(false)
            writeState("daemons_suspended", "0")
            writeState("failsafe_triggered", "1")
            writeState("failsafe_reason", "thermal_critical")
            stopDaemonFailsafeTimer()
            return
        }

        // 2. 4-Hour Safety Ceiling (only evaluated if enabled by user)
        let ceilingEnabled = readState("daemons_safety_ceiling_enabled") != "0"
        if ceilingEnabled {
            if let startTime = Double(readState("failsafe_start_time")), startTime > 0 {
                let elapsed = Date().timeIntervalSince1970 - startTime
                if elapsed >= 14400.0 { // 4 hours
                    fputs("KjolHelper: Daemon suspension 4-hour safety ceiling triggered. Auto-resuming suspended daemons.\n", stderr)
                    suspendNonEssentialDaemons(false)
                    writeState("daemons_suspended", "0")
                    writeState("failsafe_triggered", "1")
                    writeState("failsafe_reason", "safety_ceiling_timeout")
                    stopDaemonFailsafeTimer()
                }
            }
        }
    }

    private func startDaemonFailsafeTimerIfNeeded() {
        guard daemonFailsafeTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 60, repeating: 60.0)
        timer.setEventHandler { [weak self] in
            self?.checkDaemonFailsafe()
        }
        timer.resume()
        daemonFailsafeTimer = timer
    }

    private func stopDaemonFailsafeTimer() {
        daemonFailsafeTimer?.cancel()
        daemonFailsafeTimer = nil
    }

    private func onPowerSourceChanged() {
        evaluateBatteryState()
        try? evaluateFanManagement()
        checkClamshellState()
    }

    private func onSystemPowerMessage(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case kMsgCanSleep, kMsgWillSleep:
            IOAllowPowerChange(rootPowerPort, Int(bitPattern: argument))
        case kMsgHasPoweredOn:
            evaluateBatteryState()
            try? evaluateFanManagement()
            checkClamshellState()
        default:
            break
        }
    }

    private var fanWatchdogTimer: DispatchSourceTimer?
    private var lastAdaptiveTemp: Float = 0.0
    private var adaptivePeakHoldPct: Double = 0.0
    private var adaptiveHoldUntilTime: Double = 0.0
    private var gentleSmoothedTemp: Float = 0.0
    private var gentlePeakHoldPct: Double = 0.0
    private var gentleHoldUntilTime: Double = 0.0
    private var customPeakHoldPct: Double = 0.0
    private var customHoldUntilTime: Double = 0.0

    private var thermalThrottlingEngaged: Bool = false
    private var thermalThrottleHoldUntil: Double = 0.0
    private var fanSafetyBoostEngaged: Bool = false
    private var fanSafetyBoostHoldUntil: Double = 0.0

    private func parseCurvePoints(_ raw: String) -> [(temp: Float, rpm: Float)] {
        let parts = raw.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        var result: [(temp: Float, rpm: Float)] = []
        var i = 0
        while i + 1 < parts.count {
            result.append((temp: parts[i], rpm: parts[i + 1]))
            i += 2
        }
        if result.count < 2 {
            return [
                (temp: 45.0, rpm: 20.0),
                (temp: 60.0, rpm: 35.0),
                (temp: 75.0, rpm: 60.0),
                (temp: 88.0, rpm: 90.0)
            ]
        }
        return result.sorted { $0.temp < $1.temp }
    }

    private func evaluatePiecewiseCurve(temp: Float, points: [(temp: Float, rpm: Float)]) -> Double {
        guard !points.isEmpty else { return 50.0 }
        if temp <= points.first!.temp { return Double(points.first!.rpm) }
        if temp >= points.last!.temp { return Double(points.last!.rpm) }
        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            if temp >= p0.temp && temp <= p1.temp {
                let range = p1.temp - p0.temp
                guard range > 0 else { return Double(p0.rpm) }
                let frac = (temp - p0.temp) / range
                let val = p0.rpm + frac * (p1.rpm - p0.rpm)
                return Double(val)
            }
        }
        return Double(points.last!.rpm)
    }

    private func evaluateFanManagement() throws {
        let savedProfile = readState("fan_profile")
        let safetyPolicy = readState("thermal_safety_policy")
        let needsWatchdog = (!savedProfile.isEmpty && savedProfile != "auto") || (safetyPolicy == "throttleCPU" || safetyPolicy == "boostFans")

        if !needsWatchdog {
            stopFanWatchdog()
            if savedProfile == "auto" {
                FanController.shared.setAllAuto()
            }
            return
        }

        try applyFanProfile()
        startFanWatchdogIfNeeded()
    }

    private func startFanWatchdogIfNeeded() {
        guard fanWatchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.tickFanWatchdog()
        }
        timer.resume()
        fanWatchdogTimer = timer
    }

    private func stopFanWatchdog() {
        fanWatchdogTimer?.cancel()
        fanWatchdogTimer = nil
    }

    private func tickFanWatchdog() {
        let savedProfile = readState("fan_profile")
        let safetyPolicy = readState("thermal_safety_policy")
        let needsWatchdog = (!savedProfile.isEmpty && savedProfile != "auto") || (safetyPolicy == "throttleCPU" || safetyPolicy == "boostFans")

        guard needsWatchdog else {
            stopFanWatchdog()
            return
        }
        try? applyFanProfile()
    }

    private func applyFanProfile() throws {
        let fc = FanController.shared
        let count = fc.fanCount

        // 1. Evaluate Max Junction Temperature across SoC, CPU, and GPU
        let socT = fc.socTemperature() ?? 0
        let cpuT = fc.cpuTemperatures() ?? 0
        let gpuT = fc.gpuTemperatures() ?? 0
        let currentTemp = max(socT, max(cpuT, gpuT))

        // 2. Evaluate Thermal Safety Arbiter Policy
        let safetyPolicy = readState("thermal_safety_policy")
        let ceilingTemp = Double(readState("thermal_ceiling_temp")) ?? 85.0
        let now = Date().timeIntervalSince1970

        if safetyPolicy == "throttleCPU" {
            if currentTemp >= Float(ceilingTemp) {
                if !thermalThrottlingEngaged {
                    thermalThrottlingEngaged = true
                    shell(["/usr/bin/pmset", "-a", "lowpowermode", "1"])
                }
                thermalThrottleHoldUntil = now + 15.0
            } else if thermalThrottlingEngaged && currentTemp <= Float(ceilingTemp - 5.0) && now >= thermalThrottleHoldUntil {
                thermalThrottlingEngaged = false
                let sysPreset = readState("system_preset")
                if sysPreset != "gentle" {
                    shell(["/usr/bin/pmset", "-a", "lowpowermode", "0"])
                }
            }
        } else if thermalThrottlingEngaged {
            thermalThrottlingEngaged = false
            let sysPreset = readState("system_preset")
            if sysPreset != "gentle" {
                shell(["/usr/bin/pmset", "-a", "lowpowermode", "0"])
            }
        }

        if safetyPolicy == "boostFans" {
            if currentTemp >= Float(ceilingTemp) {
                if !fanSafetyBoostEngaged {
                    fanSafetyBoostEngaged = true
                }
                fanSafetyBoostHoldUntil = now + 15.0
            } else if fanSafetyBoostEngaged && currentTemp <= Float(ceilingTemp - 5.0) && now >= fanSafetyBoostHoldUntil {
                fanSafetyBoostEngaged = false
            }
        } else {
            fanSafetyBoostEngaged = false
        }

        // If fan safety boost is engaged, yield manual control to native macOS SMC so fans spin to safe speeds!
        if fanSafetyBoostEngaged {
            fc.setAllAuto()
            return
        }

        guard count > 0 else { return }

        let savedProfile = readState("fan_profile")
        if savedProfile.isEmpty || savedProfile == "auto" {
            fc.setAllAuto()
            return
        }

        var targetPercent: Double = 0.0

        if savedProfile == "adaptive" || savedProfile == "balanced" {
            let subProfile = readState("fan_adaptive_subprofile")
            let now = Date().timeIntervalSince1970

            if subProfile == "aggressive" {
                let aggressivePoints: [(temp: Float, rpm: Float)] = [
                    (temp: 40.0, rpm: 15.0),
                    (temp: 55.0, rpm: 35.0),
                    (temp: 70.0, rpm: 70.0),
                    (temp: 85.0, rpm: 100.0)
                ]
                let calculatedPct = evaluatePiecewiseCurve(temp: currentTemp, points: aggressivePoints)

                // Predictive Thermal Acceleration:
                // Boost target if rapid rise (>= +2°C / 5s) or nearing 68°C+
                if lastAdaptiveTemp > 0 {
                    let deltaT = currentTemp - lastAdaptiveTemp
                    if deltaT >= 2.0 || (currentTemp >= 68.0 && deltaT > 0.5) {
                        let proactiveBoost = Double(max(15.0, deltaT * 8.0))
                        let boostedPct = min(100.0, calculatedPct + proactiveBoost)
                        if boostedPct > adaptivePeakHoldPct {
                            adaptivePeakHoldPct = boostedPct
                            adaptiveHoldUntilTime = now + 12.0 // 12-second asymmetric spin-down hold
                        }
                    }
                }
                lastAdaptiveTemp = currentTemp

                if now < adaptiveHoldUntilTime {
                    targetPercent = max(calculatedPct, adaptivePeakHoldPct)
                } else {
                    targetPercent = calculatedPct
                    adaptivePeakHoldPct = calculatedPct
                }
                targetPercent = max(15.0, min(100.0, targetPercent))
            } else if subProfile == "custom" {
                let customPoints = parseCurvePoints(readState("fan_curve_points"))
                let calculatedPct = evaluatePiecewiseCurve(temp: currentTemp, points: customPoints)

                // 10-second asymmetric spin-down hold to prevent hunting around anchor thresholds
                if calculatedPct > customPeakHoldPct {
                    customPeakHoldPct = calculatedPct
                    customHoldUntilTime = now + 10.0
                }
                if now < customHoldUntilTime {
                    targetPercent = max(calculatedPct, customPeakHoldPct)
                } else {
                    targetPercent = calculatedPct
                    customPeakHoldPct = calculatedPct
                }
                targetPercent = max(0.0, min(100.0, targetPercent))
            } else {
                // Default: "gentle" (Cool Native)
                let gentlePoints: [(temp: Float, rpm: Float)] = [
                    (temp: 45.0, rpm: 18.0),
                    (temp: 60.0, rpm: 30.0),
                    (temp: 75.0, rpm: 55.0),
                    (temp: 90.0, rpm: 90.0)
                ]
                // Low-pass EMA smoothing: alpha = 0.35
                if gentleSmoothedTemp <= 0.0 {
                    gentleSmoothedTemp = currentTemp
                } else {
                    gentleSmoothedTemp = (gentleSmoothedTemp * 0.65) + (currentTemp * 0.35)
                }
                let calculatedPct = evaluatePiecewiseCurve(temp: gentleSmoothedTemp, points: gentlePoints)

                // 20-second gradual spin-down hold for whisper-quiet acoustic transitions
                if calculatedPct > gentlePeakHoldPct {
                    gentlePeakHoldPct = calculatedPct
                    gentleHoldUntilTime = now + 20.0
                }
                if now < gentleHoldUntilTime {
                    targetPercent = max(calculatedPct, gentlePeakHoldPct)
                } else {
                    targetPercent = calculatedPct
                    gentlePeakHoldPct = calculatedPct
                }
                targetPercent = max(15.0, min(100.0, targetPercent))
            }
        } else if savedProfile == "blast" {
            targetPercent = 100.0
        } else if savedProfile == "manual" || savedProfile == "custom" {
            targetPercent = max(0.0, min(100.0, Double(readState("fan_rpm_percent")) ?? 50.0))
        } else if savedProfile == "quiet" {
            targetPercent = 25.0
        }

        // Apply proportional target to each fan and verify persistence
        for i in 0..<count {
            let info = try fc.fanInfo(i)
            let desiredRPM = info.minRPM + Float(targetPercent / 100.0) * (info.maxRPM - info.minRPM)
            // If manual mode was cleared by macOS thermalmonitord (e.g. on lid close) or RPM drifted, re-assert
            if !fc.isManualActive(i) || !fc.isTargetRPMClose(i, target: desiredRPM, tolerance: 75.0) {
                try fc.setManual(i, rpm: desiredRPM)
            }
        }
    }

    private func setupStateDir() {
        try? FileManager.default.createDirectory(atPath: stateDir,
                                                  withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
    }

    // Cache-coherency contract: the cache is a write-through mirror of `/var/db/kjol/`
    // and is only mutated by the daemon's own XPC handlers. External out-of-band writes
    // are unsupported and will not be reflected until daemon restart.
    private func writeState(_ key: String, _ value: String) {
        stateQueue.sync {
            stateCache[key] = value
            let path = "\(stateDir)/\(key)"
            try? value.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func readState(_ key: String) -> String {
        return stateQueue.sync {
            if let cached = stateCache[key] {
                return cached
            }
            let value = (try? String(contentsOfFile: "\(stateDir)/\(key)", encoding: .utf8)) ?? ""
            stateCache[key] = value
            return value
        }
    }

    @discardableResult
    private func shell(_ args: [String]) -> (output: String, exitCode: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()

            // Fixed timeout to prevent stalling
            let timeoutTask = DispatchWorkItem {
                if task.isRunning {
                    task.terminate()
                    fputs("KjolHelper: shell task timed out: \(args)\n", stderr)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0, execute: timeoutTask)

            task.waitUntilExit()
            timeoutTask.cancel()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, task.terminationStatus)
        } catch {
            fputs("KjolHelper: shell process failed for \(args): \(error.localizedDescription)\n", stderr)
            return (error.localizedDescription, 1)
        }
    }

    private var alwaysOnActive = false
    private var caffeinateProcess: Process?

    private var powerAssertion: IOPMAssertionID = 0
    private var powerAssertionActive = false

    private func setPowerAssertion(_ reason: String) {
        clearPowerAssertion()
        var assertionID: IOPMAssertionID = 0
        let props: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertionTypeNoIdleSleep,
            kIOPMAssertionNameKey: reason,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn
        ]
        let kr = IOPMAssertionCreateWithProperties(props as CFDictionary, &assertionID)
        if kr == kIOReturnSuccess, assertionID != 0 {
            powerAssertion = assertionID
            powerAssertionActive = true
        } else {
            fputs("KjolHelper: IOPMAssertionCreateWithProperties failed: 0x\(String(kr, radix: 16))\n", stderr)
        }
    }

    private func clearPowerAssertion() {
        powerAssertionActive = false
        if powerAssertion != 0 {
            IOPMAssertionRelease(powerAssertion)
            powerAssertion = 0
        }
    }

    private func cleanupOrphanedCaffeinate() {
        shell(["/bin/launchctl", "bootout", "system/com.lappier.kjol.caffeinate"])
        try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.lappier.kjol.caffeinate.plist")
        shell(["/usr/bin/pkill", "-x", "caffeinate"])
    }

    func isClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            if let boolVal = prop as? Bool {
                return boolVal
            }
            if let numVal = prop as? NSNumber {
                return numVal.boolValue
            }
        }
        return false
    }

    func isExternalDisplayConnected() -> Bool {
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(0, nil, &count) == .success && count > 0 {
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetOnlineDisplayList(count, &displays, &count) == .success {
                for d in displays {
                    if CGDisplayIsBuiltin(d) == 0 {
                        return true
                    }
                }
                return false
            }
        }

        // Fallback to IOKit if WindowServer / CoreGraphics is not yet accessible
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        // In IOPMrootDomain, AppleClamshellCausesSleep can be false if sleep is disabled via pmset,
        // so we only trust it if sleep is NOT disabled.
        let sleepDisabled = readState("always_on") == "1"
        if !sleepDisabled {
            if let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellCausesSleep" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if let boolVal = prop as? Bool {
                    return !boolVal
                }
                if let numVal = prop as? NSNumber {
                    return !numVal.boolValue
                }
            }
        }
        return false
    }

    func checkClamshellState() {
        guard alwaysOnActive else { return }
        let closed = isClamshellClosed()
        if lastClamshellClosed == nil || closed != lastClamshellClosed {
            lastClamshellClosed = closed
            if closed {
                if !isExternalDisplayConnected() {
                    fputs("KjolHelper: Clamshell lid closed with Always-On active -> sleeping display\n", stderr)
                    runPmset(["displaysleepnow"])
                    runPmset(["-a", "displaysleep", "1"])
                }
            } else {
                fputs("KjolHelper: Clamshell lid opened with Always-On active -> waking display\n", stderr)
                runPmset(["-a", "displaysleep", "10"])
                shell(["/usr/bin/caffeinate", "-u", "-t", "1"])
            }
        }
    }

    private func startClamshellWatchdogIfNeeded() {
        guard alwaysOnActive else {
            stopClamshellWatchdog()
            return
        }
        guard clamshellTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkClamshellState()
        }
        timer.resume()
        clamshellTimer = timer
    }

    private func stopClamshellWatchdog() {
        clamshellTimer?.cancel()
        clamshellTimer = nil
        lastClamshellClosed = nil
    }

    func cleanup() {
        stopCaffeinate()
        cleanupOrphanedCaffeinate()
        stopClamshellWatchdog()
        if alwaysOnActive {
            runPmset(["-a", "disablesleep", "0", "displaysleep", "10"])
        }
    }

    private func startCaffeinate() {
        stopCaffeinate()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i", "-m"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            caffeinateProcess = process
        } catch {
            fputs("KjolHelper: Failed to start caffeinate process: \(error)\n", stderr)
        }
    }

    private func stopCaffeinate() {
        if let process = caffeinateProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        caffeinateProcess = nil
    }

    private func caffeinateRunning() -> Bool {
        return caffeinateProcess?.isRunning ?? false
    }

    func setAlwaysOn(_ on: Bool, reply: @escaping (Bool, NSError?) -> Void) {
        if on {
            guard !alwaysOnActive else {
                reply(true, nil)
                return
            }

            startCaffeinate()

            runPmset(["-a", "disablesleep", "1", "lowpowermode", "0", "powernap", "0", "sleep", "0", "displaysleep", "10", "disksleep", "0", "standby", "0", "hibernatemode", "0", "ttyskeepawake", "1", "lessbright", "0"])

            writeState("always_on", "1")
            writeState("sleep_disabled_ok", "1")
            writeState("sleep_disabled_detail", "caffeinate -i -m active")
            alwaysOnActive = true
            startClamshellWatchdogIfNeeded()
            checkClamshellState()
            reply(true, nil)
        } else {
            alwaysOnActive = false
            stopClamshellWatchdog()
            stopCaffeinate()
            writeState("always_on", "0")
            writeState("sleep_disabled_ok", "0")
            writeState("sleep_disabled_detail", "")
            runPmset(["-a", "disablesleep", "0", "lowpowermode", "1", "powernap", "1", "sleep", "1", "displaysleep", "10", "disksleep", "10", "standby", "1", "hibernatemode", "3", "lessbright", "1"])
            shell(["/usr/bin/caffeinate", "-u", "-t", "1"])
            reply(true, nil)
        }
    }

    func suspendDaemons(_ on: Bool, reply: @escaping (Bool, NSError?) -> Void) {
        suspendNonEssentialDaemons(on)
        writeState("daemons_suspended", on ? "1" : "0")
        if on {
            writeState("failsafe_start_time", String(Date().timeIntervalSince1970))
            writeState("failsafe_triggered", "0")
            writeState("failsafe_reason", "")
            startDaemonFailsafeTimerIfNeeded()
        } else {
            stopDaemonFailsafeTimer()
            writeState("failsafe_start_time", "")
            writeState("failsafe_triggered", "0")
            writeState("failsafe_reason", "")
        }
        reply(true, nil)
    }

    func setDaemonSafetyCeiling(_ enabled: Bool, reply: @escaping (Bool, NSError?) -> Void) {
        writeState("daemons_safety_ceiling_enabled", enabled ? "1" : "0")
        if enabled && readState("daemons_suspended") == "1" {
            writeState("failsafe_start_time", String(Date().timeIntervalSince1970))
            startDaemonFailsafeTimerIfNeeded()
        }
        reply(true, nil)
    }

    private func runPmset(_ args: [String]) {
        let result = shell(["/usr/bin/pmset"] + args)
        if result.exitCode != 0 {
            fputs("KjolHelper: pmset failed: \(result.output)\n", stderr)
        }
    }

    @discardableResult
    private func assertSleepDisabledOn() -> (ok: Bool, detail: String) {
        return (true, "caffeinate -i -m active")
    }

    private let defaultFreezeDaemons = [
        "mediaanalysisd",
        "photoanalysisd",
        "triald",
        "analyticsd",
        "parsecd",
        "backupd",
        "knowledge-agent"
    ]

    private let defaultThrottleDaemons = [
        "mds",
        "corespotlightd",
        "spotlightknowledged",
        "mdworker",
        "managedcorespotlightd",
        "mds_stores",
        "suggestd",
        "routined",
        "siriknowledged",
        "touristd",
        "coreduetd"
    ]

    private func getCategorizedDaemons() -> (freeze: [String], throttle: [String]) {
        let plistPath = "/var/db/kjol/suspended_daemons.plist"
        var statBuf = stat()
        if stat(plistPath, &statBuf) == 0 {
            let isRoot = statBuf.st_uid == 0
            let isWheel = statBuf.st_gid == 0
            let notWritableByOthers = (statBuf.st_mode & 0o22) == 0

            if isRoot && isWheel && notWritableByOthers {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    if let dict = plist as? [String: [String]] {
                        let freeze = dict["freeze"] ?? defaultFreezeDaemons
                        let throttle = dict["throttle"] ?? defaultThrottleDaemons
                        return (freeze, throttle)
                    } else if let array = plist as? [String] {
                        let freezeSet = Set(defaultFreezeDaemons)
                        let freeze = array.filter { freezeSet.contains($0) }
                        let throttle = array.filter { !freezeSet.contains($0) }
                        return (freeze, throttle)
                    }
                } else {
                    fputs("KjolHelper: Failed to parse \(plistPath). Falling back to defaults.\n", stderr)
                }
            } else {
                fputs("KjolHelper: Invalid permissions or ownership for \(plistPath). Falling back to defaults.\n", stderr)
            }
        }
        return (defaultFreezeDaemons, defaultThrottleDaemons)
    }

    private func suspendNonEssentialDaemons(_ on: Bool) {
        let (freezeList, throttleList) = getCategorizedDaemons()
        let freezePattern = freezeList.joined(separator: "|")
        let throttlePattern = throttleList.joined(separator: "|")

        if on {
            // 1. Halt new Spotlight indexing generation
            shell(["/usr/bin/mdutil", "-a", "-i", "off"])

            // 2. Freeze purely asynchronous batch daemons via SIGSTOP
            if !freezePattern.isEmpty {
                shell(["/usr/bin/pkill", "-STOP", "-f", freezePattern])
            }

            // 3. Demote synchronous/IPC daemons to Darwin background QoS & lowest I/O tier.
            // This confines them strictly to E-cores with IOPOL_THROTTLE, eliminating P-core contention
            // while preserving IPC responsiveness (preventing UI beachballs and file dialog hangs).
            if !throttlePattern.isEmpty {
                let pgrepResult = shell(["/usr/bin/pgrep", "-f", throttlePattern])
                let pids = pgrepResult.output
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for pid in pids {
                    shell(["/usr/sbin/taskpolicy", "-b", "-t", "3", "-p", pid])
                }
            }

            // 4. Actively reclaim unified RAM: purge inactive file cache and purgeable buffers
            shell(["/usr/sbin/purge"])
        } else {
            // 1. Unfreeze batch daemons via SIGCONT
            if !freezePattern.isEmpty {
                shell(["/usr/bin/pkill", "-CONT", "-f", freezePattern])
            }

            // 2. Restore normal Darwin QoS and default I/O tier for throttled daemons
            if !throttlePattern.isEmpty {
                let pgrepResult = shell(["/usr/bin/pgrep", "-f", throttlePattern])
                let pids = pgrepResult.output
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for pid in pids {
                    shell(["/usr/sbin/taskpolicy", "-B", "-t", "0", "-p", pid])
                }
            }

            // 3. Re-enable Spotlight indexing
            shell(["/usr/bin/mdutil", "-a", "-i", "on"])
        }
    }

    private func hostStatusDict() -> [String: Any] {
        let alwaysOn = readState("always_on")
        let daemonsSuspended = readState("daemons_suspended")
        let failsafeTriggered = readState("failsafe_triggered")
        let safetyCeilingEnabled = readState("daemons_safety_ceiling_enabled") != "0"
        let failsafeReason = readState("failsafe_reason")

        return [
            "always_on": alwaysOn == "1",
            "daemons_suspended": daemonsSuspended == "1",
            "daemons_safety_ceiling_enabled": safetyCeilingEnabled,
            "daemons_failsafe_triggered": failsafeTriggered == "1",
            "daemons_failsafe_reason": failsafeReason,
            "caffeinate_running": caffeinateRunning(),
            "caffeinate_pid": caffeinateRunning() ? String(caffeinateProcess!.processIdentifier) : "",
            "sleep_disabled_ok": readState("sleep_disabled_ok") != "0",
            "sleep_disabled_detail": readState("sleep_disabled_detail")
        ]
    }

    private func fanStatusDict() -> [String: Any] {
        let fc = FanController.shared

        let fans = fc.allFans().map { f -> [Double] in
            [Double(f.index), Double(f.actualRPM), Double(f.targetRPM),
             Double(f.minRPM), Double(f.maxRPM), Double(f.mode)]
        }
        let savedSub = readState("fan_adaptive_subprofile")
        let savedSafety = readState("thermal_safety_policy")
        let savedCeiling = Double(readState("thermal_ceiling_temp")) ?? 85.0
        let savedPreset = readState("system_preset")

        var out: [String: Any] = [
            "fanCount": fc.fanCount,
            "fans": fans,
            "profile": readState("fan_profile").isEmpty ? "auto" : readState("fan_profile"),
            "rpmPercent": Double(readState("fan_rpm_percent")) ?? 0,
            "adaptiveSubProfile": savedSub.isEmpty ? "gentle" : savedSub,
            "safetyPolicy": savedSafety.isEmpty ? "off" : savedSafety,
            "ceilingTemp": savedCeiling,
            "systemPreset": savedPreset.isEmpty ? "none" : savedPreset,
            "throttlingEngaged": thermalThrottlingEngaged,
            "fanBoostEngaged": fanSafetyBoostEngaged
        ]
        let rawPoints = readState("fan_curve_points")
        if !rawPoints.isEmpty {
            let pts = rawPoints.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if !pts.isEmpty {
                out["curvePoints"] = pts
            }
        }
        if let t = fc.socTemperature() { out["socTemp"] = Double(t) }
        if let t = fc.cpuTemperatures() { out["cpuTemp"] = Double(t) }
        if let t = fc.gpuTemperatures() { out["gpuTemp"] = Double(t) }
        return out
    }

    func getStatus(reply: @escaping ([String: Any]?, NSError?) -> Void) {
        reply(hostStatusDict(), nil)
    }

    func getFanStatus(reply: @escaping ([String: Any]?, NSError?) -> Void) {
        reply(fanStatusDict(), nil)
    }

    func getCombinedStatus(reply: @escaping ([String: Any]?, NSError?) -> Void) {
        reply([
            "host": hostStatusDict(),
            "fans": fanStatusDict()
        ], nil)
    }

    func setFanProfile(_ profile: String, rpmPercent: Double, targetTempC: Double, reply: @escaping (Bool, NSError?) -> Void) {
        let fc = FanController.shared
        let count = fc.fanCount
        guard count > 0 else {
            reply(false, KjolXPCError.makeNSError(message: "No fans detected"))
            return
        }

        do {
            if readState("system_preset") != "none" {
                writeState("system_preset", "none")
            }

            if profile == "auto" {
                writeState("fan_profile", "auto")
                writeState("fan_rpm_percent", "0")
                fc.setAllAuto()
                stopFanWatchdog()
                reply(true, nil)
                return
            }

            if profile == "adaptive" || profile == "balanced" {
                writeState("fan_profile", "adaptive")
                if readState("fan_adaptive_subprofile").isEmpty {
                    writeState("fan_adaptive_subprofile", "gentle")
                }
                writeState("fan_rpm_percent", "0")
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if profile == "adaptive_gentle" {
                writeState("fan_profile", "adaptive")
                writeState("fan_adaptive_subprofile", "gentle")
                writeState("fan_rpm_percent", "0")
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if profile == "adaptive_aggressive" {
                writeState("fan_profile", "adaptive")
                writeState("fan_adaptive_subprofile", "aggressive")
                writeState("fan_rpm_percent", "0")
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if profile == "adaptive_custom" {
                writeState("fan_profile", "adaptive")
                writeState("fan_adaptive_subprofile", "custom")
                writeState("fan_rpm_percent", "0")
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if profile == "quiet" {
                writeState("fan_profile", "manual")
                writeState("fan_rpm_percent", "25")
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if profile == "blast" {
                writeState("fan_profile", "blast")
                writeState("fan_rpm_percent", "100")
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if profile == "manual" || profile == "custom" {
                let clamped = max(0, min(rpmPercent, 100))
                writeState("fan_profile", "manual")
                writeState("fan_rpm_percent", String(Int(clamped)))
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            // Default fallback: auto
            writeState("fan_profile", "auto")
            fc.setAllAuto()
            stopFanWatchdog()
            reply(true, nil)
        } catch SMCError.ftstUnlockInProgress {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ftst unlock in progress"]))
        } catch SMCError.fanModeWriteFailed {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fan mode write rejected by SMC"]))
        } catch {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 3, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
        }
    }

    func setFanAdaptiveProfile(subProfile: String, curvePoints: [Double], reply: @escaping (Bool, NSError?) -> Void) {
        let fc = FanController.shared
        guard fc.fanCount > 0 else {
            reply(false, KjolXPCError.makeNSError(message: "No fans detected"))
            return
        }

        do {
            if readState("system_preset") != "none" {
                writeState("system_preset", "none")
            }
            writeState("fan_profile", "adaptive")
            let validSub = (subProfile == "aggressive" || subProfile == "custom") ? subProfile : "gentle"
            writeState("fan_adaptive_subprofile", validSub)
            if !curvePoints.isEmpty {
                let formatted = curvePoints.map { String(format: "%.1f", $0) }.joined(separator: ",")
                writeState("fan_curve_points", formatted)
            }
            writeState("fan_rpm_percent", "0")
            try evaluateFanManagement()
            reply(true, nil)
        } catch SMCError.ftstUnlockInProgress {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ftst unlock in progress"]))
        } catch SMCError.fanModeWriteFailed {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fan mode write rejected by SMC"]))
        } catch {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 3, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
        }
    }

    func setThermalSafetyPolicy(policy: String, ceilingTempC: Double, reply: @escaping (Bool, NSError?) -> Void) {
        let validPolicy = (policy == "boostFans" || policy == "throttleCPU") ? policy : "off"
        writeState("thermal_safety_policy", validPolicy)
        let clampedCeiling = max(65.0, min(105.0, ceilingTempC))
        writeState("thermal_ceiling_temp", String(format: "%.1f", clampedCeiling))
        if readState("system_preset") != "none" {
            writeState("system_preset", "none")
        }
        try? evaluateFanManagement()
        reply(true, nil)
    }

    func setSystemPreset(preset: String, reply: @escaping (Bool, NSError?) -> Void) {
        do {
            if preset == "maxCompute" {
                writeState("system_preset", "maxCompute")
                writeState("fan_profile", "adaptive")
                writeState("fan_adaptive_subprofile", "aggressive")
                writeState("thermal_safety_policy", "boostFans")
                writeState("thermal_ceiling_temp", "95.0")
                shell(["/usr/bin/pmset", "-a", "lowpowermode", "0"])
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            if preset == "gentle" {
                writeState("system_preset", "gentle")
                writeState("fan_profile", "manual")
                writeState("fan_rpm_percent", "25")
                writeState("thermal_safety_policy", "throttleCPU")
                writeState("thermal_ceiling_temp", "75.0")
                shell(["/usr/bin/pmset", "-a", "lowpowermode", "1"])
                try evaluateFanManagement()
                reply(true, nil)
                return
            }

            writeState("system_preset", "none")
            reply(true, nil)
        } catch {
            reply(false, NSError(domain: "com.lappier.kjol.smc", code: 3, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]))
        }
    }

    func setBatteryLimit(_ limit: Int, enabled: Bool, reply: @escaping (Bool, NSError?) -> Void) {
        writeState("battery_limit", String(limit))
        writeState("battery_limit_enabled", enabled ? "1" : "0")
        evaluateBatteryState()
        reply(true, nil)
    }

    func setBatteryLimitAdvanced(_ limit: Int, enabled: Bool, sailingDiff: Int, reply: @escaping (Bool, NSError?) -> Void) {
        writeState("battery_limit", String(limit))
        writeState("battery_limit_enabled", enabled ? "1" : "0")
        writeState("battery_sailing_diff", String(sailingDiff))
        evaluateBatteryState()
        reply(true, nil)
    }

    func setTopUpMode(_ enabled: Bool, reply: @escaping (Bool, NSError?) -> Void) {
        topUpActive = enabled
        writeState("top_up_active", enabled ? "1" : "0")
        evaluateBatteryState()
        reply(true, nil)
    }

    func setDischargeMode(_ enabled: Bool, reply: @escaping (Bool, NSError?) -> Void) {
        dischargeActive = enabled
        writeState("discharge_active", enabled ? "1" : "0")
        evaluateBatteryState()
        reply(true, nil)
    }

    func setHeatProtection(_ enabled: Bool, maxTempC: Double, reply: @escaping (Bool, NSError?) -> Void) {
        writeState("heat_protection_enabled", enabled ? "1" : "0")
        writeState("heat_protection_temp", String(format: "%.1f", maxTempC))
        evaluateBatteryState()
        reply(true, nil)
    }

    func setCalibrationMode(_ action: String, reply: @escaping (Bool, NSError?) -> Void) {
        if action == "start" {
            calibrationState = "charging100"
            calibrationHoldStartTime = 0
            calibrationProgress = 0.0
            calibrationMessage = "Starting battery calibration..."
            writeState("calibration_hold_start_time", "")
        } else {
            calibrationState = "idle"
            calibrationHoldStartTime = 0
            calibrationProgress = 0.0
            calibrationMessage = ""
            writeState("calibration_hold_start_time", "")
            try? BatteryController.shared.setForcedDischarge(false)
        }
        writeState("calibration_state", calibrationState)
        evaluateBatteryState()
        reply(true, nil)
    }

    func getBatteryStatus(reply: @escaping ([String: Any]?, NSError?) -> Void) {
        evaluateBatteryState()

        var info = BatteryController.shared.getBatteryInfo()
        let limit = Int(readState("battery_limit")) ?? 80
        let enabled = readState("battery_limit_enabled") == "1"
        let sailingDiff = Int(readState("battery_sailing_diff")) ?? 4
        let heatProtEnabled = readState("heat_protection_enabled") == "1"
        let maxTempC = Double(readState("heat_protection_temp")) ?? 36.0

        info["limit"] = limit
        info["enabled"] = enabled
        info["sailingDiff"] = sailingDiff
        info["topUpActive"] = topUpActive
        info["dischargeActive"] = dischargeActive
        info["heatProtectionEnabled"] = heatProtEnabled
        info["maxTempC"] = maxTempC
        info["calibrationState"] = calibrationState
        info["calibrationProgress"] = calibrationProgress
        info["calibrationMessage"] = calibrationMessage

        if let lastCal = readLastCalibrationRecord() {
            info["lastCalibration"] = lastCal
        }

        reply(info, nil)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: KjolHelperProtocol.self)
        newConnection.exportedObject = self

        newConnection.invalidationHandler = {
        }

        newConnection.resume()
        return true
    }
}

let helper = KjolHelper()
let listener = NSXPCListener(machServiceName: "com.lappier.kjol.helper")
listener.delegate = helper
listener.resume()

// Ensure normal charging, power connections, and processes are restored if helper daemon is terminated
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: DispatchQueue.main)
termSource.setEventHandler {
    var hasError = false
    helper.cleanup()
    do {
        try BatteryController.shared.setForcedDischarge(false)
    } catch {
        fputs("KjolHelper: Termination cleanup failed for forced discharge: \(error)\n", stderr)
        hasError = true
    }
    do {
        try BatteryController.shared.setInhibitCharging(false)
    } catch {
        fputs("KjolHelper: Termination cleanup failed for inhibit charging: \(error)\n", stderr)
        hasError = true
    }
    exit(hasError ? 1 : 0)
}
termSource.resume()

let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.main)
intSource.setEventHandler {
    var hasError = false
    helper.cleanup()
    do {
        try BatteryController.shared.setForcedDischarge(false)
    } catch {
        fputs("KjolHelper: Termination cleanup failed for forced discharge: \(error)\n", stderr)
        hasError = true
    }
    do {
        try BatteryController.shared.setInhibitCharging(false)
    } catch {
        fputs("KjolHelper: Termination cleanup failed for inhibit charging: \(error)\n", stderr)
        hasError = true
    }
    exit(hasError ? 1 : 0)
}
intSource.resume()

RunLoop.current.run()

