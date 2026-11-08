---
title: "<%= title %>"
type: concept-doc
description: "<%= description || 'Conceptual architecture and domain specification.' %>"
tags:
  - concept
  - domain
  - architecture
phase: conceptualize
status: spec
version: 1
status_flag: clean
<% if (typeof initiative !== 'undefined' && initiative) { %>initiative: <%= initiative %>
<% } %>---

# <%= title %>

## Problem Framing & Domain Scope
<%= typeof problem_statement !== 'undefined' && problem_statement ? problem_statement : 'Describe the core problem domain and functional scope.' %>

## Architectural Concepts & Domain Model
<%= typeof architecture_overview !== 'undefined' && architecture_overview ? architecture_overview : 'Detail the domain entities, relationships, and invariants.' %>

## Planned File Tree Blueprint
```filetree
<%= typeof filetree !== 'undefined' && filetree ? filetree : 'src/\n  domain/\n    core.ts.md # [NEW] Core domain sidecar specification' %>
```

## Decisions & Alternatives Considered
- **ADR-001:** Initial design rationale.
