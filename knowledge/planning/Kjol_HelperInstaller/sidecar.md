---
title: Two-Agent Grill — Kjol/HelperInstaller.swift (HelperInstaller)
domain: Kjol/HelperInstaller.swift
session_token: 94f8fce3
grill_version: 2.5.5
status: complete
---

## Grilling & Discussion

### Error swallowing with try? in Kjol/HelperInstaller.swift

**Current code (Kjol/HelperInstaller.swift: try? usage on SMC/FanController calls):**

```swift
// See: Kjol/HelperInstaller.swift
```

**A)** Keep try? for hardware access — SMC reads can fail transiently, and crashing the daemon for a transient read failure is worse than a default value.
**B)** Replace try? with try + logging — surfaces failures for debugging while still catching errors gracefully.
**C)** Use a Result type or throws with a fallback wrapper — structured error handling that logs and returns defaults.

**Recommendation:** B — Replace try? with try + logging — surfaces failures for debugging while still catching errors gracefully.

**Reviewer:** Agree. The recommendation is sound and already narrows to the lowest-overhead option.
**Verdict:** Agree
**Reasoning:** SMC reads can legitimately fail transiently, but silently swallowing every failure hides real issues and makes support harder. Adding logging preserves safety while improving debuggability.
**Risk:** Low. The helper daemon already has a logging path and adding do-catch blocks is straightforward.

<!--94f8fce3_R_Q1_DONE-->
<!--94f8fce3_GM_Q1_DONE-->

### Error handling for subprocess shell() calls in Kjol/HelperInstaller.swift

**Current code (Kjol/HelperInstaller.swift: shell() returns (output, exitCode) with try?/catch, no stderr logging):**

```swift
// See: Kjol/HelperInstaller.swift
```

**A)** Keep try? for shell() calls — hardware commands can fail transiently and crashing the daemon is worse than silent degradation.
**B)** Add explicit logging for shell() failures — surfaces issues for debugging while keeping the daemon alive.
**C)** Use Result<...> for all shell() calls — structured error handling but requires rewriting every caller.

**Recommendation:** B — Add explicit logging for shell() failures — surfaces issues for debugging while keeping the daemon alive.

**Reviewer:** Agree — adding failure logging to shell() calls preserves daemon uptime while surfacing transient hardware command failures for diagnostics.
**Verdict:** Agree
**Reasoning:** This is a pragmatic incremental step. Keep try? swallowing the error, but log the fact that a shell command failed so operators can detect patterns. Structured Result<...> (option C) would be ideal long-term but is a larger refactor not justified yet.
**Risk:** Logging must prevent recording sensitive command arguments if these calls ever pass secrets or host-specific state.
<!--94f8fce3_R_Q2_DONE-->
<!--94f8fce3_GM_Q2_DONE-->

## Proposed ADR

<!--END-->
