# Urdu and Arabic Input / Rendering Audit

## Current implementation observed

- App locales include English, Arabic, and Urdu. Locale and widget
  directionality are the language context; script characters alone do not
  identify whether text is Urdu or Arabic.
- The shared amount input formatter now retains Western, Arabic-Indic, and
  Eastern-Arabic digits and parser-supported decimal/group separators. It does
  not transliterate or rewrite names or stored business text.
- PDF code loads the bundled `NotoSansArabic.ttf` and
  `NotoNastaliqUrdu.ttf`. The current `pdf` 3.12.0 rendering path selects
  Noto Sans Arabic for Arabic-script PDF text because the package's TrueType
  shaping path does not provide verified complex Nastaliq GSUB/GPOS shaping.
  The UI Urdu font and PDF font path must not be assumed equivalent.
- Bilingual PDF row order uses explicit LTR directionality with per-text
  direction. The shaping gate requires `--dart-define=use_arabic=true`.
- Financial PDFs share the workspace header: English left, logo centered,
  selected Arabic/Urdu content right. Cash receipts are A5 and constrained to
  one page by the current builder.
- PNG, print, and share reuse PDF bytes; XLSX keeps Unicode text and RTL sheet
  direction but does not embed a font.

Relevant source: [input_formatters.dart](../../app/lib/core/utils/input_formatters.dart),
[pdf_export.dart](../../app/lib/core/utils/pdf_export.dart), and
[changelog_data.dart](../../app/lib/core/data/changelog_data.dart).

## Regression corpus and tests

Verified in the current audit:

- Western digits, Arabic-Indic digits `٠١٢٣٤٥٦٧٨٩`, Eastern-Arabic digits
  `۰۱۲۳۴۵۶۷۸۹`, and supported separators passed through the amount formatter
  into the canonical parser: `00:00 +4: All tests passed!`.
- PDF resource, localization, PDF/XLSX export, and bilingual layout tests
  exist in `pdf_export_test.dart`,
  `pdf_and_excel_export_integration_test.dart`, and
  `financial_document_localization_test.dart`.
- Prior audit records document browser inspection of selected Arabic/Urdu
  statement and receipt samples; this audit's current viewer capture was
  partial, and Arabic statement/receipt pages were blank or failed in the
  current capture. It is not valid to infer a current-source visual pass from
  prior-version screenshots or font embedding alone.

The full representative corpus requested by the master prompt is **NOT
COMPLETE**. It should include mixed Urdu/Arabic/English, combining marks,
diacritics, punctuation, numerals, non-joined characters, long descriptions,
and real business labels. No golden suite currently demonstrates all
renderers and both platforms.

## Findings and limitations

- **Fixed locally:** amount filtering dropped supported non-ASCII digits
  before parsing.
- **Known limitation:** full Urdu Nastaliq PDF shaping is not verified with
  this renderer. The current supported PDF output is Naskh-style; do not
  advertise the standalone Nastaliq prototype as production support.
- **Not confirmed in this audit:** a missing Urdu font asset in the Flutter
  UI. The assets are declared/loaded in PDF code; a device-level font render
  was not performed.
- **No language auto-correction:** no automatic translation, transliteration,
  or content rewriting was introduced. Language detection and confidence
  warnings are not implemented.
- Font resource inclusion proves only embedding, not connected glyphs,
  punctuation placement, baseline, clipping, pagination, copy/paste, or
  cross-platform visual equivalence.

## External references reviewed

- [Flutter internationalization](https://docs.flutter.dev/ui/internationalization)
  documents locale delegates and adapting widgets to the locale's direction.
- [pdf package documentation](https://pub.dev/packages/pdf) describes its
  TrueType font and multi-page widget APIs; it does not prove Nastaliq
  shaping for this app.

## Required next visual gate

Generate the same fixture in Arabic and Urdu through PDF, PNG, print/share,
and XLSX. Inspect PDF/PNG in a real viewer on Web and Android; verify font and
image resources, page size/count, text extraction, clipping, mixed-direction
columns, and long-row pagination. Record each output separately. Do not mark
visual acceptance PASS from widget tests or font-resource assertions alone.
