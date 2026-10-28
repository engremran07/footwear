---
name: flutter-accessibility-rtl
description: "Use when: changing Flutter accessibility, text scaling, keyboard/focus behavior, localization, Arabic/Urdu RTL layouts, or mixed-direction content."
---

# Flutter Accessibility, Localization, and RTL

## Purpose

Keep ShoesERP usable with assistive technologies, larger text, and its English,
Arabic, and Urdu locales across supported Flutter targets.

## Invocation

Use for layout, semantics, input, navigation, error, typography, localization,
and RTL changes, and during representative screen-family acceptance testing.

## Required inputs

- The affected widget and locale/direction source.
- Supported text scaling, target platforms, and existing localization keys.
- Current Flutter SDK and available accessibility/widget-test APIs.

## Workflow

1. Confirm the screen's locale, `Directionality`, font, text scaling, and target
   platform from the current app implementation.
2. Check semantics, labels, focus order, keyboard activation where supported,
   the shared `AppTokens.minTouchTarget`, error identification, and status
   information beyond color alone.
3. Review contrast for actual foreground/surface pairs in light, dark, and
   high-contrast modes. Apply WCAG 2.2 criteria as relevant to the target,
   without describing one mobile metric as universal WCAG conformance.
4. Check Arabic and Urdu separately, including mixed Latin identifiers, dates,
   digits, currency, phone numbers, input cursor behavior, and text expansion.
   Also test Arabic-script Firestore values while the app locale is English;
   preserve the English primary font and verify ordered bundled Noto fallback
   for each shared text style.
5. Add automated Flutter accessibility guideline checks where supported by the
   pinned SDK; manually verify screen-reader and platform behavior when
   possible.
6. Honor `MediaQuery.disableAnimations` for optional shared-component motion
   with `AppMotion`; test shared animation presets and explicit controllers.
   State changes and actions must remain immediate and available without
   animation.
7. Preserve localized validation and recovery messages. Never hardcode
   translated UI text or change export font policy based on UI typography.
   UI fallback validation is not evidence that PDF, print, image, or
   spreadsheet rendering is correct.

## Output

Report affected locales/platforms, automated checks, actual manual checks,
known compatibility limits, and unverified combinations.

## References and boundaries

Use the authoritative standards in
`.github/instructions/frontend-design-system.instructions.md`, the app
localization/font implementation, and official Flutter guidance. WCAG 2.2 is a
reference standard, not proof of legal or platform conformance. PDF shaping and
spreadsheet rendering belong to `analytics-reporting`; do not claim that UI
font support guarantees identical PDF, image, print, or XLSX rendering.

## Validation

Run focused widget tests with Arabic and Urdu locales, large text where
practical, and Flutter's supported accessibility checks. Use rendered or
assistive-technology inspection when available and state any limitation.
