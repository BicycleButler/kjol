# ADR-007: Ergonomic Control Hierarchy, Thermal Posture, and Contextual Tooltips

## Context
Kjol's initial popover interface grouped controls into fixed-width cards (380pt). As feature density expanded, several ergonomic mismatches emerged:
1. **Window Constriction:** A 380pt width caused horizontal crowding, truncated labels, and stacked controls, forcing excessive vertical scrolling.
2. **Scattered Governor Controls:** The Compute Governor toggle was placed in the Battery card. It belongs with memory reclamation and compute.
3. **Redundant Top Actions:** The top bar showed a Battery Settings button. This duplicated the primary button in Battery Management.
4. **Displaced Thermal Safety:** Macro presets occupied prime space in Fan Control. The critical safety arbiter remained at the bottom.
5. **Information Scarcity on Compact Controls:** Compact icon buttons without fast contextual guidance cause discovery friction. Native tooltips impose slow delays.

## Decision

We adopt an **Ergonomic Control Hierarchy and Contextual Tooltip Architecture** across Kjol's menu bar presentation layer:

### 1. Expanded Proportional Window Geometry
The popover canvas expands by 35% (from 380pt to 513pt). This horizontal breadth provides visual breathing room, allowing multi-point telemetry, curve canvases, and compact button groups to coexist without layout shifts or text wrapping.

### 2. Header Surface Integration with Color-Anchored Macro Presets
The top `HeaderView` integrates a persistent 3-mode macro preset toggle bar directly beside the application title:
- Anchored on the left by an immutable, colored fan symbol (`fanblades.fill`) signifying active acoustic/thermal orchestration.
- Houses three discrete mode switches in strict order: **Gentle**, **Custom**, and **Max Compute**.
- Frees the Fan Control Strategy card from macro-level switching, letting that card focus entirely on hardware-level fan curves.

### 3. Unified Compute & Memory Reclamation Cluster
The top Quick Actions bar removes redundant battery links and consolidates performance controls into an icon-centric cluster:
- **Always-On Clamshell:** Compact icon button (`cup.and.saucer`).
- **Boost Memory:** Compact icon button (`bolt.badge.automatic`), renamed from "Pause Background Daemons".
- **Compute Governor Sub-Control:** The 4-hour safety limit toggle moves directly below "Boost Memory". This establishes tight functional cohesion.

### 4. Thermal Posture Re-anchoring
In the Fan Control Strategy card, the top position previously occupied by presets is reassigned to the safety system, renamed **Thermal Posture**:
- Directly surfaces the active policy pills: **Off**, **Fan Boost**, and **Throttle CPU**.
- Immediate visual indicators reflect whether emergency fan boost or CPU throttling is actively engaged.

### 5. High-Responsiveness 200ms Contextual Tooltip Engine
We introduce a lightweight, declarative SwiftUI tooltip modifier (`.kjolTooltip(title:description:placement:delay:)`) across all interactive elements:
- Enforces an ergonomic 200ms hover delay using scheduled dispatch work items.
- Displays a structured, contrast-rich floating badge containing the control title and an explanation of its operational behavior.
- Retains native macOS `.help()` as an underlying accessibility and VoiceOver fallback.

### 6. Accurate Native Battery Guidance
Updates the system-managed battery guidance text on macOS 27+ to:
`"Set charging limits in macOS system settings - 80% charge limit recommended for battery health"`.

## Consequences

### Positive
- **High Information Density with Zero Clutter:** Icon-only buttons save vertical and horizontal space while 200ms tooltips provide instant discoverability.
- **Logical Domain Cohesion:** The Compute Governor is unified with memory reclamation and daemon suppression.
- **Immediate Thermal Visibility:** Thermal Posture sits immediately above fan curves, clarifying system failsafe boundaries.
- **Rapid Navigation:** Presets are accessible from the persistent header without scrolling.

### Negative / Trade-offs
- The 513pt popover width consumes more desktop screen space. It remains within standard bounds for Apple Silicon displays.
