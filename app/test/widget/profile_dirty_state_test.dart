import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
