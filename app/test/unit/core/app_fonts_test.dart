import 'package:flutter/material.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/theme/app_fonts.dart';

void main() {
  group('AppFonts mixed-script fallback', () {
    test(
      'English styles retain brand fonts and support Arabic-script data',
      () {
        const expectedFallback = <String>[
          AppFonts.arabicFamily,
          AppFonts.urduFamily,
        ];
        final styles = <TextStyle>[
          AppFonts.heading('en'),
          AppFonts.body('en'),
          AppFonts.textTheme('en').titleLarge!,
          AppFonts.textTheme('en').bodyMedium!,
        ];

        expect(AppFonts.heading('en').fontFamily, AppFonts.syneFamily);
        expect(AppFonts.body('en').fontFamily, AppFonts.dmSansFamily);
        for (final style in styles) {
          expect(style.fontFamilyFallback, expectedFallback);
        }
      },
    );

    test('Arabic and Urdu keep their preferred script font and fallback', () {
      expect(AppFonts.heading('ar').fontFamily, AppFonts.arabicFamily);
      expect(AppFonts.body('ar').fontFamilyFallback, const [
        AppFonts.urduFamily,
      ]);
      expect(AppFonts.heading('ur').fontFamily, AppFonts.urduFamily);
      expect(AppFonts.body('ur').fontFamilyFallback, const [
        AppFonts.arabicFamily,
      ]);
    });
  });
}
