# Frontend Skills Modernization Report

Review date: 2026-10-22

## Outcome

The frontend guidance now has one Copilot path-scoped UI contract and one
Claude-oriented orchestration skill. Existing navigation, form, performance,
testing, and export guidance was corrected and retained where useful. No
upstream skill text or runtime package was copied into the repository.

The app baseline is Flutter 3.41.6 / Dart 3.11.4 on branch `main`. Repository
customizations are discoverable through root `AGENTS.md` / `CLAUDE.md`,
`.claude/CLAUDE.md`, `.claude/skills/*/SKILL.md`, and path-targeted
`.github/instructions/*.instructions.md`.

## Instruction ecosystem and discoverability

| Surface | Status | Evidence and boundary |
| --- | --- | --- |
| `AGENTS.md` | Active repository contract | Defines runtime truth, route map, security/business constraints, and instruction hierarchy. |
| Root `CLAUDE.md` | Active coding guidance | Declares router source and project-specific implementation constraints. |
| `.claude/CLAUDE.md` | Claude helper/mirror | Links the runtime hierarchy and selected skills. |
| `.claude/skills/*/SKILL.md` | Claude-style specialist skills | Uses `name` and `description` frontmatter and repository-local procedures. |
| `.github/instructions/*.instructions.md` | Path-scoped Copilot guidance | Uses instruction frontmatter; the new frontend contract applies to Flutter UI files. |
| `.github/agents/` and `.github/skills/` | No frontend-specific customization found in the audit | Firestore-oriented customizations exist; do not create a duplicate frontend agent solely to increase file count. |
| Roo Code / Cline | No repo-local `.roo/`, `.clinerules/`, or `.cline/` files found | This is a repository scan only; it does not assert that other host-level configuration is absent. |
| `.github/copilot-instructions.md` | Not found in the audited customization scope | Copilot UI requirements are provided by path-targeted instructions and `AGENTS.md`. |

The repo does not guarantee that every third-party agent host loads Claude
skills. The path-scoped GitHub instruction and root runtime guidance provide
the cross-host entry points; no global host behavior is assumed.

## Audit rubric and pre-change scores

Scores are a qualitative 1–5 review, not a benchmark. Criteria were repository
and Flutter fit, factual accuracy, operational steps, accessibility/RTL/visual
coverage, and validation/boundary clarity. Evidence below identifies why each
item was changed or retained.

| ID | Existing guidance | Score | Verified deficiency or strength | Disposition |
| --- | --- | ---: | --- | --- |
| SKL-01 | `navigation-routing` | 1/5 | Duplicated a stale route catalog, included nonexistent `/customers` routes, and used an unverified redirect example. | Replaced with a repository-first procedure referencing the live router and shell. |
| SKL-02 | `flutter-navigation-ux` | 1/5 | Required a Zoom Drawer dependency, fixed breakpoints, fixed destination counts, and role lists without verifying the actual shell. | Replaced with adaptive, evidence-based guidance and no mandatory dependency. |
| SKL-03 | `ui-mobile-forms` | 2/5 | Recommended Nastaliq PDF rendering, conflating UI fonts with the PDF renderer; its edit example did not require visible loading/error handling. | Corrected the font contract and documented edit gating/retry and controller lifecycle. |
| SKL-04 | `navigation-forms.instructions.md` | 2/5 | Applied navigation-specific rules to every Dart library file and stated route-stack behavior too broadly. | Narrowed to router, shell, and screen code; made history decisions entrypoint-aware. |
| SKL-05 | `performance-optimization` | 1/5 | Asserted fixed listener counts/cost consequences, universal list thresholds, and an unverified “all forms” audit claim. | Replaced claims with measure-first, workload-specific guidance. |
| SKL-06 | `testing-strategy` | 3/5 | Useful Riverpod and widget examples, but lacked accessible-widget and rendered-UI acceptance guidance. | Added SDK-verified accessibility and visual-test expectations. |
| SKL-07 | `code-quality` | 3/5 | Useful cross-layer checks; its blanket literal-color warning could flag valid high-contrast text on a branded surface. | Clarified that semantic pairing/contrast, not the literal alone, determines correctness. |
| SKL-08 | `inline-audit` | 2/5 | Strong financial/Rules audit checks, but required release builds, deployment, commit, and push every session, conflicting with the root scope-aware authorization policy. | Kept domain checks; replaced the release mandate with scoped local validation and explicit authorization boundaries. |
| SKL-09 | `analytics-reporting` | 4/5 | Detailed PDF/XLSX/PNG/print/share governance; its role scope table omitted tenant admins and selected-workspace super-admins. | Retained export controls and corrected tenant-aware role scope. |
| SKL-10 | `markdown-governance` | 4/5 | Clear lint requirements and canonical document rules; not a UI design authority. | Retained as Markdown validation authority; referenced rather than duplicated. |

## Upstream research and adoption decisions

