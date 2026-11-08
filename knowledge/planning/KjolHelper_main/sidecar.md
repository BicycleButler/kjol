---
title: Two-Agent Grill — KjolHelper Daemon (XPC + SMC + Battery)
domain: KjolHelper/main.swift
session_token: 2f163eba
grill_version: 2.5.5
status: complete
---

## Code Location
`/home/ubuntu/code/projects/kjol/KjolHelper/main.swift` (686 lines)

## Module Summary
The privileged helper daemon runs as root, hosting the `KjolHelper` class which implements `KjolHelperProtocol` through `NSXPCListenerDelegate`. It manages:
- XPC server lifecycle (mach service `com.lappier.kjol.helper`)
- Always-on power management (caffeinate + pmset + IOPMAssertion)
- Daemon suspension (pkill STOP/CONT on process list)
- Adaptive fan control with predictive thermal acceleration and 12s spin-down hysteresis
- Battery management state machine (limit, top-up, discharge, heat protection, calibration) with 4-phase calibration timer
- SMC key caching and Ftst unlock fallback for M2-M4 fan mode
- State persistence to `/var/db/kjol/` (in-memory cache + file backing)

## Key Design Decisions Under Review

### Decision 1: Ftst unlock fallback in setManual()
**Current approach:** When writing to `F%dMd` (fan mode key) fails with an error, the code checks if `Ftst` (thermalmonitord inhibit) key exists. If so, it writes `1` to `Ftst`, then retries the mode write up to 12 times with 0.5s sleeps (total 6s max).

**A)** Keep the busy-wait retry loop — it is necessary because macOS thermal firmware resets SMC state on sleep/wake, and the retry window is bounded (6s) and runs infrequently (only when user explicitly sets a manual profile).

**B)** Replace the busy-wait with a single write + error propagation — if the mode write fails, surface the error to the user immediately rather than retrying. The retry window delays the user's fan-setting action by up to 6 seconds.

**C)** Move the retry logic to the caller (Host.swift / FanViewModel) with an async operation — decouple the retry from the synchronous XPC reply pattern, allow UI to show a spinner.

**Recommendation:** A — The retry is a hardware-level necessity for M2-M4 chips where thermalmonitord resets fan mode on sleep/wake. The 6s window is permitted for a rare, user-initiated action, and replacing it with error propagation (B) would degrade UX by requiring the user to manually retry. Moving to async (C) adds complexity for marginal benefit.

### Decision 2: In-memory state cache with file backing against. direct file reads
**Current approach:** `readState()`/`writeState()` use an in-memory `stateCache` dict backed by files in `/var/db/kjol/`. All cache access is serialized through `stateQueue`. Cache is never invalidated/refreshed from disk after init.

**A)** Keep the cache as-is — the helper daemon is a singleton process (no multi-process concurrency), and the `stateQueue` serializes all access, making the cache safe. Performance is critical during the 5s fan watchdog ticks.

**B)** Add periodic cache refresh from disk (for example, every 60s) — protects against external state modifications (for example, another process or a manual edit to `/var/db/kjol/*`).

**C)** Remove the cache entirely and read from disk on every access — eliminates stale cache risks entirely, at the cost of disk I/O on every `refresh()` polling cycle (every 3s) and every fan watchdog tick (5s).

**Recommendation:** A — The helper is a singleton daemon. No external process writes to `/var/db/kjol/` during normal operation. The `stateQueue` serialization makes the cache safe, and removing it (C) would add blocking disk I/O on every telemetry poll. Option B adds complexity without a real threat model. However, a potential risk: if the daemon is restarted (crash/reboot), it re-reads from disk on init, so no stale state carries over.

### Decision 3: SIG_IGN + DispatchSource signal handlers for SIGTERM/SIGINT
**Current approach:** Lines 662-678 — the helper ignores SIGTERM/SIGINT through `signal()` (so the system cannot terminate it during sleep), but ALSO sets up `DispatchSource.makeSignalSource` for the same signals to catch them through the run loop. The `signal(SIGTERM, SIG_IGN)` call makes the `DispatchSource` handler for SIGTERM never fire.

**A)** This is a bug — `signal(SIGTERM, SIG_IGN)` on line 662 prevents the `DispatchSource` SIGTERM handler from firing, so the cleanup code on lines 665-668 (`setForcedDischarge(false)`, `setInhibitCharging(false)`) never runs on termination. SIGINT works because `signal(SIGINT, SIG_IGN)` is also set but `DispatchSource` for SIGINT... actually the two are broken.

**B)** Remove the `signal(SIGTERM, SIG_IGN)` / `signal(SIGINT, SIG_IGN)` calls — let `DispatchSource.makeSignalSource` handle the signals naturally. The `SIG_IGN` was likely added to prevent default termination, but `DispatchSource` already intercepts them.

**C)** Keep `SIG_IGN` but remove the `DispatchSource` handlers — rely on a different mechanism (for example, `atexit`) for cleanup, since the signal handlers are never triggered.

**Recommendation:** B — The `signal(SIGTERM, SIG_IGN)` and `signal(SIGINT, SIG_IGN)` calls on lines 662-663 are redundant with the `DispatchSource` handlers and actually prevent them from firing. Removing the `SIG_IGN` calls lets the `DispatchSource` signal handlers run their cleanup code (restoring normal charging on termination). This is especially important because the helper ignores `SIGINT` through `SIG_IGN`, which means during development debugging, Ctrl-C will not trigger cleanup.

