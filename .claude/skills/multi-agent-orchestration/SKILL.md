---
name: multi-agent-orchestration
description: "Use when: an audit or implementation has several independent workstreams that need separate context, coordinated evidence, or a synthesized result."
---

# Skill: Bounded Multi-Agent Coordination

## Purpose

Coordinate only the independent work that benefits from separate context. The
available agent types and tools depend on the current runtime; do not assume a
fixed agent count, a `runSubagent` API, or that a requested specialist exists.

## When to Delegate

- Handle a single continuous trace directly, even when it crosses multiple
  files or subsystems.
- Handle reviews, audits, and summaries directly when their total evidence fits
  in one focused read.
- Delegate only substantial, independent questions with bounded file scope and
  a clear stop condition.
- Prefer a matching user-provided custom agent. Otherwise choose the smallest
  suitable available agent type.
- Do not spawn an agent merely to re-check direct work, rediscover files, or
  produce speculative findings.

## Coordination Procedure

1. Read current project instructions and inspect the worktree before splitting
   work.
2. Define each independent task with its exact scope, relevant evidence, and
   required output format.
3. Run independent tasks in parallel only when they have no shared edit
   targets. Keep file edits with one owner.
4. Await required results before relying on them. If the requested agent or
   invocation tool is unavailable, report that limitation and use a direct
   bounded alternative.
5. Reconcile overlaps against source, tests, and current project contracts.
   Do not turn an unverified report into a confirmed finding.
6. Run targeted validation on the combined implementation.

## Audit Output

For each finding report:

| Field | Content |
|---|---|
| ID | Stable short identifier |
| Severity | Critical, high, medium, low, or informational |
| Evidence | File, lines, and observed behavior |
| Confidence | 1–10, grounded in evidence quality |
| Status | Open, fixed locally, verified in emulator, or deployed |
| Recommendation | Minimal next step |

Separate verified findings from hypotheses and note unreviewed scope. Do not
claim the whole repository was covered when only a subset was read.

## Safety and Completion

- Never deploy, alter production data, create a release, commit, or push unless
  the user explicitly authorizes that operation.
- For Firestore Rules work, validate locally with the repository's emulator
  suite before any separately authorized deployment.
- Preserve pre-existing worktree changes; never revert unrelated changes.
- Do not use a synthetic agent roster or claim nonexistent agent results.
- Keep requested deliverables in their requested format and location. Do not
  create a redundant report file when an existing canonical report is suitable.
