# ShoesERP Changelog

All notable changes to ShoesERP are documented in this file.

Format: [semantic version] — date — description
Most recent first.

---

## [3.8.2+71] — 2026-04-19 — Backup hardening + deprecation cleanup

### Added

- Dedicated admin backup and restore workflow with timestamp tracking for last successful backup and restore.
- Safe restore guardrails with admin-only restore pathways and explicit restore controls.
- Device delivery completed: latest release APK installed successfully on connected device `671f700b`.

### Changed

- Settings screen now routes admin users to dedicated backup and danger-zone screens instead of inline sections.
- Dependency upgrades finalized in app surface: `go_router` 17.2.1 and `font_awesome_flutter` 11.0.0.

### Fixed

- Removed deprecated API usage from app code paths; analyzer now reports zero deprecation warnings.
- Cleaned duplicate `3.8.0` entry in in-app changelog data.

### Audit

- Non-app repository deprecation audit completed: no deprecated API usage found in source scripts/docs; matches in `functions/package-lock.json` are third-party npm metadata warnings.

## [3.8.0+69] — 2026-04-18 — Multi-currency exhaustive audit

### Fixed

- **Zero hardcoded `.sar()` calls remain** — all `AppFormatters.sar()` sites across every screen replaced with `AppFormatters.currency(amount, currency)` (per-route) or `AppFormatters.compact(amount)` (cross-route aggregates). Files patched: `dashboard_screen.dart`, `reports_screen.dart`, `shop_detail_screen.dart`, `shops_list_screen.dart`, `invoice_detail_screen.dart`, `invoices_list_screen.dart`, `create_sale_invoice_screen.dart`.
- **PDF invoice currency** — `generateInvoicePdf()` no longer hardcodes `'﷼'`; the `currency` parameter is honoured and call sites pass `inv.currency` directly.
- **`create_sale_invoice_screen.dart` currency scope** — currency resolution moved from `build()` into `_buildBody()` so both the body and `_buildPaymentSummary()` can access it correctly (eliminated 6 undefined-identifier errors + 1 leading-underscore lint).

### Removed

- **`_MonthlyCashFlowChart`** from `reports_screen.dart` (already done, noted here for release).
- **`_BalanceTrendChart`** from `shop_detail_screen.dart` (already done).
- **`_CashFlowChart`** from `dashboard_screen.dart` (already done).
- **Unused `app_chart_card.dart` import** from `dashboard_screen.dart`.

### Added

- **`WhatsAppIconButton` widget** (`lib/widgets/whatsapp_button.dart`) — compact icon button that opens WhatsApp chat; hidden when phone is null/blank/invalid; uses `normalizeWhatsAppPhone()` for auto-formatting.
- **`normalizeWhatsAppPhone()` enhanced** — now converts Pakistan local (`03xxxxxxxx` → `923xxxxxxxx`) and Saudi local (`05xxxxxxxx` → `9665xxxxxxxx`) in addition to stripping non-digits.
- **WhatsApp CTAs on shop cards** — `shop_detail_screen.dart` and `route_detail_screen.dart` display `WhatsAppIconButton` next to shop phone numbers.

### Governance

- 0 `flutter analyze` issues (exit 0).
- 398/398 unit + widget tests pass.

## [3.7.20+68] — 2026-04-18 — Async-safety hardening

### Fixed

- **21 `.value`→`.future` async-safety fixes across 9 screen files** — all `ref.read(authUserProvider).value` calls in async/export contexts replaced with `await ref.read(authUserProvider.future)` to prevent null user during stream warm-up. Screens fixed: reports, shop detail, users list, inventory, create sale invoice, product form, variant form, route form, profile.
- **3 `.value`→`.future` fixes in 2 provider files** (done in prior sub-session) — `transaction_provider.dart` route/all transaction export providers, `shops_list_screen.dart` multi-shop PDF export.

### Removed

- **Dead code `app_message.dart`** — 0 imports, fully superseded by `snack_helper.dart`.

### Governance

- AGENTS.md Rule 25 (Vibe Debugging Discipline) + Known Failure Signature #4 (export/PDF null user)
- CLAUDE.md Vibe Debugging Anti-Patterns table + `.value` debt signal
- New skill: `vibe-debugging-discipline` (SKILL.md + GitHub instruction)

## [3.7.16+64] — 2025-07-15 — PDF text rendering and crash hardening

### Fixed

