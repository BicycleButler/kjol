# ADR-005: Tiered Compute Governor & Memory Reclamation Architecture

## Context
Kjol provides a "Pause Background Daemons" quick action to minimize power consumption and CPU wakeups. Previously, this feature executed a blunt `pkill -STOP -f` against a flat list of 18 hardcoded daemon names alongside `/usr/bin/mdutil -a -i off`.

While effective at reducing CPU cycles to 0% for those specific processes, this design introduced four critical operational problems when the goal is to free maximum compute and memory for active user tasks:
1. **IPC Deadlocks & UI Beachballs:** Processes such as `mds` and `corespotlightd` service synchronous Mach port and XPC requests from user applications (for example, standard `NSOpenPanel` file dialogs, QuickLook, and text autocompletion). Suspending them through `SIGSTOP` causes frontmost apps to block indefinitely awaiting Mach message replies, creating spinning wait cursors (beachballs).
2. **Zero Memory Reclamation:** `SIGSTOP` freezes threads in execution, but all dirty memory pages, ARC allocations, and unified memory buffers remain locked in RAM. Active compilers (Clang, Swift), IDEs, Docker, and ML inference models receive zero freed memory.
3. **P-Core against E-Core Scheduling Agnosticism:** Apple Silicon features asymmetric Performance (P) and Efficiency (E) cores. The OS scheduler can run background tasks strictly on E-cores without degrading P-core responsiveness for user tasks. Hard freezing processes that could safely run on E-cores is an unnecessary operational risk.
4. **Blind Supervision:** A static 4-hour countdown timer was used as a failsafe, lacking awareness of Mach port queue depth, frontmost app wait-states, or system power transitions (sleep/wake).

## Decision

We adopt a **Tiered Compute Governor and Memory Reclamation Architecture** behind Kjol's background suppression engine.

### 1. Dual-Tier Execution Suppression Model
Instead of blanket `SIGSTOP`, processes are classified into distinct execution tiers:
- **Tier 1 (Hard Freeze through `SIGSTOP`):** Purely decoupled, asynchronous batch-processing daemons that never handle synchronous user-facing IPC.
  - Targets: `mediaanalysisd`, `photoanalysisd`, `triald`, `analyticsd`, `parsecd`, `backupd`, `knowledge-agent`.
- **Tier 2 (Darwin QoS Demotion & E-Core Clamping):** Synchronous and IPC-coupled daemons that must remain responsive to prevent application hangs, but must consume 0% P-core compute and minimum I/O bandwidth.
  - Targets: `mds`, `mdworker`, `mds_stores`, `corespotlightd`, `spotlightknowledged`, `managedcorespotlightd`, `suggestd`, `routined`, `siriknowledged`, `coreduetd`, `touristd`.
  - Mechanism: Applied through Darwin kernel task policy (`taskpolicy -b -t 3 -p <pid>` and POSIX `setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG)`). This confines their execution strictly to E-cores, applies `IOPOL_THROTTLE` to disk I/O, and causes the Darwin scheduler to instantly yield whenever any user thread requests execution.
- **Tier 3 (Exempt / Protected):** Critical daemons (`launchd`, `windowserver`, `diskarbitrationd`, `securityd`, `kjol.helper`) are strictly quarantined and never altered.

### 2. Active Memory Reclamation Pipeline
To actively return physical RAM to the user's running tasks:
1. **Purgeable Buffer & Disk Cache Eviction:** On engagement, KjolHelper invokes `/usr/bin/purge` to flush system-wide disk cache, invalidate inactive memory buffers, and reclaim purgeable allocations.
2. **VM Inactive Compaction:** Demoting Tier 2 daemons to Darwin background priority signals the Mach VM compressor that their dirty pages are eligible for immediate memory compression and page-out under moderate pressure.

### 3. IPC Health Supervision, Configurable Ceiling & Persistent Mode
1. **Configurable Operating Horizon:** Users can toggle between the default **4-Hour Safety Limit** (which auto-resumes indexing after 4h to prevent backlog) and **Persistent Mode** (for overnight, multi-day compute, training, or long compilation tasks).
2. **Session & Lock-Screen Invariance:** The governor does not disengage when the display sleeps, the screen locks, or when the user must enter their password. Compute remains strictly maximized for the running task.
3. **Mandatory Health Arbiter Invariants:** In Persistent Mode, the governor only disengages when strictly required for machine health:
   - *Critical Battery Depletion:* If running unplugged on battery and charge drops to $\le 8\%$, the governor auto-resumes daemons to make sure that the system can do safe sleep / state preservation without unexpected power cut.
   - *Thermal Runaway:* If SoC/CPU/GPU junction temperature reaches extreme safety thresholds ($\ge 105^\circ\text{C}$), the governor automatically yields to prioritize thermal safety and prevent permanent hardware degradation.

## Consequences

### Positive
- **Zero UI Beachballs:** Active apps never hang when opening file choosers, searching recent files, or interacting with Spotlight-backed frameworks.
- **Dedicated P-Core Availability:** 100% of P-core execution time and L2 cache bandwidth is reserved for active user applications.
- **Gigabytes of Immediate RAM Recovery:** Physical RAM is freed immediately through `/usr/bin/purge` rather than leaving dirty pages dormant in frozen memory.
- **Refactor-Resilient Interface:** The user-facing UI and XPC contract remain a single toggle (`suspendDaemons(_ on: Bool)`), hiding the multi-tier orchestration entirely inside the privileged helper.

### Negative / Trade-offs
- Setting Darwin background priority requires PID enumeration for active Tier 2 processes.
- Memory purging incurs a minor one-time disk read penalty if the user immediately re-reads a previously cached inactive file from disk.

