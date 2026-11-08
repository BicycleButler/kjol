# Kjol Optimization & Refactoring Task List

**Document Status:** Complete
**Last Updated:** 2026-08-25
**Source:** `scratch/OPTIMIZATION_RESEARCH.md` + Requirements Specification

## Overview

This task list defines the actionable implementation plan for optimizing Kjol, modernizing its architecture, fixing security gaps, removing UI jank, updating test infrastructure, and providing single-file distribution & in-app updates.

## Phase 1: Correctness, Security & Quick Wins

- [x] **Task 1.1 (t-03): Fix `getFanStatus` Hidden Side-Effect**
  - **Priority:** P0
  - **Target File:** `KjolHelper/main.swift`
  - **Problem:** `getFanStatus` re-applies manual fan profiles on every "get" call, mutating state on read calls.
  - **Implementation Plan:**
    1. Move fan profile re-application logic out of `getFanStatus` into `setFanProfile` and daemon startup initialization.
    2. Cache active profile state in `stateCache`.
    3. Make sure that `getFanStatus` strictly reads and returns fan telemetry.
  - **Acceptance Criteria:**
    - `getFanStatus` triggers zero SMC key write calls.
    - Manual fan profile persists across daemon restarts through startup re-application.

- [x] **Task 1.2 (t-04): Add XPC Listener Security Delegate**
  - **Priority:** P0
  - **Target Files:** `KjolHelper/main.swift`, `Kjol/main.swift`, `KjolHelper/helper.plist`
  - **Problem:** `KjolHelper` XPC listener unconditionally accepts all connections (`return true`), allowing any local process to connect to the privileged root helper.
  - **Implementation Plan:**
    1. Implement `NSXPCListenerDelegate` validation in `KjolHelper/main.swift`.
    2. Validate connecting client bundle identifier (`com.lappier.kjol`) and code signature / process requirements.
    3. Configure client connection context in `Kjol/main.swift`.
  - **Acceptance Criteria:**
    - Unauthorized local processes are rejected by `NSXPCListenerDelegate`.
    - Main Kjol app connects and communicates securely.

- [x] **Task 1.3 (t-01): Cache Static SMC Values**
  - **Priority:** P0
  - **Target Files:** `KjolHelper/SMC.swift`, `KjolHelper/main.swift`
  - **Problem:** ~20–30 redundant SMC IOKit round-trips occur per poll cycle reading static hardware properties.
  - **Implementation Plan:**
    1. Implement `[String: (size: UInt32, type: String)]` internal key info cache in `SMC.swift`.
    2. Cache per-fan min/max RPM in `FanController`.
    3. Cache `fanCount` on initial query.
    4. Persist SoC temperature candidate key in `/var/db/kjol/soc_temp_key`, probing only on cache miss.
    5. Invalidate caches on SMC connection reset.
  - **Acceptance Criteria:**
    - Eliminates 20–30 SMC calls per poll cycle (~30–50% reduction).
    - Temperature and fan RPM readings remain accurate.

- [x] **Task 1.4 (t-09): Tighten State Directory Permissions**
  - **Priority:** P1
  - **Target File:** `KjolHelper/main.swift`
  - **Problem:** `/var/db/kjol` directory created with `0o755` permissions, exposing system state to non-root users.
  - **Implementation Plan:**
    1. Change directory creation mask in `setupStateDir()` to `0o700` (`S_IRWXU`).
  - **Acceptance Criteria:**
    - `/var/db/kjol` permissions restricted strictly to owner/root (`0o700`).

- [x] **Task 1.5 (t-08): Replace Deprecated `IOPMAssertionCreateWithName`**
  - **Priority:** P1
  - **Target File:** `KjolHelper/main.swift`
  - **Problem:** Uses deprecated `IOPMAssertionCreateWithName` API.
  - **Implementation Plan:**
    1. Modernize calls to `IOPMAssertionCreateWithProperties`.
    2. Pass property dictionary containing assertion type, name, and level.
  - **Acceptance Criteria:**
    - Clean compilation with no deprecation warnings for power assertions.

## Phase 2: IPC Optimization & Timer Modernization

- [x] **Task 2.1 (t-02): Merge `getStatus` and `getFanStatus` into One XPC Call**
  - **Priority:** P0
  - **Target Files:** `KjolHelper/KjolHelperProtocol.swift`, `KjolHelper/main.swift`, `Kjol/main.swift`
  - **Problem:** Sequentially making `getStatus` then `getFanStatus` doubles IPC round-trips per poll.
  - **Implementation Plan:**
    1. Add `getCombinedStatus(reply: @escaping ([String: Any]) -> Void)` to `KjolHelperProtocol`.
    2. Implement `getCombinedStatus` in `KjolHelper` returning host status, fan state, and temperatures.
    3. Update `refresh()` in Kjol app to call `getCombinedStatus`.
  - **Acceptance Criteria:**
    - Halves IPC round-trips per poll cycle (2 → 1).
    - Telemetry updates in UI remain atomic.

