---
name: auto-abstract-grill
description: Autonomously execute the abstract-grilling decision loop, select recommended architectural paradigms at each round, update planning documents, implement the settled architecture in code, and verify. Supports single-pass or continuous autonomous loop until scope exhaustion or user stop.
---

# /auto-abstract-grill — Autonomous Architectural Grilling & Implementation Loop

This skill runs the abstract grilling process without waiting for manual answers. At each round, the agent generates orthogonal paradigm options and selects its recommended synthesis. It records the decision in planning documents, implements the architecture in code, and runs verification. When continuous loop mode is active, the agent does this cycle again across remaining architectural gaps within the initial scope. The loop stops when all in-scope abstractions pass depth, reusability, and verification audits.

## 1. Natural-Language Slash Command Invocation

Users invoke `/auto-abstract-grill` directly in chat and describe the scope and loop preference in plain natural language. Never require flags, key-value labels, or rigid templates.

### Example Chat Invocations

- `/auto-abstract-grill rethink how we handle parked carts and inventory reservations in pos`
- `/auto-abstract-grill clean up the auth session verification boundaries and keep looping until done`
- `/auto-abstract-grill review the contracts package and cycle through grilling and implementing until I stop you`

### Intent & Scope Resolution

1. **Extract Natural-Language Scope:** Parse the user's conversational prompt to identify the target concepts, features, packages, or problem areas. If exact paths are omitted, run `npx stubs query "<concept>"` or `npx omnibutler query "<concept>"` to find matching modules.
2. **Detect Execution Mode from Prose:**
   - **Single-Cycle Mode (Default):** Run one full pass of autonomous abstract grilling across the decision frontier for the target scope. Update planning documents, implement the architecture in code, and verify.
   - **Continuous Loop Mode:** Activate automatically when the user's prompt includes phrases such as "keep going", "loop", "cycle until stopped", "until done", or `--loop`. Each iteration finds the next architectural gap in scope, grills it, implements the design, and verifies until stopped.

### Scope Guardrail

Every round and every loop iteration must remain bounded to the domain resolved from the user's initial natural-language description. Do not expand into unrelated packages, repositories, or out-of-scope features.

## 2. Core Principles

1. **General and Reusable Abstractions:** Design abstract concepts that solve classes of problems rather than point solutions.
2. **Deep Modules:** Prefer narrow interfaces with wide internal capabilities. Hide internal state, storage mechanics, and procedural sequencing from callers.
3. **Orthogonal Exploration:** Present at least three distinct conceptual paradigms for each decision node before selecting a recommendation.
4. **Autonomous Self-Selection:** Evaluate the trade-offs, depth audit, and falsifier for each round. Lock in the strongest recommendation (single option or hybrid synthesis) and advance immediately to the next round.
5. **Refactor-Resilient Boundaries:** Frame systems around domain invariants and ownership boundaries rather than transient transport or schema details.
6. **Evidence-Driven Grounding:** Measure claims against the codebase and AST dependency graph (`npx stubs query`, `npx stubs impact`) before formulating options.

## 3. Phase 1: Scope Discovery & Decision Frontier Derivation

Before starting Round 1 of each cycle:

1. **Inspect Scope:** Query the AST graph (`npx stubs query "explain: <target>"`, `npx stubs query "blast: <target>"`) and read relevant planning documents (`knowledge/planning/`, `knowledge/architecture/ADR/`, or co-located `*.md` sidecars).
2. **Identify Shallow Modules:** Locate leaky abstractions, chatty interfaces, duplicated orchestration, or unresolved boundaries within the user's scope.
3. **Build the Decision Frontier:** Derive an ordered list of core architectural decisions (`Q1`, `Q2`, ..., `QN`) where dependencies are resolved top-down.
4. **Check Stopping Condition:** In continuous loop mode, examine all modules within the initial scope. If all modules satisfy the depth, generalization, and information-hiding audits with zero verification errors, stop and report completion.

## 4. Phase 2: Autonomous Abstract Grilling Rounds

Iterate through each decision node `Q[N]` on the frontier without pausing for user input. Emit the deliberation record for each round using this exact structure:

