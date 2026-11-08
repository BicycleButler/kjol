# Kjol Optimization Research — Findings & Implementation Plan

**Date:** 2026-08-25
**Author:** Automated research swarm (6 waves, 18 sub-agents)
**Source:** Full codebase analysis + cross-referenced validator assessments

## Executive Summary

A 6-wave research swarm analyzed the Kjol codebase for optimization opportunities across architecture, performance, platform integration, and correctness. The research converged on **13 ranked tasks** across **4 implementation phases**, with the highest-impact items being:

1. **Cache static SMC values** — eliminates ~20–30 redundant SMC IOKit calls per poll cycle
2. **Split Host god class** — 540-line class → 4 testable services + thin coordinator
3. **Modernize XPC protocol** — async/await + typed errors + connection security
4. **Merge getStatus + getFanStatus** — halves IPC round-trips per poll

Several researched items were **conclusively deferred** (batch SMC reads: not feasible with AppleSMC IOKit. ProcessThrottler: higher complexity than pkill -STOP with unclear benefit).

## Wave Structure

- Wave | Type | Agents | Focus | Output
- 1 | Discoverers (3) | Architecture / Performance / Platform | Broad codebase analysis | 3 discovery reports
- 2 | Validators (3) | Validate Waves 1 findings | Accuracy + impact assessment | 3 validation reports
- 3 | Planner (1) | Synthesize | Initial 14 task outlines | planner-1 results
- 4 | Deep-dive Discoverers (3) | XPC async/await / Host refactoring / SMC+IOKit | Detailed implementation plans | 3 deep-dive reports
- 5 | Deep-dive Validators (3) | Validate Waves 4 plans | Plan readiness assessment | 3 validation reports
- 6 | Final Planner (1) | Consolidate ALL findings | **13 ranked, implementation-ready tasks** | **planner-2 results (this document's source)**

## Phase 1: Correctness + Security + Quick Wins

Execute these first, in all order. They are highest-impact, lowest-risk, and independently executable.

### P0: Fix getFanStatus hidden side-effect (t-03)
**File:** `KjolHelper/main.swift` (getFanStatus, setFanProfile, init)
**Problem:** `getFanStatus` re-applies manual fan profiles on every "get" call — a correctness violation (get methods must not mutate) and a minor performance waste.
**Fix:** Move re-application logic into `setFanProfile` and helper startup. Cache profile state in `stateCache`.
**Risk:** Low — validator-6 confirmed all 5 risks are low-severity.

### P0: Add XPC listener security delegate (t-04)
**File:** `KjolHelper/main.swift` (listener), `Kjol/main.swift` (HelperClient.connect), `Kjol/helper.plist`
**Problem:** The XPC listener unconditionally accepts all connections (`return true`). Any local process can connect to the root-running helper. `SMPrivilegedExecutables` and `SMAuthorizedClients` plist keys protect launch, NOT the XPC connection.
**Fix:** Add `NSXPCListenerDelegate` validation — two-tier: launchd plist `<Validation>` key + delegate context check for bundle identifier `com.lappier.kjol`. Client sets `connection?.context`.
**Risk:** Low — rejecting invalid connections only blocks unauthorized callers.

### P0: Cache static SMC values (t-01)
**File:** `KjolHelper/SMC.swift` (SMC, FanController), `KjolHelper/main.swift` (stateDir helpers)
**Problem:** ~30–50 SMC IOKit round-trips per poll cycle. Min/max RPM, fanCount, and socTemp candidate key are static hardware properties read fresh every poll.
**Fix:** 4 caches:
- `SMC.keyInfo(_:)` — internal `[String: (size, type)]` cache, cleared on reconnect
- `FanController.fanInfo(_:)` — per-fan min/max RPM cache, cleared on reconnect
- `FanController.fanCount` — cached after first read, cleared on reconnect
- `FanController.socTemperature()` — persisted candidate key in `stateDir`, fallback to full probe if invalid

**Impact:** ~20–30 SMC calls eliminated per poll (30–50% of hot path).
**Risk:** Low — all cached values are static. Fallback paths handle edge cases.

### P1: Tighten state directory permissions (t-09)
**File:** `KjolHelper/main.swift` (setupStateDir)
**Problem:** `/var/db/kjol` created with `0o755` (world-readable) — exposes always-on state, fan profile, daemon suspension status to all local users.
**Fix:** Change to `0o700`. One-line change.
**Risk:** Low — trivial. Helper runs as root, owner-only is correct.

### P1: Replace deprecated IOPMAssertionCreateWithName (t-08)
**File:** `KjolHelper/main.swift` (power assertion, lines 74–100)
**Problem:** `IOPMAssertionCreateWithName` deprecated since macOS 10.9.
**Fix:** Drop-in replacement with `IOPMAssertionCreateWithProperties`, passing reason strings and assertion properties.
**Risk:** Low — new API is a superset of the old.

## Phase 2: IPC Optimization + Timer Modernization

### P0: Merge getStatus + getFanStatus into one XPC call (t-02)
**File:** `KjolHelper/KjolHelperProtocol.swift`, `KjolHelper/main.swift`, `Kjol/main.swift`, `Kjol/Resources/KjolHelperProtocol.swift`
**Problem:** `refresh()` makes two sequential XPC round-trips per poll — `getStatus` then `getFanStatus`. They could be one.
**Fix:** Add combined protocol method returning the two status + fan data in one reply. Refactor `refresh()` to use it. Keep old methods during transition.
**Impact:** Halves IPC round-trips per poll (2 → 1).
**Risk:** Medium — protocol change touches the two helper and app. Resources copy must stay in sync.

### P1: Switch to DispatchSourceTimer + NSProcessInfo activity assertions (t-10)
**File:** `Kjol/main.swift` (Timer setup, refresh, updatePolling, invalidation handler)
**Problem:** Uses `Timer` instead of `DispatchSourceTimer`. No `beginActivity`/`endActivity` to tell OS the app is doing useful work. XPC invalidation handler does not trigger a refresh (one-cycle staleness after helper restart).
**Fix:**
- Replace `Timer` with `DispatchSourceTimer` using `.relaxed` tolerance
- Wrap poll window with `beginActivity(options: .userInitiated, reason: ...)` / `endActivity`
- Add reconnection trigger in invalidation handler
**Risk:** Low-Medium — API swap is mechanical. New reconnection behavior must be tested.

## Phase 3: Structural Refactoring (the big one)

### P0: Split Host god class into focused services (t-05)
**File:** `Kjol/main.swift` (Host, CpuSampler, HelperClient, installHelper, refresh, KjolView, AppDelegate) + new service files
**Problem:** `Host` (540 lines) conflates 5 responsibilities: XPC client, CPU sampler, helper installer, fan state coordinator, and app state coordinator.
**Fix:** Extract 4 services:
- **XpcClient** — NSXPCConnection lifecycle, all 6 protocol methods, reconnection. Zero dependencies on Host's `@Published` props. Extract first.
- **CpuSamplerService** — already separate class. Rename + optional timer ownership.
- **HelperInstaller** — installHelper/installHelperManual/checkHelperInstalled. `@Published var isInstalled`.
- **FanStateCoordinator** — refreshFans() + FanState assembly. Depends on XpcClient (only inter-service dependency).
- **Host** → thin coordinator (~80–100 lines): owns services, drives poll cycle, bridges actions to services. Keeps `@Published` props during transition (Option A — lowest risk for SwiftUI bindings).

**Extraction order:** XpcClient → CpuSamplerService → HelperInstaller → FanStateCoordinator → thin Host.
**Risk:** Medium — refactoring central coordinator. Mitigated by: extracting each service behind existing private interface first, keeping Host as single ObservableObject injection point, preserving connection lifecycle verbatim.

### P0: Add typed errors + async/await to XPC protocol and XpcClient (t-06)
**File:** `KjolHelper/KjolHelperProtocol.swift`, `KjolHelper/main.swift`, `Kjol/main.swift` (XpcClient), `Kjol/Resources/KjolHelperProtocol.swift`
**Problem:** Unstructured `(Bool, String)` callbacks. `remoteObjectProxy` silently swallows errors. `DispatchSemaphore` blocks caller with no cancellation. Missing `interruptionHandler`/`invalidationHandler`.
**Fix:**
- Protocol returns typed results, throws `NSError` on helper side (domain: `com.lappier.kjol.helper`)
- Client-side `KjolXPCError` enum: `.notConnected`, `.helperUnavailable`, `.interrupted`, `.helperError(code:message:)`, `.invalidResponse`
- Use `remoteObjectProxyWithErrorHandler` (not `remoteObjectProxy`)
- Set `interruptionHandler` + `invalidationHandler` with structured reconnection (exponential backoff: immediate → 0.2s → 0.5s → 1.0s → 2.0s → 4.0s, max 5 attempts)
- Remove `DispatchSemaphore` from `syncSetAlwaysOn` — fire-and-forget `Task` for termination path
- All 6 methods use async/await — no more copy-paste boilerplate

**Risk:** Medium — protocol change is breaking. The two sides must update together. Done alongside t-05 (XpcClient is where async/await lives).

## Phase 4: Polish + Distribution Readiness

### P1: Pre-allocate CpuSampler arrays (t-07)
**File:** `Kjol/main.swift` (CpuSampler init + sample)
**Problem:** `prevTotal`/`prevBusy` arrays allocated fresh every 3-second sample.
**Fix:** Pre-allocate in init to `cachedPCoreCount` capacity. 2-line change.
**Risk:** Low — mechanical.

### P1: Add codesign step to build script (t-11)
**File:** `build-kjol.sh`, `Kjol/Info.plist`, `KjolHelper/Info.plist`
**Problem:** Build produces ad-hoc-signed binaries. `SMPrivilegedExecutables` and `SMAuthorizedClients` requirement strings require a Developer ID certificate chain. SMAppService registration fails for built bundles. Only manual fallback works.
**Fix:** Add `codesign` step: sign helper first (with `--options runtime`), then sign app bundle (embeds helper signature). Handle missing certificate gracefully for local dev.
**Risk:** Medium — distribution prerequisite. Codesign errors can break build if cert is absent.

### P2: Update/remove stale test scripts (t-12)
**File:** `tests/mode-test.swift`, `tests/xpc-test.swift`, `tests/test_leak.swift`
**Problem:** `mode-test.swift` and `xpc-test.swift` declare a non-existent `setPowerMode` method.
**Fix:** Update to match current protocol or remove. Evaluate XCTest suite post-refactoring.

### P2: Extract protocol into shared module (t-13)
**File:** `build-kjol.sh`, `KjolHelper/KjolHelperProtocol.swift`
**Problem:** `KjolHelperProtocol.swift` compiled twice — once into helper binary, once into app binary.
**Fix:** Compile once, link the two binaries against it. Minimal `Package.swift` with library target is lowest-risk approach.
**Risk:** Low-Medium — introduces SPM/module structure. Benefit is structural more than absolute time savings.

## Deferred / Future Work

These were researched but are NOT in the task list:

### Not feasible (drop entirely)
- **Batch SMC reads** — not feasible with AppleSMC IOKit. `SMCParamStruct` carries a single fourCC; `IOConnectCallStructMethod` selector 2 is a single-key operation. No documented batch mechanism exists. Caching (t-01) is the correct path.

### Uncertain API (research only)
- **IOKit notifications for fan/SMC state changes** — AppleSMC notification support uncertain. Requires live testing before commitment.
- **Fan read privilege separation** — fan RPM reads can not require root on Apple Silicon, but needs live hardware verification first.

### Profiling-only (add when needed)
- **os_signpost instrumentation** — good for future profiling, not an optimization itself. Add when profiling before further optimization work.

### Separate concern (keep current behavior)
- **ProcessThrottler for daemon suspension** — feasible but higher complexity than pkill -STOP (requires PID enumeration, does not replace `mdutil -a -i off`, macOS 13+ only). Keep `pkill -STOP` as primary. Evaluate as future enhancement if users report issues.

### Deferred to post-refactoring
- **Full XCTest suite** — discoverer-6's SMCConnection protocol + mock approach enables unit testing without hardware. Must follow t-05 (Host refactoring) so tests target testable components.
- **SPM/Xcode build migration** — full migration would enable incremental compilation. For a 4-file project, current shell-script approach is honest and transparent.

### Dropped as low-impact
- LaunchDaemon key additions (ExitTimeOut, SuccessfulExit)
- Menu-bar HIG polish (multi-monitor positioning, status item menu)
- History ring buffer / Deque (O(n) shift on 60-element array is negligible)
- Build flags (-O only — negligible impact for single-compilation-unit project)

## Implementation Sequence

```
Phase 1 (any order):  t-03 → t-04 → t-01 → t-09 → t-08
Phase 2:              t-02 (after t-03) → t-10
Phase 3 (together):   t-05 + t-06 (XpcClient extraction first, then async/await)
Phase 4 (when time):  t-07 → t-12 → t-11 → t-13
```

**Rationale:** Phase 1 correctness/security wins are independent and low-risk. Phase 2 IPC optimization benefits from Phase 1's side-effect fix (t-02's combined method must not carry t-03's fixed side-effect). Phase 3 is the coordinated structural refactor — t-05 and t-06 are complementary and the extracted XpcClient is where async/await lives. Phase 4 is polish and distribution readiness.

## Key Validator Verdicts (for reference)

- Task | Validator basis | Verdict
- t-01 (SMC caching) | Validator-2: "highest-impact finding," ~8-9 calls saved from min/max+fanCount alone + 13-of-14 socTemp probes eliminated | **Pursue immediately**
- t-02 (XPC merge) | Validator-2: "high impact, medium effort". Validator-1: "clean, scoped change" | **Pursue immediately**
- t-03 (side-effect fix) | Validator-1: "quick, low-risk win". Validator-6: all 5 risks Low | **Pursue immediately**
- t-04 (XPC security) | Validator-3: "single most actionable platform finding, HIGH priority, HIGH impact, LOW effort" | **Pursue immediately**
- t-05 (Host split) | Validator-1: "highest-impact structural problem". Validator-4: "plan is sound, service boundaries correct" | **Pursue as coordinated effort**
- t-06 (async XPC) | Validator-4: "technically sound". Validator-1: "do Finding 2 + Finding 7 together" | **Pursue alongside t-05**
- t-07 (array pre-alloc) | Validator-2: "clean, 2-line win" | **Pursue**
- t-08 (IOPMAssertion) | Validator-3: "straightforward, low-risk modernization" | **Pursue**
- t-09 (perms) | Validator-3: "trivial fix" | **Pursue**
- t-10 (DispatchSourceTimer) | Validator-2: "low-risk API swap" | **Pursue**
- t-11 (codesign) | Validator-3: "blocking gap for distribution" | **Pursue**
- t-12 (stale tests) | Validator-1: "low-effort cleanup" | **Pursue**
- t-13 (shared module) | Validator-1: "quick win with modest impact" | **Pursue**

## Full Research Artifacts

All raw research outputs are preserved under:
`.hermes/skills/contextloop/tasks/kjol-optimization/`

- `discoverer-1/` through `discoverer-6/` — discovery reports
- `validator-1/` through `validator-6/` — validation reports
- `planner-1/` — initial task outlines (14 tasks)
- `planner-2/` — final synthesis (this document's source, 47KB)

*Generated by contextloop research swarm. 6 waves, 18 sub-agents, 14 source files reviewed.*
