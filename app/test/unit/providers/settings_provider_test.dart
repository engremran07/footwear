import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/tenant_scope.dart';
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

  group('Workspace settings resolution', () {
    test('uses the current tenant settings document instead of the global fallback', () {
      final tenantUser = seller.copyWith(tenantId: 'tenant-42');
      final platformAdmin = UserModel(
        id: 'platform-admin',
        email: 'admin@example.com',
        displayName: 'Platform Admin',
        role: UserRole.superAdmin,
        activeWorkspaceId: 'tenant-42',
        activeWorkspaceReason: 'Workspace settings support',
        activeWorkspaceSelectedAt: Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        active: true,
        createdAt: ts,
        updatedAt: ts,
      );

      expect(settingsDocumentIdForUser(tenantUser), 'tenant-42');
      expect(settingsDocumentIdForUser(platformAdmin), 'tenant-42');
      expect(settingsDocumentIdForUser(null), TenantScope.noActiveWorkspaceId);
    });

    test(
      'does not resolve settings after super-admin support context expiry',
      () {
        final now = DateTime.now();
        final expiredPlatformAdmin = UserModel(
          id: 'platform-admin',
          email: 'admin@example.com',
          displayName: 'Platform Admin',
          role: UserRole.superAdmin,
          activeWorkspaceId: 'tenant-42',
          activeWorkspaceReason: 'Workspace settings support',
          activeWorkspaceSelectedAt: Timestamp.fromDate(
            now.subtract(const Duration(hours: 8, minutes: 1)),
          ),
          active: true,
          createdAt: ts,
          updatedAt: ts,
        );

        expect(
          settingsDocumentIdForUser(expiredPlatformAdmin),
          TenantScope.noActiveWorkspaceId,
        );
      },
    );

    test(
      'settings provider avoids Firestore for expired support context',
      () async {
        final expiredPlatformAdmin = UserModel(
          id: 'platform-admin',
          email: 'admin@example.com',
          displayName: 'Platform Admin',
          role: UserRole.superAdmin,
          activeWorkspaceId: 'tenant-42',
          activeWorkspaceReason: 'Workspace settings support',
          activeWorkspaceSelectedAt: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 8, minutes: 1)),
          ),
          active: true,
          createdAt: ts,
          updatedAt: ts,
        );
        final container = containerWithUser(expiredPlatformAdmin);
        addTearDown(container.dispose);
        final authSub = keepAuthAlive(container);
        addTearDown(authSub.close);
        await container.read(authUserProvider.future);
        final settingsSub = container.listen(
          settingsProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(settingsSub.close);

        final settings = await container.read(settingsProvider.future);

        expect(settings.tenantId, TenantScope.noActiveWorkspaceId);
      },
    );
  });

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

    test('save rejects oversized logo data before writing settings', () async {
      final admin = seller.copyWith(role: UserRole.admin, tenantId: 'tenant-1');
      final container = containerWithUser(admin);
      addTearDown(container.dispose);
      final authSub = keepAuthAlive(container);
      addTearDown(authSub.close);
      await container.read(authUserProvider.future);

      await expectLater(
        container.read(settingsNotifierProvider.notifier).save({
          'logo_base64': List<String>.filled(50 * 1024 + 1, 'a').join(),
        }),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('50 KB'),
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
