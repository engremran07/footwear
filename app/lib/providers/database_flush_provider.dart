import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/tenant_scope.dart';
import 'auth_provider.dart';

class FlushResult {
  final int deletedCount;
  final int resetCount;
  final String operation;

  FlushResult({
    required this.deletedCount,
    required this.resetCount,
    required this.operation,
  });

  int get totalAffected => deletedCount + resetCount;
}

class DatabaseFlushNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> _requireSuperAdmin(String tenantId) async {
    final user = await ref.read(authUserProvider.future);
    final requestedTenantId = TenantScope.normalize(tenantId);
    final activeTenantId = TenantScope.normalize(user?.tenantId);
    if (user == null ||
        !user.active ||
        !user.isSuperAdmin ||
        requestedTenantId == null ||
        requestedTenantId != activeTenantId) {
      throw ArgumentError(
        'Only super_admin may flush the currently selected workspace',
      );
    }
  }

  Never _requireSupportedReset() {
    throw UnsupportedError('flush_data_reset_unavailable');
  }

  Future<FlushResult> flushFinancialData({required String tenantId}) async {
    await _requireSuperAdmin(tenantId);
    _requireSupportedReset();
  }

  Future<FlushResult> flushInventory({required String tenantId}) async {
    await _requireSuperAdmin(tenantId);
    _requireSupportedReset();
  }

  Future<FlushResult> flushShops({required String tenantId}) async {
    await _requireSuperAdmin(tenantId);
    _requireSupportedReset();
  }

  Future<FlushResult> flushRoutes({required String tenantId}) async {
    await _requireSuperAdmin(tenantId);
    _requireSupportedReset();
  }

  Future<FlushResult> flushProducts({required String tenantId}) async {
    await _requireSuperAdmin(tenantId);
    _requireSupportedReset();
  }

  Future<FlushResult> flushUsers(
    String keepAdminId, {
    required String tenantId,
  }) async {
    await _requireSuperAdmin(tenantId);
    if (keepAdminId.trim().isEmpty) {
      throw ArgumentError('keepAdminId must not be empty');
    }
    _requireSupportedReset();
  }

  Future<FlushResult> flushPerUser(
    String userId, {
    required String tenantId,
  }) async {
    await _requireSuperAdmin(tenantId);
    if (userId.trim().isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    _requireSupportedReset();
  }

  Future<FlushResult> resetSettings({required String tenantId}) async {
    await _requireSuperAdmin(tenantId);
    _requireSupportedReset();
  }

  Future<FlushResult> flushAll({
    required String keepAdminId,
    required bool includeUsers,
    required String tenantId,
  }) async {
    await _requireSuperAdmin(tenantId);
    if (keepAdminId.trim().isEmpty) {
      throw ArgumentError('keepAdminId must not be empty');
    }
    _requireSupportedReset();
  }
}

final databaseFlushProvider =
    AsyncNotifierProvider<DatabaseFlushNotifier, void>(
      DatabaseFlushNotifier.new,
    );
