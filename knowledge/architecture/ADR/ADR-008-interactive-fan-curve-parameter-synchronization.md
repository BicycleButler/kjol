# ADR-008: Interactive Fan Curve Parameter Synchronization & Non-Blocking Control Gating

## Context
In Kjol v1.2, adjusting the 4-milestone custom adaptive fan curve ($45^\circ\text{C}, 60^\circ\text{C}, 75^\circ\text{C}, 88^\circ\text{C}$) in `CustomCurveEditorView` suffered from a regression:
1. When dragging milestone sliders, releasing the slider caused the popover to flicker and the slider immediately snapped back to its default value.
2. In `milestoneSliderRow(_ anchor: CurveMilestone)`, `anchor` was passed as a value parameter (`struct`). The `Slider`'s `onEditingChanged` closure captured `anchor.rpmPercent` at construction time. When released (`editing == false`), it invoked `updateCurveAnchorRPM(temp: anchor.temp, rpm: anchor.rpmPercent, immediate: true)`, resetting the RPM to the stale initial value.
3. Mid-drag debounce timers (`0.25s`) fired `Host.performAction`, engaging `host.busy = true`. Because controls were bound to `.disabled(host.busy)`, the slider was disabled while the user was actively dragging it, aborting AppKit mouse tracking and forcing premature termination.
4. Subsequent background telemetry polls (`refresh()`) echoed stale daemon curve points before the helper's state directory write could be reflected.

## Decision

### 1. Keyed Lens Binding & Parameterless Commit
Replace value-captured parameters in `CustomCurveEditorView` with live bindings provided by `FanControlViewModel`:
- `anchorBinding(for temp: Double) -> Binding<Double>`: Reads directly from the live `@Published var customCurveAnchors` collection by milestone temperature, updating in-memory values continuously for 60fps canvas spline rendering.
- `commitCurveAnchor(temp: Double)`: Parameterless commit method invoked on `onEditingChanged(false)`. Retrieves the current in-memory value, persists to `UserDefaults`, and dispatches to the helper.

### 2. Non-Blocking Parameter Adjustments (`performQuietAction`)
Introduce `Host.performQuietAction`:
- Continuous parameter tuning (fan curves, manual fan percentages, thermal ceilings) executes asynchronously without engaging `host.busy = true`.
- Controls remain enabled throughout interaction, preventing AppKit mouse tracking cancellation and popover visual flicker.
- `host.busy` remains reserved for coarse state transitions (SMC unlock retries, daemon reinstallation, macro preset changes).

### 3. Interaction Gating & Reconciliation Grace Window
- While a slider is being actively adjusted (`isInteracting == true`), intermediate XPC writes are suspended.
- On drag release, the final value is transmitted immediately.
- In `FanControlViewModel.updateFromDaemon`, incoming daemon `curvePoints` are suppressed if the last user mutation occurred within a $3.0\text{s}$ grace window (`lastUserMutationTime`), preventing telemetry polls from clobbering in-flight user adjustments.

## Consequences
- Milestones can be dragged smoothly and accurately without visual flicker or premature resets.
- Spline canvas updates in real-time with zero XPC or disk overhead during drag.
- Background telemetry polling safely coexists with interactive curve editing.

