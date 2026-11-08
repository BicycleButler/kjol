---
name: stubs-context-mapping
description: Build, maintain, and audit hierarchical architectural context maps across a codebase, connecting the root context-map.md to domain-specific context maps in knowledge/architecture/domains/.
---

# Stubs Context Mapping Sub-Skill

This sub-skill guides agents and developers in systematically mapping an application's architecture, core domains, and implementation contracts.

## Structure & File Layout

A completed context mapping structure follows this hierarchy:

- `knowledge/`:
  - `architecture/`:
    - `context-map.md`: Central application-wide context map
    - `domains/`: Domain-specific deep dives
      - `{domain-a}-domain-map.md`: for example,. financial-domain-map.md
      - `{domain-b}-domain-map.md`: for example,. auth-domain-map.md
      - `{domain-c}-domain-map.md`: for example,. graph-domain-map.md

## 1. Root Context Map: `knowledge/architecture/context-map.md`

The root context map provides an immediate mental model of the entire system for AI agents and human engineers.

### Required Contents:
1. **OKF Frontmatter**:
   ```yaml
   ---
   title: Project Architecture Context Map
   type: context-map
   description: High-level architectural map of core domains, subsystem responsibilities, and data flows.
   tags:
     - architecture
     - context-map
   ---
   ```
2. **System Purpose & Core Abstractions**: High-level problem statement, design philosophy, and execution model.
3. **Domain Index & Routing Table**: A clear breakdown of all domains, summarizing:
   - Domain Name & Subsystem
   - Core Responsibilities
   - Clickable link to its domain map: `[domains/{domain}-domain-map.md]`
4. **Subsystem Flow / Interaction Diagram**: A high-level ASCII/Mermaid graph illustrating communication and dependency boundaries between domains.

## 2. Domain Context Maps: `knowledge/architecture/domains/{domain}-domain-map.md`

Each domain context map zooms in on a specific domain/subsystem.

### Required Contents:
1. **OKF Frontmatter**:
   ```yaml
   ---
   title: {Domain Name} — Domain Context Map
   type: domain-context-map
   domain: {domain-key}
   parent_map: ../context-map.md
   description: Deep-dive context map for {Domain Name} domain responsibilities, contracts, and source files.
   tags:
     - domain-map
     - {domain-key}
   ---
   ```
2. **Backlink**: Direct link back to the root context map `[../context-map.md]`.
3. **Domain Deep Dive & Invariants**:
   - Detailed domain logic, architectural boundaries, and design invariants that go beyond the brief summary in `context-map.md`.
4. **Key Files & Sidecars Table**:
   - A completed inventory linking directly to the source files (`*.ts`, `*.py`, and so on.) and sidecar specs (`*.ts.md`, `*.py.md`):
   ```markdown
   | File / Sidecar | Purpose & Exported Symbols | Depends On |
   | :--- | :--- | :--- |
   | [file:///absolute/path/or/relative/src/graph/engine.ts] | Core SQLite graph state manager (`GraphEngine`) | `schema.ts`, `better-sqlite3` |
   ```
5. **Key Types, Contracts & State**:
   - Core interfaces, database tables, or message protocols managed within this domain.
6. **Cross-Domain Dependencies**:
   - Explicit calls, events, or storage shared with other domains.

## 3. Agent Execution Steps

When tasked with generating or updating context maps for a repository:

1. **Discovery**:
   - Scan top-level source folders (for example,. `src/`, `packages/`, `lib/`, `services/`).
   - Identify distinct bounded contexts / subsystems (for example,., `auth`, `billing`, `graph`, `cli`, `server`).

2. **Scaffolding / Checking**:
   - Make sure that `knowledge/architecture/` and `knowledge/architecture/domains/` directories exist.
   - Run `node .agents/skills/stubs/dist/cli.cjs map --scaffold` (or manually create the skeleton if CLI is not yet built).

3. **Domain Deep Dives**:
   - For each identified domain, create/update `knowledge/architecture/domains/{domain}-domain-map.md`.
   - Make sure that each important source file and sidecar in that domain links to an explanation of its role.

4. **Aggregate to Root Context Map**:
   - Create/update `knowledge/architecture/context-map.md` summarizing the domain responsibilities and linking down to each `{domain}-domain-map.md`.

5. **Make sure that AGENTS.md Navigation**:
   - Verify `AGENTS.md` directs incoming agents to read `knowledge/architecture/context-map.md` as their primary navigational context map.