## Proposed ADR

### Always-on clamshell power management
The `setAlwaysOn` method configures `pmset -a` with 12 parameters that reset macOS sleep behavior. The approach of spawning `caffeinate -u -i -m` as a subprocess (separate from `pmset`) provides defense-in-depth — `caffeinate` prevents idle sleep, while `pmset` controls the power management policy.

**Concern:** The `assertSleepDisabledOff()` verification on line 411 reads `pmset -g` output and parses for `sleepdisabled`/`disablesleep` — this is a synchronous shell call in the XPC handler, adding latency to the `setAlwaysOn` reply.

**Proposed:** Accept this latency for correctness — verifying `disablesleep` after writing it is critical for the always-on clamshell use case. Alternative: make verification async through a timer check, but the current synchronous approach makes sure that the user gets immediate feedback on whether always-on actually worked.

## Obvious Optimizations
1. Extract the hard-coded daemon list (lines 433-454) into a configurable constant or plist — the 18-daemon array is a maintenance burden if new macOS daemons need to be added.
2. The `shell()` helper (line 285) creates a new `Process` on every call — could be reused for high-frequency operations, though current call frequency is low enough that this is not a bottleneck.
3. `socTemperature()` scans up to 14 SMC keys on every cache miss — this happens only once per daemon session (cached to `/var/db/kjol/soc_temp_key`), so it is permitted.

## Grilling & Discussion

<!--2f163eba_GM_Q1_DONE-->
### Q1: Ftst unlock fallback busy-wait in setManual()
Must the 12×0.5s busy-wait retry loop in `setManual()` (lines 266-286) — which waits up to 6s for the Ftst unlock + mode write to succeed — be kept, replaced with immediate error propagation, or moved to an async caller-side retry?

**Current code (KjolHelper/main.swift line 266-286):**
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

**A) Keep as-is:** The 6s retry is a hardware-level necessity for M2-M4 where thermalmonitord resets fan mode on sleep/wake. The retry window is bounded and only runs for rare, user-initiated fan profile changes.

**B) Replace with immediate error:** If the mode write fails and Ftst unlock fails, surface the error to the user immediately. Eliminates the 6s latency but requires manual retry.

**C) Move retry to async caller:** Decouple retry from the synchronous XPC reply — return success/failure immediately, let the UI show a spinner and retry through a background task.

**Recommendation:** A — The retry is hardware-necessary. 6s latency for a rare user action is permitted. Error propagation (B) degrades UX. Async (C) adds complexity for minimal benefit.

**Reviewer:** The 6s busy-wait retry must be preserved in principle for M2-M4 thermalmonitord resets, but blocking the XPC synchronous reply thread for the full window is a significant design flaw because it serializes all daemon interactions during that period.
**Verdict:** Partially agree
**Reasoning:** The Ftst unlock fallback and retry window are justified by observed firmware behavior after sleep/wake, yet tying the retry directly to the XPC reply handler means a single fan-profile change can stall the entire XPC interface for up to 6s. A caller-side async retry (option C) or a pre-emptive Ftst write before the initial mode write would retain hardware coverage while decoupling latency from the synchronous reply path.
**Risk:** The current implementation risks XPC client-side timeouts or watchdog kills if the daemon is simultaneously handling other high-priority requests. Furthermore, the all-or-nothing 12-attempt loop conflates two distinct failure modes (Ftst unlock timing against. mode write rejection), making debugging production SMC issues opaque.

<!--2f163eba_R_Q1_DONE-->

### Q2: State cache against. disk-backed reads in Helper daemon
The helper daemon uses an in-memory `stateCache` dict (lines 265-282) with file backing to `/var/db/kjol/`. All access is serialized through `stateQueue`. The cache is never refreshed from disk after init. Must this caching scheme be kept, refreshed periodically, or removed in favor of direct disk reads?

**Current code (KjolHelper/main.swift lines 265-282):**
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

**A) Keep as-is:** Daemon is a singleton (no external writers). `stateQueue` serialization makes cache safe. Disk reads on every 3s poll + 5s watchdog tick would add blocking I/O.

**B) Add periodic refresh:** Every 60s, invalidate and re-read all keys from disk — protects against external state modifications but adds complexity for a non-existent threat model.

**C) Remove cache:** Read from disk on every access — eliminates stale cache risks but adds disk I/O on every telemetry poll and watchdog tick.

**Recommendation:** A — The daemon is a singleton process. No external process writes to `/var/db/kjol/` during normal operation. The cache improves performance on high-frequency ticks. On daemon restart, all state is re-read from disk, so no stale state carries over.

**Reviewer:** Design reviewer recommends keeping the cache with the addition of an explicit cache invalidation hook on writeState.
**Verdict:** Partially agree
**Reasoning:** The singleton/no-external-writers assumption holds in normal operation, so periodic disk refresh is unnecessary. However, the current scheme has no explicit invalidation beyond restart, so any future external mutation or XPC-driven state write could leave the cache stale without a clear repair path.
**Risk:** Stale cache after an out-of-band write to /var/db/kjol/ would persist until the daemon restarts, potentially serving outdated telemetry or fan state until then.

<!--2f163eba_R_Q2_DONE-->

## Proposed ADR

<!--END-->
