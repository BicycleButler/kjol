---
name: stubs-lint
description: Perform zero-dependency architectural guardrail checks, layer hierarchy validation, and circular dependency detection.
---

# Stubs Architectural Guardrails & Layer Linter

Use `stubs lint-arch` in CI pipelines, pre-commit hooks, and multi-agent development cycles to enforce clean architectural boundaries with zero runtime bloat.

## CLI Usage

```bash
# Run complete architectural linting
stubs lint-arch

# Strict mode (warnings treated as blocking errors)
stubs lint-arch --strict

# Structured JSON output for CI pipelines
stubs lint-arch --json

# Filter to specific rules
stubs lint-arch --rule LAYER_VIOLATION,CIRCULAR_DEPENDENCY
```

## Architectural Invariants Checked

1. **Downward Layer Hierarchy (`LAYER_VIOLATION`):**
   - Layer 0 $\rightarrow$ Layer 1 $\rightarrow$ Layer 2 $\rightarrow$ Layer 3 $\rightarrow$ Layer 4 $\rightarrow$ Layer 5 $\rightarrow$ Layer 6.
   - Lower tiers can never import from higher tiers.
2. **Circular Dependency Prevention (`CIRCULAR_DEPENDENCY`):**
   - Asserts zero closed dependency loops using Tarjan SCC.
3. **Sidecar Manifest Parity (`UNMANIFESTED_DEPENDENCY`):**
   - Asserts all code imports in `.ts` files are documented in the sidecar's `depends_on` frontmatter.
4. **Domain Encapsulation (`DOMAIN_LEAK`):**
   - Flags cross-domain bypasses targeting internal private symbols.
