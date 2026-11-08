---
name: stubs-context
description: Extract token-optimized, topologically bounded context packages and blast-radius impact analysis for AI agents.
---

# Stubs Context & Impact Primitives

When operating on complex repositories or dispatching subagent tasks, minimize prompt bloat and calculate breaking change risks using `stubs context` and `stubs impact`.

## Commands

```bash
# Generate token-optimized, tiered context package for an agent
stubs context <file_path> [--depth <N>] [--json] [--output <file>] [--no-code]

# Calculate blast-radius and regression risk for a target module
stubs impact <file_path> [--depth <N>] [--json] [--transitive] [--upstream]
```

## Tiered Context Slicing Invariants

1. **Tier 0 (Target Module):** Full sidecar spec (`.ts.md`) + full implementation source code (`.ts`).
2. **Tier 1 (Direct 1-Hop Dependencies):** Architectural Decisions (ADRs) + sidecar interface contract tables + distilled TypeScript AST signatures (functions/classes with bodies stripped, interfaces, types).
3. **Tier 1 (Direct 1-Hop Dependents):** Upstream callers and consumers, their lifecycle phase, and status flags.
4. **Tier 2 (Transitive 2-Hop Boundary):** Exported symbol names and high-level descriptions.

## Agent Workflow Integration

- **Before Modifying a Module:** Run `stubs impact <path>` to check whether changes break downstream callers or cross domain boundaries.
- **Before Subagent Dispatch:** Run `stubs context <path>` to extract a clean context package for the subagent prompt.
