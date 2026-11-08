---
title: Two-Agent Grill — KjolHelper/KjolHelperProtocol.swift (KjolHelperProtocol)
domain: KjolHelper/KjolHelperProtocol.swift
session_token: 388367c7
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### General code organization in KjolHelper/KjolHelperProtocol.swift

**Current code (KjolHelper/KjolHelperProtocol.swift (general review)):**

```swift
// See: KjolHelper/KjolHelperProtocol.swift
```

**A)** Keep KjolHelperProtocol as-is — it has clear responsibilities and follows Swift conventions.
**B)** Refactor KjolHelperProtocol into smaller focused types — improves testability and separation of concerns.
**C)** Extract shared utilities from KjolHelperProtocol into a common module — reduces duplication if patterns appear elsewhere.

**Recommendation:** A — Keep KjolHelperProtocol as-is — it has clear responsibilities and follows Swift conventions.

**Reviewer:** The recommendation to keep the current organization is reasonable given the protocol's focused responsibility set and Swift idiomatic structure.
**Verdict:** Agree
**Reasoning:** KjolHelperProtocol is small and cohesive. Premature splitting would add abstraction cost without a demonstrated need for independent reuse or testability gains.
**Risk:** Future growth can eventually warrant extraction if new responsibilities accumulate and the file becomes difficult to maintain.

<!--388367c7_R_Q1_DONE-->
<!--388367c7_GM_Q1_DONE-->

### Battery calibration state machine in KjolHelper/KjolHelperProtocol.swift

**Current code (KjolHelper/KjolHelperProtocol.swift: calibrationState machine lines 453-500):**

```swift
// See: KjolHelper/KjolHelperProtocol.swift
```

**A)** Keep the 4-phase calibration state machine (charging100 → holding100 → discharging15 → rechargingLimit) — it is a well-established battery calibration protocol.
**B)** Simplify to a 2-phase approach (charge to 100%, then discharge to 0%) — less user-friendly but simpler to maintain.
**C)** Make calibration duration configurable by the user — allows power users to tune hold times (currently hardcoded to 60 min).

**Recommendation:** A — Keep the 4-phase calibration state machine (charging100 → holding100 → discharging15 → rechargingLimit) — it is a well-established battery calibration protocol.

**Reviewer:** Option A is reasonable, but ignoring configurability of hold times in option C leaves calibration poorly tunable for different battery chemistries or user needs.
**Verdict:** Partially agree
**Reasoning:** The 4-phase state machine is a proven pattern and must stay. However, dismissing option C entirely overlooks a real maintainability concern: hardcoded 60-minute hold times can not be optimal across all hardware generations. The right move is to keep the state machine but externalize hold durations as tunable constants.
**Risk:** Leaving hold times hardcoded can require a larger refactor later if Apple changes SMC calibration behavior across silicon generations.
<!--388367c7_R_Q2_DONE-->

<!--388367c7_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
