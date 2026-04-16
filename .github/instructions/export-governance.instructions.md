---
applyTo: "app/lib/screens/**/*.dart,app/lib/core/utils/pdf_export.dart,app/lib/core/utils/export_context.dart,app/lib/widgets/export_sheet.dart"
---

# Export Governance

## pdfBytesBuilder Mandate

Every `ExportSheet.show()` call that exports ledger, account statement, or
seller report data MUST provide `pdfBytesBuilder`. The generic `buildPdfTable()`
fallback is ONLY acceptable for simple flat tables (inventory list, shops list,
product catalog, routes list).

Builder selection:

| Data type | Builder |

| --- | --- |

| Single shop ledger / account statement | `buildPdfLedger()` |

| Multi-shop ledger (route-level) | `buildPdfMultiShopLedger()` |

| Seller performance report | `buildPdfSellerReport()` |

| Invoice document | `generateInvoicePdf()` |

| Simple flat table | `buildPdfTable()` (default OK) |

## NameResolver Mandate

All export paths MUST use `NameResolver` from `name_resolver.dart` to resolve
Firestore UIDs to display names. Never build ad-hoc `uid → name` maps. Never
fall back to a raw UID string. Fallback must be `trRead('unknown_user', locale)`
or `'—'`.

## I18n in Exports

All string literals in PDF/Excel/image exports MUST use `trRead()` with the
current locale. No hardcoded English. The `??` fallback in label maps must be
`'—'` or another localized key — never `'Opening Balance'` or similar English.

## Changelog Requirement

When `app/pubspec.yaml` version is bumped, a corresponding entry MUST be added
to `app/lib/core/data/changelog_data.dart` with trilingual (EN/AR/UR)
descriptions. The `whats_new_sheet.dart` auto-displays the latest changelog on
first launch after update.

## Grep Gates

```bash

# All ExportSheet.show() calls — audit each for pdfBytesBuilder

grep -rn "ExportSheet.show(" app/lib/ --include="*.dart"

# No raw UID fallback in exports

grep -rn "?? entry\[" app/lib/core/utils/pdf_export.dart

# NameResolver used in all export screens

grep -rn "NameResolver" app/lib/screens/ --include="*.dart"

```
