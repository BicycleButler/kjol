---
title: Two-Agent Grill — Kjol/UpdateViewModel.swift (UpdateViewModel)
domain: Kjol/UpdateViewModel.swift
session_token: 65b61474
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### Async state management pattern in Kjol/UpdateViewModel.swift

**Current code (Kjol/UpdateViewModel.swift: @Published properties, Task-based async state updates):**

```swift
// See: Kjol/UpdateViewModel.swift
```

**A)** Keep Task + @Published — SwiftUI's native pattern, clear and correct for view model updates.
**B)** Switch to Combine's ObservableObject + async sequences — more boilerplate but works on older macOS.
**C)** Add a caching layer between async calls and @Published — prevents UI flicker when polling faster than rendering.

**Recommendation:** A — Keep Task + @Published — SwiftUI's native pattern, clear and correct for view model updates.

**Reviewer:** Agree. Task + @Published remains the simplest and most idiomatic SwiftUI approach for this scope.
**Verdict:** Agree
**Reasoning:** Options B and C add complexity without a clear requirement here—no stated need for legacy macOS support or anti-flicker caching at this time. Keeping the native pattern minimizes maintenance burden and aligns with the project's SwiftUI-first architecture.
**Risk:** Low. If polling frequency later exceeds rendering rate, flicker can be revisited, but no evidence of that issue is present now.
<!--65b61474_R_Q1_DONE-->
<!--65b61474_GM_Q1_DONE-->

### State machine completeness in Kjol/UpdateViewModel.swift

**Current code (Kjol/UpdateViewModel.swift: switch on state enum, needs transition logging):**

```swift
// See: Kjol/UpdateViewModel.swift
```

**A)** Keep the UpdateViewModel state machine as-is — all cases are handled with a default fallback.
**B)** Add exhaustive switch checking (no default) — Swift's exhaustive switches would catch unhandled states at compile time but requires @frozen or all-case enumeration.
**C)** Add state transition logging — helps debug state machine issues in production through os_log, currently no logging of transitions.

**Recommendation:** C — Add state transition logging — helps debug state machine issues in production through os_log, currently no logging of transitions.

**Reviewer:** Option C is the lowest-cost improvement for production debuggability.
**Verdict:** Agree
**Reasoning:** The existing default fallback already suppresses compile-time exhaustiveness, making option B a future refactor with limited near-term payoff. Adding os_log transition logging (option C) directly improves observability without changing runtime behavior or adding build constraints.
**Risk:** Minimal. State transition logs are read-only diagnostics and must not affect performance or correctness.
<!--65b61474_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
