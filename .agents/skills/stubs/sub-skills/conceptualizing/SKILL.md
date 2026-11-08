---
name: stubs-conceptualizing
description: Conceptualize architectural initiatives, problem framing, and planned filetree blueprints for the Stubs 5-Phase Lifecycle.
---

# Stubs Conceptualizing & Planning Primitive

The first phase of the Stubs 5-Phase Lifecycle (`Conceptualize` -> `Grill` -> `Spec/Scaffold` -> `Materialize` -> `Sand & Audit`).

## Core Rules

1. **Problem Framing & Domain Boundaries:**
   - Frame the domain scope, primary goals, invariants, and trade-offs before authoring code.
   - Create centralized initiatives in `knowledge/planning/<initiative>-plan.md` or domain concepts in `src/<domain>/concept.md`.
2. **File Tree Blueprint Declaration:**
   - Always declare the planned directory and file structure using a standard ````filetree```` markdown code block.
   - Annotate planned files with comments describing actions (`# [NEW]`, `# [MODIFY]`, `# [DELETE]`).
3. **Scaffold Early:**
   - Run `stubs concept scaffold <docPath>` to automatically instantiate directories, stub source files, and skeleton OKF sidecar specs (`*.ts.md`).
4. **Track Tasks Deterministically:**
   - Use standard markdown checklists (`- [ ]` / `- [x]`) inside initiative plans.
   - GraphEngine automatically extracts, indexes, and surfaces task completion metrics in the Planning Hub.
5. **Phase Gating:**
   - Run `stubs phase check <docPath>` to verify gating criteria before moving to the `Grill` phase.
