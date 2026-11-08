# ADR-007: Ergonomic Control Hierarchy, Non-Occluding Tooltip Architecture, and Unified Action Strip

## Context
Kjol's initial popover interface grouped controls into fixed-width cards (380pt). As feature density expanded, several ergonomic mismatches emerged:
1. **Window Constriction:** A 380pt width caused horizontal crowding, truncated labels, and stacked controls, forcing excessive vertical scrolling.
2. **Scattered Governor Controls:** The Compute Governor toggle was placed in the Battery card. It belongs with memory reclamation and compute.
3. **Redundant Top Actions:** The top bar showed a Battery Settings button. This duplicated the primary button in Battery Management.
4. **Header Clutter & Sizing Disparity:** Macro fan presets crowded the header with small buttons. Quick Actions had oversized buttons.
5. **Tooltip Occlusion & Stacking Errors:** Tooltips drawn through local offsets covered interactive toggles and blocked user clicks. The Governor toggle had verbose text.

## Decision

We adopt an **Ergonomic Control Hierarchy, Non-Occluding Tooltip Architecture, and Unified Action Strip**:

### 1. Expanded Proportional Window Geometry
The popover canvas maintains the expanded 513pt breadth. This horizontal breadth provides visual breathing room, allowing multi-point telemetry, curve canvases, and compact button groups to coexist without layout shifts or text wrapping.

### 2. Clean Header Surface
`HeaderView` is simplified to contain only the application motif/title on the left, and the busy indicator and helper status badge on the right. The fan preset toggle bar is evicted from the header.

### 3. Unified Action Strip with Equal-Sized Action Buttons
A unified action row consolidates all primary quick actions:
- **Always-On Clamshell:** Compact 40x40pt action button (`cup.and.saucer`).
- **Boost Memory:** Compact 40x40pt action button (`bolt.badge.automatic`).
- **Compute Governor Minimalist Toggle:** Only the toggle switch (no text label, no extraneous icon) mounted directly beneath the Boost Memory button, centered to its width.
- **Fan Cooling Presets:** Three 40x40pt preset buttons (**Gentle Silent**, **Custom**, and **Max Compute**) share the row. All five buttons have identical 40x40pt dimensions.

### 4. Non-Occluding Tooltip Presentation Architecture
We introduce a hoisted/window-level or non-overlapping clearance geometry for `.kjolTooltip`:
- Enforces an ergonomic 200ms hover delay using scheduled dispatch work items.
- Guarantees strict non-occlusion ($gap \ge 6\text{pt}$ clearance strictly outside the target control's bounding box), preventing tooltips from ever covering the button, toggle, or adjacent pills.
- Removes duplicate native macOS `.help()` to eliminate conflicting OS-level hover popups.
- Sets `.allowsHitTesting(false)` and elevates tooltips to the topmost presentation layer.

### 5. Thermal Posture Re-anchoring
In the Fan Control Strategy card, the top position is assigned to the safety system, **Thermal Posture**:
- Directly surfaces the active policy pills: **Off**, **Fan Boost**, and **Throttle CPU**.
- Non-occluding tooltips appear above or below with guaranteed clearance, preserving full clickability of the pills.

## Consequences

### Positive
- **Zero Click Blocking:** Tooltips never overlap their trigger elements or neighboring toggles.
- **Consistent Action Row:** Always-On, Boost Memory, and Fan Presets share identical dimensions and visual weight.
- **De-cluttered Governor:** Governor toggle is compact, clean, and positioned directly below Boost Memory without distracting label text.
- **Clean Header:** The top header is reserved for app identity and privileged daemon connectivity status.

### Negative / Trade-offs
- The 40x40pt uniform buttons require careful spacing across the horizontal row. (513pt window width accommodates this comfortably).
