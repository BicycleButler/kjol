---
title: Two-Agent Grill — Kjol/Host.swift (Host)
domain: Kjol/Host.swift
session_token: 3c5c3a75
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### XPC reconnection polling with retry timer in Kjol/Host.swift

**Current code (Kjol/Host.swift: XPC reconnection backoff + telemetry polling):**

```swift
// See: Kjol/Host.swift
```

**A)** Keep separate retry timers for XPC reconnection and telemetry polling — decouples connection recovery (exponential backoff) from data refresh (fixed 3s).
**B)** Unify retry timers into one polling loop — simpler but couples connection recovery to telemetry refresh rates.
**C)** Use async sequence for reconnection (AsyncStream) — more Swift-concurrency-idiomatic but harder to cancel cleanly.

**Recommendation:** A — Keep separate retry timers for XPC reconnection and telemetry polling — decouples connection recovery (exponential backoff) from data refresh (fixed 3s).
**Reviewer:** Agree — separate retry loops prevent starvation and backoff interference.
**Verdict:** Agree
**Reasoning:** Coupling XPC reconnection to a 3s telemetry timer would delay recovery during transient failures, and async sequences here add cancellation complexity without measurable benefit.
**Risk:** Managing two timers increases state tracking, but the decoupling benefit outweighs that overhead.
<!--3c5c3a75_R_Q1_DONE-->

<!--3c5c3a75_GM_Q1_DONE-->

### Polling interval and activity assertion in Kjol/Host.swift

**Current code (Kjol/Host.swift: startPolling(interval: TimeInterval = 3.0)):**

```swift
// See: Kjol/Host.swift
```

**A)** Keep 3.0s polling with IDLE_SYSTEM_SLEEP_DISABLED activity — makes sure that telemetry is fresh for UI while preventing sleep during polling.
**B)** Increase to 5.0s polling — reduces CPU/battery overhead at the cost of slightly stale telemetry.
**C)** Make polling interval configurable — allows users to balance freshness against. battery life.

**Recommendation:** B — Increase to 5.0s polling — reduces CPU/battery overhead at the cost of slightly stale telemetry.

**Reviewer:** Hermes
**Verdict:** Agree
**Reasoning:** B is the correct tradeoff for a menu-bar utility: 3.0s is unnecessarily chatty for UI telemetry, while 5.0s still keeps displays current enough for human interaction without keeping the CPU awake more than needed.
**Risk:** Telemetry lag can briefly delay UI updates in low-power/idle states.

<!--3c5c3a75_R_Q2_DONE-->
<!--3c5c3a75_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
