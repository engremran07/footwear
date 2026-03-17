import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';

/// Streams `true` when Firestore snapshots come from the server (online),
/// `false` when they come from cache (offline).
/// Uses the `settings/global` doc which every authenticated user can read.
final isOnlineProvider = StreamProvider<bool>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.settings)
      .doc('global')
      .snapshots(includeMetadataChanges: true)
      .map((snap) => !snap.metadata.isFromCache);
});