- **Arabic/Urdu text scattered in PDF and PNG exports** — `pw.TableHelper.fromTextArray` was missing `tableDirection: dir` on both `buildPdfTable` (all generic reports) and `buildPdfSellerReport` (seller report). Without this, data cells defaulted to LTR causing Arabic/Urdu characters to render as isolated (unjoined) glyphs. Both calls now pass `tableDirection: dir`.
- **PDF crash still occurring despite prior fix** — `pdfBytesBuilder` calls in `ExportSheet._buildPdfBytes()` were not wrapped in try/catch. Any exception from `buildPdfSellerReport` or `buildPdfLedger` propagated raw. Now wrapped with proper catch → rethrown as `'pdf export failed'` so `AppErrorMapper` maps it consistently and the actual error is logged via `debugPrint`.
- **Auth guard in export providers could return empty on stream cold-start** — All three export providers (`allUsersExportProvider`, `sellerTransactionsExportProvider`, `sellerInventoryExportProvider`) used `ref.read(authUserProvider).value` which is `null` while the autoDispose stream is loading. Changed to `await ref.read(authUserProvider.future)` so the guard waits for the first auth emission before proceeding.
- **Seller report PDF showing hardcoded company name** — `buildPdfSellerReport` was called without `companyName:` parameter, falling back to the default `'FOOTWEAR'`. Now passes `settings.companyName` so the PDF header reflects the configured company name.

---

## [3.7.5+53] — 2026-04-15 — Audit backlog implementation sweep

### Changed

- Auth and network stream providers now use `autoDispose` to reduce stale listeners while preserving the same public provider contracts.
- Export queries for shop, route, and global transaction exports are capped to `2000` documents per run to avoid unbounded bulk reads.
- Manual APK, CI, and release workflows are aligned on Flutter `3.41.6` with expanded Flutter test reporting; release validation timeout increased to 15 minutes.
- Firebase Hosting immutable cache rules now include `.wasm` assets.

### Fixed

- Route creation now rejects empty `created_by` values instead of silently writing invalid audit data.
- Shop creation now rejects null-or-blank route selections consistently.
- Inventory return dialog controller cleanup now happens reliably after the dialog closes.
- Shimmer placeholders no longer rely on hardcoded greys and now track the active theme.
- Offline indicator now uses the semantic error color instead of the stock color.

### Tests

- Added regression coverage for new model `copyWith` and equality behavior.
- Added ledger coverage for `payment` and `write_off` transaction types plus unknown-type failure behavior.

## [3.7.0+48] — 2026-04-13 — Audit v14: Navigation Overhaul + Governance Hardening

### Added

- WhatsApp-style double-back exit in AppShell (first back → toast, second within 2 s → exit)
- CI Gate 15: `StateProvider` banned — grep must return zero
- `.claude/skills/markdown-governance/SKILL.md` — full governance pack for markdown authoring
- `.github/instructions/markdown-governance.instructions.md` — enforced on all `.md` edits

### Changed

- All shell-hosted screen AppBars stripped; back gesture now works from every nav destination
- Detail screens (route, shop, product, invoice, inventory, shops-list) converted to inline action rows
- All 4 CI workflows standardized on Flutter `3.41.6` (build-apk.yml was last outlier at 3.29.2)
- `.markdownlint.json`: added `MD024 siblings_only`, disabled `MD056`
- AGENTS.md: Rules 19–22 added; §8 pre-commit checklist extended to Gate 8 (temp-artifact check)
- CLAUDE.md: Chain 6 (StateProvider lifecycle), Anti-Bypass Enforcement Matrix added
- README.md × 2 fully rewritten (v3.7.0+48 content, fat APK commands, all 21 routes)
- `.gitignore` extended: installer flags (`*.flag`), temp build outputs

### Fixed

- 30 lint issues: 15 × `unnecessary_underscores`, 3 × `use_null_aware_elements`, 1 × `prefer_const_constructors`, 8 × share_plus API deprecations
- 90 markdown lint issues across `CHANGELOG.md` and `SESSION_LOG.md` auto-fixed to zero
- Temp artifacts deleted from repo root: `auth-users.json`, `check_locale.ps1/py`, `debug.log`

### Upgraded

- `fl_chart` → 1.2.0, `share_plus` → 13.0.0, `permission_handler` → 12.0.1, `dart_jsonwebtoken` → 3.4.0, `flutter_lints` → 6.0.0

---

## [3.5.0+43] — 2026-04-11 — Audit v13: Governance Layer + CI Hardening

### Added

