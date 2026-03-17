import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_brand.dart';
import 'core/l10n/app_locale.dart';

class FootwearErpApp extends ConsumerWidget {
  const FootwearErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final appLocale = ref.watch(appLocaleProvider);
    return Directionality(
      textDirection: appLocale.direction,
      child: MaterialApp.router(
        title: AppBrand.appName,
        theme: AppTheme.lightTheme(appLocale),
        darkTheme: AppTheme.darkTheme(appLocale),
        themeMode: ThemeMode.system,
        locale: appLocale.locale,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
