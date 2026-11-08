---
name: stubs-materialization
description: Extract implementation blocks from sidecar specs into runnable TypeScript files using in-memory compilation.
---

# Stubs Materialization Sub-Skill

## Execution Rules
1. Validate that the target `*.ts.md` sidecar has `status_flag: clean` and zero pending `user_notes`.
2. Invoke `node .agents/skills/stubs/dist/cli.cjs materialize <path> [flags]`.
3. Respect flags: `--target=types` (`.d.ts`), `--target=stubs` (placeholder throws), or `--target=full`.
4. Make sure that the output `.ts` file includes the injected `@sidecar` header banner.
