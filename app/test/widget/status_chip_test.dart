import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/theme/app_theme.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/providers/theme_preference_provider.dart';
import 'package:footwear_erp/widgets/status_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app locale restores the saved language preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_locale': 'ur'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) =>
              MaterialApp(home: Scaffold(body: Text(tr('status', ref)))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(appLocaleProvider), AppLocale.ur);
  });

  testWidgets('StatusChip localizes status text and semantics', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appLocaleProvider.notifier).set(AppLocale.ar);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: StatusChip(status: 'pending_approval')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusLabel = trRead('pending_admin_approval', AppLocale.ar);
    final semanticLabel = '${trRead('status', AppLocale.ar)}: $statusLabel';
    expect(find.text(statusLabel), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == semanticLabel,
      ),
      findsOneWidget,
    );
  });

  test('high-contrast status colors meet AA text contrast on black', () {
    for (final status in ['paid', 'pending', 'rejected', 'processing']) {
      final color = AppTheme.statusColor(
        status,
        mode: AppThemeMode.highContrast,
      );
      final contrast = _contrastRatio(color, AppTheme.hcBg);
      expect(
        contrast,
        greaterThanOrEqualTo(4.5),
        reason: '$status status text should remain readable in high contrast',
      );
    }
  });

  test('dark theme actions and status text meet AA contrast', () {
    final theme = AppTheme.darkThemeForLocale('en');
    final buttonStyle = theme.filledButtonTheme.style!;
    final buttonForeground = buttonStyle.foregroundColor!.resolve({})!;
    final buttonBackground = buttonStyle.backgroundColor!.resolve({})!;
    final linkColor = theme.textButtonTheme.style!.foregroundColor!.resolve(
      {},
    )!;
    final statusColor = AppTheme.statusColor(
      'rejected',
      mode: AppThemeMode.dark,
    );

    expect(
      _contrastRatio(buttonForeground, buttonBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(linkColor, theme.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(statusColor, AppTheme.arcticDarkBg),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
