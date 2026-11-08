# Concept Plan: Ephemeral Presentation Lifecycle & Dormant Memory Reclamation

## Problem Statement
Kjol is designed to be an unobtrusive, ultra-lightweight macOS menu bar utility for Apple Silicon. While the user is not actively interacting with the popover UI, Kjol should consume minimal memory overhead and zero CPU wakeups.

Prior to this architecture, opening the UI caused the app's physical memory footprint to climb from ~15 MB to 60–110 MB. Dismissing the popover did not reclaim this memory because `NSPopover` and its `KjolHostingController` were held indefinitely in `AppDelegate`, pinning the SwiftUI `AttributeGraph`, CoreAnimation layer trees, and `IOSurface` backing buffers in RAM.

## Architectural Objectives
1. **Minimal Dormant Memory Footprint:** Return all transient UI memory, textures, and dirty heap pages to macOS immediately upon popover dismissal.
2. **Zero Functional Compromise:** Preserve all background operations (Always-On clamshell management, AppleSMC fan watchdog, battery limits, compute governor) with 100% fidelity.
3. **Sub-Perceptual UI Latency:** Keep popover presentation latency under 5ms so the UI opens instantaneously when the user clicks the status bar item.
4. **Information Hiding:** Keep the popover lifecycle encapsulated entirely within `AppDelegate`, maintaining clean separation from the persistent coordinator (`Host`).

## Implementation Roadmap

### Phase 1: Ephemeral Popover Lifecycle in `AppDelegate`
- Eliminate persistent retention of `popover`.
- On `togglePopover`:
  - Materialize `NSPopover` and `KjolHostingController(rootView: KjolView().environmentObject(host))` just-in-time.
- On `popoverDidClose`:
  - Nullify `contentViewController`.
  - Close and release `popover`.
  - Execute dismissal inside an `autoreleasepool`.
  - Invoke `malloc_zone_pressure_relief(nil, 0)`.

### Phase 2: Memory Pressure Source & Asset Optimization
- Cache status item template image in `AppDelegate` to prevent repeated disk bundle reads.
- Register a `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` to automatically invoke `malloc_zone_pressure_relief(nil, 0)` under global system memory pressure.

### Phase 3: Verification & Memory Profiling
- Validate build with `build-kjol.sh`.
- Measure process memory before opening popover, during active presentation, and after dismissal.
- Verify seamless popover opening, closing, and control interaction.

