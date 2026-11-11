# AGENTS.md

Developer, Agent, and Contributor guide for building, testing, packaging, versioning, and releasing Kjol.

<!-- stubs-instructions-start -->
## Architecture Context Maps — Read First

Agent entry point: knowledge/architecture/context-map.md
Repo ADRs: knowledge/architecture/ADR/
Module specs: co-located `*.ts.md` sidecars in `src/`.

## Architecture Graph & GraphRAG Intelligence

AST dependency graph in `.stubs/graph.sqlite` with Louvain community detection, PageRank centrality, FTS5 BM25 hybrid search.

- Querying GraphRAG: `npx stubs query "<query>"` (preferred single call, 3-tier progressive disclosure):
  - `npx stubs query "map:"`: Level 0 Macro Map (subsystem communities, hubs, domains)
  - `npx stubs query "stub: <target>"`: Level 1 Interface Skeleton Stubs (stripped signatures, types, line links)
  - `npx stubs query "explain: <target>"`: Level 2 Symbol Profile (callers, callees, PageRank)
  - `npx stubs query "path: <A> to <B>"`: Level 2 Shortest dependency path chain
  - `npx stubs query "blast: <target>"`: Level 2 Downstream impact radius and dependents
  - `npx stubs query "pkg:<package> <query>"`: Monorepo package-scoped query
  - `npx stubs query "<concept>"`: Multi-hop token-budgeted GraphRAG context retrieval
- Model Context Protocol (MCP): connect through standard JSON-RPC 2.0 stdio:
  ```json
  {
    "mcpServers": {
      "stubs": {
        "command": "node",
        "args": [".agents/skills/stubs/dist/cli.cjs", "mcp"]
      }
    }
  }
  ```
  (or `"command": "npx", "args": ["stubs", "mcp"]`). Ultra-lean suite exposes `stubs_query` and `stubs_scan`.
- Monorepo & workspace boundary resolution:
  - Discovers package boundaries through `package.json` (`workspaces`), `pnpm-workspace.yaml`, `Cargo.toml` (`[workspace]`), `go.work`.
  - Path aliases in `tsconfig.json` (`compilerOptions.paths`) and package exports map directly to canonical source files.
  - Monorepo query prefix: `pkg:<package>` (for example, `npx stubs query "pkg:billing invoice"`).
- Automatic graph maintenance: auto-checks file mtime (<30ms) for 0% staleness. Refresh manually through `npx stubs scan`.

## CLI Commands

- Scan & Index Code Graph: `npx stubs scan`
- Query GraphRAG Subgraph: `npx stubs query "<question>"`
- Unified Surgical Query: `npx stubs query "explain: <target>"` | `path: <A> to <B>` | `blast: <target>`
- Concrete Spec Grilling: `npx stubs grill <file.md>`
- Abstract Architecture Grilling: `npx stubs abstract-grill <file.md>`
- Autonomous Abstract Grilling: `npx stubs auto-abstract-grill <file.md>` (or `/auto-abstract-grill`)
- Architecture Mapping: `npx stubs map --generate` (refreshes prerequisite domain maps + root context-map.md)
- Domain Maps Only: `npx stubs map --domains` | `npx stubs map --domain <name>`
- Export Knowledge Graph: `npx stubs export <obsidian|wiki> [--out <dir>]`
- Start MCP Stdio Server: `npx stubs mcp`
- Install Assistant Rules: `npx stubs hook install`
- Audit ASD-STE100 Compliance: `npx stubs tale`
- Auto-Remediate Prose & Formatting: `npx stubs tale --fix`
<!-- stubs-instructions-end -->

## Project Overview & Architecture

Kjol is a native macOS menu bar utility for Apple Silicon power management and hardware control. Root-level operations are delegated from the unprivileged user menu-bar app to a privileged helper tool through XPC.

```
Kjol.app (menu-bar, runs as user)
     XPC → com.lappier.kjol.helper (LaunchDaemon, runs as root)
                     pmset commands & caffeinate (always-on clamshell)
                     SMC hardware driver (fan control & charge limit)
                     pkill (daemon suspension)
                     mdutil (Spotlight control)
```

## Project Structure

```
kjol/
 build-kjol.sh          # Unified build and packaging script (generates Kjol.pkg)
 uninstall-kjol.sh      # Complete uninstaller script
 Kjol/
    main.swift            # Menu-bar UI (SwiftUI popover)
    Host.swift            # State coordinator & polling
    ViewModels.swift      # Telemetry, fan control & power view models
    XpcClient.swift       # Resilient XPC connection client
    HelperInstaller.swift # Diagnostic helper verification
    CpuSamplerService.swift # P/E Core CPU sampler
    Info.plist            # App bundle metadata
    helper.plist          # Helper LaunchDaemon plist
 KjolHelper/
    main.swift            # Privileged helper daemon (XPC server, root operations)
    SMC.swift             # Native AppleSMC IOKit driver & battery controls
    KjolHelperProtocol.swift # Shared XPC protocol definition
    Info.plist            # Helper metadata
 build/                    # Build output and packaging staging
```

## Building & Local Development

### Build Single-File Installer (`Kjol.pkg`)

```bash
./build-kjol.sh
```

### Direct Terminal Build & Install

Builds the application and privileged helper, stages the package, and installs/starts it locally:

```bash
./build-kjol.sh --install
```

### Uninstallation

Remove all installed components (`Kjol.app`, helper tool, launch daemon, and preferences):

```bash
./uninstall-kjol.sh
# or
./build-kjol.sh --uninstall
```

## Versioning & Publishing Releases

Kjol features in-app auto-updates driven by GitHub Releases (`Wiltermoodj/kjol`). When cutting a release:

1. **Bump Version in `Kjol/Info.plist`:**
   ```bash
   /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.1" Kjol/Info.plist
   /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.0.1" Kjol/Info.plist
   ```

2. **Rebuild Installer Package:**
   ```bash
   ./build-kjol.sh
   ```
   *(Automatically embeds the version from `Kjol/Info.plist` into `Kjol.pkg`)*

3. **Commit, Tag, and Push:**
   ```bash
   git commit -am "Bump version to v1.0.1"
   git tag v1.0.1
   git push origin main --tags
   ```

4. **Publish GitHub Release through `gh`:**
   ```bash
   gh release create v1.0.1 ./Kjol.pkg \
     --repo Wiltermoodj/kjol \
     --title "Kjol v1.0.1" \
     --notes "Description of changes, enhancements, or bug fixes."
   ```

## Technical Details

### Always-On (Lid Closed)
- Spawns `caffeinate -i -m` from the root helper daemon (avoids `-u` so internal display can sleep when the lid is closed).
- Monitors lid state via `IOPMrootDomain` and checks online display list; triggers `displaysleepnow` and dynamic 1-minute display sleep while the clamshell is shut.
- Configures power management through `pmset -a disablesleep 1 lowpowermode 0 powernap 0 sleep 0 displaysleep 10 disksleep 0 standby 0 hibernatemode 0 ttyskeepawake 1 lessbright 0`.
- Preserves always-on state across helper restarts and reboots until toggled off (restoring `pmset -a disablesleep 0` upon deactivation).

### Fan Control (AppleSMC)
- Direct SMC hardware manipulation through IOKit driver.
- Supports Auto, Quiet (25%), Cool (60%), Blast (100%), and Custom (0–100%) slider.
- M1/M5: direct mode writes. M2–M4: automatic `Ftst` unlock fallback. M5 lowercase `F%dmd` handled.
- Helper auto-recovers fan profile if system firmware resets SMC state on sleep/wake.
- Unprivileged reads for telemetry. Privileged writes through root helper.
