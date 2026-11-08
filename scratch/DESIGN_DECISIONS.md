# Final Design Decisions (Frontier Mapping)

**Round 1 Decisions:**
1. **SMC Fan Mode Async Retry:** Implement caller-side async retry for `Ftst` unlock. Daemon returns immediate error. UI retries.
2. **State Cache Coherency:** Keep in-memory cache. Document the coherency contract in `KjolHelper/main.swift` explicitly prohibiting out-of-band external writes.
3. **Subprocess Timeout Logging:** Use `try` + logging (or explicit `do-catch`) in `shell()` wrappers instead of silently ignoring transient errors.

**Round 2 Decisions:**
4. **Redundant Signals:** Make sure that `signal(SIGTERM, SIG_IGN)` and `SIGINT` are completely removed, relying solely on `DispatchSource`.
5. **Always-on Clamshell Assertion:** Keep the synchronous `assertSleepDisabledOff()` shell execution inside the XPC reply path for correctness and immediate UI feedback.
6. **Hardcoded Daemons List:** Extract the 20 hardcoded macOS daemons in `suspendNonEssentialDaemons()` into a configurable constant or plist.

**Round 3 Decisions:**
7. **Sync XPC API Blocking:** Keep `syncSetAlwaysOn` with `DispatchSemaphore`, but add explicit error logging if the 2.0s timeout is reached.
8. **NSLock in XpcClient:** Retain `NSLock` for synchronous state protection. Do not refactor to actors.
9. **Telemetry Polling Interval:** Increase `Host.swift` polling interval to 5.0 seconds.

**Round 4 Decisions (from sidecar files):**
10. **Battery Calibration State Machine:** Keep the 4-phase state machine but externalize hold durations as tunable constants.
11. **UpdateViewModel State Machine:** Add state transition logging through `os_log` to help debug state machine issues in production.
12. **Subprocess/Shell Error Handling:** Add explicit logging for `shell()` failures instead of swallowing them with `try?`.

These decisions successfully close out the gap analysis phase before code materialization.

**Round 5 Decisions (Feature Expansion - Code Quality & Testing):**
13. **Stale Test Files:** Update the stale manual test files (`mode-test.swift`, `xpc-test.swift`) to use the current protocol methods rather than deleting them. They serve as simple script-based log runners (using `print` instead of `XCTest`).
14. **XCTest Suite Integration:** Introduce a minimal SPM-based test target using a mock approach. Keep `build-kjol.sh` as the primary build mechanism, using SPM only for unit testing (through `swift test`).
15. **os_signpost Instrumentation:** Defer adding `os_signpost` to telemetry polling until specifically needed for profiling.
16. **Shared Module Location:** Keep `KjolHelperProtocol.swift` in `KjolHelper/`. Do not create a separate `Shared/` directory. The build script handles cross-compilation adequately.
17. **Unit Test Scope:** The SPM tests must primarily focus on pure logic components like `CpuSamplerService` and battery state calculations, preventing XPC framework internals.
18. **SMC Mocking Strategy:** Use protocol-oriented dependency injection (`protocol SMCProvider`) for future SMC unit tests rather than `#if DEBUG` macros, making sure that production binaries remain clean.

**Round 6 Decisions (From Sidecar Files):**
19. **CpuSamplerService Structure:** Keep `CpuSamplerService` as-is. It has clear responsibilities and follows Swift conventions without needing further fragmentation.
20. **Host Reconnection Timers:** Keep separate retry timers for XPC reconnection and telemetry polling to decouple connection recovery (exponential backoff) from data refresh.
21. **Host Polling Interval:** Increase `Host.swift` polling interval to 5.0s to reduce CPU/battery overhead while keeping telemetry current enough for the UI.
22. **ViewModels Async Flow:** Keep the current `Task` + `@Published` approach for async data flow in `ViewModels`. SwiftUI's native async support is clean and correct for a macOS Apple-Silicon target.
23. **UpdateCheckerService Async Pattern:** Keep `Task` + `@Published` for async state updates in `UpdateCheckerService`. Wait to add debounce/equality guards for UI flicker until it becomes an observable issue.
24. **UpdateCheckerService State Machine:** Add state transition logging through `os_log` to help debug state machine issues in production.
25. **KjolHelperProtocol Organization:** Keep `KjolHelperProtocol` as-is. It is small and cohesive, and premature splitting would add abstraction cost without a demonstrated need.
26. **Battery Calibration State Machine (KjolHelperProtocol):** Keep the 4-phase state machine but externalize the hold durations as tunable constants to adapt to different hardware chemistries.
27. **UpdateViewModel State Machine:** Add state transition logging through `os_log` to improve production debuggability without altering runtime behavior.
28. **HelperInstaller Error Handling:** Replace `try?` with `try` + logging for SMC reads to surface failures for debugging while keeping the daemon alive.
29. **HelperInstaller Subprocess Error Handling:** Add explicit logging for `shell()` failures instead of silently swallowing them with `try?`, preserving daemon uptime while surfacing issues.
30. **XpcClient Sync API Blocking:** Keep the `DispatchSemaphore` wrapper for `syncSetAlwaysOn()` but add explicit error logging if the 2.0s timeout is hit to make sure that failures are not silently swallowed.
31. **XpcClient Lock Serialization:** Keep `NSLock` to protect the `stateCache` and connection state, as critical sections are short and synchronous.
32. **Main.swift Organization:** Keep `main.swift` as-is. It serves appropriately as the composition root, while delegating well-scoped concerns to `Host.swift`, `ViewModels.swift`, and so on.
33. **Main.swift Fan Watchdog Strategy:** Keep the 5s periodic fan watchdog with a 12s asymmetric spin-down hold. This hysteresis prevents acoustic fan hunting while maintaining thermal responsiveness.

