import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../models/settings_model.dart';

final settingsProvider = StreamProvider<SettingsModel?>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.settings)
      .doc('global')
      .snapshots()
      .map((doc) =>
          doc.exists ? SettingsModel.fromJson(doc.data()!, doc.id) : null);
});

class SettingsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(Map<String, dynamic> data) async {
    state = const AsyncLoading();
    try {
      await FirebaseFirestore.instance
          .collection(Collections.settings)
          .doc('global')
          .set({
        ...data,
        'updated_at': Timestamp.now(),
      }, SetOptions(merge: true));
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, void>(SettingsNotifier.new);
