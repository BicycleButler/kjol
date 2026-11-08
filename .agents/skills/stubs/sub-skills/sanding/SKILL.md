---
name: stubs-sanding
description: Reconcile code-to-spec or spec-to-code drift using AST hashes and diffing.
---

# Stubs Sanding Sub-Skill

Execute bidirectional code-to-spec synchronization whenever `.ts` code or `.ts.md` sidecars are manually edited.

## Execution Rules
1. Run `node .agents/skills/stubs/dist/cli.cjs sand <path>` to check drift state.
2. If reverse sanding is indicated: extract modified AST from source code. Update sidecar YAML and set `clean`.
3. If forward sanding (`spec-to-code`) is indicated: extract code from `.ts.md` and overwrite `.ts`.
4. On 3-way conflicts, present a visual AST diff to the user before applying changes.
