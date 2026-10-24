---
name: performance-optimization
description: "Use when: profiling or reducing measured Flutter rebuild, frame, list, image, memory, or Firestore-listener cost in ShoesERP."
---

# ShoesERP Flutter Performance

## Purpose

Diagnose and improve a measured performance problem without changing tenant
scope, query meaning, financial integrity, or user-visible completeness.

## Invocation

Use when profiling jank, slow screens, large lists, memory growth, repeated
provider work, image decoding, or listener behavior. Do not invoke solely to
apply generic micro-optimizations.

## Required inputs

- A repeatable screen/workflow and target device or browser.
- Flutter/Dart versions and build mode.
- Baseline trace, metric, or reproducible observation when available.
- Relevant screen, provider, list, and image-loading implementation.

## Workflow

1. Reproduce and measure in the relevant environment. Use Flutter profile mode
   and DevTools for frame and raster behavior; do not infer release performance
   from debug-mode timings.
2. Locate the measured work in the widget/provider path. Compare rebuilds,
   query/listener activity, allocation, layout, image decode, and raster work
   as appropriate.
3. Change one evidence-backed cause at a time and keep observable behavior
   equivalent.
4. Prefer scoped `ref.watch`, stable child widgets, `const` values, lazy list
   builders, bounded image decoding, and correct controller/subscription
   disposal when the trace supports them.
5. Preserve pagination and full-history export requirements. A UI query limit
   must communicate truncation; never cap a complete export to improve a
   benchmark.
6. Re-measure the same scenario, compare before/after evidence, and run focused
   tests plus `flutter analyze lib --no-pub`.

## Safe principles

- A provider subscription does not, by itself, prove a particular network
  connection count, cost, or frame impact. Measure Firestore reads, active
  subscriptions, and cost separately.
- Do not impose universal thresholds such as a fixed number of listeners or
  list items without device- and workload-specific evidence.
- Choose `ListView.builder` or slivers for lazy construction when list size or
  profiling warrants it. Do not add `RepaintBoundary` indiscriminately.
- Apply `autoDispose` only after checking provider ownership, screen lifecycle,
  export awaits, and Riverpod 3 behavior.
- Keep expensive sorting, PDF/XLSX generation, and image work off the UI thread
  when the actual workload justifies it and the existing architecture supports
  safe background execution.
- Respect reduced-motion settings and avoid creating animation work that does
  not improve task feedback.
- Do not add a package, backend service, query, or cache without measuring its
  expected benefit and reviewing lifecycle and data-scope consequences.

## Output

State the baseline, measurement environment, diagnosed cause, change, before /
after evidence, behavior-preservation checks, and remaining uncertainty. If no
profile or device data is available, report that performance was not measured.

## Boundaries

This skill does not own feature design, authorization, data contracts, or
release authorization. Use the frontend standards in
`.github/instructions/frontend-design-system.instructions.md`; use the
analytics-reporting skill for export completeness and PDF behavior.