- `REGRESSION_REGISTRY.md` — 14 regression entries (RR-001 to RR-014) + 6 process improvements (PI-001 to PI-006)
- `SESSION_LOG.md` — chronological 8-session history reconstructed from git history
- `MASTER_BLUEPRINT.md` — living architecture handoff document
- `CHANGELOG.md` — this file — full version history v1.0.0 → v3.5.0
- `AUDIT_REPORT_FOOTWEAR_ERP.md` — final 88-agent audit synthesis with score matrix
- `.github/baselines/apk_size_kb.txt` — APK size baseline (75000 KB)
- CI Gates 7–10: no hardcoded Colors.*, version sync check, widget_test check, no Colors.black patterns

### Changed

- All 4 CI/CD workflows pinned to Flutter `3.29.2` (was: 3.22.x / 3.29.x drift)
- All 3 CI jobs now have `timeout-minutes` (20/30/10 minutes)
- Test job now runs with `--coverage`
- APK size gate added to release.yml hygiene job
- `Colors.white / grey / red / black54 / black.withAlpha(20)` in 6 screens replaced with `AppBrand.*` / `cs.*` constants (dark-mode safe)
- `widget_test.dart` placeholder replaced with real auth-flow smoke test + GoRouter absent check
- Version bumped to 3.5.0+43 in pubspec.yaml and app_brand.dart

### Fixed

- Dark mode color regression risk eliminated (RR-011)
- CI version drift eliminated (RR-012)
- CI placeholder test eliminated (RR-013)
- CI timeout absence eliminated (RR-014)

---

## [3.4.11+42] — 2026-04-11 — Audit v12: Spark Hardening + Ledger Correctness

### Changed

- Shops analytics listener capped at 500 docs (Spark quota protection)
- Shop-detail ledger listener capped at 150 docs
- Full-history account-statement export uses one-shot ordered query (not live listener)
- Running-balance reconstruction uses typed balance impact
- Return / payment / write-off entries no longer render as new debt in ledger
- Running-balance label localized in shop ledger UI
- Role-aware invoices migrated away from deprecated Riverpod `.stream`
- Raw async exception text replaced with mapped localized `ErrorState` across affected screens
- Invoice PDF totals labels and inactive badges localized
- Hardcoded route `R` prefix removed from touched shop flows
- Inventory long-press no longer routes to itself
- `tool/release.ps1` now PS 5.1 compatible (no `&&` chaining)

---

## [3.4.10+41] — 2026-04-11 — Audit v11: Shops Analytics Correction

### Fixed

- `I got` / `I gave` chips on shops screen now aggregate real `cash_in` / `cash_out` ledger entries
- `I will get` stays tied to current outstanding `shop.balance`
- Seller analytics read route-scoped transactions via dedicated `route_id + created_at` composite index

---

## [3.4.9+40] — 2026-04-11 — Audit v10: Invoice + Session + Navigation

### Added

- Seller edit-approval flow: sellers cannot re-submit while a prior request is pending
- Admin dashboard surfaces pending seller edit requests
- Composite index: `transactions(edit_request_pending, created_at desc)`
- Bottom-nav long-press quick actions for invoices and inventory

### Changed

- Invoice creation: preselected shop now uses one-shot auto-selection guard
- Invoice detail back-context routing to originating shop after creation
- In-shell navigation uses `context.go()` throughout
- Admin quick actions route to correct in-shell destinations
- Discount field clarified as absolute discount amount (not percentage)
- Account-statement PDF renders Debit left / Credit right with LTR amount cells in RTL locales
- Password minimum length raised to 8 chars (profile + admin/user-management paths)
- Approval-flow strings localized (EN/AR/UR)
- Validator min/max messages parameterized

### Fixed

- Android Kotlin incremental compilation disabled in `gradle.properties` (Windows cross-drive cache crash)

---

## [3.4.4+35] — 2026-04-09 — Audit v9: Write-Rate + Route Concurrency

### Fixed

- Admin user updates bypass write-rate throttle (route assignment edits no longer fail)
- Route/shop detail providers guard seller subscriptions client-side (no transient permission-denied)
- Route assignment create/update moved to Firestore transactions (concurrency-safe)
- Login password-reset lookup moved from screen to auth provider
- Account-statement export reads moved from screen to transaction provider
- Removed 8 unused defensive composite indexes

---

## [3.4.5+36] — 2026-04-10 — Wasm Dep-Lock Fix (Chain 5)

### Fixed

- `excel 4.0.6` locked `archive ^3.x` → blocked `image` upgrade past 4.3.0 (Wasm violation)
- Fixed: replaced `excel` with custom minimal xlsx writer (`app/lib/core/utils/excel_export.dart`)
- `archive` now at ^4.0.0, `image` at 4.8.0 (Wasm clean since 4.6.0)
- `flutter build web --release` Wasm dry-run reports "succeeded"
- PowerShell false-positive behavior documented in CLAUDE.md

