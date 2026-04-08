---
mode: agent
description: 20-agent autonomous ShoesERP audit. Launches 20 specialized subagents concurrently (via runSubagent), collects all findings, and synthesizes a severity-ranked risk register with closure matrix. Run this prompt to trigger a full codebase audit.
---

# ShoesERP 20-Agent Autonomous Audit

You are the **Orchestrator** for a comprehensive 20-agent parallel audit of the ShoesERP Flutter ERP application. Launch all 20 agents concurrently using `runSubagent`, wait for all results, then synthesize a closure matrix and severity-ranked risk register.

## Audit Context

This is a Flutter ERP for route-based shoe distribution.
- **Roles:** admin, seller (manager = admin-equivalent)
- **Collections:** users, products, product_variants, seller_inventory, inventory_transactions, routes, shops (Firestore: 'customers'), transactions, invoices, settings
- **Tech:** Flutter + Riverpod + Firestore + Firebase Auth (Spark free tier, zero Cloud Functions)
- **Key constraints:** Fat APK only, no Firebase Storage, admin = seller + admin

## Agent Roster (launch ALL concurrently)

Run all 20 agents simultaneously with `runSubagent`:

**Agent 1 — Role & Rules Alignment**
Audit: `app/lib/models/user_model.dart`, `firestore.rules`, `app/lib/core/constants/collections.dart`
Check: isAdmin/isSeller/managers coverage, role normalization, admin-as-seller rules path, manager alias

**Agent 2 — Firestore Rules**
Audit: `firestore.rules`
Check: deny-by-default, all collection rules, docSizeOk/withinWriteRate, seller inventory paths, soft-delete update rules, transaction field restrictions

**Agent 3 — Provider Architecture**
Audit: `app/lib/providers/` (all files)
Check: No direct Firestore writes in screens, _invalidateRoleScopedProviders completeness, AsyncValue error propagation, autoDispose patterns

**Agent 4 — Financial Integrity**
Audit: `app/lib/providers/invoice_provider.dart`, `app/lib/providers/transaction_provider.dart`, `app/lib/screens/create_sale_invoice_screen.dart`
Check: 3-pathway integrity (sale/cash/void), atomic batch writes, amountReceived bounds, total=subtotal-discount, no fake invoices for cash collection

**Agent 5 — Auth & Session Security**
Audit: `app/lib/core/services/admin_identity_service.dart`, `app/lib/core/services/session_guard.dart`, `app/lib/providers/auth_provider.dart`
Check: 3-step VERIFY_EMAIL flow, credential caching, cloud-platform scope, session expiry warning, _invalidateRoleScopedProviders completeness

**Agent 6 — OWASP Mobile Security**
Audit: All screen files, `firestore.rules`, `app/lib/core/services/`
Check: Input validation, injection prevention, insecure storage, auth bypass, excessive data exposure, admin-only screen defense-in-depth

**Agent 7 — Performance & Quota**
Audit: `app/lib/providers/`, `app/lib/screens/`, `app/lib/core/services/session_guard.dart`
Check: Listener count (Spark free limit), aggregate query volume, last-good-cache fallback, rebuild scope, dashboard graceful degradation

**Agent 8 — Android / Gradle Build**
Audit: `app/android/app/build.gradle.kts`, `app/android/gradle.properties`, `app/proguard-rules.pro`, `app/pubspec.yaml`
Check: Fat APK (no split-per-abi), signing config, ProGuard rules 8+ plugins, isMinifyEnabled, versionCode monotonic

**Agent 9 — Navigation & Routing**
Audit: `app/lib/core/router/app_router.dart`
Check: All required routes present (per AGENTS.md §2), role-based redirect guards, seller route constraints, admin-only screen protection

**Agent 10 — Inventory Management**
Audit: `app/lib/providers/product_provider.dart`, `app/lib/providers/seller_inventory_provider.dart`, `app/lib/screens/inventory_screen.dart`
Check: Dozen/pair unit consistency, quantity_available >= 0 guard, transfer audit log in inventory_transactions, admin self-stock allocation

**Agent 11 — Data Integrity & Soft Delete**
Audit: All providers + models
Check: DI-01 soft-delete pattern (`deleted != true`), toJson/fromJson round-trip, copyWith completeness, document size limits

**Agent 12 — User Management**
Audit: `app/lib/screens/users_list_screen.dart`, `app/lib/providers/user_provider.dart`, `app/lib/core/services/admin_identity_service.dart`
Check: 4-way auth pipeline, SA credentials provisioned, email verification 3-step, password reset, edit dialog email read-only

**Agent 13 — Composite Firestore Indexes**
Audit: `firestore.indexes.json`, all providers with Firestore queries
Check: Every where(A)+orderBy(B) (A != B) has composite index, no missing indexes for active provider queries

**Agent 14 — Firebase Free Tier**
Audit: All providers with Firestore reads, `app/lib/core/services/`
Check: Listener count within Spark limits, no aggregate overkill, no Firebase Storage usage, no Cloud Functions imports, base64 logo pattern

**Agent 15 — L10n Parity & Completeness**
Audit: `app/lib/core/l10n/app_locale.dart`
Check: All EN keys exist in AR and UR, tr() calls use valid keys, no hardcoded user-visible strings in screens

**Agent 16 — Documentation & Markdown Accuracy**  
Audit: `AGENTS.md`, `CLAUDE.md`, `README.md`, `app/README.md`, `SYSTEM_DEEP_DIVE_2026-03-27.md`
Check: Version number consistency, build commands accuracy (fat APK only), no split-per-abi in instructions, runtime contract alignment

**Agent 17 — GitHub Instructions + Prompts System**
Audit: `.github/instructions/`, `.github/prompts/`, `.claude/skills/`
Check: applyTo patterns correct, financial pathway rules documented, testing requirements present, code-quality gates defined

**Agent 18 — CI/CD & GitHub Actions**
Audit: `.github/workflows/`
Check: Workflow triggers correct, secret names match conventions, monotonic versionCode guard present, hygiene gates all 6 present, L10n parity gate, concurrency cancel-in-progress

**Agent 19 — Skill & Rule Completeness**
Audit: `.claude/skills/*/SKILL.md`, `.claude/CLAUDE.md`
Check: All 20 agents in multi-agent roster, breakage chains documented, auth pipeline failure playbooks present, testing strategy templates up-to-date

**Agent 20 — Synthesis & Orchestration (YOU)**
After all 19 agents report: synthesize findings into severity-ranked register (P0/P1/P2), produce closure matrix, write final consolidated report

## Synthesis Requirements (Agent 20)

After all agents complete, produce:

1. **Closure Matrix** (table: Issue ID | Domain | Severity | Status | Fix File | Effort)
2. **Top 10 by Severity** (P0 first, then P1)
3. **Already-Fixed Verification** (confirm P0-01, P0-02, P0-03 from prior audit are resolved)
4. **New Findings** (anything not in prior register)
5. **Recommended Action Order** (parallel-safe groups)

## Output Format

Save the consolidated report as a file in `/memories/session/` with today's date, named `Agent20-CONSOLIDATED-RISK-REGISTER-{date}.md`.
