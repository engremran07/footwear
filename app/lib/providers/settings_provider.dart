import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/settings_model.dart';

final settingsProvider = StreamProvider<SettingsModel>((ref) {
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
        updatedAt: Timestamp.now(),
      );
    }
    return SettingsModel.fromJson(doc.data()!);
  });
});

class SettingsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(Map<String, dynamic> data) async {
    await FirebaseFirestore.instance
        .collection(Collections.settings)
        .doc('global')
        .set({...data, 'updated_at': Timestamp.now()}, SetOptions(merge: true));
  }
}

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, void>(SettingsNotifier.new);
