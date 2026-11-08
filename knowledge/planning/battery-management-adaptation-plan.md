# Battery Management Adaptation Plan: macOS 27+ & Legacy Architecture

## Goal
Provide a clean, elegant, and high-utility battery management experience in Kjol for all macOS generations:
1. Retain 100% full direct hardware SMC battery controls for machines and macOS versions (<27) where third-party control is supported.
2. For macOS 27 and newer where direct SMC battery writes are restricted, remove clutter, disabled sliders, and warning banners. Replace them with a dedicated **Battery Health & Telemetry Hub** and a streamlined button to open macOS Battery Settings.
3. Provide universal battery telemetry (charge %, health %, cycle count, battery temperature, power connection status) across all Apple Silicon laptops.
4. Gracefully handle desktop Macs (Mac Studio, Mac mini, Mac Pro) with no internal battery.

## Architecture

### 1. Capability Domain Model (`BatteryControlTier`)
```swift
enum BatteryControlTier: String, Equatable {
    case directSMC        // Pre-macOS 27 with writable SMC keys
    case systemManaged    // macOS 27+ or hardware where OS controls charging natively
    case desktopNoBattery // Stationary Apple Silicon desktops
}
```

### 2. SMC Controller Updates (`KjolHelper/SMC.swift`)
- Update `BatteryController.hardwareControlSupported` to evaluate `if #available(macOS 27.0, *)` and restrict direct SMC write attempts on macOS 27+.
- Preserve SMC keys detection for pre-macOS 27 systems.
- Expose battery presence, health percentage, cycle counts, and temperatures reliably in `batteryStatus()`.

### 3. View Model Integration (`Kjol/ViewModels.swift`)
- Add `BatteryControlTier` enum and expose `batteryTier` on `PowerViewModel` and `TelemetryViewModel`.
- Parse `healthPercent` into `batteryHealthPercent` if present.
- Derive `batteryTier` cleanly in `updateBatteryState(batteryDict:)`.

### 4. UI Transformation (`Kjol/main.swift`)
- Introduce `BatterySettingsLauncher` for multi-stage URL scheme resolution.
- Refactor `PowerManagementView`:
  - Show Compute Governor at top.
  - For `.systemManaged` (macOS 27+):
    - Compact, informative Battery Telemetry Grid (Charge %, Battery Health %, Cycle Count, Battery Temperature).
    - Clear, subtle status label: *"Battery health and charging limits are managed natively by macOS 27."*
    - Styled primary action button: *"Open macOS Battery Settings"*.
    - Optional collapsed disclosure: *"Legacy Hardware Controls (Restricted on macOS 27+)"* for debugging / historical reference.
  - For `.directSMC`:
    - Full active Charge Limit slider (50%–90%).
    - Quick actions: Top Up (100%) and Discharge to Limit.
    - Advanced controls: Sailing gap, heat protection, and calibration.
  - For `.desktopNoBattery`:
    - Clean desktop power state with no extraneous battery controls.
- Update `QuickActionsView` to adapt the 4th action button:
  - `.directSMC`: "Charge Limit\n\(limit)%"
  - `.systemManaged`: "Battery\nSettings" (opens macOS Settings)
  - `.desktopNoBattery`: omitted or contextually adjusted.

## Verification
- Rebuild unified installer with `./build-kjol.sh`.
- Run AST graph index with `npx stubs scan`.
- Verify ASD-STE100 technical documentation compliance with `npx stubs tale`.

