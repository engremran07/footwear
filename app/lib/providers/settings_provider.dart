import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/settings_model.dart';
import 'auth_provider.dart';

final settingsProvider = StreamProvider.autoDispose<SettingsModel>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.settings)
      .doc('global')
      .snapshots()
      .map((doc) {
        if (!doc.exists) {
          return SettingsModel(
            companyName: 'My Business',
            currency: 'SAR',
            pairsPerCarton: 12,
            requireAdminApprovalForSellerTransactionEdits: false,
            updatedAt: Timestamp.now(),
          );
        }
        return SettingsModel.fromJson(doc.data()!);
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

    final role = (profileSnap.data()?['role'] as String? ?? '')
        .trim()
        .toLowerCase();
    if (role != 'admin' && role != 'manager') {
      throw StateError('Admin privileges required');
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    await _requireAdmin();
    await FirebaseFirestore.instance
        .collection(Collections.settings)
        .doc('global')
        .set({...data, 'updated_at': Timestamp.now()}, SetOptions(merge: true));
  }

  /// Encodes [imageBytes] as Base64 and stores it directly in the
  /// settings/global Firestore document. No Firebase Storage required.
  /// All connected devices receive the updated logo via the real-time stream.
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
