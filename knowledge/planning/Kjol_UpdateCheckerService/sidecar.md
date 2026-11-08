---
title: Two-Agent Grill — Kjol/UpdateCheckerService.swift (UpdateCheckerService)
domain: Kjol/UpdateCheckerService.swift
session_token: f3ff6352
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### Async state management pattern in Kjol/UpdateCheckerService.swift

**Current code (Kjol/UpdateCheckerService.swift: @Published properties, Task-based async state updates):**

```swift
// See: Kjol/UpdateCheckerService.swift
```

**A)** Keep Task + @Published — SwiftUI's native pattern, clear and correct for view model updates.
**B)** Switch to Combine's ObservableObject + async sequences — more boilerplate but works on older macOS.
**C)** Add a caching layer between async calls and @Published — prevents UI flicker when polling faster than rendering.

**Recommendation:** A — Keep Task + @Published — SwiftUI's native pattern, clear and correct for view model updates.

**Reviewer:** The recommendation is sound for a SwiftUI-only, modern-macOS codebase, but it omits any mitigation for polling-driven UI flicker.
**Verdict:** Partially agree
**Reasoning:** Option A is the right baseline for Kjol's current deployment target because Task + @Published is the idiomatic, lowest-overhead path for view-model-driven UI. However, given this is a polling service, frequent state updates can still produce visible flicker. The recommendation must at least note that, or adopt a minimal debounce/equality guard before publishing.
**Risk:** Without additional protection, rapid polling updates can cause visual jitter or redundant view renders in the menu bar UI.
<!--f3ff6352_R_Q1_DONE-->
<!--f3ff6352_GM_Q1_DONE-->

### State machine completeness in Kjol/UpdateCheckerService.swift

**Current code (Kjol/UpdateCheckerService.swift: switch on state enum, needs transition logging):**

```swift
// See: Kjol/UpdateCheckerService.swift
```

**A)** Keep the UpdateCheckerService state machine as-is — all cases are handled with a default fallback.
**B)** Add exhaustive switch checking (no default) — Swift's exhaustive switches would catch unhandled states at compile time but requires @frozen or all-case enumeration.
**C)** Add state transition logging — helps debug state machine issues in production through os_log, currently no logging of transitions.

**Recommendation:** C — Add state transition logging — helps debug state machine issues in production through os_log, currently no logging of transitions.

**Reviewer:** Agree — logging state transitions is a safe, low-risk observability improvement that directly supports troubleshooting in production without changing behavior.
**Verdict:** Agree
**Reasoning:** This is the lowest-risk option and adds immediate operational value. Adding compile-time exhaustive switches (B) would be an invasive refactor for an existing working state machine, while leaving it as-is (A) misses an easy debugging win.
**Risk:** Minimal — os_log has negligible runtime cost and does not alter state machine semantics.

<!--f3ff6352_R_Q2_DONE-->

<!--f3ff6352_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
