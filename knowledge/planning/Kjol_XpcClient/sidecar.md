---
title: Two-Agent Grill — Kjol/XpcClient.swift (XpcClient)
domain: Kjol/XpcClient.swift
session_token: 8c1ecc25
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### Sync XPC API blocking pattern in Kjol/XpcClient.swift

**Current code (XpcClient.swift, syncSetAlwaysOn() lines 79-86: DispatchSemaphore with 2.0s timeout):**

```swift
// See: Kjol/XpcClient.swift
```

**A)** Keep the sync wrapper with DispatchSemaphore — it is needed for synchronous calls where the caller cannot use async, and the 2s timeout provides a reasonable safety bound.
**B)** Remove syncSetAlwaysOn entirely — force all callers to use the async path, eliminating the sync bridge complexity and potential semaphore deadlock risks.
**C)** Replace semaphore with a dedicated sync dispatch queue and XPC reply handler — cleaner separation but still synchronous.

**Recommendation:** A — Keep the sync wrapper with DispatchSemaphore — it is needed for synchronous calls where the caller cannot use async, and the 2s timeout provides a reasonable safety bound.
**Reviewer:** Hermes Agent
**Verdict:** Partially agree
**Reasoning:** Option A is pragmatic for callers that genuinely cannot use async, and the 2s timeout is a sensible safety bound. However, there is no discussion of exception-safe cancellation, so the risk analysis is incomplete.
**Risk:** If the semaphore timeout is hit without explicit error propagation, the caller can proceed on a stale/default state rather than surfacing the failure.
<!--8c1ecc25_GM_Q1_DONE-->
<!--8c1ecc25_R_Q1_DONE-->

### Lock serialization in async context in Kjol/XpcClient.swift

**Current code (Kjol/XpcClient.swift: NSLock usage for stateCache / connection protection):**

```swift
// See: Kjol/XpcClient.swift
```

**A)** Keep NSLock for synchronous critical sections in XpcClient — NSLock is safe for short critical sections and does not interact with Swift's cooperative threading model.
**B)** Replace NSLock with os.unfairlock or actor isolation — actors provide better async-safety guarantees, NSLock can deadlock in Swift concurrency contexts.
**C)** Use DispatchQueue(label:).async for all state mutations — prevents locks entirely but serializes all access.

**Recommendation:** A — Keep NSLock for synchronous critical sections in XpcClient — NSLock is safe for short critical sections and does not interact with Swift's cooperative threading model.

**Reviewer:** Hermes Agent
**Verdict:** Agree
**Reasoning:** NSLock remains appropriate here because the critical sections in XpcClient are short and synchronous. Swift Concurrency's cooperative threading model does not directly interact with pthread locks, and introducing actors would add unneeded complexity for this scope.
**Risk:** If present future work incorrectly moves these NSLock-guarded sections into an async context, deadlocks can emerge and require mitigation through os_unfair_lock or isolation boundary changes.

<!--8c1ecc25_R_Q2_DONE-->
<!--8c1ecc25_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
