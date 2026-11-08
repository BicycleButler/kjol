---
title: Two-Agent Grill — Kjol/main.swift (main)
domain: Kjol/main.swift
session_token: 3eb071fa
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### General code organization in Kjol/main.swift

**Current code (Kjol/main.swift (general review)):**

```swift
// See: Kjol/main.swift
```

**A)** Keep main as-is — it has clear responsibilities and follows Swift conventions.
**B)** Refactor main into smaller focused types — improves testability and separation of concerns.
**C)** Extract shared utilities from main into a common module — reduces duplication if patterns appear elsewhere.

**Recommendation:** A — Keep main as-is — it has clear responsibilities and follows Swift conventions.

**Reviewer:** The recommendation is sound because the current main.swift already follows Swift conventions and maintains clear separation through the dedicated types identified in the project structure.
**Verdict:** Agree
**Reasoning:** The project already delegates well-scoped concerns to Host.swift, ViewModels.swift, XpcClient.swift, and other focused types, so main.swift appropriately serves as the composition root. Premature refactoring into additional abstractions would add complexity without a demonstrated duplication or testability problem. Keeping main as-is preserves the existing, battle-tested startup path for a small native macOS tool.
**Risk:** Low risk. The main change surface is minimal and limited to the existing app entry point, with the actual risky operations already encapsulated in the helper daemon and supporting types.

<!--3eb071fa_R_Q1_DONE-->
<!--3eb071fa_GM_Q1_DONE-->

### Adaptive fan watchdog timer strategy in Kjol/main.swift

**Current code (Kjol/main.swift: applyFanProfile() adaptive logic, tickFanWatchdog() at 5s intervals):**

```swift
// See: Kjol/main.swift
```

**A)** Keep 5s periodic fan watchdog with 12s asymmetric spin-down hold — the hysteresis prevents acoustic fan hunting while maintaining thermal responsiveness.
**B)** Reduce watchdog interval to 2s for faster thermal response — but increases CPU wakeups and SMC read load on a root daemon.
**C)** Switch to event-driven fan updates (trigger on temperature events) rather than polling — more efficient but requires kernel notification setup that can not be available for SMC keys.

**Recommendation:** A — Keep 5s periodic fan watchdog with 12s asymmetric spin-down hold — the hysteresis prevents acoustic fan hunting while maintaining thermal responsiveness.

**Reviewer:** Agree with A. The 5s/12s pairing is a defensible default for a root daemon.
**Verdict:** Agree
**Reasoning:** A prevents the unnecessary CPU wakeup and SMC read overhead of B, while C is architecturally preferable but blocked by uncertain SMC key notification support. The asymmetric hold elegantly prevents acoustic fan hunting without sacrificing thermal responsiveness.
**Risk:** If Apple later exposes kernel notifications for SMC temperature keys, C can become the better choice and this must be revisited.

<!--3eb071fa_R_Q2_DONE-->
<!--3eb071fa_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