**Round 7 Decisions (Design Discovery Tree - Round 1):**
34. **SMC Mocking Strategy:** Agree. Protocol injection makes sure that clean separation of concerns without cluttering the production SMC layer.
35. **CpuSamplerService Structure:** Keep as-is. It has a focused single responsibility, and adding indirection would hurt readability without clear gain.
36. **XPC Client Sync API Blocking:** Keep the sync wrapper with error logging. It is pragmatic for callers that cannot use async, and logging prevents silent failures.
37. **Battery Calibration State Machine:** Externalizing hold durations adapts to different hardware chemistries while keeping the proven 4-phase pattern.
38. **UpdateCheckerService State Machine:** Adding `os_log` is a low-risk observability improvement that aids troubleshooting without altering runtime behavior.

**Round 8 Decisions (Design Discovery Tree - Round 2):**
39. **HelperInstaller Error Handling:** Logging preserves safety and daemon uptime while surfacing transient hardware/command failures for diagnostics.
40. **XpcClient Lock Serialization:** `NSLock` remains appropriate for short synchronous sections. Actors would add unneeded complexity here.
41. **Adaptive Fan Watchdog Strategy:** This provides the right balance for a root daemon, minimizing SMC read load while effectively preventing acoustic hunting.
42. **Host Polling Interval & Retry Timers:** 5.0s polling reduces overhead, and separate timers prevent backoff interference between connection recovery and data refresh.
43. **ViewModels Async Flow:** It aligns perfectly with modern SwiftUI patterns and prevents unnecessary Combine boilerplate.

**Round 9 Decisions (Design Discovery Tree - Round 3):**
44. **Main.swift Organization:** The project already delegates concerns well; `main.swift` acts as a clean composition root. Premature refactoring adds complexity.
45. **UpdateViewModel Async State Updates:** Keep the native pattern to minimize maintenance burden, as there is no current evidence of flicker requiring caching.
46. **KjolHelperProtocol Organization:** Premature splitting would add abstraction cost without a demonstrated need for independent reuse.
47. **Feature Expansion Process:** Acknowledge that Feature Proposals (Doc-Gap, Infrastructure Extension, Architecture Inference) generated in sidecars are NOT immediate ADRs, but proposals requiring explicit human review before implementation. This maintains the rule that agents propose and humans decide, preventing uncontrolled scope creep.

**Round 10 Decisions (Deferred Architecture & Polling Optimization):**
48. **IOKit Notifications against Polling:** Keep 5s polling. IOKit kernel notifications for AppleSMC are undocumented and historically unreliable on Apple Silicon. The complexity and crash risk outweigh the marginal power savings over a relaxed DispatchSourceTimer.
49. **ProcessThrottler against SIGSTOP:** Keep `pkill -STOP`. While a ProcessThrottler (macOS 13+) is more graceful, the current approach is highly effective and simple. Defer custom throttler development until user issues arise.
50. **Fan Read Privilege Separation:** Keep unified XPC reads in the root daemon. Splitting hardware access across permission domains introduces race conditions and complicates the XPC security boundary without meaningful IPC savings.
51. **os_signpost Instrumentation:** Defer `os_signpost` integration. Prevent cluttering the codebase with profiling code until a specific performance regression requires investigation.

