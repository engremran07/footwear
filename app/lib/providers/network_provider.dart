import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks online/offline status by listening to Firestore connection state.
final networkStatusProvider = StreamProvider<bool>((ref) {
  // This stream emits true when Firestore detects internet connectivity
  return FirebaseFirestore.instance.snapshotsInSync().map((_) => true);
});

/// Checks real device internet connectivity using a DNS lookup.
/// Uses dart:io so it works without Firebase authentication — safe on the
/// login screen (where the user is not yet signed in).
final isOnlineProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();

  Future<void> check() async {
    try {
      final result = await InternetAddress.lookup('8.8.8.8');
      if (!controller.isClosed) {
        controller.add(result.isNotEmpty && result[0].rawAddress.isNotEmpty);
      }
    } catch (_) {
      if (!controller.isClosed) controller.add(false);
    }
  }

  check(); // Immediate check — emits within ~100 ms
  final timer = Timer.periodic(const Duration(seconds: 10), (_) => check());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});
