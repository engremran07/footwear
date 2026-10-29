---
name: analytics-reporting
description: "Use when: building analytics dashboards, adding export features, generating per-route/per-shop/per-seller reports, integrating ExportSheet, adding filter dropdowns, or implementing consolidated report generation."
---

# Skill: Analytics & Reporting for ShoesERP

## Purpose

Generate production-quality reports from Firestore data using ExportSheet, PDF
export, and role-aware data scoping. Support per-route, per-seller, per-shop
and consolidated all-data reporting.

## Invocation and required inputs

Use for report data selection, PDF/XLSX/image generation, printing, sharing,
export localization, and RTL font/rendering issues. Read the relevant screen,
provider, export builder, `ExportContext`, and focused tests. Confirm user role,
tenant/workspace context, locale, currency, and the exact report data shape
before changing a report.

## Architecture

### Data Flow

```text
Provider (StreamProvider) → Screen (ConsumerStatefulWidget) → ExportSheet.show()
                                                               ↓
                                                    buildPdfTable() / pdfBytesBuilder
                                                               ↓
                                                    Isolate.run() → PDF bytes

```

### Report Scoping

| Role | Scope |

|------|-------|

| Local admin / manager | Authorized records in the active tenant |
| Tenant admin | Authorized records in the assigned active tenant |
| Super admin | No business records without an explicitly selected, audited active workspace |
| Seller | Assigned route and own permitted transactions |

### Export Formats

- XLSX (Excel) — `exportToExcel()`

- PDF — `buildPdfTable()` + custom `pdfBytesBuilder`

- PNG (Image) — rasterized from the same generated PDF bytes

- Print — system dialog

- Share — via `SharePlus`

## ExportSheet API

```dart

ExportSheet.show(
  context, ref,
  title: tr('shops_report', ref),
  headers: ['Name', 'Route', 'Phone', 'Balance'],
  rows: shops.map((s) => [s.name, s.routeNumber, s.phone, s.balance]).toList(),
  fileName: 'shops_report',
  subtitle: 'Route 5 — Generated ${DateTime.now()}',
  pdfBytesBuilder: () => buildPdfTable(...), // REQUIRED for ledger data — see rule 10
);

```

### pdfBytesBuilder Requirement

`ExportSheet.show()` accepts an optional `pdfBytesBuilder` callback. When
omitted, the sheet falls back to `buildPdfTable()` which renders a simple
header+rows flat table. **This fallback is ONLY acceptable for simple flat
tables** (inventory list, shops list, product catalog).

For any export that contains:

- Running balances

- Debit/credit columns

- Entry By column

- Date-grouped rows

- Summary/totals row

…the caller MUST supply a `pdfBytesBuilder` that calls the appropriate
specialized builder:

| Data type | Builder function |

| --- | --- |

| Single shop ledger / account statement | `buildPdfLedger()` |

| Multi-shop ledger (route-level) | `buildPdfMultiShopLedger()` |

| Seller performance report | `buildPdfSellerReport()` |

| Invoice document | `generateInvoicePdf()` |

| Simple flat table | `buildPdfTable()` (default fallback OK) |

### ExportSheet.show() Call Site Audit

Every `ExportSheet.show()` call in the codebase must be audited against the
table above. Grep gate:

```bash

grep -rn "ExportSheet.show(" app/lib/ --include="*.dart"

```

Known call sites and their pdfBytesBuilder status:

| File | Export | pdfBytesBuilder |

| --- | --- | --- |

| `shop_detail_screen.dart` | Account statement | ✅ `buildPdfLedger` |

| `reports_screen.dart` | Account statement | ✅ `buildPdfLedger` |

| `reports_screen.dart` | Seller report | ✅ `buildPdfSellerReport` |

| `shops_list_screen.dart` | Shops list | ❌ flat table OK |

| `shops_list_screen.dart` | Multi-shop ledger | ✅ `buildPdfMultiShopLedger` |

| `reports_screen.dart` | Shops list | ❌ flat table OK |

| `reports_screen.dart` | Product catalog | ❌ flat table OK |

| `reports_screen.dart` | Inventory report | ❌ flat table OK |

| `reports_screen.dart` | Routes list | ❌ flat table OK |

| `inventory_screen.dart` | Inventory list | ❌ flat table OK |

## Per-Route Report Pattern

```dart

// Group shops by routeId, generate one report per route
final routes = ref.read(routesProvider).valueOrNull ?? [];
for (final route in routes) {
  final routeShops = allShops.where((s) => s.routeId == route.id).toList();
  // Build per-route export data
}

```

## Dropdown Filter Pattern

```dart

// Route dropdown for admin filtering
DropdownButton<String?>(
  value: _selectedRouteId,
  items: [
    DropdownMenuItem(value: null, child: Text(tr('all_routes', ref))),
    ...routes.map((r) => DropdownMenuItem(
      value: r.id,
      child: Text('${r.routeNumber} · ${r.name}'),
    )),
  ],
  onChanged: (v) => setState(() => _selectedRouteId = v),
)

```

## L10n Keys Required

- `filter_by_route` — "Filter by Route"

- `all_routes` — "All Routes"