**Round 11 Decisions (Polling & Daemon Suspension Implications):**
52. **Polling Timer QoS:** Keep the timer QoS at `.default` or `.userInitiated`. Since polling only runs when the popover is open, UI responsiveness is paramount. Background QoS might cause visible lag in telemetry readouts.
53. **Daemon Suspension Failsafe:** Implement a failsafe auto-resume timer (for example, 4 hours) for suspended daemons. This protects the system from silently hanging due to long-held database locks (for example, by `mds`) during prolonged "Always-On" sessions.
54. **XPC Payload Size Optimization:** Keep `getCombinedStatus` simple without `OptionSet` masks. Serializing a small dictionary through XPC is microscopically fast. Masks add unnecessary protocol complexity for current scale.

**Round 12 Decisions (Failsafe Architecture):**
55. **Failsafe Timer Ownership:** The `KjolHelper` daemon must own the 4-hour failsafe timer. Failsafes must be resilient against standard user app crashes. The privileged daemon that sent `SIGSTOP` is the safest entity to make sure that `SIGCONT` is sent.
56. **Failsafe Reset Mechanism:** The failsafe timer resets to 4 hours when Always-On is toggled off and back on. Toggling off sends `SIGCONT`, clearing locks, so a subsequent activation is a clean state.
57. **UI Notification for Failsafe Trigger:** If the failsafe triggers, the Always-On toggle remains "On" (to keep `caffeinate` active), but the UI must reflect a "Suspension Paused" warning state, decoupling sleep prevention from daemon suspension states.

**Round 13 Decisions (Design Discovery Tree - Final Phase 1):**
58. **Testing Architecture:** Maintain strictly separate `KjolApp` and `KjolHelper` targets for the planned XCTest suite to enforce the XPC security boundary at compile time.
59. **Process Suspension Mechanism:** Stick with `SIGSTOP` for daemon management (rather than `ProcessThrottler`) due to its reliability and simplicity.
60. **Build System Modernization:** Migrate entirely to an Xcode project (`.xcodeproj`) to leverage native Gatekeeper notarization workflows in the long run.

**Round 14 Decisions (Design Discovery Tree - Final Phase 2):**
61. **Failsafe Timer Implementation:** Persist the failsafe start time to `/var/db/kjol/failsafe_start_time` so the 4-hour timer can reliably resume across helper daemon crashes or restarts.
62. **Xcode Migration Strategy:** Maintain the two build systems (`build-kjol.sh` and the new Xcode project) in parallel during the transition phase to minimize disruption.
63. **Testing Architecture - Shared Protocol:** Create a third, strictly shared target (`KjolShared`) to house `KjolHelperProtocol.swift` and common XPC types, eliminating duplication.

**Round 15 Decisions (Design Discovery Tree - Final Phase 3):**
64. **Failsafe UI State Coordination:** Use a dedicated state file (`failsafe_triggered`) returned through `getCombinedStatus` so the UI can reflect the "Suspension Paused" state safely through existing polling.
65. **Shared Target Scope:** Restrict the `KjolShared` target strictly to the XPC protocol and typed errors to maintain a tight boundary and prevent premature abstraction.
66. **Xcode CI Integration Strategy:** Implement a custom Xcode Build Phase that falls back to ad-hoc signing (`codesign -f -s -`) if a Developer ID certificate is absent, preserving the current frictionless contribution workflow.

**Round 16 Decisions (Design Discovery Tree - Optimization Refinements):**
67. **Daemon List Configuration Format:** Use a standard macOS `.plist` file located in `/var/db/kjol/suspended_daemons.plist` to allow users to customize which daemons get suspended, preventing maintenance overhead.
68. **Daemon Suspension Fallback:** If the external configuration file is absent, malformed, or unreadable, fall back to the hard-coded list of 20 daemons (`mediaanalysisd`, `mds`, and so on.) to make sure that the feature always works out-of-the-box.
69. **SMC Temperature Cache Invalidation:** Add a runtime check during `socTemperature()`. If reading the cached key fails or returns an out-of-bounds value (for example, `< 5` or `> 130`), invalidate the cache and trigger a fresh scan of the 14 candidates.
70. **Daemon Configuration File Ownership:** The `/var/db/kjol/suspended_daemons.plist` file must be owned by `root:wheel` with `644` permissions to prevent unprivileged tampering. The daemon will explicitly check ownership before reading. If not owned by root, it falls back to the hard-coded list.
71. **SMC Re-scan Threshold:** If no valid key is found after a full scan, cache a sentinel value (for example, `UNSUPPORTED`) to `/var/db/kjol/soc_temp_key` to skip scanning for the remainder of the session.
72. **Process Execution Timeout in shell():** Keep the global timeout but relax it slightly to `3.0s` to account for heavily loaded systems while still preventing indefinite hangs.
73. **Shell Process Reuse:** Keep `shell()` as-is for now, creating a new `Process` and `Pipe` on every call, because the call frequency is relatively low and process reuse introduces stream handling complexity.

