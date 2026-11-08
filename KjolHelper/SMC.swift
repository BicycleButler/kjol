
// Key map (Apple Silicon):
//   FNum  ui8   number of fans
//   F%dAc flt   actual RPM (read-only)
//   F%dTg flt   target RPM
//   F%dMn flt   min RPM   F%dMx flt   max RPM
//   F%dMd ui8   mode: 0=auto 1=manual 3=system (M5 uses lowercase F%dmd)
//   Ftst  ui8   thermalmonitord inhibit flag (M2-M4 unlock; absent M1/M5)
//   Tp??  flt   temperature sensors

import Foundation
import IOKit


struct SMCVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
struct SMCPLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0 }
struct SMCKeyInfoData { var dataSize: IOByteCount32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

enum SMCCommand: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
}

enum SMCError: Error, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case smcError(UInt8)
    case keyNotFound(String)
    case ftstUnlockInProgress
    case fanModeWriteFailed

    var description: String {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found"
        case .openFailed(let k): return "IOServiceOpen failed: \(k)"
        case .callFailed(let k): return "IOConnectCallStructMethod failed: \(k)"
        case .smcError(let r): return r == 0x84 ? "SMC key not found (0x84)" : "SMC error result: 0x\(String(r, radix: 16))"
        case .keyNotFound(let k): return "SMC key not found: \(k)"
        case .ftstUnlockInProgress: return "Ftst unlock in progress"
        case .fanModeWriteFailed: return "Fan mode write rejected by SMC"
        }
    }
}


final class SMC {
    static let shared = SMC()
    private var conn: io_connect_t = 0
    private let lock = NSLock()

    private var keyInfoCache: [String: (size: UInt32, type: UInt32)] = [:]

    private init() {}
    deinit { if conn != 0 { IOServiceClose(conn) } }

    func resetCache() {
        lock.lock(); defer { lock.unlock() }
        keyInfoCache.removeAll()
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }

    private func ensureOpen() throws {
        if conn != 0 { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { conn = 0; throw SMCError.openFailed(kr) }
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for c in s.utf8.prefix(4) { r = (r << 8) | UInt32(c) }
        return r
    }

    private func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        try ensureOpen()
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let inSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(conn, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS else { throw SMCError.callFailed(kr) }
        guard output.result == 0 else { throw SMCError.smcError(output.result) }
        return output
    }

    func keyInfo(_ key: String) throws -> (size: UInt32, type: UInt32) {
        lock.lock(); defer { lock.unlock() }
        if let cached = keyInfoCache[key] {
            return cached
        }
        var p = SMCParamStruct()
        p.key = Self.fourCC(key)
        p.data8 = SMCCommand.readKeyInfo.rawValue
        let out = try call(&p)
        let info = (UInt32(out.keyInfo.dataSize), out.keyInfo.dataType)
        keyInfoCache[key] = info
        return info
    }

    func hasKey(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    func readBytes(_ key: String) throws -> [UInt8] {
        let cachedInfo = try keyInfo(key)
        lock.lock(); defer { lock.unlock() }

        var p = SMCParamStruct()
        p.key = Self.fourCC(key)
        p.keyInfo.dataSize = cachedInfo.size
        p.data8 = SMCCommand.readBytes.rawValue
        let out = try call(&p)
        return withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(cachedInfo.size))) }
    }

    func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        let cachedInfo = try keyInfo(key)
        lock.lock(); defer { lock.unlock() }

        var p = SMCParamStruct()
        p.key = Self.fourCC(key)
        p.keyInfo.dataSize = cachedInfo.size
        p.data8 = SMCCommand.writeBytes.rawValue
        withUnsafeMutableBytes(of: &p.bytes) { buf in
            for (i, b) in bytes.prefix(32).enumerated() { buf[i] = b }
        }
        _ = try call(&p)
    }


    func readFloat(_ key: String) throws -> Float {
        let info = try keyInfo(key)
        let bytes = try readBytes(key)
        let fltType = Self.fourCC("flt ")
        let fpe2Type = Self.fourCC("fpe2")
        if info.type == fltType, bytes.count >= 4 {
            return bytes.withUnsafeBytes { $0.load(as: Float32.self) }
        } else if info.type == fpe2Type, bytes.count >= 2 {
            return Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        } else if bytes.count >= 4 {
            return bytes.withUnsafeBytes { $0.load(as: Float32.self) }
        }
        throw SMCError.keyNotFound(key)
    }

    func writeFloat(_ key: String, _ value: Float) throws {
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        try writeBytes(key, bytes)
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        let bytes = try readBytes(key)
        guard let b = bytes.first else { throw SMCError.keyNotFound(key) }
        return b
    }

    func writeUInt8(_ key: String, _ value: UInt8) throws {
        try writeBytes(key, [value])
    }

    func readUInt16(_ key: String) throws -> UInt16 {
        let bytes = try readBytes(key)
        guard bytes.count >= 2 else { throw SMCError.keyNotFound(key) }
        return bytes.withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    func readUInt32(_ key: String) throws -> UInt32 {
        let bytes = try readBytes(key)
        guard bytes.count >= 4 else { throw SMCError.keyNotFound(key) }
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    func writeUInt32(_ key: String, _ value: UInt32) throws {
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        try writeBytes(key, bytes)
    }
}


struct FanInfo: Codable {
    var index: Int
    var actualRPM: Float
    var targetRPM: Float
    var minRPM: Float
    var maxRPM: Float
    var mode: UInt8
}

final class FanController {
    static let shared = FanController()
    private let smc = SMC.shared

    private var cachedFanLimits: [Int: (minRPM: Float, maxRPM: Float)] = [:]
    private var cachedFanCount: Int?
    private var cachedSocTempKey: String?

    private lazy var modeKeyFormat: String = {
        if smc.hasKey("F0Md") { return "F%dMd" }
        if smc.hasKey("F0md") { return "F%dmd" }
        return "F%dMd"
    }()

    private func modeKey(_ i: Int) -> String { String(format: modeKeyFormat, i) }

    var fanCount: Int {
        if let count = cachedFanCount { return count }
        let count = (try? Int(smc.readUInt8("FNum"))) ?? 0
        if count > 0 { cachedFanCount = count }
        return count
    }

    func invalidateCaches() {
        cachedFanLimits.removeAll()
        cachedFanCount = nil
        cachedSocTempKey = nil
        smc.resetCache()
    }

    func fanInfo(_ i: Int) throws -> FanInfo {
        let limits: (minRPM: Float, maxRPM: Float)
        if let cached = cachedFanLimits[i] {
            limits = cached
        } else {
            let minR = (try? smc.readFloat("F\(i)Mn")) ?? 0
            let maxR = (try? smc.readFloat("F\(i)Mx")) ?? 0
            limits = (minR, maxR)
            if minR > 0 || maxR > 0 {
                cachedFanLimits[i] = limits
            }
        }

        return FanInfo(index: i,
                       actualRPM: (try? smc.readFloat("F\(i)Ac")) ?? 0,
                       targetRPM: (try? smc.readFloat("F\(i)Tg")) ?? 0,
                       minRPM: limits.minRPM,
                       maxRPM: limits.maxRPM,
                       mode: (try? smc.readUInt8(modeKey(i))) ?? 0)
    }

    func allFans() -> [FanInfo] {
        (0..<fanCount).compactMap { try? fanInfo($0) }
    }

    func setManual(_ i: Int, rpm: Float) throws {
        let info = try fanInfo(i)
        let clamped = max(info.minRPM, min(rpm, info.maxRPM))
        let mk = modeKey(i)

        do {
            try smc.writeUInt8(mk, 1)
        } catch {
            guard smc.hasKey("Ftst") else { throw SMCError.fanModeWriteFailed }
            try smc.writeUInt8("Ftst", 1)
            var unlocked = false
            for _ in 0..<2 {
                Thread.sleep(forTimeInterval: 0.1)
                if let m = try? smc.readUInt8(mk), m != 3 {
                    if (try? smc.writeUInt8(mk, 1)) != nil { unlocked = true; break }
                }
            }
            guard unlocked else { throw SMCError.ftstUnlockInProgress }
        }
        try smc.writeFloat("F\(i)Tg", clamped)
    }

    func setAuto(_ i: Int) throws {
        try? smc.writeUInt8(modeKey(i), 0)
        let anyManual = allFans().contains { $0.mode == 1 }
        if !anyManual, smc.hasKey("Ftst"), (try? smc.readUInt8("Ftst")) == 1 {
            try? smc.writeUInt8("Ftst", 0)
        }
    }

    func isManualActive(_ i: Int) -> Bool {
        guard let mode = try? smc.readUInt8(modeKey(i)) else { return false }
        return mode == 1
    }

    func isTargetRPMClose(_ i: Int, target: Float, tolerance: Float = 50.0) -> Bool {
        guard let actualTg = try? smc.readFloat("F\(i)Tg") else { return false }
        return abs(actualTg - target) <= tolerance
    }

    func setAllAuto() {
        for i in 0..<fanCount { try? setAuto(i) }
    }


    func socTemperature() -> Float? {
        if let key = cachedSocTempKey {
            if key == "UNSUPPORTED" { return nil }
            if let t = try? smc.readFloat(key), t > 5, t < 130 {
                return t
            }
            // Invalid key found in memory, invalidate and scan
            cachedSocTempKey = nil
        }

        let keyPath = "/var/db/kjol/soc_temp_key"
        if cachedSocTempKey == nil, let savedKey = try? String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !savedKey.isEmpty {
            if savedKey == "UNSUPPORTED" {
                cachedSocTempKey = savedKey
                return nil
            }
            if let t = try? smc.readFloat(savedKey), t > 5, t < 130 {
                cachedSocTempKey = savedKey
                return t
            }
        }

        let candidates = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tg05", "Tg0D", "Tg0L", "Tg0T"]
        var bestKey: String?
        var maxVal: Float?
        for k in candidates {
            if let t = try? smc.readFloat(k), t > 5, t < 130 {
                if maxVal == nil || t > maxVal! {
                    maxVal = t
                    bestKey = k
                }
            }
        }

        let finalKey = bestKey ?? "UNSUPPORTED"
        cachedSocTempKey = finalKey
        try? finalKey.write(toFile: keyPath, atomically: true, encoding: .utf8)

        return maxVal
    }

    func cpuTemperatures() -> Float? {
        let candidates = ["Tc0p", "Tc0P", "Tc0D", "Tc0H", "Tc0a", "Tc0b", "Tp01", "Tp05"]
        let temps = candidates.compactMap { k -> Float? in
            guard let t = try? smc.readFloat(k), t > 5, t < 130 else { return nil }
            return t
        }
        return temps.max()
    }

    func gpuTemperatures() -> Float? {
        let candidates = ["Tg0p", "Tg0P", "Tg0D", "Tg0H", "Tg0a", "Tg0b", "Tg05"]
        let temps = candidates.compactMap { k -> Float? in
            guard let t = try? smc.readFloat(k), t > 5, t < 130 else { return nil }
            return t
        }
        return temps.max()
    }
}

final class BatteryController {
    static let shared = BatteryController()
    private let smc = SMC.shared
    private let lock = NSLock()
    private(set) var chargingInhibited = false
    private(set) var forcedDischargeActive = false
    private(set) var heatProtectionActive = false

    var hardwareControlSupported: Bool {
        // macOS 27 and newer restrict direct third-party SMC battery charge writes.
        if #available(macOS 27.0, *) {
            return false
        }
        return smc.hasKey("CHTE") || smc.hasKey("CH0B") || smc.hasKey("CH0C") || smc.hasKey("BCLM")
    }

    var nativeChargeLimitAvailable: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    @discardableResult
    private func writeSmartKey(_ key: String, _ value: UInt32) -> Bool {
        guard smc.hasKey(key) else { return false }
        do {
            let info = try smc.keyInfo(key)
            if info.size == 1 {
                try smc.writeUInt8(key, UInt8(value & 0xFF))
            } else if info.size == 2 {
                let v16 = UInt16(value & 0xFFFF)
                var v = v16
                let bytes = withUnsafeBytes(of: &v) { Array($0) }
                try smc.writeBytes(key, bytes)
            } else {
                try smc.writeUInt32(key, value)
            }
            return true
        } catch {
            fputs("KjolHelper: SMC write failed for key \(key): \(error)\n", stderr)
            return false
        }
    }

    func setInhibitCharging(_ inhibit: Bool) throws {
        lock.lock()
        defer { lock.unlock() }

        guard hardwareControlSupported else {
            chargingInhibited = false
            return
        }

        var writeSuccess = false
        for key in ["CHTE", "CH0B", "CH0C"] {
            if smc.hasKey(key) {
                let val: UInt32 = (key == "CHTE") ? (inhibit ? 1 : 0) : (inhibit ? 2 : 0)
                if writeSmartKey(key, val) {
                    writeSuccess = true
                }
            }
        }

        chargingInhibited = writeSuccess ? inhibit : false
    }

    func setForcedDischarge(_ discharge: Bool) throws {
        lock.lock()
        defer { lock.unlock() }

        var success = false
        if smc.hasKey("CHIE") {
            if writeSmartKey("CHIE", discharge ? 0x08 : 0x00) {
                success = true
            }
        }
        if smc.hasKey("CH0I") {
            if writeSmartKey("CH0I", discharge ? 0x01 : 0x00) {
                success = true
            }
        }

        forcedDischargeActive = success ? discharge : false
    }

    func batteryTemperature() -> Double? {
        let keys = ["TB0T", "TB1T", "TB2T", "TB0p"]
        for k in keys {
            if let t = try? smc.readFloat(k), t > 0, t < 100 {
                return Double(t)
            }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var propDict: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propDict?.takeRetainedValue() as? [String: Any],
               let temp = dict["Temperature"] as? Double {
                return temp / 100.0
            }
        }
        return nil
    }

    struct CalibrationConfig {
        static let holdDurationSeconds: TimeInterval = 3600.0 // 60 minutes
        static let dischargeTargetFloor: Int = 15 // Discharge to 15%
        static let phase1Weight: Double = 0.3 // 0% - 30% progress
        static let phase2Weight: Double = 0.2 // 30% - 50% progress
        static let phase3Weight: Double = 0.3 // 50% - 80% progress
        static let phase4Weight: Double = 0.2 // 80% - 100% progress
    }

    func evaluateBatteryManagement(limit: Int,
                                   enabled: Bool,
                                   sailingDiff: Int,
                                   topUpActive: inout Bool,
                                   dischargeActive: inout Bool,
                                   heatProtectionEnabled: Bool,
                                   maxTempC: Double,
                                   calibrationState: inout String,
                                   calibrationHoldStartTime: inout Double,
                                   calibrationProgress: inout Double,
                                   calibrationMessage: inout String) {
        if smc.hasKey("BCLM") {
            let bclmVal = enabled ? UInt32(max(20, min(100, limit))) : 100
            writeSmartKey("BCLM", bclmVal)
        }

        let info = getBatteryInfo()
        guard let currentCap = info["chargePercent"] as? Int else { return }
        let externalConnected = (info["externalConnected"] as? Bool) ?? false
        let currentTemp = batteryTemperature() ?? 25.0

        // 1. Safety Cutoffs: if unplugged or battery is critically low, always stop forced discharge
        if !externalConnected || currentCap <= 10 {
            if forcedDischargeActive { try? setForcedDischarge(false) }
            if dischargeActive { dischargeActive = false }
            if !externalConnected && topUpActive { topUpActive = false }
        }

        // 2. Battery Calibration State Machine
        if calibrationState != "idle" && calibrationState != "completed" {
            switch calibrationState {
            case "charging100":
                calibrationProgress = Double(currentCap) / 100.0 * CalibrationConfig.phase1Weight
                calibrationMessage = "Phase 1/4: Charging to 100% (\(currentCap)%)"
                try? setForcedDischarge(false)
                try? setInhibitCharging(false)
                if currentCap >= 100 {
                    calibrationState = "holding100"
                    calibrationHoldStartTime = Date().timeIntervalSince1970
                }
                return

            case "holding100":
                let elapsed = Date().timeIntervalSince1970 - calibrationHoldStartTime
                let holdTarget: Double = CalibrationConfig.holdDurationSeconds
                let fraction = min(1.0, elapsed / holdTarget)
                calibrationProgress = CalibrationConfig.phase1Weight + fraction * CalibrationConfig.phase2Weight
                let remainingMins = max(1, Int((holdTarget - elapsed) / 60))
                calibrationMessage = "Phase 2/4: Soaking at 100% (\(remainingMins)m remaining)"
                try? setForcedDischarge(false)
                try? setInhibitCharging(false)
                if elapsed >= holdTarget {
                    calibrationState = "discharging15"
                }
                return

            case "discharging15":
                let floor = CalibrationConfig.dischargeTargetFloor
                let dischargeFraction = max(0.0, min(1.0, Double(100 - currentCap) / Double(max(1, 100 - floor))))
                let baseProgress = CalibrationConfig.phase1Weight + CalibrationConfig.phase2Weight
                calibrationProgress = baseProgress + dischargeFraction * CalibrationConfig.phase3Weight
                calibrationMessage = "Phase 3/4: Discharging on AC to \(floor)% (\(currentCap)%)"
                if currentCap > floor && externalConnected {
                    try? setForcedDischarge(true)
                } else {
                    try? setForcedDischarge(false)
                    calibrationState = "rechargingLimit"
                }
                return

            case "rechargingLimit":
                let floor = CalibrationConfig.dischargeTargetFloor
                let rechargeTarget = enabled ? limit : 80
                let rechargeFraction = max(0.0, min(1.0, Double(currentCap - floor) / Double(max(1, rechargeTarget - floor))))
                let baseProgress = CalibrationConfig.phase1Weight + CalibrationConfig.phase2Weight + CalibrationConfig.phase3Weight
                calibrationProgress = baseProgress + rechargeFraction * CalibrationConfig.phase4Weight
                calibrationMessage = "Phase 4/4: Recharging to target \(rechargeTarget)% (\(currentCap)%)"
                try? setForcedDischarge(false)
                try? setInhibitCharging(false)
                if currentCap >= rechargeTarget {
                    calibrationState = "completed"
                    calibrationProgress = 1.0
                    calibrationMessage = "Calibration complete!"
                    try? setInhibitCharging(true)
                }
                return

            default:
                break
            }
        }

        // 3. Forced Discharge / Discharge on AC mode
        if dischargeActive {
            if externalConnected && currentCap > limit {
                try? setForcedDischarge(true)
                return
            } else {
                try? setForcedDischarge(false)
                try? setInhibitCharging(true)
                dischargeActive = false
            }
        } else if forcedDischargeActive {
            try? setForcedDischarge(false)
        }

        // 4. Top Up Mode (Temporary 100% boost for travel)
        if topUpActive {
            if currentCap >= 100 {
                try? setInhibitCharging(true)
            } else {
                try? setInhibitCharging(false)
            }
            return
        }

        // 5. Overheating Protection (Thermal Gating)
        if heatProtectionEnabled {
            if currentTemp >= maxTempC {
                heatProtectionActive = true
                try? setInhibitCharging(true)
                return
            } else if heatProtectionActive {
                if currentTemp <= (maxTempC - 2.0) {
                    heatProtectionActive = false
                } else {
                    try? setInhibitCharging(true)
                    return
                }
            }
        } else {
            heatProtectionActive = false
        }

        // 6. Normal Limiter with Configurable Sailing Mode Hysteresis
        guard enabled else {
            try? setInhibitCharging(false)
            return
        }

        let effectiveSailing = max(1, min(15, sailingDiff))
        let lowerBound = max(1, limit - effectiveSailing)

        if chargingInhibited {
            if currentCap < lowerBound {
                try? setInhibitCharging(false)
            } else {
                try? setInhibitCharging(true)
            }
        } else {
            if currentCap >= limit {
                try? setInhibitCharging(true)
            } else {
                try? setInhibitCharging(false)
            }
        }
    }

    func setChargeLimit(_ limit: Int, enabled: Bool) throws {
        var topUp = false
        var discharge = false
        var calState = "idle"
        var calHold = 0.0
        var calProg = 0.0
        var calMsg = ""
        evaluateBatteryManagement(limit: limit,
                                  enabled: enabled,
                                  sailingDiff: 4,
                                  topUpActive: &topUp,
                                  dischargeActive: &discharge,
                                  heatProtectionEnabled: false,
                                  maxTempC: 36.0,
                                  calibrationState: &calState,
                                  calibrationHoldStartTime: &calHold,
                                  calibrationProgress: &calProg,
                                  calibrationMessage: &calMsg)
    }

    func getBatteryInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        if smc.hasKey("BCLM") {
            info["bclm"] = try? Int(smc.readUInt8("BCLM"))
        }
        if smc.hasKey("BATP") {
            info["present"] = ((try? smc.readUInt8("BATP")) ?? 0) != 0
        }
        if smc.hasKey("B0CT") {
            if let count = try? smc.readUInt16("B0CT") {
                info["cycleCount"] = Int(count)
            } else if let count = try? smc.readFloat("B0CT") {
                info["cycleCount"] = Int(count)
            }
        }

        if let temp = batteryTemperature() {
            info["temperature"] = temp
        }

        // Determine current hardware inhibit & forced discharge state
        if smc.hasKey("CHTE") {
            let chteVal = (try? smc.readUInt32("CHTE")) ?? 0
            info["chargingInhibited"] = (chteVal != 0)
        } else if smc.hasKey("CH0C") {
            let ch0cVal = (try? smc.readUInt8("CH0C")) ?? 0
            info["chargingInhibited"] = (ch0cVal != 0)
        } else {
            info["chargingInhibited"] = chargingInhibited
        }

        if smc.hasKey("CHIE") {
            let chieVal = (try? smc.readUInt8("CHIE")) ?? 0
            info["forcedDischarge"] = (chieVal == 0x08)
        } else {
            info["forcedDischarge"] = forcedDischargeActive
        }

        info["heatProtectionActive"] = heatProtectionActive

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var propDict: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propDict, kCFAllocatorDefault, 0) == KERN_SUCCESS, let dict = propDict?.takeRetainedValue() as? [String: Any] {
                if let cap = dict["CurrentCapacity"] as? Int { info["chargePercent"] = cap }
                if let isCharging = dict["IsCharging"] as? Bool { info["isCharging"] = isCharging }
                if let external = dict["ExternalConnected"] as? Bool { info["externalConnected"] = external }
                if let cycles = dict["CycleCount"] as? Int, info["cycleCount"] == nil { info["cycleCount"] = cycles }
                if let temp = dict["Temperature"] as? Double, info["temperature"] == nil { info["temperature"] = temp / 100.0 }
                if let health = dict["Health"] as? String { info["health"] = health }
                if let rawMax = dict["AppleRawMaxCapacity"] as? Int ?? dict["NominalChargeCapacity"] as? Int ?? dict["MaxCapacity"] as? Int {
                    info["rawMaxCapacity"] = rawMax
                }
                if let design = dict["DesignCapacity"] as? Int {
                    info["designCapacity"] = design
                }
                if let rawMax = info["rawMaxCapacity"] as? Int, let design = info["designCapacity"] as? Int, design > 0 {
                    let hp = (Double(rawMax) / Double(design)) * 100.0
                    info["healthPercent"] = max(0.0, min(100.0, (hp * 10.0).rounded() / 10.0))
                }
            }
        }
        info["hardwareControlSupported"] = hardwareControlSupported
        info["nativeChargeLimitAvailable"] = nativeChargeLimitAvailable
        return info
    }
}