---

## [3.4.0+30] — 2026-04-07 — Enterprise Audit v8: 20-Agent CI/CD System

### Added

- GitHub Actions: ci.yml (6 hygiene gates), build-apk.yml, release.yml, deploy-web.yml
- Session expiry UI: 7h30m warning dialog before 8h hard cutoff
- Band-Aid Loop Reversal protocol (AGENTS.md rule 17, instruction file, skill, custom agent)
- `_invalidateRoleScopedProviders()` in auth_provider.dart

### Security

- Seller transaction update rules restricted to `['description', 'updated_at']` only
- `allInvoicesProvider` and `adminAllSellerInventoryProvider` added to invalidation list (seller leak fix)
- `voidInvoice` admin-only guard added in rules + provider

### Changed

- AGENTS.md §4: Rules 17+18 added
- `updateTransactionNote()` provider method for seller annotation

---

## [3.3.0+21] — 2026-04-06 — Audit v7: Admin as Full Seller

### Added

- Admin can own `seller_inventory` docs (seller_id = adminUid)
- Transfer dialog shows admin as recipient option

### Fixed

- `product_provider.transferToSeller` audit log written to `inventory_transactions` (was `transactions`)
- Transfer type corrected to `transfer_out`
- Customer transaction visibility: client-side `deleted != true` filter on all providers
- `canHaveSellerInventory` getter always true (admin = god tier)

---

## [3.2.6+18] — 2026-04-06 — Audit v6: 62-Issue Synthesis

### Added

- `_lastGoodDashboardStatsProvider` cache (graceful resource-exhausted recovery)
- ProGuard rules for 8+ plugins; `isMinifyEnabled=true`, `isShrinkResources=true`
- L10n: 3 new keys × 3 languages (err_url_open, err_whatsapp_unavailable, whatsapp_greeting)
- Tests: 206 → 272 (sanitizer_test, error_mapper_test, create_sale_invoice_guard_test, mark_paid_outstanding_test)

### Security

- Seller admin data leak: `allInvoicesProvider` and `adminAllSellerInventoryProvider` guarded
- `voidInvoice` admin-only check in provider
- `isValidRole()` in Firestore rules
- Invoice math validation in rules
- Transaction type + amount validation in rules

### Fixed

- `createSaleInvoice` `amountReceived` guard
- `voidInvoice` atomic transaction
- `markAsPaid` outstanding fallback fix
- Android signing fallback removed (throws GradleException on missing keystore)

---

## [3.0.0+7] — 2026-03-30 — Enterprise Upgrade (22-section 6-phase plan)

### Added

- Design system: app_tokens, app_animations, app_sanitizer, input_formatters
- 14 widgets (6 upgraded + 8 new) with accessibility tooltips
- 5 list screens: search/filter/shimmer/pull-to-refresh/animations
- 7 forms: PopScope/dirty-check/sanitizer/haptic
- 5 detail screens: charts/badges/grouping
- Reports: monthly cash flow BarChart, outstanding PieChart
- PDF export: Isolate.run() for all 4 functions, sanitized interpolation (S-08)
- Session guard: AppLifecycleListener, 8h admin hard session limit (S-10)
- Base64 logo: 256×256 + flutter_image_compress + ≤50KB cap (S-07)
- Firestore rules: `docSizeOk()` <50KB, `withinWriteRate()` 1s cooldown
- L10n: 372+ keys × 3 languages with full parity
- 21 provider queries covered by 17+ composite indexes

### Removed

- Firebase Storage (zero-cost architecture — not available on Spark for writes)
- Cloud Functions dependency (user CRUD via secondary FirebaseApp)

### Changed

- Company logo stored as base64 in Firestore settings doc (≤50KB cap, 256×256 compressed)
- Product images use external HTTP URLs only
- Role normalization hardened: `trim().toLowerCase()` on all writes, regex in rules
- SnackBar system: Material 3 container-color card-style (19 screens converted)
- Dark mode QA: theme-aware colors throughout
- RTL QA: EdgeInsetsDirectional throughout
- Multi-device tested: Samsung A56 (Android 16/API 36), V2247 (Android 14/API 34)

---

## [1.0.0+1] — Initial baseline

- Core ERP: routes, shops, products, variants, inventory
- Basic invoicing, cash transactions
- Firebase Auth + Firestore
- Single admin role