**Round 17 Decisions (Design Discovery Tree - Implementation Materialization):**
74. **Plist Schema:** Use a flat array of strings (`[String]`) for `/var/db/kjol/suspended_daemons.plist` as it is the simplest structure and minimizes parsing complexity.
75. **Plist Creation:** Do not auto-create the plist template on daemon startup. It must only be read if explicitly provisioned by the user, preventing unnecessary disk I/O.
76. **Plist Read Frequency:** Parse the plist file on demand every time `suspendNonEssentialDaemons(_ on: Bool)` is invoked, rather than caching it, to allow users to tweak the list without restarting the daemon.
77. **SMC Sentinel Lifetime:** Persist the `UNSUPPORTED` sentinel for `soc_temp_key` to disk to prevent repetitive fallback scanning on reboots.
78. **Plist Ownership Validation:** Use POSIX `stat()` to verify `st_uid == 0` and `st_gid == 0` for `/var/db/kjol/suspended_daemons.plist` ownership instead of high-level Foundation APIs, keeping checks fast and native.
79. **Plist Parsing Error Handling:** If the plist is owned by root but malformed, fall back to the safe default array and log an error to `stderr` to aid administrator debugging.
80. **SMC Temperature Cache Format:** Use the explicit string `"UNSUPPORTED"` written to `/var/db/kjol/soc_temp_key` rather than an empty file, making the disabled state unambiguous.
81. **Plist Read Serialization:** Do not use explicit locking (`stateQueue.sync`) around the on-demand plist reads, preventing unnecessary global lock contention.
82. **Plist Permission Strictness:** Make sure that the plist file is not writable by group or others (`(st_mode & 0o22) == 0`) while allowing `0644` or stricter permissions.
83. **SMC Invalid Cache Purge:** When a cached SMC key becomes invalid, do not delete the cache file first. Instead, proceed with a fallback scan and atomically overwrite the cache file with the new key (or the `UNSUPPORTED` sentinel) to minimize disk operations.

**Round 18 Decisions (Design Discovery Tree - Two-Agent Grill 2.5.5 - Round 1):**
84. **Fan Control Retry Loop Architecture:** Move the Ftst unlock retry logic out of the synchronous XPC path in `KjolHelper/SMC.swift`. Implement a caller-side async retry in the UI layer (`Kjol/Host.swift`) to decouple latency from the XPC reply path while retaining the hardware-necessary retry.
85. **State Cache Coherency Contract:** Keep the in-memory `stateCache` in `KjolHelper/main.swift` as-is, but add documentation explicitly defining the coherency contract: the cache is a write-through mirror of `/var/db/kjol/` and is only mutated by the daemon's own XPC handlers. External out-of-band writes are unsupported.

**Round 19 Decisions (Design Discovery Tree - Two-Agent Grill 2.5.5 - Round 2):**
86. **UpdateCheckerService State Updates:** Keep `Task` + `@Published` for async state updates in `UpdateCheckerService`, but add minimal equality guards before publishing changes to prevent unnecessary view re-renders and UI flicker during fast polling.
87. **UpdateCheckerService State Machine Observability:** Add `os_log` statements for state transitions within the `UpdateCheckerService` to provide low-risk observability that directly supports production debugging.

**Round 20 Decisions (Design Discovery Tree - Two-Agent Grill 2.5.5 - Round 3):**
88. **Helper Daemon Signal Handling for Cleanup:** Remove the redundant `signal(SIGTERM, SIG_IGN)` and `signal(SIGINT, SIG_IGN)` calls in `KjolHelper/main.swift` so the `DispatchSource` signal handlers can properly run their cleanup code (restoring normal charging) when the daemon terminates.
89. **Always-on Power Management Verification:** Accept the latency of the synchronous shell call to `assertSleepDisabledOff()` in `setAlwaysOn()`. Immediate verification provides defense-in-depth and gives the user accurate, instantaneous feedback on whether "Always-On" was successfully engaged.
