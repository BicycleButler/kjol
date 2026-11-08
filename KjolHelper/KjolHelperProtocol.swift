import Foundation

public enum KjolXPCError: Error, LocalizedError, CustomNSError {
    case notConnected
    case helperUnavailable
    case interrupted
    case helperError(String)
    case invalidResponse

    public static var errorDomain: String { "com.lappier.kjol.xpc" }

    public var errorCode: Int {
        switch self {
        case .notConnected: return 1
        case .helperUnavailable: return 2
        case .interrupted: return 3
        case .helperError: return 4
        case .invalidResponse: return 5
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Helper not connected"
        case .helperUnavailable: return "Helper daemon unavailable"
        case .interrupted: return "XPC connection interrupted"
        case .helperError(let msg): return msg
        case .invalidResponse: return "Invalid response from helper"
        }
    }

    public static func makeNSError(message: String) -> NSError {
        return NSError(
            domain: errorDomain,
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

@objc(KjolHelperProtocol)
public protocol KjolHelperProtocol {
    func setAlwaysOn(_ on: Bool, reply: @escaping (Bool, NSError?) -> Void)

    func suspendDaemons(_ on: Bool, reply: @escaping (Bool, NSError?) -> Void)

    func setDaemonSafetyCeiling(_ enabled: Bool, reply: @escaping (Bool, NSError?) -> Void)

    func getStatus(reply: @escaping ([String: Any]?, NSError?) -> Void)

    func getFanStatus(reply: @escaping ([String: Any]?, NSError?) -> Void)

    func getCombinedStatus(reply: @escaping ([String: Any]?, NSError?) -> Void)

    func setFanProfile(_ profile: String, rpmPercent: Double, targetTempC: Double, reply: @escaping (Bool, NSError?) -> Void)

    func setFanAdaptiveProfile(subProfile: String, curvePoints: [Double], reply: @escaping (Bool, NSError?) -> Void)

    func setThermalSafetyPolicy(policy: String, ceilingTempC: Double, reply: @escaping (Bool, NSError?) -> Void)

    func setSystemPreset(preset: String, reply: @escaping (Bool, NSError?) -> Void)

    func setBatteryLimit(_ limit: Int, enabled: Bool, reply: @escaping (Bool, NSError?) -> Void)

    func setBatteryLimitAdvanced(_ limit: Int, enabled: Bool, sailingDiff: Int, reply: @escaping (Bool, NSError?) -> Void)

    func setTopUpMode(_ enabled: Bool, reply: @escaping (Bool, NSError?) -> Void)

    func setDischargeMode(_ enabled: Bool, reply: @escaping (Bool, NSError?) -> Void)

    func setHeatProtection(_ enabled: Bool, maxTempC: Double, reply: @escaping (Bool, NSError?) -> Void)

    func setCalibrationMode(_ action: String, reply: @escaping (Bool, NSError?) -> Void)

    func getBatteryStatus(reply: @escaping ([String: Any]?, NSError?) -> Void)
}