- [x] **Task 2.2 (t-10): Modernize Polling Timer & Activity Assertions**
  - **Priority:** P1
  - **Target File:** `Kjol/main.swift`
  - **Problem:** Uses basic `Foundation.Timer` without OS activity assertions or automatic reconnection refresh.
  - **Implementation Plan:**
    1. Replace `Timer` with `DispatchSourceTimer` using `.relaxed` leeway tolerance.
    2. Wrap polling updates in `ProcessInfo.processInfo.beginActivity` / `endActivity`.
    3. Trigger immediate poll refresh on XPC reconnection events.
  - **Acceptance Criteria:**
    - Polling runs with OS wake-up coalescing.
    - Automatic state refresh upon helper daemon restart.

## Phase 3: Structural Refactoring & SwiftUI State Architecture

- [x] **Task 3.1 (t-05): Split Host God Class & Refactor SwiftUI View State (Fix UI Jank)**
  - **Priority:** P0
  - **Target Files:** `Kjol/main.swift`, new service/view-model files under `Kjol/`
  - **Problem:**
    - `Host` (540 lines) mixes XPC client, CPU sampling, helper installation, fan coordination, and app state.
    - Single monolithic `Host` `@Published` state causes full UI view re-renders on every 3-second telemetry tick, leading to UI jank, frame jumps, and secondary layout passes.
  - **Implementation Plan:**
    1. **Extract Core Services:**
       - `XpcClient`: NSXPCConnection lifecycle and protocol calls.
       - `CpuSamplerService`: CPU tick sampling with pre-allocated buffers.
       - `HelperInstaller`: SMAppService and osascript manual fallback installation.
       - `FanStateCoordinator`: Fan state assembly and profile logic.
    2. **Refactor SwiftUI View State Models:**
       - Decouple static UI controls (Always-On toggle, Fan strategy picker, Charge Limit controls) from high-frequency telemetry updates (CPU usage, fan RPM, temperatures).
       - Split view models into focused state holders (`TelemetryViewModel`, `FanControlViewModel`, `PowerViewModel`).
       - Apply `sizingOptions = []` on `NSHostingController` (macOS 13+) and fixed `preferredContentSize` (360x490) to eliminate NSPopover frame jumping.
       - Replace layout-shifting view modifiers (such as `.opacity()`) with explicit `if/else` conditional rendering.
       - Use fixed `.frame()` dimensions on view containers and card slots to prevent secondary layout passes.
       - Rely strictly on native `show(relativeTo:of:)` positioning without manual frame recalculation overrides.
  - **Acceptance Criteria:**
    - `Host` reduced to a lightweight coordinator (~80 lines).
    - NSPopover opens smoothly without frame jumping or content shifting.
    - High-frequency telemetry ticks do not trigger re-renders on interactive controls (toggles, pickers, sliders).
    - Zero visual jank during popover display or control interaction.

- [x] **Task 3.2 (t-06): Add Typed Errors & Async/Await to XPC Protocol**
  - **Priority:** P0
  - **Target Files:** `KjolHelper/KjolHelperProtocol.swift`, `KjolHelper/main.swift`, `Kjol/main.swift`
  - **Problem:** Protocol uses unstructured `(Bool, String)` callbacks and `DispatchSemaphore` blocking on termination.
  - **Implementation Plan:**
    1. Define `async/await` protocol methods in `KjolHelperProtocol` with typed `NSError` support.
    2. Introduce `KjolXPCError` enum (`.notConnected`, `.helperUnavailable`, `.interrupted`, `.helperError`, `.invalidResponse`).
    3. Use `remoteObjectProxyWithErrorHandler` across all calls.
    4. Implement structured exponential backoff reconnection (immediate -> 0.2s -> 0.5s -> 1.0s -> 2.0s -> 4.0s).
    5. Replace blocking `DispatchSemaphore` in termination path with fire-and-forget `Task`.
  - **Acceptance Criteria:**
    - Async/await used cleanly across XPC client.
    - Robust connection recovery without UI thread blocking.

## Phase 4: Polish, Distribution Readiness & Test Cleanup

- [x] **Task 4.1 (t-07): Pre-allocate CpuSampler Buffers**
  - **Priority:** P1
  - **Target File:** `Kjol/CpuSamplerService.swift`
  - **Problem:** `prevTotal` and `prevBusy` arrays re-allocated every sample.
  - **Implementation Plan:**
    1. Pre-allocate buffer arrays in `init()` to `cachedPCoreCount + cachedECoreCount` capacity.
    2. Reuse existing buffer memory in `sample()`.
  - **Acceptance Criteria:**
    - Zero array re-allocations during standard CPU sampling cycles.

- [x] **Task 4.2 (t-11): Maintain Ad-hoc Code Signing & Order in Build Script**
  - **Priority:** P1
  - **Target File:** `build-kjol.sh`
  - **Problem:** Code signing order and options must consistently preserve ad-hoc signatures across executables and app bundle.
  - **Implementation Plan:**
    1. Make sure that bottom-up signing sequence in `build-kjol.sh`:
       - Helper daemon binary (`codesign -f -s - --options runtime "$HELPER_DIR/com.lappier.kjol.helper"`)
       - Main app binary (`codesign -f -s - --options runtime "$APP_DIR/Contents/MacOS/Kjol"`)
       - Outer app bundle (`codesign -f -s - --options runtime "$APP_DIR"`)
    2. Maintain ad-hoc signing (`-s -`) fallback when Developer ID certificates are absent.
  - **Acceptance Criteria:**
    - `./build-kjol.sh` builds and signs app bundle cleanly.
    - App bundle passes `codesign --verify --deep --strict`.

