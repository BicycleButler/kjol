# Planning: Fan Control Consolidation & Adaptive Curves

## Objectives
1. Remove deprecated `Quiet` mode.
2. Rename `Custom` (fixed percentage) to `Manual`.
3. Enhance `Adaptive` mode with three distinct sub-strategies:
   - **Gentle (Cool Native)**: Quiet, progressive curve with low-pass filtering and 20s gradual decay for cool yet silent everyday computing.
   - **Aggressive (Heavy Compute)**: Existing thermal acceleration ($\Delta T/\Delta t$) and 12s peak hold for compile/render workloads.
   - **Custom Curve**: Interactive, user-configurable temperature milestones ($45^\circ\text{C}, 60^\circ\text{C}, 75^\circ\text{C}, 88^\circ\text{C}$) with a polished SwiftUI visual curve editor.
4. Maintain full backward-compatibility and safe watchdog daemon state persistence in `/var/db/kjol/`.

## Architectural Mapping & File Updates

- Component | Target File | Changes
- Shared Model | `Kjol/main.swift` | Update `FanProfile` enum to `auto`, `adaptive`, `manual`, `blast`. Add `AdaptiveSubProfile` enum (`gentle`, `aggressive`, `custom`). Add `CustomCurvePoints` struct with persistence.
- UI Component | `Kjol/main.swift` | Refactor `FanControlCardView`: top segmented bar, adaptive sub-selector pills, manual slider, and new `CustomCurveEditorView` (SwiftUI `Canvas` spline + milestone controls).
- View Model | `Kjol/ViewModels.swift` | Update `FanControlViewModel` with `subProfile: AdaptiveSubProfile`, `customCurve: CustomCurvePoints`, debouncing, and XPC sync.
- Host Coordinator | `Kjol/Host.swift` | Propagate sub-profile and curve point changes through `XpcClient`.
- XPC Client | `Kjol/XpcClient.swift` | Support sending sub-profile and custom curve points over XPC.
- XPC Protocol | `KjolHelper/KjolHelperProtocol.swift` | Add or extend methods to support curve points configuration or encoding.
- Helper Daemon | `KjolHelper/main.swift` | Update profile parser, add piecewise curve evaluator, implement gentle EMA filter + 20s decay, aggressive delta-T boost, and custom curve interpolation.

## Implementation Steps
1. **Helper & Protocol**: Update `KjolHelperProtocol.swift` and `KjolHelper/main.swift` to evaluate piecewise curves and persist curve state in `/var/db/kjol/`.
2. **Models & ViewModels**: Update `FanProfile`, `AdaptiveSubProfile`, `FanControlViewModel`, and `Host.swift`.
3. **SwiftUI View**: Implement `CustomCurveEditorView` in `Kjol/main.swift` with smooth curve rendering, milestone adjustment, and temperature tracking.
4. **Interactive Parameter Synchronization (ADR-008)**:
   - Eliminate value-copy closure capture in `milestoneSliderRow` via `anchorBinding(for:)` and parameterless `commitCurveAnchor(temp:)`.
   - Route parameter adjustments through non-blocking `performQuietAction` without toggling `host.busy`, preventing slider track aborts and popover visual flicker.
   - Implement a 3.0-second reconciliation grace window in `FanControlViewModel.updateFromDaemon` to guard against stale telemetry echoes clobbering active edits.
5. **Verification**: Run `./build-kjol.sh` to make sure clean compilation and packaging.

