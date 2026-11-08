---
name: abstract-grill
description: Stress-test high-level architecture, general abstractions, and deep modules using orthogonal conceptual paradigms and hybrid recommendations. Use when invoked via the /abstract-grill slash command or when designing reusable abstractions.
---

# /abstract-grill — Architectural & Abstract Grilling Skill

This skill stress-tests software architecture, general abstractions, and deep module boundaries. It guides an interview where each decision explores meaningfully different conceptual paradigms before settling on a recommendation.

## When to Use

- When the user invokes the `/abstract-grill` slash command.
- When designing high-level domain abstractions, system boundaries, and reusable primitives.
- When evaluating architectural initiatives in `knowledge/planning/` before writing concrete sidecars.
- For autonomous multi-round self-selection, planning updates, and code implementation loops, use [../auto-abstract-grill/SKILL.md].

## 1. Core Principles

1. **Design general and reusable abstract concepts:** Solve classes of problems, not point solutions.
2. **Deep modules with narrow interfaces and wide capabilities:** The interface must hide complex internal mechanics from the caller. Do not create shallow modules that leak internal state or procedural sequencing.
3. **The first idea is rarely the best idea:** Each presented option must be meaningfully different. Present distinct conceptual paradigms, not slight variations of the same idea.
4. **Flexible recommendations (single or hybrid):** Recommendations do not require a hybrid structure. Recommend a single option if it is superior. Recommend a hybrid if combined elements give the best result.
5. **Abstract plans must survive refactoring:** Frame systems around invariants and domain primitives rather than transient transport protocols or schema details.
6. **Information hiding:** It is not necessary for the caller to know internal sequencing, storage formats, or transient states.

## 2. Generate Meaningfully Different Options

When exploring an architectural decision, do not present minor variations or parameter tweaks. Present at least three orthogonal paradigm archetypes:

- **Archetype 1 — Declarative / Schema-Driven Engine:**
  The caller provides intent through a pure declaration or schema. An internal engine evaluates constraints, builds execution plans, and enforces invariants.
- **Archetype 2 — Reactive / Dataflow Pipeline:**
  The system processes data as a stream of unidirectional transforms through discrete stages. Invariants stay intact at transition boundaries.
- **Archetype 3 — Autonomous State Machine / Deep Runtime:**
  The system encapsulates mutable state inside an explicit finite state machine. Callers submit typed transitions. The state machine protects invariants and dispatches side effects.
- **Other Orthogonal Archetypes:**
  Other paradigms include Content-Addressable Storage, Algebraic Core, Security Broker, and Event Sourcing with Projections.

Do not present options that only differ by configuration flags or syntax. Each option must represent a distinct mental model and trade-off profile.

## 3. Test Abstractions (Depth & Reusability)

Evaluate every proposed abstraction against these filters:

### 3.1 Interface-to-Depth Ratio
Measure the interface surface area against the capability provided.
- **Narrow Interface:** Minimal methods, small parameter list, minimal public types.
- **Wide Capability:** Substantial automation, robust invariant protection, comprehensive edge-case handling.
- **Verdict:** Reject shallow wrappers where the caller does most of the cognitive work or step-by-step orchestration.

### 3.2 The Three-Scenario Generalization Test
Can the proposed abstraction solve three distinct, realistic use cases without changing its public contract?
- If the interface requires custom flags or specific methods for each new scenario, the abstraction is too narrow.
- If the abstraction is too generic to provide concrete leverage (an empty wrapper), the abstraction is too vague.

### 3.3 Information Hiding & Leaky Abstraction Audit
- Must the caller know the storage engine?
- Must the caller know the execution order of internal steps?
- If the underlying technology changes (for example, in-memory to SQLite, or sync to async), does the caller interface change?
- If the answer to these questions is yes, redesign the boundary to hide internal details.

## 4. Run the Abstract Grilling Interview

### 4.1 Guidelines for the Agent
- Ask questions **one at a time** using the `ask_question` tool.
- For each question, provide 3 orthogonal paradigm options.
- Provide a clear recommendation (single option or hybrid synthesis).
- Cite concrete technical reasons from the codebase or architecture, not personal taste.
- Include a concrete **falsifier** that states what condition would prove the choice wrong.

### 4.2 Question Format

```
**Q[N] — [Abstraction Domain / Decision Boundary]**: [One core architectural decision]

**Orthogonal Options:**

- **Option A ([Paradigm Archetype 1])**:
  [Concept description, public contract signature, and core trade-offs]
- **Option B ([Paradigm Archetype 2])**:
  [Concept description, public contract signature, and core trade-offs]
- **Option C ([Paradigm Archetype 3])**:
  [Concept description, public contract signature, and core trade-offs]

**Recommendation: [Option A | Option B | Option C | Hybrid Synthesis of Options]**
- **Rationale**: [Technical justification based on abstraction depth, reusability, and invariants]
- **Hybrid Details (if applicable)**: [Explain how elements from different options combine to maximize capability while preserving a narrow interface]

**Depth & Reusability Audit:**
- **Interface Surface**: [Why the public contract is narrow]
- **Encapsulated Capability**: [Why the internal implementation is wide]
- **Three-Scenario Fit**: [Briefly list 3 distinct scenarios this abstraction supports]

**Falsifier:** [The concrete fact, constraint, or scale threshold that would invalidate this recommendation]
```

## 5. Document the Settled Decisions

At the conclusion of the abstract grilling session, always ask the user how they wish to document the settled decisions. Offer these options based on session outcomes:

1. **Initiative Concept Plan (`knowledge/planning/` or `knowledge/planning/<domain>/`):**
   Record the architectural model, chosen paradigms, and interface contracts in the plan.
2. **Architecture Decision Record (`knowledge/architecture/ADR/`):**
   Record a formal ADR with context, decided paradigms, discarded alternatives, and consequences.
3. **Downstream Sidecar Specs (`*.ts.md`, `*.py.md`, and so on):**
   Record settled contracts, invariants, and decisions into downstream sidecar spec frontmatter (`decisions` and `user_notes`).

The user can choose one, two, or all three documentation targets depending on the scope of the architectural session.

## 6. CLI Command Reference

To run abstract grilling from the terminal or in headless CI:

```bash
npx stubs abstract-grill <file.md>
npx stubs abstract-grill knowledge/planning/payment-plan.md --depth deep_interrogation
npx stubs abstract-grill src/service.ts.md --non-interactive --output adr
```
