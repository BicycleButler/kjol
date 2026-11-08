---
name: stubs-changelog
description: Synthesize semantic architectural changelogs, ADR evolution logs, and contract drift reports from git history.
---

# Stubs Semantic Architectural Changelog

Use `stubs changelog` during pull requests, releases, and multi-agent milestones to document architectural evolution rather than simple line diffs.

## Commands

```bash
# Compare uncommitted working tree changes
stubs changelog

# Compare changes since a git tag or commit
stubs changelog --since v1.0.0
stubs changelog --since HEAD~5

# Compare an explicit commit range
stubs changelog --from main --to feat/new-engine

# Write changelog directly to markdown file
stubs changelog --output CHANGELOG.md

# Output machine-readable JSON for release automations
stubs changelog --json
```

## Changelog Sections

1. **Executive Summary:** Aggregated counts of modified specifications, ADR additions/modifications/removals, public contract additions/removals, and phase advances.
2. **Architectural Decisions (ADRs):** Itemized list of newly registered and modified ADRs.
3. **Public Contract & Signature Drift:** Exported symbols and function additions or deletions.
4. **Lifecycle Phase Transitions:** Status changes across the 5-phase lifecycle state machine.
