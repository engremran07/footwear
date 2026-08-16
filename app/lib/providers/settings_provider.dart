import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/tenant_scope.dart';
import '../models/settings_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

String _settingsDocumentIdForCurrentUser(UserModel? currentUser) {
  final tenantId = TenantScope.normalize(currentUser?.tenantId);
  return tenantId ?? TenantScope.globalTenantId;
}

final settingsProvider = StreamProvider<SettingsModel>((ref) {
  final currentUser = ref.watch(authUserProvider).value;
  final settingsDocId = _settingsDocumentIdForCurrentUser(currentUser);

  return FirebaseFirestore.instance
      .collection(Collections.settings)
      .doc(settingsDocId)
      .snapshots()
      .map((doc) {
        final data = doc.data();
        if (data == null) {
          return SettingsModel(
            tenantId: settingsDocId,
            companyName: 'My Business',
            currency: 'SAR',
            pairsPerCarton: 12,
            requireAdminApprovalForSellerTransactionEdits: false,
            updatedAt: Timestamp.now(),
          );
        }

        final model = SettingsModel.fromJson(data);
        return model.copyWith(tenantId: settingsDocId);
      });
});

class SettingsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> _requireAdmin() async {
    final cachedUser = ref.read(authUserProvider).value;
    if (cachedUser != null) {
      if (!cachedUser.isAdmin) {
        throw StateError('Admin privileges required');
      }
      return;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('No authenticated user found');
    }

    final profileSnap = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    if (!profileSnap.exists) {
      throw StateError('Authenticated user profile not found');
    }

    final role = (profileSnap.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) {
      throw StateError('Admin privileges required');
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    await _requireAdmin();
    final currentUser = ref.read(authUserProvider).value;
    final tenantId = TenantScope.normalize(currentUser?.tenantId) ??
        TenantScope.globalTenantId;
    await FirebaseFirestore.instance
        .collection(Collections.settings)
        .doc(tenantId)
        .set(
          {
            ...data,
            'tenant_id': tenantId,
            'updated_at': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
  }

  /// Encodes [imageBytes] as Base64 and stores it directly in the workspace
  /// settings Firestore document for the signed-in tenant. No Firebase Storage
  /// required. All connected devices receive the updated logo via the real-time
  /// stream.
  Future<void> uploadLogo(Uint8List imageBytes) async {
    final encoded = base64Encode(imageBytes);
    await save({'logo_base64': encoded, 'logo_url': null});
  }

  /// Clears the company logo from the settings document.
  Future<void> deleteLogo() async {
    await save({'logo_base64': null, 'logo_url': null});
  }
}

final settingsNotifierProvider = AsyncNotifierProvider<SettingsNotifier, void>(
  SettingsNotifier.new,
);
