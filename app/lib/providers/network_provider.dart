import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bidirectional online/offline detection with hysteresis.
///
/// Why this shape:
/// - Single DNS probes can flap on mobile networks and falsely report offline.
/// - We keep the app optimistic (`true`) until repeated probe failures occur.
/// - We only switch to offline after consecutive failures to reduce jitter.
final networkStatusProvider = StreamProvider.autoDispose<bool>((ref) {
  final controller = StreamController<bool>();
  const probeHost = 'firestore.googleapis.com';
  const probeTimeout = Duration(seconds: 2);
  const pollInterval = Duration(seconds: 30);
  const startupDelay = Duration(seconds: 2);
  const offlineFailureThreshold = 3;

  var failureCount = 0;
  var lastStatus = true;

  Future<bool> probe() async {
    final result = await InternetAddress.lookup(probeHost).timeout(
      probeTimeout,
    );
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  }

  Future<void> check() async {
    var reachable = false;
    try {
      reachable = await probe();
    } catch (_) {
      // probe failed
    }

    if (reachable) {
      failureCount = 0;
      if (!lastStatus && !controller.isClosed) {
        controller.add(true);
      }
      lastStatus = true;
      return;
    }

    failureCount += 1;
    if (failureCount >= offlineFailureThreshold && lastStatus) {
      if (!controller.isClosed) {
        controller.add(false);
      }
      lastStatus = false;
    }
  }

  // Optimistic initial state: avoids false offline badge during startup warm-up.
  controller.add(true);

  // Defer first probe to avoid blocking app startup.
  Timer? timer;
  final startTimer = Timer(startupDelay, () {
    check();
    timer = Timer.periodic(pollInterval, (_) => check());
  });

  ref.onDispose(() {
    startTimer.cancel();
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Alias kept for backward compatibility — prefer [networkStatusProvider].
final isOnlineProvider = networkStatusProvider;
