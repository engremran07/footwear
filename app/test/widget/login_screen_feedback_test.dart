import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/network_provider.dart';
import 'package:footwear_erp/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'login layout keeps normalized constraints across narrow and wide widths',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(
              () => _DelayedAuthNotifier(Completer<void>()),
            ),
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) => Directionality(
                textDirection: ref.watch(appLocaleProvider).direction,
                child: const LoginScreen(),
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LoginScreen)),
      );
      for (final locale in AppLocale.values) {
        await container.read(appLocaleProvider.notifier).set(locale);
        await tester.pumpAndSettle();

        for (final width in [320.0, 360.0, 420.0, 668.0, 719.0, 720.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pump();
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                'Login layout should render at $width logical pixels in '
                '${locale.name}.',
          );
          expect(find.byType(TextFormField), findsNWidgets(2));
        }
      }
    },
  );

  testWidgets('slow sign-in hint is replaced by a persistent auth error', (
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

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));

    expect(find.byKey(const ValueKey('login-slow-message')), findsOneWidget);

    result.completeError(
      FirebaseAuthException(code: 'network-request-failed'),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-slow-message')), findsNothing);
    expect(find.byKey(const ValueKey('login-error-message')), findsOneWidget);
    expect(
      find.text('No internet connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a pending password reset dialog is safe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final resetRequest = Completer<void>();
    final notifier = _DelayedPasswordResetNotifier(resetRequest);

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

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'user@example.com');
    await tester.tap(find.text('Send Password Reset Email'));
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    resetRequest.complete();
    await tester.pump();
    await tester.pumpAndSettle();

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

class _DelayedPasswordResetNotifier extends AuthNotifier {
  _DelayedPasswordResetNotifier(this.result);

  final Completer<void> result;

  @override
  Future<void> sendPasswordReset(String emailAddress) => result.future;
}
