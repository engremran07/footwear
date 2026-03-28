import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks Firestore connectivity by listening to snapshot metadata.
/// Returns true when the app has server connectivity (not just cache).
final connectivityProvider = StreamProvider<bool>((ref) {
  ref.keepAlive();
  final controller = StreamController<bool>();
  // Listen to a lightweight doc that always exists
  final sub = FirebaseFirestore.instance
      .collection('settings')
      .doc('global')
      .snapshots(includeMetadataChanges: true)
      .listen((snap) {
    controller.add(!snap.metadata.isFromCache);
  }, onError: (_) {
    controller.add(false);
  });
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
