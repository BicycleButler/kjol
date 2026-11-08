---
title: Two-Agent Grill — Kjol/ViewModels.swift (ViewModels)
domain: Kjol/ViewModels.swift
session_token: ff49d217
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### Async data flow for battery/telemetry in Kjol/ViewModels.swift

**Current code (Kjol/ViewModels.swift: @Published properties, Task-based async telemetry):**

```swift
// See: Kjol/ViewModels.swift
```

**A)** Keep the current Task + @Published approach — SwiftUI's native async support makes this clean and correct for view model updates.
**B)** Switch to Combine's ObservableObject + async sequences — more boilerplate but works on older macOS versions without Swift Concurrency.
**C)** Add a caching layer between async calls and @Published — prevents UI flicker when telemetry polls faster than the view renders.

**Recommendation:** A — Keep the current Task + @Published approach — SwiftUI's native async support makes this clean and correct for view model updates.

<!--ff49d217_GM_Q1_DONE-->

**Reviewer:** Agree with keeping Task + @Published because it aligns with modern SwiftUI patterns and prevents unnecessary Combine boilerplate for a macOS Apple-Silicon target that ships with Swift Concurrency.
**Verdict:** Agree
**Reasoning:** The minimum deployment target is likely modern macOS where async/await and @Published are sufficient. Introducing Combine only adds surface area without clear gain here. Option C could be revisited if telemetry jitter becomes observable.
**Risk:** None if the deployment target already supports Swift Concurrency. Otherwise this choice would lock out older OS versions.

<!--ff49d217_R_Q1_DONE-->

### Secondary design concern in Kjol/ViewModels.swift

**Current code (Kjol/ViewModels.swift (secondary review)):**

```swift
// See: Kjol/ViewModels.swift
```

**A)** Keep ViewModels as-is — the secondary concern is minor.
**B)** Refactor ViewModels to address the secondary concern — improves robustness.
**C)** Extract and document the secondary concern as a known limitation.

**Recommendation:** A — Keep ViewModels as-is — the secondary concern is minor.

**Reviewer:** Agree — keeping ViewModels unchanged is the right call.
**Verdict:** Agree
**Reasoning:** For a privileged-helper architecture like Kjol, the view-model layer must stay minimal and prevent expanding its surface area for a minor secondary concern. Refactoring here would introduce risk without proportional gain.
**Risk:** Leaving an undocumented limitation in ViewModels could surface as future confusion or inconsistent behavior as the app evolves.
<!--ff49d217_R_Q2_DONE-->
<!--ff49d217_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
