---
name: stubs-grilling
description: Stress-test software designs and sidecar specs using frontier-based dependency tree rounds.
---

# Stubs Grilling Primitive

## 1. Principles

1. Design an abstract capability such as a role resolution service. Do not design concrete endpoints
   such as profile CRUD routes. Abstract plans survive a refactor.
2. Check whether existing structures already solve the problem before you add a schema or a setting.
3. Prefer one module with a narrow interface and a wide capability. Do not split it into shallow
   modules. Describe the contract, not the internal steps.
4. Test each proposal against three filters. The proposal must match the user goals. The proposal must
   match what the code provides, measured on disk. The proposal must follow patterns that other
   systems proved.
5. Measure claims against the file system, not against documents. Every count has a date. Re-measure
   before you use a count.
6. Trace data flow through a critical path. Do not read modules in isolation. One function can hide the
   entire gap between the plan and the code.

## 2. Derive the tree

Do not start from a fixed category list. Interfaces, context objects, error handling, and ADRs are
node types, not required sections.

1. Find the source of intent. Use the concept doc, the sidecar, or the ADR set. Name which one.
2. Trace the data flow through the critical path. Name the inputs, the transforms, the storage
   boundary, and the outputs.
3. Emit one decision per node. Use these node types as a vocabulary: boundary, contract, lifecycle,
   error model, tenancy, data ownership, phase gate, ADR.
4. Record the dependencies between nodes. The frontier holds each node with no open dependency.

## 3. Test each node before you ask

### 3.1 Answer facts yourself

If the codebase answers the question, read the codebase. Use the CLI, read files, query the graph, and
count on disk. Never ask the user a question that a search answers.

### 3.2 Require two real answers

A question with one defensible answer is not a decision. Decide it, store the reason, and continue.

### 3.3 Treat code conflict as normal

When the code conflicts with the node, the code is usually out of date. That is the reason for the
grill. The code describes what exists. It does not describe what must exist. If the code can overrule
the node, a flawed module can confirm a flawed design.

Do not ask for a reproduced fault first. That rule selects the wrong case. Sound code that implements
the wrong intent shows no fault, so the rule marks it as sound, and sound code then supports the
wrong design.

Ask one question instead. Does a person already decide this? Search the ADR set and the decisions
section. A matching decision settles the node. A differing decision forces one question. No decision
means the node stands.

### 3.4 Store each decision when you settle it

While storing is optional, a later run cannot know what is already decided. Record the decision at the
moment of settling, not at the end of the project.

## 4. Run the round

### 4.1 Use this form for each question

```
 **Q[N] — [node path]**: [one decision]

**Options**
A. … then this result
B. … then this result
C. … then this result

️ **Recommended: A** — [reason from the codebase or a rule, not from taste]

**Falsifier:** [the fact that would show this choice is wrong]
```

Ask about one decision at a time. Split a question that carries two. Give each node options with
different results. Give each node a reason that cites the codebase or a rule.

### 4.2 Set the effort by reach

Most of this decision is measurement, not judgment. Measure the node fan-out and the blast radius
with `stubs blast` and `stubs impact`.

Give a node the full effort when its fan-out or blast radius is high. A low effort on a wide node
removes the falsifier from the riskiest decision.

For each other node, and where a class is unclear, give the node the higher effort. State the class in
the question. A high effort on a narrow node costs one slow question.

Use the depth flag as an effort control. Each flag sets the effort level.

- `light_probe` limits the grill to narrow nodes.
- `standard_drill` uses the classes above.
- `deep_interrogation` gives each node the full effort.

### 4.3 Close the round correctly

- Ask each node on the frontier in one round. Do not ask a node at a time.
- Do not ask a node that lacks a part of the form in 4.1.
- After the answers, list the settled nodes, the nodes that a new answer reopened, and the new
  frontier.
- Stop when each node is settled or dropped. If principle 4 or principle 6 would still apply, say so
  and stop. Do not invent depth.

## 5. Store the result

- `## Open questions` holds each node with no answer, with its options and its recommendation.
- `## Decisions (locked)` holds each settled decision with its reason, its lost options, and its date.
  State the condition that would reopen it. Where no system is in production and a change can break
  freely, a locked decision is deferred rather than final.
- `## Grilling audit` holds each lookup: the command, the result, and the date. This record stops a
  later run from asking a settled fact again.
- `## Grilling & Discussion` holds the round text in one section. Each later run replaces the section.
  The CLI appends instead, because it computes `body + qaLog`, so it adds a new section on each run.

Set `status: grilling` to `spec` in the frontmatter. Keep `user_notes[].status` a top-level field.
