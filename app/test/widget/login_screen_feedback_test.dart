import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/network_provider.dart';
import 'package:footwear_erp/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('slow sign-in hint is replaced by a persistent mapped error', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final result = Completer<void>();
    final notifier = _DelayedAuthNotifier(result);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => notifier),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));

    expect(find.byKey(const ValueKey('login-slow-message')), findsOneWidget);

    result.completeError(
      StateError('session-limit-reached'),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-slow-message')), findsNothing);
    expect(find.byKey(const ValueKey('login-error-message')), findsOneWidget);
    expect(
      find.text(
        'Active session limit reached. End another session or ask your workspace administrator.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _DelayedAuthNotifier extends AuthNotifier {
  _DelayedAuthNotifier(this.result);

  final Completer<void> result;

  @override
  Future<void> signIn(
    String emailAddress,
    String password, {
    bool rememberMe = true,
  }) async {
    state = const AsyncLoading();
    try {
      await result.future;
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}