Research checked the named sources, cited files/pages, accessible license
metadata, and accessible commit dates on 2026-10-22. Popularity counters are
time-sensitive and were not treated as evidence of correctness or compatibility.

| Source | Verified relevance | License / recency evidence | Decision |
| --- | --- | --- | --- |
| [Flutter adaptive and responsive design](https://docs.flutter.dev/ui/adaptive-responsive) | Constraint-based adaptation; distinguishes responsive fitting from adaptive interaction/layout. | Current documentation states Flutter 3.47; adaptive guidance page updated 2026-05-05. | Primary design reference, but verify every API against this app's Flutter 3.41.6. |
| [Flutter accessibility](https://docs.flutter.dev/ui/accessibility) and [accessibility testing](https://docs.flutter.dev/ui/accessibility/accessibility-testing) | Semantics, screen-reader checks, text scaling, meaningful errors, touch targets, and automated guideline testing. | Current docs state Flutter 3.47; not a version-pinned contract for 3.41.6. | Adopt applicable principles and verify test API availability in the pinned SDK. |
| [Flutter UI guidance](https://docs.flutter.dev/ui) and [performance best practices](https://docs.flutter.dev/perf/best-practices) / [rendering performance](https://docs.flutter.dev/perf/rendering-performance) | UI composition, measured optimization, frame/raster analysis, rebuild and lazy-list guidance. | Official Flutter documentation; guidance is newer than the pinned app SDK. | Use as principles, not as proof of project behavior or API compatibility. |
| [Flutter widget testing](https://docs.flutter.dev/cookbook/testing/widget/introduction) | Widget layout and interaction testing; integration remains necessary for broader behavior. | Official Flutter documentation. | Use widget tests for deterministic states and rendered/manual checks for platform behavior. |
| [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | Testable web-content accessibility criteria. SC 1.4.3 uses 4.5:1 ordinary text and 3:1 large text; SC 2.5.8 defines a 24×24 CSS-pixel minimum target with exceptions. | W3C Document License; Recommendation. | Use as a relevant reference; do not call Flutter's 48×48 recommendation the WCAG AA minimum or claim blanket conformance. |
| [Anthropic frontend-design](https://github.com/anthropics/skills/tree/main/skills/frontend-design) | Product-grounded visual direction and avoiding generic design defaults; not Flutter implementation guidance. | Apache-2.0; reviewed skill file commit `41bbe19d` (2026-09-03). | Adopt the design-critique method in original project wording; do not copy the skill. |
| [Addy Osmani frontend UI engineering](https://github.com/addyosmani/agent-skills/tree/main/skills/frontend-ui-engineering) | Component and responsive thinking; examples are React/TypeScript/CSS/ARIA, and the reviewed accessibility text names WCAG 2.1. | MIT; reviewed skill file commit `3e1e0a2d` (2026-10-03). | Reference only; do not transplant web-specific breakpoints, DOM semantics, or code. |
| [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Multi-platform design/style data for ideation; no verified Flutter implementation contract in reviewed material. | MIT; relevant dataset changed 2026-08-13; repository activity visible through 2026-10-22. | Optional ideation reference only; not a source of project tokens or accessibility verdicts. |
| [Flutter Design Engineer](https://github.com/musabekisakov-imj/flutter-design-engineer) | Flutter-focused repository inspection, visual direction, state coverage, accessibility, golden/render review, and refinement. | MIT; cited design/accessibility skill files last accessible commit 2026-07-21. | Closest workflow match; adapt process only and verify the app's pinned SDK. |
| [Flutter Skills](https://github.com/zakariaf/Flutter-Skills) | Adaptive layout, accessibility, performance, and widget/golden testing. | MIT; accessibility material initially committed 2026-07-21 and README edited 2026-09-23. | Supplemental checklist only; its stack prescriptions do not replace this app's Riverpod/go_router architecture. |

Flutter's website repository identifies documentation as CC BY 3.0 except as
otherwise noted and code samples as BSD-licensed. No upstream content was
copied. No dependency was added. Flutter 3.41.5 release metadata maps to Dart
3.11.3; this repository's installed Flutter 3.41.6 / Dart 3.11.4 baseline was
verified separately.

## Follow-up upstream verification — 2026-10-24

| Source | Current material inspected | License / compatibility | Decision |
| --- | --- | --- | --- |
| [Flutter Agent Plugins](https://github.com/flutter/agent-plugins) | Repository README and widget-test and responsive-layout skills on `main` | Repository BSD 3-Clause; examples require checking against Flutter 3.41.6 | Use test-first interaction and constraint-based layout principles. Do not adopt generic layouts, fixed example breakpoints, or agent-specific metadata as project rules. |
| [Flutter App Skills](https://github.com/TheSimpleApp/flutter-app-skills) | README and custom-design-system/accessibility skills | MIT; guidance describes practices newer than the pinned Flutter 3.41.6 SDK | Use only compatible principles: inspect the existing system first and test semantics/reduced motion. Its advice to replace Material styling and require a custom Pressable conflicts with the current ShoesERP design contract and was not adopted. |
| [Flutter design taste landing page](https://flutterskills.md/) and [source repository](https://github.com/kamranbekirovyz/skills) | Current landing page and repository README; only `flutter-improve-design` is listed as available, while motion/theme/accessibility entries remain roadmap items | License file was not available at the checked root path; reuse permission was not established | Not copied or installed; treated as a discovery source only. |
| [Flutter animation documentation](https://docs.flutter.dev/ui/animations), [performance best practices](https://docs.flutter.dev/perf/best-practices), and [accessibility UI design](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling) | Official guidance on animation choices, rendering costs, text scaling, contrast, and touch targets | Current pages describe Flutter 3.47, newer than the app's 3.41.6; principles only, with APIs checked locally | Apply reduced-motion, constraints, accessibility, and measure-before-optimization principles without claiming newer SDK compatibility or profiling results. |

No upstream skill text, code, or dependency was copied into the repository.
License verification informed source selection only.

## Target architecture and ownership

| Responsibility | Owner |
| --- | --- |
| Cross-screen orchestration and safe completion | `.claude/skills/flutter-frontend-modernization/SKILL.md` |
| Theme/token/component/accessibility contract for Copilot and other path-aware hosts | `.github/instructions/frontend-design-system.instructions.md` |
| Visual token and shared component application | `.claude/skills/frontend-design-system/SKILL.md` |
| Full route/screen/state audit | `.claude/skills/frontend-ui-audit/SKILL.md` |
| Accessibility, localization, RTL, and text scaling | `.claude/skills/flutter-accessibility-rtl/SKILL.md` |
| Navigation and forms | Existing `navigation-routing`, `flutter-navigation-ux`, `ui-mobile-forms`, and scoped navigation instruction |
| Measured performance | Existing `performance-optimization` |
| Widget, accessibility, integration, and visual testing | Existing `testing-strategy` |
| PDF/XLSX/image/print/share reporting | Existing `analytics-reporting` |
| Runtime, roles, tenant boundaries, financial contracts, and release authorization | `AGENTS.md` and root `CLAUDE.md` |

Implementation ownership remains in the existing Flutter code: `AppTheme`,
`AppTokens`, `AppFonts`, `AppAnimations`, `app_router.dart`, `app_shell.dart`,
and shared widgets. Skills describe workflows; they do not create a second
runtime component system.

## Changes made

- Added a path-scoped frontend design-system instruction as the single UI
  standard for semantic styling, adaptive layout, accessibility, RTL,
  interaction, and performance claims.
- Added frontend orchestration, design-system, UI-audit, and accessibility/RTL
  skills with invocation, inputs, workflows, outputs, validation, and scope
  boundaries.
- Removed the stale `/customers` route catalog and fixed Zoom Drawer/fixed-nav
  prescriptions.
- Corrected the Urdu PDF font claim and added explicit edit-form loading/error
  expectations.
- Narrowed navigation instruction scope and made route history decisions
  entrypoint-specific.
- Removed unmeasured performance thresholds and corrected release-operation
  instructions to match `AGENTS.md` authorization rules.
- Added accessibility/visual-test expectations and tenant-aware reporting
  scope.
- Updated `AGENTS.md` route coverage and linked the authoritative UI standard
  from the runtime hierarchy and Claude guidance.
- Applied the shared UI contract to filter targets, reduced-motion-aware
  empty/error/status states and stat-card value transitions, and localized
  balance badge semantics.
- Extended reduced-motion handling to every shared `AppAnimations` preset and
  retained usable tap and semantic behavior when press scale is suppressed.
- Applied the same reduced-motion preference to both custom GoRouter page
  transition builders; focused route tests cover enabled and disabled fade
  and slide transitions.
- Fixed the narrow login form's invalid min/max width constraints at
  intermediate window widths; widget coverage exercises six widths in EN/AR/UR.
- Added a route/state register and prioritized UI/UX report distinguishing
  source findings from unperformed visual and role-flow checks.

## Validation and limitations

- Markdown lint after the instruction/skill updates exited 0 with no output.
- Phase A skills/doc changes are complete. Phase B has a tested shared
  component foundation; screen-specific findings remain tracked and are not
  represented as implemented.
- The signed-out login page was rendered in the local browser after fixing its
  intermediate-width crash. Authenticated business-screen review, Android
  device acceptance, and PDF/image viewer inspection were not performed.
- After the router motion follow-up, the full Flutter suite reported
  `01:01 +589: All tests passed!`; `flutter analyze lib --no-pub` reported
  `No issues found! (ran in 102.3s)` and `dart analyze test/` reported
  `No issues found!`. The debug APK attempt failed at
  `:app:mergeDebugJavaResource` with an insufficient-system-resources error.
- No release build, deployment, commit, or push was authorized or performed.
- External research did not run or certify the upstream skills' example
  applications against Flutter 3.41.6.
