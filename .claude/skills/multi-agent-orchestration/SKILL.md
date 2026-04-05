---
name: multi-agent-orchestration
description: "Use when: coordinating multiple expert agents for a comprehensive audit, structuring parallel analysis tasks, synthesizing findings from 15+ concurrent agents, generating master audit reports."
---

# Skill: Multi-Agent Orchestration for ShoesERP Audits

## Purpose
Deploy 15+ specialized expert agents concurrently to audit the ShoesERP repository.
Each agent reads the FULL source, applies domain expertise, and reports findings.
The Orchestrator (Agent 13+) cross-references and synthesizes the final report.

## Agent Roster Template (Minimum 15 Agents)

### Agents 01-05: Core Architecture
| Agent | Domain | Focus Files |
|-------|--------|-------------|
| 01 | Flutter Architecture & Code Quality | lib/**/*.dart, analysis_options.yaml |
| 02 | Firestore Security Rules & Permissions | firestore.rules, security-owasp-mobile skill |
| 03 | CA/ERP Financial Controls | invoice_provider.dart, transaction_provider.dart |
| 04 | Riverpod State Management & Lifecycle | providers/*.dart, app.dart |
| 05 | Testing Strategist & Coverage | test/**, pubspec.yaml |

### Agents 06-10: Security & Platform
| Agent | Domain | Focus Files |
|-------|--------|-------------|
| 06 | Authentication & App Security | auth_provider.dart, login_screen.dart |
| 07 | Performance, Memory & Cost | dashboard_provider.dart, all StreamProviders |
| 08 | APK Breaking Changes & Signing | android/**, build.gradle.kts, AGENTS.md |
| 09 | Internationalization & PDF | l10n/**, pdf_export.dart, assets/fonts/ |
| 10 | Android Build & CI/CD | gradle files, proguard-rules.pro |

### Agents 11-15: Data & Features
| Agent | Domain | Focus Files |
|-------|--------|-------------|
| 11 | Data Integrity & Ledger Analyst | invoice_provider, customer_provider, batch writes |
| 12 | Missing-Feature Detective | screens/**, AGENTS.md route map |
| 13 | Navigation & UX Expert | app_shell.dart, app_router.dart |
| 14 | Free-Tier Firebase Compliance | pubspec.yaml, firestore.rules, all providers |
| 15 | Orchestrator & Cross-Reference | ALL files, synthesizes all findings |

## Audit Workflow

### Phase 1: Parallel Deep Read (All agents simultaneously)
Each agent reads their assigned files and identifies:
- CRITICAL issues (data loss, security breach, financial error potential)
- HIGH severity (user-facing bugs, performance degradation)
- MEDIUM severity (code quality, missing tests, UX issues)
- LOW severity (style, docs, naming)
- MISSING features vs AGENTS.md contract

### Phase 2: Cross-Reference
Agent 15 collates findings and:
- Identifies overlapping issues found by multiple agents (higher confidence)
- Resolves conflicts between agents
- Assigns final severity ratings
- Groups by theme: Security | Financial | Performance | UX | Testing | Infrastructure

### Phase 3: Synthesis Report
Format: atomic, exhaustive `.txt` master audit report with:
- Executive Summary
- Critical Findings (must fix before next release)
- Per-Domain Findings (each agent's report)
- Issue Register (numbered, with file:line references where possible)
- Remediation Roadmap (priority-ordered action items)
- Compliance Matrix (AGENTS.md contract vs actual state)

## Issue Template
```
ISSUE-NNN | SEVERITY | DOMAIN | AGENT
File: app/lib/...
Description: What is wrong and why it matters
Evidence: Code snippet or behavior that demonstrates the issue
Risk: What could go wrong (financial, security, UX, performance)
Fix: Specific remediation steps with code example
Effort: S/M/L (Small < 1h, Medium 1-4h, Large > 4h)
```

## TDD Enforcement (from Superpowers framework)
For every new feature identified as missing:
1. Write failing test first
2. Implement minimum code to pass
3. Refactor and green
4. Document in skills if pattern is reusable

## Anti-Drift Rules (prevent "every prompt breaks everything")
1. All changes MUST run `flutter analyze lib --no-pub` → zero issues before merge
2. All changes MUST run `flutter test -r expanded` → all tests green before merge
3. Schema changes MUST update `fromJson()` defaults + add corresponding model test
4. Navigation changes MUST update navigation-routing SKILL.md
5. Rules changes MUST be deployed: `firebase deploy --only firestore:rules,firestore:indexes`
6. Never change multiple systems simultaneously (one logical unit per change)
7. If a change breaks a test, fix the test root cause — NEVER delete or skip tests

## Conflict Resolution Protocol
When two agents disagree on severity or fix approach:
- Agent 15 (Orchestrator) rules
- Default to MORE conservative (higher severity) finding
- Document both perspectives in report
- Recommend A/B if genuinely ambiguous

## Documentation Sync Rule
Any finding that identifies architecture behavior changes MUST also update:
- AGENTS.md
- CLAUDE.md
- README.md
- app/README.md
- SYSTEM_DEEP_DIVE_2026-03-27.md
(or create new SYSTEM_DEEP_DIVE_YYYY-MM-DD.md for major audits)
