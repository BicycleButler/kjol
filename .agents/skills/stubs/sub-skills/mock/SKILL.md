---
name: stubs-mock
description: Scaffold spec-driven test suites and typed mocks directly from sidecar specifications and AST signatures.
---

# Stubs Spec-Driven Test & Mock Scaffolder

Use `stubs mock` during the `spec` phase to enforce Test-Driven Development (TDD) before materializing executable code.

## Commands

```bash
# Preview generated test file in stdout (dry-run)
stubs mock src/service.ts.md --dry-run

# Scaffold test file to tests/<module>.test.ts
stubs mock src/service.ts.md

# Custom output destination and framework
stubs mock src/service.ts.md --output tests/unit/custom.test.ts --framework vitest

# Overwrite existing test file
stubs mock src/service.ts.md --force
```

## Generated Artifact Features

1. **Automated Imports:** Computes POSIX relative paths from the test folder to target implementation modules.
2. **ADR Invariant Test Cases:** Scaffolds test cases for each Architectural Decision in the sidecar specification.
3. **Symbol Structure:** Generates `describe()` blocks for each exported class, interface, and function with assertion templates.
