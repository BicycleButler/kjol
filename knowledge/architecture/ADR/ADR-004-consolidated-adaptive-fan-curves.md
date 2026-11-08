# ADR-004: Consolidated Adaptive Fan Curves & Strategy Taxonomy

## Context
Kjol manages Apple Silicon fan speeds through direct SMC hardware control through a privileged helper (`KjolHelper`). Previously, fan control options exposed five flat strategies:
- `Auto`: Native Apple SMC bypass
- `Quiet`: Static 25% RPM clamp
- `Adaptive`: Fixed linear curve (42°C–85°C) with reactive thermal boost (+15%–40% if $\Delta T \ge 2^\circ\text{C}/5\text{s}$ or $T \ge 68^\circ\text{C}$) and 12s peak-hold
- `Blast`: Static 100% RPM max
- `Custom`: Manual 0%–100% RPM slider

This configuration suffered from several design issues:
1. `Quiet` (25%) is largely redundant when gentle adaptive curves or manual presets are available, and risks thermal throttling under unmonitored load.
2. `Custom` was ambiguously named. It represented fixed manual RPM rather than custom adaptive curves.
3. `Adaptive` had only one aggressive profile, forcing fans to rapidly ramp up during moderate bursts, which is disruptive during general desktop use and only appropriate for sustained heavy compute.
4. Users had no ability to define their own temperature-to-speed curve or choose a quiet, gentle profile that tracks native macOS thermal acoustics while maintaining lower operating temperatures.

## Decision

### 1. Strategy Taxonomy Consolidation
Consolidate top-level modes into 4 primary strategies:
- `Auto`: Native macOS SMC thermal management (manual override disabled).
- `Adaptive`: Dynamic piecewise curve engine with three sub-options:
  - `Gentle`: Follows a gentle, native-like acoustic curve with a modest floor/offset (+10%–15% over idle) and low-pass exponential moving average (EMA) smoothing to prevent fan revving during brief spikes.
  - `Aggressive` (Heavy Compute): Retains proactive rate-of-rise thermal acceleration ($\Delta T / \Delta t$) and 12s asymmetric peak-hold for heavy compilation, rendering, and training workloads.
  - `Custom Curve`: 4-point milestone anchor curve ($45^\circ\text{C}, 60^\circ\text{C}, 75^\circ\text{C}, 88^\circ\text{C}$) editable by the user through interactive controls with live curve visualization.
- `Manual`: Fixed RPM target slider (0%–100% in 5% increments), replacing and clarifying the previous `Custom` mode.
- `Blast`: 100% emergency maximum RPM cooling flush.

Remove `Quiet` mode entirely.

### 2. Piecewise Curve Engine & Control Point Schema
The helper runtime evaluates fan speeds through a declarative piecewise linear transfer function:
Given control points $P = \{(T_0, R_0), (T_1, R_1), \dots, (T_n, R_n)\}$ where $T_i < T_{i+1}$:
- For $T \le T_0$, $R = R_0$.
- For $T \ge T_n$, $R = R_n$.
- For $T_i \le T < T_{i+1}$, $R = R_i + \frac{T - T_i}{T_{i+1} - T_i} \cdot (R_{i+1} - R_i)$.

### 3. Sub-Profile Dynamic Invariants
- **Aggressive**: Points: $(40^\circ\text{C}, 15\%), (55^\circ\text{C}, 35\%), (70^\circ\text{C}, 70\%), (85^\circ\text{C}, 100\%)$. If $\Delta T \ge 2.0^\circ\text{C}/5\text{s}$ or $(T \ge 68^\circ\text{C} \land \Delta T > 0.5^\circ\text{C})$, apply proactive boost $\min(100, R + \max(15, \Delta T \cdot 8))$ with 12s peak-hold.
- **Gentle**: Points: $(45^\circ\text{C}, 18\%), (60^\circ\text{C}, 30\%), (75^\circ\text{C}, 55\%), (90^\circ\text{C}, 90\%)$. No derivative spike boost. Temperature is smoothed through exponential moving average ($\alpha = 0.35$) with 20s gradual cooldown decay to maintain acoustic tranquility.
- **Custom Curve**: Points: User-defined anchors at $45^\circ\text{C}, 60^\circ\text{C}, 75^\circ\text{C}, 88^\circ\text{C}$ (persisted in helper state / user defaults) with 10s asymmetric hysteresis to prevent hunting around milestone transitions.

### 4. UI Architecture
In `FanControlCardView`:
- Top-level segmented control displays `[Auto, Adaptive, Manual, Blast]`.
- When `Adaptive` is active, an animated secondary pill picker reveals `[Gentle, Aggressive, Custom]`.
- When `Adaptive -> Custom` is active, a SwiftUI `Canvas` renders the smooth monotonic spline curve with gradient area fill and real-time SoC temperature tracking beacon, paired with milestone stepper/slider handles.
- When `Manual` is active, the fixed RPM slider and quick-snap chips (25%, 50%, 75%, 100%) are displayed.

### 5. XPC Protocol Compatibility
The XPC protocol `setFanProfile(_ profile: String, rpmPercent: Double, targetTempC: Double)` is backward-compatible:
- `profile` supports `"auto"`, `"blast"`, `"manual"` (with `"custom"` alias for migration), and adaptive profiles:
  - `"adaptive"` / `"adaptive_aggressive"`
  - `"adaptive_gentle"`
  - `"adaptive_custom"`
- For custom curves, serialized anchor points (for example, `fan_curve_points` in state dir) are transmitted and cached cleanly.

### 6. Thermal Safety Arbiter & Dual-Action Policy
A safety governor runs inside the watchdog evaluation loop to protect the hardware if manual or gentle curves run hotter than safe limits:
- **Max Junction Telemetry**: Evaluates $T_{\text{effective}} = \max(T_{\text{SoC}}, T_{\text{CPU}}, T_{\text{GPU}})$.
- **User-Configurable Ceiling**: Configurable threshold ($70^\circ\text{C}$ to $100^\circ\text{C}$, default $85^\circ\text{C}$).
- **Dual Policy Options**:
  - `boostFans` (Performance Priority): Temporarily yields manual SMC override to allow native macOS thermalmonitord / SMC firmware to spin fans to safe speeds until $T \le T_{\text{ceiling}} - 5^\circ\text{C}$.
  - `throttleCPU` (Acoustic Priority): Preserves silent fan speeds and engages macOS Low Power Mode (`pmset -a lowpowermode 1`) to cap package power at $10\text{–}15\text{W}$ until $T \le T_{\text{ceiling}} - 5^\circ\text{C}$ for a 15-second deadband window.
  - `off`: Direct manual control without active safety governor intervention.

### 7. 1-Click Macro Presets
Top-level quick action buttons for common profiles:
- **Max Compute Power**: Adaptive Heavy Compute fan speed, full Turbo clock speeds (Low Power Mode disabled), fan ramp up to 100% with thermal acceleration.
- **Gentle Silent Mode**: Keeps Low Power Mode enabled, fan speeds capped $\le 25\%$, thermal ceiling pinned at $75^\circ\text{C}$ with throttling protection.
- **Custom / Standard**: Disengages macro override, restoring individual user curve, manual slider, and battery limit configurations.

## Consequences
- Clean separation of concerns between manual fixed speed and dynamic temperature tracking.
- Eliminates acoustic fan hunting for everyday tasks while preserving maximum cooling for compute spikes.
- Prevents overheating when fans are held artificially quiet without sacrificing silence.
- UI fits natively inside the 320–360px menu-bar popover without modal bloat.

