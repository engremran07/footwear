import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/user_provider.dart';
import 'package:footwear_erp/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile name save uses self-profile access for every role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    for (final role in [
      UserRole.admin,
      UserRole.tenantAdmin,
      UserRole.superAdmin,
      UserRole.supervisor,
      UserRole.seller,
    ]) {
      final user = UserModel(
        id: 'user-1',
        email: 'user@example.com',
        displayName: 'User Name',
        role: role,
        tenantId: role == UserRole.superAdmin ? null : 'workspace-a',
        active: true,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );
      final notifier = _NameCapturingNotifier();

      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(role.name),
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(user)),
            userManagementNotifierProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile_display_name_field')),
        'Updated Name',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        notifier.displayName,
        'Updated Name',
        reason: '$role should use the owner-only name update path',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('profile becomes clean when display name is restored', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final user = UserModel(
      id: 'user-1',
      email: 'user@example.com',
      displayName: 'User Name',
      role: UserRole.admin,
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authUserProvider.overrideWith((ref) => Stream.value(user))],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final nameField = find.byKey(const Key('profile_display_name_field'));
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Changed Name');
    await tester.pump();
    final popScope = find.byKey(const Key('profile_pop_scope'));
    expect(tester.widget<PopScope>(popScope).canPop, isFalse);

    await tester.enterText(nameField, 'User Name');
    await tester.pump();
    expect(tester.widget<PopScope>(popScope).canPop, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seller profile exposes privacy and account deletion links', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final user = UserModel(
      id: 'seller-1',
      email: 'seller@example.com',
      displayName: 'Seller',
      role: UserRole.seller,
      tenantId: 'workspace-a',
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authUserProvider.overrideWith((ref) => Stream.value(user))],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

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

    expect(tester.takeException(), isNull);
  });

  testWidgets('password dialog preserves entered whitespace', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final user = UserModel(
      id: 'user-1',
      email: 'user@example.com',
      displayName: 'User Name',
      role: UserRole.admin,
      active: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );
    final passwordNotifier = _PasswordCapturingNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          userManagementNotifierProvider.overrideWith(() => passwordNotifier),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final changePasswordButton = find.text('Change Password');
    await tester.scrollUntilVisible(
      changePasswordButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(changePasswordButton);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'current password ');
    await tester.enterText(fields.at(1), ' new pass ');
    await tester.enterText(fields.at(2), ' new pass ');
    await tester.tap(find.descendant(of: dialog, matching: find.text('Save')));
    await tester.pumpAndSettle();

    expect(passwordNotifier.currentPassword, 'current password ');
    expect(passwordNotifier.newPassword, ' new pass ');
    expect(tester.takeException(), isNull);
  });
}

class _PasswordCapturingNotifier extends UserManagementNotifier {
  String? currentPassword;
  String? newPassword;

  @override
  Future<void> build() async {}

  @override
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    this.currentPassword = currentPassword;
    this.newPassword = newPassword;
  }
}

class _NameCapturingNotifier extends UserManagementNotifier {
  String? displayName;

  @override
  Future<void> build() async {}

  @override
  Future<void> updateOwnDisplayName(String displayName) async {
    this.displayName = displayName;
  }
}
