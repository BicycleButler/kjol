# ADR-006: Adaptive Battery Management and System Delegation Architecture

## Context
In macOS 27 and newer, Apple restricted direct SMC register writes. System integrity protection gates writes to `CHTE`, `CH0B`, `CH0C`, and `BCLM`. In response, macOS manages the 80% charge limit natively in System Settings.

Older macOS versions continue to support direct SMC battery writes. Previously, Kjol displayed legacy controls on all systems. On macOS 27+, this created three problems:
1. **Pervasive UI Friction:** Disabled sliders and warning banners filled the UI card.
2. **Obscured Diagnostic Value:** Vital telemetry like cycle count and temperature stayed hidden below inactive controls.
3. **Leaky Capability Logic:** Sub-views used loose booleans like `hardwareControlSupported` instead of a unified model.

## Decision

We adopt an **Adaptive Battery Management and System Delegation Architecture** structured around three pillars:

### 1. Three-Tier Capability Domain Model (`BatteryControlTier`)
Kjol classifies machine battery capabilities into a single domain enum:
- **`directSMC`:** Writable SMC battery registers exist (macOS < 27). This mode exposes charge limits, sailing gap, AC discharge, and calibration.
- **`systemManaged`:** Modern macOS (macOS 27+) manages battery charge limits. Kjol acts as a **Battery Health and Telemetry Hub**, pairing telemetry with System Settings handoff.
- **`desktopNoBattery`:** Stationary hardware (Mac Studio, Mac mini, Mac Pro). The UI omits battery controls.

### 2. Contextual Telemetry Hub and Morphing UI Layout
The Power and Battery card adapts to the active `BatteryControlTier`:
- **Universal Telemetry First:** Displays charge level, cycle count, temperature, and health for all laptops.
- **Clean macOS 27+ Presentation:** Removes disabled controls from default view. Adds a direct button to open macOS Battery Settings. A collapsed drawer keeps legacy controls for diagnostics.
- **Full Legacy Hardware Controls:** Shows the charge limiter, Top-Up button, and calibration tools on older macOS systems.

### 3. Resilient Multi-Tier Deep Link Resolver (`BatterySettingsLauncher`)
External handoff to macOS Battery Settings uses a tiered URI resolution cascade:
1. `x-apple.systempreferences:com.apple.Battery-Settings.extension` (macOS 13+ Settings pane)
2. `x-apple.systempreferences:com.apple.preference.battery` (Legacy System Preferences pane)
3. `x-apple.systempreferences:` (System Settings root fallback)

## Consequences

### Positive
- **Clean, Modern UX on macOS 27+:** No visual clutter or dead controls on modern Macs.
- **Backwards Compatibility:** Older systems retain granular battery tuning.
- **First-Class Telemetry:** Cycle counts and battery health metrics are easily accessible.
- **Single-Source Capability:** All views bind to `BatteryControlTier`.

### Negative / Trade-offs
- macOS 27+ users adjust the 80% charge ceiling inside native System Settings.

## Falsifier
If Apple restores direct SMC write access in macOS 27, `BatteryControlTier.directSMC` can be re-enabled without changing UI code.
