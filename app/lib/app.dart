import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_brand.dart';
import 'core/l10n/app_locale.dart';
import 'core/services/session_guard.dart';
import 'providers/theme_preference_provider.dart';

class FootwearErpApp extends ConsumerWidget {
  const FootwearErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final appLocale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(themePreferenceProvider);
    return MaterialApp.router(
      title: AppBrand.appName,
      theme: AppTheme.lightTheme(appLocale),
      darkTheme: AppTheme.darkTheme(appLocale),
      themeMode: themeMode,
      locale: appLocale.locale,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Directionality(
          textDirection: appLocale.direction,
          child: SessionGuard(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
