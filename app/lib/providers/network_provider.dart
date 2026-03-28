import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks online/offline status by listening to Firestore connection state.
final networkStatusProvider = StreamProvider<bool>((ref) {
  // This stream emits true when Firestore detects internet connectivity
  return FirebaseFirestore.instance.snapshotsInSync().map((_) => true);
});

/// Alternative: Use a timer-based check on the settings doc (more reliable for UI feedback)
final isOnlineProvider = StreamProvider<bool>((ref) {
  final firestore = FirebaseFirestore.instance;

  // Listen to real-time connection via `snapshotsInSync`
  // When connection is active, Firestore will emit.
  // When offline, it will timeout or get caught by error handling below.

  return firestore
      .collection('settings')
      .doc('global')
      .snapshots()
      .map((_) => true)
      .handleError(
        (_) => false, // If we can't connect, we're offline
        test: (e) => e is Exception,
      );
});
