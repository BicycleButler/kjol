---
name: stubs-prune
description: Audit and prune phantom sidecars, untracked code files, zombie exports, and stale database records.
---

# Stubs Phantom Spec & Dead Code Pruning

Use `stubs prune` in CI pipelines and pre-release audits to maintain architectural hygiene and prevent dead code buildup.

## Commands

```bash
# Run full orphan and phantom spec audit
stubs prune

# Include zero-in-degree zombie export detection
stubs prune --zombies

# Output structured JSON for CI
stubs prune --json

# Automatically clean up stale database entries
stubs prune --fix
```

## Issue Types Detected

1. **`PHANTOM_SIDECAR`:** A sidecar specification whose `target_code_file` does not exist on disk.
2. **`UNTRACKED_CODE`:** A `.ts` implementation file missing a paired `.ts.md` specification.
3. **`ZOMBIE_EXPORT`:** An exported function or class with zero incoming import or call edges across the codebase.
4. **`STALE_DB_NODE`:** An indexed graph node referencing a deleted physical file.
