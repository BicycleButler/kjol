# Proposed Decisions — KjolHelper Daemon (XPC + SMC + Battery)

## Q1: Ftst unlock fallback busy-wait in setManual()

**Verdict rating (1-5): 3**

**Recommended decision (from Reviewer):** Partially agree

**GM position:** A — Keep the 12x0.5s busy-wait retry loop as-is. The retry is hardware-necessary for M2-M4 where thermalmonitord resets fan mode on sleep/wake, and the 6s latency for a rare, user-initiated fan profile change is permitted.

**Synthesized decision: Option C — Move the retry loop out of the synchronous XPC reply path and implement a caller-side async retry with a decoupled failure model.**

Specifically:
- The initial SMC write attempt must remain synchronous and fast (no retry).
- If the mode write fails AND the Ftst unlock attempt also fails within a short bounded window (for example, 2–3 quick attempts, not 6s), return an immediate failure to the XPC client with a specific error code ("FtstUnlockInProgress" or "FanModeWriteFailed").
- The UI layer (caller-side) handles retry through a background task, displaying a spinner to the user. The retry can be more aggressive (for example, 12 attempts over 6s) because it no longer blocks the XPC reply.
- Separate the two failure modes: distinguish "Ftst unlock timing" from "mode write rejection" with distinct error codes for production debugging clarity.

**Rationale:** The two positions are partially correct — the hardware-level retry is genuinely necessary for M2-M4 sleep/wake recovery, but blocking the XPC reply path for 6s risks client timeouts and watchdog kills. Option C retains the hardware coverage while decoupling latency from the synchronous reply path, satisfying the Reviewer's risk concerns without surrendering the GM's hardware-necessity stance. The added complexity is justified by the resilience gains in a privileged daemon handling concurrent requests.

## Q2: State cache against. disk-backed reads in Helper daemon

**Verdict rating (1-5): 4**

**Recommended decision (from Reviewer):** Partially agree

**GM position:** A — Keep the in-memory `stateCache` dict with file backing as-is. The daemon is a singleton with no external writers, the cache improves performance on high-frequency ticks, and state is re-read from disk on daemon restart.

**Synthesized decision: Option A — Keep the cache as-is, but add a targeted invalidation hook for XPC-driven state writes.**

Specifically:
- Retain the existing `stateCache` + `stateQueue` serialization scheme.
- No periodic disk refresh (the singleton/no-external-writers assumption holds).
- Add an explicit cache invalidation path when the daemon itself writes state through XPC (that is, `writeState` already updates the cache in-place, which is correct — no change needed there).
- Document the cache-coherency contract: the cache is a write-through mirror of `/var/db/kjol/` and is only mutated by the daemon's own XPC handlers. External out-of-band writes are unsupported and will not be reflected until daemon restart.

**Rationale:** The cache scheme is sound for the current threat model (singleton daemon, no external writers). The Reviewer's stale-cache risk is valid but only materializes under out-of-band external writes, which the daemon does not support or need to defend against. The synthesized decision preserves the GM's performance rationale while documenting the coherency boundary, making the cache safe by construction rather than by accident. A periodic refresh (Option B) or full disk reads (Option C) would add unnecessary I/O to a correctly-isolated system.

## Summary

- Q | GM Recommendation | Reviewer Verdict | Synthesized Decision | Complexity Delta
- 1 | A (keep retry) | Partially agree | C (async caller-side retry) | Moderate (UI-side retry logic)
- 2 | A (keep cache) | Partially agree | A (keep cache + documented invariants) | Minimal (documentation only)

Note: The "Proposed ADR" section and "Obvious Optimizations" list from the GM were out of scope for the two graded Q&A pairs and are not addressed here. They must be evaluated in a separate session.
