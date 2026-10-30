import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/constants/app_brand.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';
import 'package:footwear_erp/screens/about_screen.dart';
import 'package:footwear_erp/screens/settings_screen.dart';
import 'package:footwear_erp/widgets/app_shell.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('navigation keeps platform settings scoped and About universal', () {
    final rootSuperAdmin = _user(UserRole.superAdmin);
    final scopedSuperAdmin = _user(
      UserRole.superAdmin,
      activeWorkspaceId: 'workspace-1',
      supportReason: 'Investigating workspace issue',
      selectedAt: Timestamp.fromDate(
        DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      ),
    );
    final tenantAdmin = _user(UserRole.tenantAdmin, tenantId: 'workspace-1');
    final admin = _user(UserRole.admin, tenantId: 'workspace-1');
    final seller = _user(UserRole.seller, tenantId: 'workspace-1');

    for (final user in [
      rootSuperAdmin,
      scopedSuperAdmin,
      tenantAdmin,
      admin,
      seller,
    ]) {
      expect(AppShell.navigationRoutesFor(user), contains('/about'));
    }
    expect(
      AppShell.navigationRoutesFor(rootSuperAdmin),
      containsAll(['/settings', '/tenants']),
    );
    expect(
      AppShell.navigationRoutesFor(scopedSuperAdmin),
      contains('/settings'),
    );
    expect(AppShell.navigationRoutesFor(tenantAdmin), contains('/settings'));
    expect(AppShell.navigationRoutesFor(admin), contains('/settings'));
    expect(AppShell.navigationRoutesFor(seller), isNot(contains('/settings')));
  });

  testWidgets('platform settings hub offers safe global destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final superAdmin = _user(UserRole.superAdmin);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(superAdmin)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platform Settings'), findsOneWidget);
    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('About Us'), findsOneWidget);
    expect(find.text("What's New"), findsOneWidget);
    expect(find.text('Company Name'), findsNothing);
  });

  for (final role in [UserRole.admin, UserRole.tenantAdmin]) {
    testWidgets('$role sees the maintenance entry after scrolling', (
      tester,
    ) async {
      final account = _user(role, tenantId: 'workspace-1');
      final settings = SettingsModel(
        tenantId: 'workspace-1',
        currency: 'SAR',
        pairsPerCarton: 12,
        updatedAt: Timestamp.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(account)),
            settingsProvider.overrideWith((ref) => Stream.value(settings)),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final maintenanceEntry = find.widgetWithText(ListTile, 'Danger Zone');
      await tester.scrollUntilVisible(
        maintenanceEntry,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(maintenanceEntry, findsOneWidget);
      expect(tester.widget<ListTile>(maintenanceEntry).onTap, isNotNull);
    });
  }

  for (final locale in [AppLocale.ar, AppLocale.ur]) {
    testWidgets('About screen renders in ${locale.name}', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLocaleProvider.overrideWith(
              () => _FixedAppLocaleNotifier(locale),
            ),
          ],
          child: const MaterialApp(home: AboutScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(AppBrand.appName), findsOneWidget);
      expect(find.text('Aeonis Labs'), findsOneWidget);
      expect(find.text(trRead('published_by', locale)), findsOneWidget);

      for (final key in [
        'privacy_policy_link',
        'account_deletion_request_link',
      ]) {
        final link = find.byKey(Key(key));
        await tester.scrollUntilVisible(
          link,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(link, findsOneWidget);
        expect(tester.widget<ListTile>(link).onTap, isNotNull);
      }

      expect(find.text(trRead('privacy_policy', locale)), findsOneWidget);
      expect(
        find.text(trRead('account_deletion_request', locale)),
        findsOneWidget,
      );
    });
  }
}

UserModel _user(
  UserRole role, {
  String? tenantId,
  String? activeWorkspaceId,
  String? supportReason,
  Timestamp? selectedAt,
}) => UserModel(
  id: role.name,
  email: '${role.name}@example.com',
  displayName: role.name,
  role: role,
  tenantId: tenantId,
  activeWorkspaceId: activeWorkspaceId,
  activeWorkspaceReason: supportReason,
  activeWorkspaceSelectedAt: selectedAt,
  active: true,
  createdAt: Timestamp.now(),
  updatedAt: Timestamp.now(),
);

class _FixedAppLocaleNotifier extends AppLocaleNotifier {
  _FixedAppLocaleNotifier(this.locale);

  final AppLocale locale;

  @override
  AppLocale build() => locale;
}
