import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/settings_provider.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);
  final seller = UserModel(
    id: 'seller-1',
    email: 'seller@example.com',
    displayName: 'Seller',
    role: UserRole.seller,
    active: true,
    createdAt: ts,
    updatedAt: ts,
  );

  ProviderContainer containerWithUser(UserModel? user) {
    return ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream<UserModel?>.value(user)),
      ],
    );
  }

  ProviderSubscription<AsyncValue<UserModel?>> keepAuthAlive(
    ProviderContainer container,
  ) {
    return container.listen<AsyncValue<UserModel?>>(
      authUserProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }

  group('SettingsNotifier admin guard', () {
    test('save throws for seller credentials', () async {
      final container = containerWithUser(seller);
      addTearDown(container.dispose);
      final authSub = keepAuthAlive(container);
      addTearDown(authSub.close);
      await container.read(authUserProvider.future);

      expect(
        () => container.read(settingsNotifierProvider.notifier).save({
          'company_name': 'Blocked',
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Admin privileges required'),
          ),
        ),
      );
    });

    test('uploadLogo throws for seller credentials', () async {
      final container = containerWithUser(seller);
      addTearDown(container.dispose);
      final authSub = keepAuthAlive(container);
      addTearDown(authSub.close);
      await container.read(authUserProvider.future);

      expect(
        () => container
            .read(settingsNotifierProvider.notifier)
            .uploadLogo(Uint8List.fromList(const [1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    });

    test('deleteLogo throws for seller credentials', () async {
      final container = containerWithUser(seller);
      addTearDown(container.dispose);
      final authSub = keepAuthAlive(container);
      addTearDown(authSub.close);
      await container.read(authUserProvider.future);

      expect(
        () => container.read(settingsNotifierProvider.notifier).deleteLogo(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
