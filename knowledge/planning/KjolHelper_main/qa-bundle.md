# QA Bundle — Two-Agent Grill Session 2f163eba

## Session Info
- **Token:** 2f163eba
- **Domain:** KjolHelper/main.swift (privileged helper daemon)
- **GM Model:** gpt-4o (Hermes Agent master)
- **Reviewer Model:** stepfun/step-3.7-flash:free
- **Date:** 2026-09-01

## Q1: Ftst unlock fallback busy-wait in setManual()

### Question
Must the 12×0.5s busy-wait retry loop in `setManual()` (KjolHelper/main.swift lines 266-286) — which waits up to 6s for the Ftst unlock + mode write to succeed — be kept, replaced with immediate error propagation, or moved to an async caller-side retry?

### Current Code (lines 266-286)
```swift
func setManual(_ i: Int, rpm: Float) throws {
    let info = try fanInfo(i)
    let clamped = max(info.minRPM, min(rpm, info.maxRPM))
    let mk = modeKey(i)
    do {
        try smc.writeUInt8(mk, 1)
    } catch {
        guard smc.hasKey("Ftst") else { throw error }
        try smc.writeUInt8("Ftst", 1)
        var unlocked = false
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.5)
            if let m = try? smc.readUInt8(mk), m != 3 {
                if (try? smc.writeUInt8(mk, 1)) != nil { unlocked = true; break }
            }
        }
        guard unlocked else { throw error }
    }
    try smc.writeFloat("F\(i)Tg", clamped)
}
```

### Options
**A) Keep as-is:** The 6s retry is a hardware-level necessity for M2-M4 where thermalmonitord resets fan mode on sleep/wake. The retry window is bounded and only runs for rare, user-initiated fan profile changes.

**B) Replace with immediate error:** If the mode write fails and Ftst unlock fails, surface the error to the user immediately. Eliminates the 6s latency but requires manual retry.

**C) Move retry to async caller:** Decouple retry from the synchronous XPC reply — return success/failure immediately, let the UI show a spinner and retry through a background task.

### GM Recommendation
A — The retry is hardware-necessary. 6s latency for a rare user action is permitted. Error propagation (B) degrades UX. Async (C) adds complexity for minimal benefit.

### Reviewer Verdict
**Partially agree**

### Reviewer Reasoning
The Ftst unlock fallback and retry window are justified by observed firmware behavior after sleep/wake, yet tying the retry directly to the XPC reply handler means a single fan-profile change can stall the entire XPC interface for up to 6s. A caller-side async retry (option C) or a pre-emptive Ftst write before the initial mode write would retain hardware coverage while decoupling latency from the synchronous reply path.

### Reviewer Risk
The current implementation risks XPC client-side timeouts or watchdog kills if the daemon is simultaneously handling other high-priority requests. Furthermore, the all-or-nothing 12-attempt loop conflates two distinct failure modes (Ftst unlock timing against. mode write rejection), making debugging production SMC issues opaque.

## Q2: State cache against. disk-backed reads in Helper daemon

### Question
The helper daemon uses an in-memory `stateCache` dict (lines 265-282) with file backing to `/var/db/kjol/`. All access is serialized through `stateQueue`. The cache is never refreshed from disk after init. Must this caching scheme be kept, refreshed periodically, or removed in favor of direct disk reads?

### Current Code (lines 265-282)
```swift
private func writeState(_ key: String, _ value: String) {
    stateQueue.sync {
        stateCache[key] = value
        let path = "\(stateDir)/\(key)"
        try? value.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
private func readState(_ key: String) -> String {
    return stateQueue.sync {
        if let cached = stateCache[key] { return cached }
        let value = (try? String(contentsOfFile: "\(stateDir)/\(key)", encoding: .utf8)) ?? ""
        stateCache[key] = value
        return value
    }
}
```

### Options
**A) Keep as-is:** Daemon is a singleton (no external writers). `stateQueue` serialization makes cache safe. Disk reads on every 3s poll + 5s watchdog tick would add blocking I/O.

**B) Add periodic refresh:** Every 60s, invalidate and re-read all keys from disk — protects against external state modifications but adds complexity for a non-existent threat model.

**C) Remove cache:** Read from disk on every access — eliminates stale cache risks but adds disk I/O on every telemetry poll and watchdog tick.

### GM Recommendation
A — The daemon is a singleton process. No external process writes to `/var/db/kjol/` during normal operation. The cache improves performance on high-frequency ticks. On daemon restart, all state is re-read from disk, so no stale state carries over.

### Reviewer Verdict
**Partially agree**

### Reviewer Reasoning
The singleton/no-external-writers assumption holds in normal operation, so periodic disk refresh is unnecessary. However, the current scheme has no explicit invalidation beyond restart, so any future external mutation or XPC-driven state write could leave the cache stale without a clear repair path.

### Reviewer Risk
Stale cache after an out-of-band write to /var/db/kjol/ would persist until the daemon restarts, potentially serving outdated telemetry or fan state until then.

## Proposed ADR

## Obvious Optimizations (from GM)
1. Extract the hard-coded daemon list (lines 433-454) into a configurable constant or plist — the 18-daemon array is a maintenance burden if new macOS daemons need to be added.
2. The `shell()` helper (line 285) creates a new `Process` on every call — could be reused for high-frequency operations, though current call frequency is low enough that this is not a bottleneck.
3. `socTemperature()` scans up to 14 SMC keys on every cache miss — this happens only once per daemon session (cached to `/var/db/kjol/soc_temp_key`), so it is permitted.