- `export_report` — "Export Report"

- `export_all_shops` — "Export All Shops"

- `export_per_route` — "Export Per Route"

- `route_report` — "Route Report"

- `generating_report` — "Generating report..."

## Name Resolution (Single Source of Truth)

All export paths MUST use `NameResolver` from
`app/lib/core/utils/name_resolver.dart` to resolve user UIDs to display names.
Never build ad-hoc `entryByMap` maps. Never fall back to a raw Firestore UID.

```dart

import '../core/utils/name_resolver.dart';

final names = NameResolver(
  users: allUsers,
  extra: {if (user != null) user.id: user.displayName},
  unknownLabel: trRead('unknown_user', locale),
);

// Pass to PDF/Excel builders:
entryByMap: names.map,

```

`ExportContext` (`app/lib/core/utils/export_context.dart`) carries the
`NameResolver`, locale, company branding, and pre-resolved labels as a single
object. Use it when building new export paths.

## Export I18n Keys

All string literals in export output (PDF, Excel, images) MUST use localized
keys from `app_locale.dart`. Key export-specific keys:

| Key | EN | AR | UR |

| --- | --- | --- | --- |

| `page_x_of_y` | Page %1 of %2 | صفحة %1 من %2 | صفحہ %1 از %2 |

| `others` | Others | أخرى | دیگر |

| `excel_generated` | Generated | تم الإنشاء | بنایا گیا |

| `unknown_user` | Unknown | غير معروف | نامعلوم |

## Arabic and Urdu Font Contract

All PDF builders load fonts through `_ensureFontBytes()` in
`app/lib/core/utils/pdf_export.dart`. Every Flutter test, run, or build that
can generate PDFs MUST pass `--dart-define=use_arabic=true`. Without that
compile-time option, the `pdf` package can reorder RTL text but does not shape
Arabic-script letters. The central loader fails closed with a typed,
localized configuration error instead of returning a malformed report.

PDFs embed Noto Sans Arabic for Arabic and Urdu, with the PDF package's Arabic
shaping enabled. Urdu output is Naskh-style, not Nastaliq: the current PDF
renderer does not support Nastaliq's complex OpenType GSUB/GPOS shaping. The
Flutter UI uses Noto Nastaliq Urdu independently. Do not call the PDF output
Nastaliq or install a reshaping dependency without first verifying Dart/PDF
version compatibility, Web support, and mixed-direction behavior.

`ExportSheet` builds one PDF byte sequence for PDF share, printing, and PNG
page rasterization. Keep these paths unified so layout and embedded fonts
cannot drift. XLSX preserves Unicode and sets RTL sheet direction, but fonts
are chosen by the spreadsheet application and are not embedded; document this
limitation rather than promising identical appearance in every viewer.

Regression checks:

- With `use_arabic=true`, verify generated report PDFs include the
  `NotoSansArabic` font resource, embedded `/FontFile2` program, and
  Arabic/Urdu-specific text fixtures.
- Without the define, verify shared PDF generation fails with
  `PdfExportConfigurationException` and that `ExportSheet` preserves it for
  localized error mapping.
- Verify XLSX XML retains Urdu/Arabic text and `rightToLeft="1"`.
- The current PNG unit tests inject a rasterizer; they verify shared-byte
  routing, not pixel-level font appearance. Do not claim browser/device
  visual validation unless it was actually performed.
- A screenshot/JPEG does not retain font metadata. To identify the actual
  embedded family, inspect the original PDF's font resources; use screenshots
  only for visual comparison.

### PDF Layout and Rendering Regressions

When a user reports that a PDF looks broken, do not treat an embedded font
assertion as proof that the rendered page is correct. Trace the complete
screen → provider/settings → builder → PDF layout/font path, and reproduce the
reported document type, language pair, current/snapshotted branding, logo
visibility, and representative long values.

For shared financial documents:

- Keep one shared workspace brand header for invoices, receipts, statements,
  and reports. Place English content on the left, the consistently sized
  company logo in the center, and selected Arabic or Urdu content on the
  right. Every builder, including the flat-table fallback, must use this same
  placement and size; set text direction explicitly for each side and pin
  physical row order with
  `pw.Directionality(textDirection: pw.TextDirection.ltr)` when a page-level
  RTL direction could reverse children. `pw.Row` in pinned `pdf` 3.13.1
  does not accept a `textDirection` argument.
- Prefer current workspace logo bytes when available, but preserve a saved
  invoice logo when the current-header path has no usable logo bytes. Respect
  the explicit `visibleFields` logo setting.
- For half-sheet cash receipts, verify the generated PDF page is A5-sized and
  remains exactly one page with bounded receipt identifiers/references. Keep
  balance calculations and ledger writes outside the presentation change.
- Assert page count, media-box dimensions, image resources, font embedding,
  shaping configuration, and Arabic plus Urdu-specific text in focused tests.
  If rendering tools are available, rasterize the generated PDF and inspect
  English-left/RTL-right placement and connected glyphs in the actual output.
