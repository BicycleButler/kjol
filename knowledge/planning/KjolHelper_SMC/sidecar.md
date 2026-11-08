---
title: Two-Agent Grill — KjolHelper/SMC.swift (SMC)
domain: KjolHelper/SMC.swift
session_token: b22b541b
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### Ftst unlock retry loop in KjolHelper/SMC.swift

**Current code (main.swift setManual() lines 266-286: 12x0.5s retry for Ftst unlock):**

```swift
// See: KjolHelper/SMC.swift
```

**A)** Keep the busy-wait retry loop — necessary for M2-M4 sleep/wake recovery, bounded 6s window permitted for rare user actions.
**B)** Replace with single attempt + immediate error — eliminates latency but requires manual retry by user.
**C)** Move retry to caller-side async with spinner — decouples latency from XPC reply path.

**Recommendation:** C — Move retry to caller-side async with spinner — decouples latency from XPC reply path.

**Reviewer:** The caller-side async decoupling is architecturally sound for an XPC-based macOS helper because it keeps the daemon responsive and moves latency to the UI layer where a spinner is permitted.
**Verdict:** Agree
**Reasoning:** Option C preserves the bounded retry semantics for the rare M2-M4 Ftst unlock failure while freeing the privileged helper from blocking on sleep/wake recovery. Option A’s 6s busy-wait in the daemon is the riskier choice for future latency regressions.
**Risk:** The main risk is coupling spinner lifecycle to the XPC reply path, but this is manageable in SwiftUI with task/id and presents less latency surface than the current in-daemon loop.

<!--b22b541b_R_Q1_DONE-->
<!--b22b541b_GM_Q1_DONE-->

### Adaptive fan watchdog timer strategy in KjolHelper/SMC.swift

**Current code (KjolHelper/SMC.swift: applyFanProfile() adaptive logic, tickFanWatchdog() at 5s intervals):**

```swift
// See: KjolHelper/SMC.swift
```

**A)** Keep 5s periodic fan watchdog with 12s asymmetric spin-down hold — the hysteresis prevents acoustic fan hunting while maintaining thermal responsiveness.
**B)** Reduce watchdog interval to 2s for faster thermal response — but increases CPU wakeups and SMC read load on a root daemon.
**C)** Switch to event-driven fan updates (trigger on temperature events) rather than polling — more efficient but requires kernel notification setup that can not be available for SMC keys.

**Recommendation:** A — Keep 5s periodic fan watchdog with 12s asymmetric spin-down hold — the hysteresis prevents acoustic fan hunting while maintaining thermal responsiveness.

**Reviewer:** Hermes Agent
**Verdict:** Agree
**Reasoning:** Option A is the right balance for a root daemon: 5s polling is conservative enough to prevent thermal risk while keeping SMC reads low, and the 12s asymmetric hold directly solves fan hunting without needing unavailable SMC event sources.
**Risk:** If Apple removes the current SMC key behavior on future Silicon, the watchdog spin-down hold can need tuning.
<!--b22b541b_R_Q2_DONE-->
<!--b22b541b_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
