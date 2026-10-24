import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/database_flush_provider.dart';

void main() {
  test('destructive flush methods fail closed before writing', () async {
    final now = Timestamp.now();
    final superAdmin = UserModel(
      id: 'platform-admin',
      email: 'admin@example.com',
      displayName: 'Platform Admin',
      role: UserRole.superAdmin,
      activeWorkspaceId: 'tenant-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(superAdmin)),
      ],
    );
    addTearDown(container.dispose);
    final authSubscription = container.listen(authUserProvider, (_, _) {});
    addTearDown(authSubscription.close);
    await container.read(authUserProvider.future);

    final notifier = container.read(databaseFlushProvider.notifier);
    Future<void> expectFlushRejected(Future<FlushResult> operation) async {
      await expectLater(operation, throwsA(isA<UnsupportedError>()));
    }

    await expectFlushRejected(
      notifier.flushFinancialData(tenantId: 'tenant-1'),
    );
    await expectFlushRejected(notifier.flushInventory(tenantId: 'tenant-1'));
    await expectFlushRejected(notifier.flushShops(tenantId: 'tenant-1'));
    await expectFlushRejected(notifier.flushRoutes(tenantId: 'tenant-1'));
    await expectFlushRejected(notifier.flushProducts(tenantId: 'tenant-1'));
    await expectFlushRejected(
      notifier.flushUsers('platform-admin', tenantId: 'tenant-1'),
    );
    await expectFlushRejected(
      notifier.flushPerUser('seller-1', tenantId: 'tenant-1'),
    );
    await expectFlushRejected(
      notifier.flushAll(
        keepAdminId: 'platform-admin',
        includeUsers: true,
        tenantId: 'tenant-1',
      ),
    );
    await expectFlushRejected(notifier.resetSettings(tenantId: 'tenant-1'));
  });
}
