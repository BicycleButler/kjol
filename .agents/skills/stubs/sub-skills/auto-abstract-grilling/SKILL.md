---
name: auto-abstract-grilling
description: Autonomously iterate through abstract-grilling rounds by self-selecting recommended orthogonal paradigms, updating planning documents, implementing settled architecture in code, and cycling until scope completion or user stop.
---

# Autonomous Abstract Grilling & Implementation Primitive

## 1. Principles

1. **Design general and reusable abstractions:** Solve classes of problems rather than point solutions.
2. **Prefer deep modules:** Build narrow public interfaces that hide wide internal capabilities, state transitions, and storage mechanics.
3. **Explore orthogonal paradigms:** Formulate at least three distinct conceptual archetypes (such as Declarative Engine, Reactive Dataflow Pipeline, Autonomous State Machine, or Algebraic Core) for every architectural decision.
4. **Autonomous recommendation lock-in:** Evaluate each option against codebase evidence, abstraction depth, and falsifiers. Select the strongest option or hybrid synthesis automatically and advance to the next round without manual prompts.
5. **Keep scope discipline:** Restrict all grilling rounds, planning updates, and code changes to the initial scope from the user.

## 2. Autonomous Cycle Workflow

Each execution cycle runs five sequential stages within the user's defined scope:

### Stage 1: Natural-Language Scope Resolution & Frontier Derivation
1. Parse the user's natural-language `/auto-abstract-grill` prompt to identify the target domain, concepts, and loop mode.
2. Map the natural-language concepts to concrete modules and dependencies with `npx stubs query "<concept>"` and `npx stubs impact`.
3. Read existing planning documents in `knowledge/planning/`, ADRs in `knowledge/architecture/ADR/`, and relevant `*.md` sidecars.
4. Identify shallow wrappers, leaky interfaces, or unimplemented architectural boundaries in scope.
5. Derive a topologically ordered decision frontier (`Q1` through `QN`).

### Stage 2: Self-Answering Abstract Grilling Rounds
For each node `Q[N]` on the frontier:
1. Formulate three orthogonal paradigm options (`Option A`, `Option B`, `Option C`) with distinct mental models and public contract signatures.
2. Do the **Depth & Reusability Audit** (Interface-to-Depth Ratio, Three-Scenario Generalization Test, and Information Hiding Check).
3. State a concrete **Falsifier**.
4. Select the **Autonomous Selection** (best option or hybrid synthesis) and immediately advance to `Q[N+1]`, pruning all downstream questions absorbed by the deep module boundary.

### Stage 3: Planning Document Synchronization
Record the settled decisions before or during implementation:
1. Update or create the initiative plan in `knowledge/planning/`.
2. Record or update formal ADRs in `knowledge/architecture/ADR/` when core subsystem paradigms change.
3. Synchronize all in-scope module sidecar specs (`*.ts.md`).

### Stage 4: Code Implementation & Verification
1. Implement the settled deep modules and contracts in production code.
2. Run fast diagnostics (`npx omnibutler check <files>`).
3. Verify that `npm run typecheck`, `npm run lint`, `npx stubs scan`, and `npx stubs tale` pass with exit code `0`.

### Stage 5: Continuous Loop Evaluation (`--loop`)
When operating in continuous loop mode:
1. Emit a concise summary of the completed cycle (decisions locked, planning files updated, code files changed, and verification results).
2. Re-evaluate the initial scope against the updated codebase graph.
3. If additional in-scope architectural gaps, shallow boundaries, or planned items remain, immediately begin the next cycle (`Cycle C+1`).
4. Stop when all in-scope abstractions satisfy the depth and verification gates, or when the user stops execution.