- [x] **Task 4.3 (t-12): Clean Up & Fix Existing Test Scripts**
  - **Priority:** P2
  - **Target Files:** `tests/mode-test.swift`, `tests/xpc-test.swift`, `tests/fan-test.swift`, `tests/test_leak.swift`
  - **Problem:**
    - `mode-test.swift` and `xpc-test.swift` declare non-existent `setPowerMode` protocol method.
    - `test_leak.swift` is in root directory instead of `tests/`.
  - **Implementation Plan:**
    1. Relocate `test_leak.swift` to `tests/test_leak.swift`.
    2. Update `tests/mode-test.swift` and `tests/xpc-test.swift` to match modernized `KjolHelperProtocol` (`getCombinedStatus`, `setAlwaysOn`, `setFanProfile`, and so on.) and remove deprecated `setPowerMode`.
    3. Verify test scripts compile and run cleanly against built binaries.
  - **Acceptance Criteria:**
    - All scripts under `tests/` compile and execute without protocol errors.

- [x] **Task 4.4 (t-13): Extract Protocol into Shared Module**
  - **Priority:** P2
  - **Target Files:** `KjolHelper/KjolHelperProtocol.swift`, `build-kjol.sh`
  - **Problem:** `KjolHelperProtocol.swift` duplicated into `Kjol/Resources/` during build.
  - **Implementation Plan:**
    1. Consolidate protocol into single source path (`KjolHelper/KjolHelperProtocol.swift`).
    2. Update `build-kjol.sh` to compile directly from source path for the two helper and app targets.
  - **Acceptance Criteria:**
    - Single protocol source file used across all targets.

## Phase 5: Distribution & In-App Updater Implementation (Wiltermoodj/kjol)

- [x] **Task 5.1: `UpdateCheckerService` Implementation**
  - **Priority:** P1
  - **Target File:** `Kjol/UpdateCheckerService.swift`
  - **Problem:** App currently lacks background update discovery and downloading.
  - **Implementation Plan:**
    1. Create `UpdateCheckerService` class querying `https://api.github.com/repos/Wiltermoodj/kjol/releases/latest`.
    2. Parse `tag_name`, compare against `CFBundleShortVersionString` using semantic version parsing.
    3. Extract `.pkg` download asset URL and provide `downloadInstaller` method with progress reporting.
  - **Acceptance Criteria:**
    - Successfully parses GitHub release response and detects newer versions.
    - Downloads `Kjol.pkg` into temporary directory safely.

- [x] **Task 5.2: `UpdateViewModel` & FooterView UI Integration**
  - **Priority:** P1
  - **Target Files:** `Kjol/ViewModels.swift`, `Kjol/main.swift`
  - **Problem:** Users need an in-app notice and one-click "Update Now" button when a new release is available.
  - **Implementation Plan:**
    1. Implement `UpdateViewModel` managing checking, downloading, and installation states.
    2. Trigger silent update check on popover open (throttled to once per hour).
    3. Add "Check for Updates" button to `FooterView` in menu bar UI.
    4. Display "Update Available: vX.Y.Z" banner with an "Update Now" button when a new version is detected.
    5. Trigger `NSWorkspace.shared.open(pkgURL)` upon download completion to initiate macOS GUI installer.
  - **Acceptance Criteria:**
    - Popover open triggers silent update check.
    - Manual check button triggers explicit status update.
    - Clicking "Update Now" downloads `.pkg` and opens installer.

- [x] **Task 5.3: Package Script & Gatekeeper Release Documentation**
  - **Priority:** P1
  - **Target Files:** `build-kjol.sh`, `README.md`, `scratch/DISTRIBUTION_PLAN.md`
  - **Problem:** Non-technical users need simple instructions for opening ad-hoc signed installer packages without terminal commands.
  - **Implementation Plan:**
    1. Make sure that `build-kjol.sh` builds a single `Kjol.pkg` executable without external dependencies.
    2. Update `README.md` with step-by-step instructions for non-technical users on how to install `Kjol.pkg` and bypass Gatekeeper ("Right-Click -> Open").
  - **Acceptance Criteria:**
    - README includes simple, non-technical instructions for single-file installation and update process.

## Progress Summary

- Phase | Tasks | Status
- **Phase 1: Correctness & Security** | 1.1, 1.2, 1.3, 1.4, 1.5 | Completed
- **Phase 2: IPC & Timer Modernization** | 2.1, 2.2 | Completed
- **Phase 3: Refactoring & UI State** | 3.1, 3.2 | Completed
- **Phase 4: Polish & Test Cleanup** | 4.1, 4.2, 4.3, 4.4 | Completed
- **Phase 5: Distribution & In-App Updater** | 5.1, 5.2, 5.3 | Completed