```markdown
**Q[N] — [Abstraction Domain / Decision Boundary]**: [One core architectural decision]

**Orthogonal Options:**

- **Option A ([Paradigm Archetype 1 — e.g., Declarative / Schema-Driven Engine])**:
  [Concept description, public contract signature, and core trade-offs]
- **Option B ([Paradigm Archetype 2 — e.g., Reactive / Dataflow Pipeline])**:
  [Concept description, public contract signature, and core trade-offs]
- **Option C ([Paradigm Archetype 3 — e.g., Autonomous State Machine / Deep Runtime])**:
  [Concept description, public contract signature, and core trade-offs]

**Autonomous Selection: [Option A | Option B | Option C | Hybrid Synthesis of Options]**
- **Rationale**: [Technical justification grounded in codebase metrics, abstraction depth, reusability, and invariants]
- **Hybrid Details (if applicable)**: [How elements from multiple archetypes combine behind a narrow interface]

**Depth & Reusability Audit:**
- **Interface Surface**: [Why the public contract is narrow]
- **Encapsulated Capability**: [Why the internal implementation is wide]
- **Three-Scenario Fit**: [3 distinct, realistic scenarios this abstraction solves without contract changes]
- **Information Hiding Check**: [Confirmation that storage engine, step order, and transient states do not leak]

**Falsifier:** [Concrete fact, constraint, or threshold that would invalidate this choice]
```

### Round Transition Rules

1. After locking in the **Autonomous Selection** for `Q[N]`, immediately evaluate how that decision constrains or simplifies downstream nodes (`Q[N+1]`).
2. Prune redundant downstream questions that the settled deep module now encapsulates automatically.
3. Continue until all decision nodes for the current cycle are settled.

## 5. Phase 3: Planning Document & ADR Synchronization

Before or alongside code changes, persist the settled architectural decisions into the repository's planning records:

1. **Initiative Concept Plan (`knowledge/planning/`):** Create or update the plan with the domain model, chosen paradigms, contracts, and decisions.
2. **Architecture Decision Record (`knowledge/architecture/ADR/`):** When a cycle changes a subsystem paradigm, record or update the ADR with context and falsifiers.
3. **Module Sidecars (`*.ts.md`):** Where co-located sidecars exist or are part of the scope, update their frontmatter (`decisions`, `status: spec`) and contract sections.

## 6. Phase 4: Autonomous Code Implementation & Verification

Translate the settled architecture directly into production code within the target scope:

1. **Pre-Flight & Blast Check:** Run `npx omnibutler blast "<target>"` (or `npx stubs impact <file>`) before modifying shared exports or high-fan-out modules.
2. **Implement Deep Modules:** Write or refactor the production code to enforce the narrow public contract and encapsulate internal complexity. Obey all compiler and linter standards (zero `any`, zero non-null assertions, zero diagnostic suppressions).
3. **Fast Diagnostics:** Run `npx omnibutler check <modified-files>` after edits for immediate compiler and linter feedback.
4. **Full Cycle Verification:** Run the verification suite before concluding the cycle:
   - `npm run typecheck`
   - `npm run lint`
   - `npx stubs scan`
   - `npx stubs tale` (auto-remediate with `npx stubs tale --fix` if needed)

## 7. Phase 5: Continuous Loop Progression (`--loop`)

When the user requests continuous cycling (for example, "cycle through the autonomous grilling and implementation loop until stopped" or `--loop`):

1. **Cycle Summary:** Output a concise cycle report listing:
   - Cycle number and scoped target addressed.
   - Decisions locked (`Q1`..`QN`) and chosen paradigm syntheses.
   - Planning documents updated and code files modified.
   - Verification status (`typecheck`, `lint`, `stubs scan`, `tale`).
2. **Re-Scan & Re-Evaluate Scope:** Re-examine the initial scope against the updated AST graph (`.stubs/graph.sqlite`) and planning backlog:
   - Examine whether implementation or testing triggered a falsifier.
   - Identify the next unaddressed module, leaky boundary, or remaining task item within the initial scope.
3. **Advance or Terminate:**
   - **Continue:** If valid architectural work remains within the initial scope, start **Cycle `C+1`** at Phase 1 automatically.
   - **Terminate:** Stop the loop when:
     - Every module and requirement within the initial scope satisfies all depth, reusability, and verification checks (Scope Exhaustion).
     - A blocking external constraint or unresolvable falsifier requires human clarification.
     - The user stops or interrupts execution.
