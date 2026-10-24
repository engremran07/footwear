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

When identifying a font from a report, prefer the original PDF's embedded font
resources. A screenshot or JPEG does not retain font metadata and can support
visual comparison only.

## RTL Fonts and Shared Rendering

Every Flutter test, run, and build that can generate PDFs MUST include
`--dart-define=use_arabic=true`. The shared font loader must reject PDF
generation with a typed configuration error when this flag is missing; do not
silently export bidi-reordered but unshaped Arabic/Urdu text.

PDFs embed Noto Sans Arabic for Arabic and Urdu. Urdu PDF output is Naskh-style,
not Nastaliq: the current `pdf` renderer does not support Nastaliq's complex
OpenType GSUB/GPOS shaping. Noto Nastaliq Urdu is used by the Flutter UI only.
Do not claim full Nastaliq support or add an incompatible shaping dependency
without validating Dart, PDF package, Web, and Android compatibility.

PDF, print, share, and PNG actions must use the same generated PDF bytes; PNG
pages are rasterized from those bytes. XLSX preserves Unicode and RTL worksheet
direction, but does not embed fonts and cannot guarantee how every spreadsheet
application will shape or select a font. Test both the generated PDF font
resource and RTL worksheet XML, then perform visual checks in target viewers
when release-level visual signoff is requested.

Direct `PdfPreview` callers must provide an `onError` builder that maps the
failure through `AppErrorMapper` and localizes it; do not leave a generic blank
preview when font configuration is invalid.

Focused regression coverage belongs in `pdf_export_test.dart`,
`export_sheet_page_export_test.dart`, and `excel_export_test.dart`. Include
Arabic plus Urdu-specific letters (`ٹ ڈ ڑ ں ھ ے`), verify the PDF embeds
NotoSansArabic with a `/FontFile2` font program, and test fail-closed behavior
both with and without the shaping define. Preserve the typed configuration
exception through `ExportSheet` so the localized error mapper can report it.

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

## Open-Source References Reviewed

References below were reviewed on 2026-10-22; repository star counts are a
snapshot, not a quality guarantee. Do not copy their contents into project
skills:

- [anthropics/skills — PDF](https://github.com/anthropics/skills/tree/main/skills/pdf)
  and [XLSX](https://github.com/anthropics/skills/tree/main/skills/xlsx)
  (about 183k stars): relevant format-specific production checklists.
- [github/awesome-copilot](https://github.com/github/awesome-copilot)
  (about 40k stars): relevant VS Code/Copilot customization conventions.
- [obra/superpowers — test-driven development](https://github.com/obra/superpowers/tree/main/skills/test-driven-development)
  (about 304k stars): useful testing workflow, not an RTL font solution.

The evaluated [`pdf_text_shaper`](https://pub.dev/packages/pdf_text_shaper)
was not adopted: its current Dart/PDF minimums exceed this app's toolchain, it
does not support Web, and it documents mixed-direction limitations.