- If pixel-level rendering is unavailable, state that limitation explicitly;
  do not claim visual acceptance based only on source review, Unicode input,
  or a font-resource assertion.

  For RTL financial tables, verify physical columns in the rendered PDF, not
  only the extracted text or successful PDF generation. In `pdf` 3.13.1, the
  page-level RTL direction can reverse `pw.Row`/table children. Wrap table
  headers, data rows, summary blocks, and final-balance rows in explicit LTR
  directionality when the intended physical order is English-left and
  amount/balance-right; give each Arabic/Urdu text widget its own RTL direction.
  Keep amount direction explicit as well.
  English-first mixed-script values must be shaped through
  `pdfTextForDirection` before LTR layout. Test medial Arabic and Urdu Yeh,
  and avoid changing the paragraph to RTL merely because Arabic/Urdu occurs
  later in the value.

  Statement-specific density changes must preserve the shared workspace
  header and financial calculations. Centralized logo placement and sizing
  apply across all financial PDFs, including receipts. Place the entry count
  in the final-page footer and tune table padding only with rendered multi-row
  and paginated samples. Treat statement and receipt references as separate
  artifacts.
  Before making a receipt layout claim, confirm and inspect an actual receipt
  image. The available 2026-10-24 cash-receipt reference includes a compact
  three-row Total/Advance/Balance summary, receipt number/date, bilingual
  payer/amount/payment/account lines, signature area, and footer phone numbers.
  Reproduce the body while passing the configured workspace header unchanged;
  keep optional extra contacts in the receipt footer and preserve A5,
  single-page output.

Do not switch fonts, add a shaping dependency, or add a workaround until the
actual PDF output and renderer compatibility establish that font selection or
shaping is the culprit. Separate a confirmed font defect from a layout or
direction defect and record the evidence for each.

An isolated `payv` Nastaliq proof is not release evidence for the existing
document pipeline. Before replacing the renderer, verify Web and Android
compatibility, workspace-logo embedding, pagination, selectable/searchable
text, and output parity for invoices, receipts, statements, seller reports,
multi-shop reports, and flat tables. Until all gates pass, production Urdu PDF
output remains Naskh-style and must not be described as Nastaliq.

Open-source references reviewed 2026-10-22 (star counts are a point-in-time
signal, not endorsement; do not copy skill text):

- [anthropics/skills PDF](https://github.com/anthropics/skills/tree/main/skills/pdf)
  and [XLSX](https://github.com/anthropics/skills/tree/main/skills/xlsx)
  (about 183k stars): format-specific document workflows.
- [github/awesome-copilot](https://github.com/github/awesome-copilot)
  (about 40k stars): VS Code/Copilot customization patterns.
- [obra/superpowers TDD](https://github.com/obra/superpowers/tree/main/skills/test-driven-development)
  (about 304k stars): relevant test discipline, not font shaping.

## Rules

1. All exports use `ExportSheet.show()` — no direct PDF generation in screens

2. PDF generation MUST run on `Isolate.run()` — never on main thread

3. Sanitize all user text with `_s()` before PDF interpolation

4. All data reads through providers — no direct Firestore in screens

5. Role-aware: admin sees all, seller sees own route only

6. Export file names: `{report_type}_{route_name}_{date}.xlsx`

7. Never show raw Firestore UIDs in any export — use `NameResolver.resolve()`

8. Never hardcode English strings in PDF/Excel output — use `trRead()` with locale

9. Route labels use `'${route.routeNumber} · ${route.name}'` — no `'R'` prefix

10. Every `ExportSheet.show()` call with ledger/statement/report data MUST provide
    `pdfBytesBuilder`. The generic `buildPdfTable()` fallback is ONLY for simple flat
    tables. Omitting `pdfBytesBuilder` on ledger data causes "PDF generation failed"
    errors or produces unusable flat-table output instead of a formatted ledger.

11. `changelog_data.dart` MUST be updated on every version bump with trilingual
    (EN/AR/UR) entries. The `whats_new_sheet.dart` auto-displays the latest changelog
    on first launch after update.

12. Task continuity: when user adds new export/report work mid-session, merge into
    existing todo list. Never discard prior pending export tasks.

13. Workspace logo appearance is preserved: transparency stays transparent,
    and an opaque colored background remains present with its colors. Never
    auto-remove, replace, tint, crop, or flatten a background. Optimize locally
    within Firestore limits while preserving alpha and visual appearance.
    Reuse the shared logo source, invoice/receipt fallback, and `visibleFields`
    behavior across PDF, report, image, print, and share paths. Test transparent
    and colored-background assets through processing, persistence, and
    rasterized export; embedding assertions alone are not pixel-level proof.

## Output, boundaries, and validation

Report affected formats and scope, exact builders, role/tenant rules, locale
and font behavior, tests, and visual limitations. Keep all Firestore reads in
providers and all writes in their existing notifier owners. Do not change
financial calculations or authorization to simplify an export.

Run focused PDF/XLSX/ExportSheet tests with
`--dart-define=use_arabic=true`, relevant analysis, and Markdown lint when
documentation changes. Verify embedded PDF fonts, RTL sheet metadata, and the
shared PDF-byte path where applicable. State when pixel-level browser/viewer
rendering was not inspected.
