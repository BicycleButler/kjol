# Concept Plan: Tiered Compute Governor & Memory Reclamation

## Problem Statement
The user activates "Pause Background Daemons" to dedicate all possible CPU and memory resources to demanding foreground tasks (compilation, containerized workloads, machine learning, 3D rendering). The previous mechanism was a blunt `pkill -STOP` on 18 processes, which:
1. Caused system beachballs when frontmost applications attempted synchronous IPC with suspended Spotlight/search daemons (`mds`, `corespotlightd`).
2. Failed to free memory, leaving hundreds of megabytes of dirty RAM held hostage by frozen tasks.
3. Ignored Apple Silicon's asymmetric P/E core topology.

## Architectural Objectives
1. **Maximize Active Compute:** Make sure that 100% of Performance (P) core compute and L2 cache capacity is freed for foreground user tasks.
2. **Reclaim Unified Memory:** Flush inactive file buffers and purgeable RAM back to the operating system pool.
3. **Prevent Deadlocks:** Make sure that zero user-facing application hangs, beachballs, or broken file dialogues.
4. **Information Hiding:** Keep the public XPC protocol interface narrow (`suspendDaemons(Bool)`) while encapsulating multi-tier process classification, Darwin task policy calls, and purge sequencing inside the privileged helper.

## Implementation Roadmap

### Phase 1: Process Classification Matrix
Define two distinct collections in `KjolHelper/main.swift`:
- `freezeDaemons`: Decoupled batch tasks (`mediaanalysisd`, `photoanalysisd`, `triald`, `analyticsd`, `parsecd`, `backupd`, `knowledge-agent`).
- `throttleDaemons`: Synchronous daemons (`mds`, `mdworker`, `mds_stores`, `corespotlightd`, `spotlightknowledged`, `managedcorespotlightd`, `suggestd`, `routined`, `siriknowledged`, `coreduetd`, `touristd`).

### Phase 2: Darwin Task Policy & Memory Eviction Engine
- When engaged:
  1. `mdutil -a -i off` to halt new index queue generation.
  2. `pkill -STOP -f` for `freezeDaemons`.
  3. Enumerate PIDs for `throttleDaemons` and apply `taskpolicy -b -t 3 -p <pid>` (Darwin background QoS + `IOPOL_THROTTLE`).
  4. Invoke `/usr/bin/purge` to flush file system buffers and purgeable memory.
- When disengaged:
  1. `pkill -CONT -f` for `freezeDaemons`.
  2. Enumerate PIDs for `throttleDaemons` and apply `taskpolicy -B -t 0 -p <pid>` to restore normal scheduling and I/O tier.
  3. `mdutil -a -i on` to re-enable Spotlight indexing.

### Phase 3: Configurable Safety Ceiling & Health Arbiter
- Expose `daemons_safety_ceiling_enabled` (default `true`) allowing users to choose between a 4-hour safety ceiling and Persistent Mode for overnight/multi-day runs.
- In Persistent Mode, the governor remains active across display sleep, screen lock, and password authentication.
- Implement mandatory Health Arbiter invariants in `checkDaemonFailsafe()`:
  - Critical battery ($\le 8\%$ on unplugged battery) automatically resumes daemons for safe sleep.
  - Extreme junction temperature ($\ge 105^\circ\text{C}$) auto-resumes daemons to prevent hardware damage.
- Report `daemons_safety_ceiling_enabled` and `daemons_failsafe_reason` in `hostStatusDict` to render context-aware status in the menu bar.
- Re-anchor the Governor toggle in the UI directly underneath the "Boost Memory" button in the unified Action Strip as a minimalist toggle switch (zero text beside it) for strict functional cohesion, accompanied by a non-occluding contextual tooltip.

